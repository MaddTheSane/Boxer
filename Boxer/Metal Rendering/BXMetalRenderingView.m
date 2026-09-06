//
//  BXMetalRenderingView.m
//  Boxer
//
//  Created by Stuart Carnie on 7/10/20.
//  
//

@import QuartzCore;
@import OpenEmuShaders;

#import "ADBGeometry.h"
#import "BXMetalRenderingView+Private.h"
#import "BXVideoFrame.h"
#import "BXMetalLayer.h"

/// Only send 1 frame at once to the GPU.
/// Since we aren't synced to the display, even one more
/// is enough to block in nextDrawable for more than a frame
/// and cause audio skipping.
/// TODO(sgc): implement triple buffering
#define MAX_INFLIGHT 1

@interface BXMetalRenderingView() {
    
}

@property (nonatomic, readwrite) NSArray<OEShaderParamGroup *> *parameterGroups;

@end

@implementation BXMetalRenderingView {
    CAMetalLayer    *_videoLayer;
    OEFilterChain   *_filterChain;
    id<MTLTexture>  _texture;
    
    dispatch_semaphore_t    _inflightSemaphore;
    NSInteger               _skippedFrames;
    id<MTLDevice>           _device;
    id<MTLCommandQueue>     _commandQueue;
    MTLClearColor           _clearColor;
    
    BOOL _inViewportAnimation;
    BOOL _managesViewport;
    NSSize _maxViewportSize;
    NSRect _viewportRect;
    NSRect _targetViewportRect;
    BXRenderingStyle _renderingStyle;
    NSString *_selectedShaderPresetPath;
}

@synthesize currentFrame=_currentFrame;
@synthesize maxFrameSize=_maxFrameSize;

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder: coder]) {
        [self initDefaults];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    
    if (self = [super initWithFrame: frameRect device:device]) {
        [self initDefaults];
    }
    return self;
}

- (OEFilterChain *)filterChain {
    return _filterChain;
}

- (void)initDefaults {
    _inflightSemaphore = dispatch_semaphore_create(MAX_INFLIGHT);
    _device = self.device;
    self.framebufferOnly = YES;
    self.presentsWithTransaction = NO;
    self.paused = NO;
    
    _commandQueue      = [_device newCommandQueue];
    _clearColor        = MTLClearColorMake(0, 0, 0, 1);
    _filterChain = [[OEFilterChain alloc] initWithDevice:_device];
    [_filterChain setDefaultFilteringLinear:NO];
    
    // some reasonable default
    [_filterChain setSourceRect:CGRectMake(0, 0, 648, 480) aspect:CGSizeMake(4, 3)];
    self.renderingStyle = BXRenderingStyleNormal;
    
    self.wantsLayer = YES;
    
    _videoLayer = (CAMetalLayer *)self.layer;
    
    [self updateRenderState];
    
    _maxFrameSize = NSMakeSize(16384, 16384);
}

- (BOOL)supportsRenderingStyle:(BXRenderingStyle)style {
    return YES;
}

- (NSArray<NSString *> *)availableShaderPresetPaths
{
    NSURL *shadersURL = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"Shaders" isDirectory:YES];
    NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager]
        enumeratorAtURL:shadersURL
        includingPropertiesForKeys:@[NSURLIsRegularFileKey]
        options:(NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants)
        errorHandler:nil];

    if (enumerator == nil)
    {
        return @[];
    }

    NSMutableArray<NSString *> *presetPaths = [NSMutableArray array];
    for (NSURL *presetURL in enumerator)
    {
        NSNumber *isRegularFile = nil;
        [presetURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (!isRegularFile.boolValue || ![presetURL.pathExtension.lowercaseString isEqualToString:@"slangp"])
        {
            continue;
        }

        NSString *relativePath = [presetURL.path substringFromIndex:shadersURL.path.length];
        relativePath = [relativePath stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
        if (relativePath.length > 0)
        {
            [presetPaths addObject:relativePath];
        }
    }

    [presetPaths sortUsingComparator:^NSComparisonResult(NSString *first, NSString *second) {
        return [first.lastPathComponent localizedStandardCompare:second.lastPathComponent];
    }];
    return presetPaths;
}

- (NSString *)selectedShaderPresetPath
{
    return _selectedShaderPresetPath;
}

- (BOOL)loadShaderPresetAtPath:(NSString *)presetPath
{
    if (presetPath.length == 0 || ![self.availableShaderPresetPaths containsObject:presetPath])
    {
        return NO;
    }

    NSURL *shadersURL = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"Shaders" isDirectory:YES];
    NSURL *presetURL = [shadersURL URLByAppendingPathComponent:presetPath];
    NSError *error = nil;
    if (![_filterChain setShaderFromURL:presetURL error:&error])
    {
        NSLog(@"Could not load shader preset at %@: %@", presetPath, error.localizedDescription);
        return NO;
    }

    _selectedShaderPresetPath = [presetPath copy];
    self.parameterGroups = _filterChain.shader.parameterGroups;
    return YES;
}

