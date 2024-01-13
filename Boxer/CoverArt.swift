//
//  CoverArt.swift
//  Boxer
//
//  Created by C.W. Betts on 1/6/24.
//  Copyright © 2024 Alun Bestor and contributors. All rights reserved.
//

import Cocoa

/// `CoverArt` renders a boxed cover-art appearance from an original source image. It can return
/// an `NSImage` resource suitable for use as a file thumbnail, or draw the art directly into the
/// current graphics context.
@objcMembers
class CoverArt: NSObject {
	/// The original image we will render into cover art.
	var sourceImage: NSImage?

	// MARK: - Art assets
	
	/// Returns the drop shadow effect to be applied to icons of the specified size.
	///
	/// This shadow ensures the icon stands out on light backgrounds, such as a Finder folder window.
	@objc(dropShadowForSize:)
	class func dropShadow(for iconSize: NSSize) -> NSShadow? {
		guard iconSize.height >= 32 else {
			return nil;
		}
		
		let blurRadius	= max(1.0, iconSize.height / 32)
		let offset		= max(1.0, iconSize.height / 128)
		
		return NSShadow(blurRadius: blurRadius,
						offset: NSSize(width: 0, height: -offset),
						color: NSColor(calibratedWhite: 0, alpha: 0.85))
	}
	
	/// Returns the inner glow effect to be applied to icons of the specified size.
	/// This inner glow ensures the icon stands out on dark backgrounds, such as Finder's Coverflow.
	@objc(innerGlowForSize:)
	class func innerGlow(for iconSize: NSSize) -> NSShadow? {
		guard iconSize.height >= 64 else {
			return nil
		}
		let blurRadius = max(1.0, iconSize.height / 64)
		
		return NSShadow(blurRadius: blurRadius,
						offset: .zero,
						color: NSColor(calibratedWhite: 1, alpha: 0.33))
	}
	
	/// Returns a shine overlay image to be applied to icons of the specified size.
	/// This overlay gives the image a stylized glossy appearance.
	@objc(shineForSize:)
	class func shine(for iconSize: NSSize) -> NSImage? {
		let shine: NSImage = NSImage(named: "BoxArtShine")!.copy() as! NSImage
		shine.size = iconSize
		return shine
	}
	
	// MARK: - Rendering methods
	
	//	@objc(drawInRect:)
	/// Draws the source image as cover art into the specified frame in the current graphics context.
	func draw(in frame: NSRect) {
		//Switch to high-quality interpolation before we begin, and restore it once we're done
		//(this is not stored by saveGraphicsState/restoreGraphicsState unfortunately)
		let oldInterpolation = NSGraphicsContext.current?.imageInterpolation ?? .`default`
		NSGraphicsContext.current?.imageInterpolation = .high
		defer {
			NSGraphicsContext.current?.imageInterpolation = oldInterpolation
		}
		
		let iconSize = frame.size
		guard let image = sourceImage else {
			return
		}
		
		//Effects we'll be applying to the cover art
		let shine = type(of: self).shine(for: iconSize)
		let dropShadow = type(of: self).dropShadow(for: iconSize)
		let innerGlow = type(of: self).innerGlow(for: iconSize)
		
		//Allow enough room around the image for our drop shadow
		let availableSize	= NSMakeSize(
			iconSize.width	- (dropShadow?.shadowBlurRadius ?? 0) * 2,
			iconSize.height	- (dropShadow?.shadowBlurRadius ?? 0) * 2
		)
		var artFrame = NSRect()
		//Scale the image proportionally to fit our target box size
		artFrame.size = sizeToFitSize(image.size, availableSize)
		artFrame.origin	= NSMakePoint(
			//Center the box horizontally...
			(iconSize.width - artFrame.size.width) / 2,
			//...but put its baseline along the bottom, with enough room for the drop shadow
			((dropShadow?.shadowBlurRadius ?? 0) - (dropShadow?.shadowOffset.height ?? 0))
		);
		
		//Round the rect up to integral values, to avoid blurry subpixel lines
		artFrame = NSIntegralRect(artFrame)

		//Draw the original image into the appropriate space in the canvas, with our drop shadow
		do {
			NSGraphicsContext.saveGraphicsState()
			defer {
				NSGraphicsContext.restoreGraphicsState()
			}
			
			dropShadow?.set()
			image.draw(in: artFrame, from: .zero, operation: .sourceOver, fraction: 1)
		}
		
		//Draw the inner glow inside the box region
		if let innerGlow {
			NSBezierPath(rect: artFrame).fill(withInnerShadow: innerGlow)
		}
		
		//Draw our pretty box shine into the box's region
		shine?.draw(in: artFrame,
					from: artFrame,
					operation: .sourceOver,
					fraction: 0.25)
		
		//Finally, outline the box
		NSColor(calibratedWhite: 0, alpha: 0.33).set()
		NSBezierPath.defaultLineWidth = 1
		NSBezierPath.stroke(NSInsetRect(artFrame, -0.5, -0.5))
	}
	
