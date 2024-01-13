/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */


#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// BXBootlegCoverArt is similar to BXCoverArt, but creates generic cover art based on a title string
/// rather than a box image. Implementing classes create artwork to resemble bootleg floppy disks and
/// CD-ROM jewel-cases.
@protocol BXBootlegCoverArt <NSObject>

/// Return a new BXBootlegCoverArt implementor using the specified title.
- (instancetype) initWithTitle: (NSString *)coverTitle;

/// The game title to display on this cover art.
@property (copy, nonatomic) NSString *title;

/// Draws the source image as cover art into the specified frame in the current graphics context.
- (void) drawInRect: (NSRect)frame;

/// Returns a cover art image representation from the instance's title rendered at the specified size and scale.
- (NSImageRep *) representationForSize: (NSSize)iconSize scale: (CGFloat)scale;

/// Returns a cover art image rendered from the instance's title, suitable for use as an OS X icon.
- (NSImage *) coverArt;

/// Returns a cover art image rendered from the specified title, suitable for use as an OS X icon.
+ (NSImage *) coverArtWithTitle: (NSString *)title;

@end

NS_ASSUME_NONNULL_END