- (void)setRenderingStyle:(BXRenderingStyle)renderingStyle {
    [self willChangeValueForKey:@"renderingStyle"];
    
    _renderingStyle = renderingStyle;
    
    switch (renderingStyle) {
    case BXRenderingStyleNormal: {
        [self loadShaderPresetAtPath:@"Pixellate/Pixellate.slangp"];
        break;
    }
        
    case BXRenderingStyleCRT: {
        [self loadShaderPresetAtPath:@"CRT Geom/CRT Geom.slangp"];
        break;
    }
        
    case BXRenderingStyleSmoothed: {
        [self loadShaderPresetAtPath:@"Smooth/Smooth.slangp"];
        break;
    }
    }
    
    [self didChangeValueForKey:@"renderingStyle"];
    
}

- (void)updateWithFrame:(BXVideoFrame *)frame {
    if (frame == nil) {
        _currentFrame = nil;
        _texture      = nil;
        return;
    }
    
    CGRect sourceRect = CGRectMake(0, 0, frame.size.width, frame.size.height);
    [_filterChain setSourceRect:sourceRect aspect:frame.scaledSize];
    
    if (frame != _currentFrame) {
        if (NSIsEmptyRect(self.viewportRect)) {
            NSRect viewportRect = [self viewportForFrame:frame];
            [self setViewportRect:viewportRect animated:NO];
        }
        
        // new buffer
        _currentFrame = frame;
        MTLTextureDescriptor *td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:frame.size.width
                                                          height:frame.size.height
                                                       mipmapped:NO];
        _texture = [_device newTextureWithDescriptor:td];
        [_filterChain setSourceTexture:_texture];
    }
    
    [_texture replaceRegion:MTLRegionMake2D(0, 0, sourceRect.size.width, sourceRect.size.height)
                mipmapLevel:0
                  withBytes:frame.bytes
                bytesPerRow:frame.pitch];
    
    // If the frame changes size or aspect ratio, and we're responsible for the viewport ourselves,
    // then smoothly animate the transition to the new size.
    if (self.managesViewport)
    {
        [self setViewportRect:[self viewportForFrame:frame] animated:YES];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    if (_texture == nil) {
        return;
    }
    
    @autoreleasepool {
        if (dispatch_semaphore_wait(_inflightSemaphore, DISPATCH_TIME_NOW) != 0) {
            _skippedFrames++;
        } else {
            id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
            commandBuffer.label = @"offscreen";
            [commandBuffer enqueue];
            [_filterChain renderOffscreenPassesWithCommandBuffer:commandBuffer];
            [commandBuffer commit];
            
            id<CAMetalDrawable> drawable = _videoLayer.nextDrawable;
            if (drawable != nil) {
                MTLRenderPassDescriptor *rpd = [MTLRenderPassDescriptor new];
                rpd.colorAttachments[0].clearColor = _clearColor;
                // TODO: Use MTLLoadActionDontCare
                // We can use MTLLoadActionDontCare when source texture
                // is same aspect ratio as drawable (i.e. windowed)
                rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
                rpd.colorAttachments[0].texture    = drawable.texture;
                commandBuffer = [_commandQueue commandBuffer];
                commandBuffer.label = @"final";
                id<MTLRenderCommandEncoder> rce = [commandBuffer renderCommandEncoderWithDescriptor:rpd];
                [_filterChain renderFinalPassWithCommandEncoder:rce];
                [rce endEncoding];
                
                __block dispatch_semaphore_t inflight = _inflightSemaphore;
                [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _) {
                    dispatch_semaphore_signal(inflight);
                }];
                
                [commandBuffer presentDrawable:drawable];
                [commandBuffer commit];
            } else {
                dispatch_semaphore_signal(self->_inflightSemaphore);
            }
        }
    }
}

