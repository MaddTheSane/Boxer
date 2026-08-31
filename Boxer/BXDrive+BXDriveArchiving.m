/*
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXDrive+BXDriveArchiving.h"
#import "BXDrivePrivate.h"
#import "ADBFilesystem.h"
#import "Boxer-Swift.h"


/// Used when decoding drive records from previous Boxer versions,
/// to decide whether to resolve bookmarks or aliases.
#define BXCurrentDriveEncodingVersion 1400
#define BXFirstBookmarkSupportingVersion 1400


/// Used for decoding NDAlias-encoded paths from previous Boxer versions.
@interface __NDAliasDecoder : NSObject
@property (copy) NSData *aliasData;
@end

@implementation __NDAliasDecoder

/// NDAlias encoded its internal alias record as an NSData object;
/// we no longer use NDAlias, but we can convert its alias record
/// into modern bookmark data. This class is substituted for NDAlias
/// during decoding.
- (id) initWithCoder: (NSCoder *)aDecoder
{
    if (self = [super init]) {
        self.aliasData = [aDecoder decodeDataObject];
    }
    return self;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (NSUInteger)hash
{
    return _aliasData.hash;
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[__NDAliasDecoder class]]) {
        return [_aliasData isEqualToData:[(__NDAliasDecoder*)object aliasData]];
    }
    return NO;
}

- (NSURL*)URLByResolvingAliasRecordWithOptions: (NSURLBookmarkResolutionOptions)options
                                 relativeToURL: (NSURL *)relativeURL
                           bookmarkDataIsStale: (out BOOL *)isStale
                                         error: (out NSError **)outError
{
    return [NSURL URLByResolvingAliasRecord: self.aliasData options: options relativeToURL: relativeURL bookmarkDataIsStale: isStale error: outError];
}

@end


@implementation BXDrive (BXDriveArchiving)

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (id) initWithCoder: (NSCoder *)aDecoder
{
    if ((self = [self init]))
    {
        NSError *err;
        NSInteger encodingVersion = [aDecoder decodeIntegerForKey: @"encodingVersion"];
        if (encodingVersion > BXCurrentDriveEncodingVersion) {
            [aDecoder failWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSCoderReadCorruptError userInfo:@{NSLocalizedDescriptionKey: [NSString localizedStringWithFormat:NSLocalizedString(@"Unable to decode drive: encoding version %ld is higher than supported version %ld.", @"Unable to decode drive: encoding version %ld is higher than supported version %ld."), (long)encodingVersion, (long)BXCurrentDriveEncodingVersion], NSDebugDescriptionErrorKey: [NSString stringWithFormat:@"Unable to decode drive: encoding version %ld is higher than supported version %ld.", (long)encodingVersion, (long)BXCurrentDriveEncodingVersion]}]];
            return nil;
        }
        
        //Paths were encoded as OS X 10.6+ bookmark data
        if (encodingVersion >= BXFirstBookmarkSupportingVersion)
        {
#define URL_FROM_BOOKMARK(bookmark) ((NSURL *)[NSURL URLByResolvingBookmarkData: bookmark options: NSURLBookmarkResolutionWithoutUI relativeToURL: nil bookmarkDataIsStale: NULL error: &err])
            
            NSData *sourceBookmarkData = [aDecoder decodeObjectOfClass: [NSData class] forKey: @"sourceURLBookmark"];
            if (sourceBookmarkData)
            {
                self.sourceURL = URL_FROM_BOOKMARK(sourceBookmarkData);
            }
            else {
                err = [NSError errorWithDomain:NSCocoaErrorDomain code:NSCoderValueNotFoundError userInfo:nil];
            }
            //If we couldn't resolve the bookmark to this drive's path, this drive is useless
            //and we shouldn't bother continuing.
            if (self.sourceURL == nil)
            {
                [aDecoder failWithError:err];
                return nil;
            }
            
            NSData *shadowBookmarkData = [aDecoder decodeObjectOfClass: [NSData class] forKey: @"shadowURLBookmark"];
            if (shadowBookmarkData)
            {
                self.shadowURL = URL_FROM_BOOKMARK(shadowBookmarkData);
            }
            
            NSData *mountPointBookmarkData = [aDecoder decodeObjectOfClass: [NSData class] forKey: @"mountPointURLBookmark"];
            if (mountPointBookmarkData)
            {
                self.mountPointURL = URL_FROM_BOOKMARK(mountPointBookmarkData);
            }
            
            NSSet *equivalentURLBookmarks = [aDecoder decodeObjectOfClasses: [NSSet setWithObjects: [NSData class], [NSSet class], nil] forKey: @"equivalentURLBookmarks"];
            if (equivalentURLBookmarks)
            {
                for (NSData *bookmarkData in equivalentURLBookmarks)
                {
                    NSURL *equivalentURL = URL_FROM_BOOKMARK(bookmarkData);
                    if (equivalentURL)
                        [self.filesystem addRepresentedURL: equivalentURL];
                }
            }
        }
        
        //Paths were encoded as legacy alias data
        else
        {
#define URL_FROM_ALIAS(alias) ((NSURL *)[alias URLByResolvingAliasRecordWithOptions: NSURLBookmarkResolutionWithoutUI relativeToURL: nil bookmarkDataIsStale: NULL error: &err])
            
            //IMPLEMENTATION NOTE: previous Boxer versions encoded paths as NDAlias instances.
            //We no longer use NDAlias in favour of NSURL bookmarks, but we can still resolve encoded
            //NDAlias instances as NSData instances representing serialized alias records.
            if ([aDecoder respondsToSelector: @selector(setClass:forClassName:)])
                [(NSKeyedUnarchiver *)aDecoder setClass: [__NDAliasDecoder class]
                                           forClassName: @"NDAlias"];
            
            __NDAliasDecoder *sourceAliasData = [aDecoder decodeObjectOfClass: [__NDAliasDecoder class] forKey: @"path"];
            if (sourceAliasData)
            {
                self.sourceURL = URL_FROM_ALIAS(sourceAliasData);
            }
            else {
                err = [NSError errorWithDomain:NSCocoaErrorDomain code:NSCoderValueNotFoundError userInfo:nil];
            }
            
            if (self.sourceURL == nil)
            {
                [aDecoder failWithError:err];
                return nil;
            }
            
            __NDAliasDecoder *shadowAliasData = [aDecoder decodeObjectOfClass: [__NDAliasDecoder class] forKey: @"shadowPath"];
            if (shadowAliasData)
                self.shadowURL = URL_FROM_ALIAS(shadowAliasData);
            
            __NDAliasDecoder *mountPointAliasData = [aDecoder decodeObjectOfClass: [__NDAliasDecoder class] forKey: @"mountPoint"];
            if (mountPointAliasData)
                self.mountPointURL = URL_FROM_ALIAS(mountPointAliasData);
            
            NSSet<__NDAliasDecoder*> *pathAliases = [aDecoder decodeObjectOfClasses: [NSSet setWithObjects: [NSSet class], [__NDAliasDecoder class], nil] forKey: @"pathAliases"];
            for (__NDAliasDecoder *aliasData in pathAliases)
            {
                NSURL *equivalentURL = URL_FROM_ALIAS(aliasData);
                if (equivalentURL)
                    [self.filesystem addRepresentedURL: equivalentURL];
            }
        }
        
        self.type = [aDecoder decodeIntegerForKey: @"type"];
        
        NSString *letter = [aDecoder decodeObjectOfClass: [NSString class] forKey: @"letter"];
        if (letter) self.letter = letter;
        
        NSString *title = [aDecoder decodeObjectOfClass: [NSString class] forKey: @"title"];
        if (title) self.title = title;
        
        NSString *volumeLabel = [aDecoder decodeObjectOfClass: [NSString class] forKey: @"volumeLabel"];
        if (volumeLabel) self.volumeLabel = volumeLabel;
        
        if ([aDecoder containsValueForKey: @"freeSpace"])
            self.freeSpace  = [aDecoder decodeIntegerForKey: @"freeSpace"];
        
        if ([aDecoder containsValueForKey: @"usesCDAudio"])
            self.usesCDAudio = [aDecoder decodeBoolForKey: @"usesCDAudio"];
        
        self.readOnly   = [aDecoder decodeBoolForKey: @"readOnly"];
        self.locked     = [aDecoder decodeBoolForKey: @"locked"];
        self.hidden     = [aDecoder decodeBoolForKey: @"hidden"];
        self.mounted    = [aDecoder decodeBoolForKey: @"mounted"];
    }
    
    return self;
}

- (void) encodeWithCoder: (NSCoder *)aCoder
{
    NSAssert1(self.sourceURL != nil, @"Attempt to serialize virtual drive or drive missing URL: %@", self);
    
#define BOOKMARK_FROM_URL(url) ((NSData *)[url bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil relativeToURL: nil error: NULL])
    
    //Convert all paths to bookmarks before encoding, so that we can track them if they move.
    NSData *sourceURLBookmark = BOOKMARK_FROM_URL(self.sourceURL);
    [aCoder encodeObject: sourceURLBookmark forKey: @"sourceURLBookmark"];
    
    [aCoder encodeInteger: self.type forKey: @"type"];
    
    if (self.letter)
        [aCoder encodeObject: self.letter forKey: @"letter"];
    
    if (self.shadowURL)
    {
        NSData *shadowURLBookmark = BOOKMARK_FROM_URL(self.shadowURL);
        [aCoder encodeObject: shadowURLBookmark forKey: @"shadowURLBookmark"];
    }
    
    //For other paths and strings, only bother recording them if they have been
    //manually changed from their autodetected versions.
    if (self.mountPointURL && !self.hasAutodetectedMountPoint)
    {
        NSData *mountPointURLBookmark = BOOKMARK_FROM_URL(self.mountPointURL);
        [aCoder encodeObject: mountPointURLBookmark forKey: @"mountPointURLBookmark"];
    }
    
    if (self.title && !self.hasAutodetectedTitle)
    {
        [aCoder encodeObject: self.title forKey: @"title"];
    }
    
    if (self.volumeLabel && !self.hasAutodetectedVolumeLabel)
        [aCoder encodeObject: self.volumeLabel forKey: @"volumeLabel"];
    
    if (self.filesystem.representedURLs.count)
    {
        //TODO: filter out URLs that are already represented by the mount point et. al.
        NSMutableSet *equivalentURLBookmarks = [[NSMutableSet alloc] initWithCapacity: self.filesystem.representedURLs.count];
        
        for (NSURL *equivalentURL in self.filesystem.representedURLs)
        {
            NSData *bookmarkData = BOOKMARK_FROM_URL(equivalentURL);
            [equivalentURLBookmarks addObject: bookmarkData];
        }
        
        [aCoder encodeObject: equivalentURLBookmarks forKey: @"equivalentURLBookmarks"];
    }
    
    //For scalar properties, we only bother recording exceptions to the defaults
    if (self.freeSpace != BXDefaultFreeSpace)
        [aCoder encodeInteger: self.freeSpace forKey: @"freeSpace"];
    
    if (self.readOnly)
        [aCoder encodeBool: self.readOnly forKey: @"readOnly"];
    
    if (self.hidden)
        [aCoder encodeBool: self.hidden forKey: @"hidden"];
    
    if (self.locked)
        [aCoder encodeBool: self.locked forKey: @"locked"];
    
    if (self.isMounted)
        [aCoder encodeBool: self.isMounted forKey: @"mounted"];
    
    if (!self.usesCDAudio)
        [aCoder encodeBool: self.usesCDAudio forKey: @"usesCDAudio"];
    
    [aCoder encodeInteger: BXCurrentDriveEncodingVersion forKey: @"encodingVersion"];
}

@end