	//	@objc(representationForSize:scale:)
	/// Returns a cover art image representation from the source image rendered at the specified size and scale.
	private func representation(for iconSize: NSSize, scale: CGFloat = 1) -> NSImageRep! {
		var frame = NSRect(origin: .zero, size: iconSize)
		
		//Create a new empty canvas to draw into
		let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(iconSize.width * scale), pixelsHigh: Int(iconSize.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 32)!
		rep.size = iconSize
		
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
			draw(in: frame)
		NSGraphicsContext.restoreGraphicsState()
		
		return rep
	}
	
	/// Default initializer: returns a `CoverArt` object initialized with the specified original image.
	@objc(initWithSourceImage:)
	required public init(sourceImage image: NSImage?) {
		sourceImage = image
		super.init()
	}

	/// Returns a cover art image rendered from the source image to 512, 256, 128 and 32x32 sizes,
	/// suitable for use as an OS X icon.
	func coverArt() -> NSImage? {
		//If our source image could not be read, then bail out.
		guard let image = sourceImage, image.isValid else {
			return nil
		}
		
		//If our source image already has transparency data,
		//then assume that it already has effects of its own applied and don't process it.
		if type(of: self).imageHasTransparency(image) {
			return image
		}
		
		let coverArt = NSImage()
		coverArt.addRepresentation(representation(for: NSSize(width: 512, height: 512), scale: 2))
		coverArt.addRepresentation(representation(for: NSSize(width: 512, height: 512)))
		coverArt.addRepresentation(representation(for: NSSize(width: 256, height: 256), scale: 2))
		coverArt.addRepresentation(representation(for: NSSize(width: 256, height: 256)))
		coverArt.addRepresentation(representation(for: NSSize(width: 128, height: 128), scale: 2))
		coverArt.addRepresentation(representation(for: NSSize(width: 128, height: 128)))
		coverArt.addRepresentation(representation(for: NSSize(width: 32, height: 32), scale: 2))
		coverArt.addRepresentation(representation(for: NSSize(width: 32, height: 32)))
		return coverArt
	}
	
	/// Returns a cover art image rendered from the specified image to 512, 256, 128 and 32x32 sizes,
	/// suitable for use as an OS X icon.
	///
	/// Note that this returns an NSImage directly, not a `CoverArt` instance.
	@objc(coverArtWithImage:)
	class func coverArt(with image: NSImage) -> NSImage? {
		let generator = self.init(sourceImage: image)
		return generator.coverArt()
	}
	
	/// Returns whether the specified image appears to contain actual transparent/translucent pixels.
	/// This is distinct from whether it has an alpha channel, as the alpha channel may go unused
	/// (e.g. in an opaque image saved as 32-bit PNG.)
	private class func imageHasTransparency(_ image: NSImage) -> Bool {
		var hasTranslucentPixels = false

		//Only bother testing transparency if the image has an alpha channel
		if image.representations.last?.hasAlpha ?? false {
			let imageSize = image.size
			
			//Test 5 pixels in an X pattern: each corner and right in the center of the image.
			let testPoints = [
				NSMakePoint(0,						0),
				NSMakePoint(imageSize.width - 1.0,	0),
				NSMakePoint(0,						imageSize.height - 1.0),
				NSMakePoint(imageSize.width - 1.0,	imageSize.height - 1.0),
				NSMakePoint(imageSize.width * 0.5,	imageSize.height * 0.5)
			]
							
			image.lockFocus()
			for point in testPoints {
				//If any of the pixels appears to be translucent, then stop looking further.
				if let pixel = NSReadPixel(point), pixel.alphaComponent < 0.9 {
					hasTranslucentPixels = true
					break
				}
			}
			image.unlockFocus()
		}

		return hasTranslucentPixels
	}
}