#pragma mark - Viewport / Bounds

- (void)updateRenderState {
    [_videoLayer setBounds:self.bounds];
    NSRect rect = [self convertRectToBacking:self.bounds];
    _videoLayer.drawableSize = NSSizeToCGSize(rect.size);
    [_filterChain setDrawableSize:_videoLayer.drawableSize];
    if (self.currentFrame) {
        [self setViewportRect:[self viewportForFrame:self.currentFrame] animated:NO];
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (!self.inLiveResize) {
        [self updateRenderState];
    }
}

- (void) viewDidEndLiveResize
{
    [self updateRenderState];
}

- (void) windowDidChangeBackingProperties: (NSNotification *)notification
{
    //[self _applyViewportToRenderer];
}

#pragma mark - Animation

+ (id) defaultAnimationForKey: (NSString *)key
{
    if ([key isEqualToString: @"viewportRect"])
    {
        CABasicAnimation *animation = [CABasicAnimation animation];
        animation.duration = 0.2;
        animation.timingFunction = [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseIn];
        return animation;
    }
    else
    {
        return [super defaultAnimationForKey:key];
    }
}

- (void)animationDidStart:(CAAnimation *)anim
{
    _inViewportAnimation = YES;
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag
{
    _inViewportAnimation = NO;
    anim.delegate = nil;
}

//Returns the rectangular region of the view into which the specified frame should be drawn.
- (NSRect)viewportForFrame:(BXVideoFrame *)frame
{
    if (frame != nil && self.managesViewport)
    {
        NSSize frameSize = frame.scaledSize;
        NSRect frameRect = NSMakeRect(0.0f, 0.0f, frameSize.width, frameSize.height);
        
        NSRect canvasRect = self.bounds;
        NSRect maxViewportRect = canvasRect;
        
        //If we have a maximum viewport size, fit the frame within that; otherwise, just fill the canvas as best we can.
        if (!NSEqualSizes(self.maxViewportSize, NSZeroSize) && sizeFitsWithinSize(self.maxViewportSize, canvasRect.size))
        {
            maxViewportRect = resizeRectFromPoint(canvasRect, self.maxViewportSize, NSMakePoint(0.5f, 0.5f));
        }
        
        NSRect fittedViewportRect = fitInRect(frameRect, maxViewportRect, NSMakePoint(0.5f, 0.5f));
        
        return fittedViewportRect;
    }
    else
    {
        return self.bounds;
    }
}

- (void) setManagesViewport:(BOOL)enabled
{
    if (_managesViewport != enabled)
    {
        _managesViewport = enabled;
        
        // Update our viewport immediately to compensate for the change
        [self setViewportRect:[self viewportForFrame:self.currentFrame]
                     animated:NO];
    }
}

- (void)setViewportRect:(NSRect)newRect
{
    if (!NSEqualRects(newRect, _viewportRect))
    {
        _viewportRect = newRect;
        [self needsDisplay];
    }
}

- (void)setViewportRect:(NSRect)newRect animated:(BOOL)animated
{
    if (!NSEqualRects(_targetViewportRect, newRect))
    {
        //If our viewport is zero (i.e. we haven't received a frame until now)
        //then just replace the viewport with the new one instead of animating to it.
        if (!animated || NSIsEmptyRect(_viewportRect))
        {
            _targetViewportRect = newRect;
            self.viewportRect = newRect;
        }
        else
        {
            _targetViewportRect = newRect;
            
            [NSAnimationContext beginGrouping]; {
                NSAnimationContext.currentContext.duration = 0.2;
                [self.animator setViewportRect:_targetViewportRect];
                [NSAnimationContext endGrouping];
            }
        }
    }
}


@end
