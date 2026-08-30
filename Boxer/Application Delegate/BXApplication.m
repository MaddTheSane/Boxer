/* 
 Copyright (c) 2013 Alun Bestor and contributors. All rights reserved.
 This source file is released under the GNU General Public License 2.0. A full copy of this license
 can be found in this XCode project at Resources/English.lproj/BoxerHelp/pages/legalese.html, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXApplication.h"
#import "BXBaseAppController.h"
#import "BXBaseAppController+BXHotKeys.h"
#import "BXEmulatorErrors.h"
#import <objc/runtime.h>

static NSString *BXApplicationCrashDumpSafeFilenameComponent(NSString *string)
{
    NSMutableCharacterSet *allowedCharacters = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowedCharacters addCharactersInString: @"-_. "];
    
    NSMutableString *result = [NSMutableString stringWithCapacity: string.length];
    for (NSUInteger index = 0; index < string.length; index++)
    {
        unichar character = [string characterAtIndex: index];
        if ([allowedCharacters characterIsMember: character])
            [result appendFormat: @"%C", character];
        else
            [result appendString: @"-"];
    }
    
    return result;
}

static BOOL BXApplicationIsReportingEmulatorExceptionFromSession(void)
{
    for (NSString *symbol in NSThread.callStackSymbols)
    {
        if ([symbol containsString: @"_reportEmulatorException:"])
            return YES;
    }
    
    return NO;
}

static NSURL *BXApplicationWriteFallbackCrashDumpForException(NSException *exception)
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *applicationSupportURL = [manager URLsForDirectory: NSApplicationSupportDirectory
                                                   inDomains: NSUserDomainMask].firstObject;
    if (!applicationSupportURL)
        return nil;
    
    NSURL *dumpFolderURL = [[applicationSupportURL URLByAppendingPathComponent: @"Boxer"
                                                                   isDirectory: YES] URLByAppendingPathComponent: @"Crash Dumps"
                                                                                                      isDirectory: YES];
    
    NSError *folderError = nil;
    if (![manager createDirectoryAtURL: dumpFolderURL
           withIntermediateDirectories: YES
                            attributes: nil
                                 error: &folderError])
    {
        NSLog(@"Could not create Boxer fallback crash dump folder at %@: %@", dumpFolderURL.path, folderError);
        return nil;
    }
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier: @"en_US_POSIX"];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH.mm.ss";
    
    NSString *safeName = BXApplicationCrashDumpSafeFilenameComponent(exception.name ?: @"Exception");
    NSString *fileName = [NSString stringWithFormat: @"Boxer Fallback Crash %@ - %@.txt",
                                                    [dateFormatter stringFromDate: [NSDate date]],
                                                    safeName];
    NSURL *dumpURL = [dumpFolderURL URLByAppendingPathComponent: fileName];
    
    NSMutableString *dump = [NSMutableString string];
    [dump appendString: @"Boxer Fallback Crash Dump\n"];
    [dump appendString: @"==========================\n\n"];
    [dump appendFormat: @"Created: %@\n", [NSDate date]];
    [dump appendFormat: @"Boxer version: %@ (%@)\n",
                        [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"] ?: @"unknown",
                        [[NSBundle mainBundle] objectForInfoDictionaryKey: (NSString *)kCFBundleVersionKey] ?: @"unknown"];
    
    [dump appendString: @"\nException\n"];
    [dump appendString: @"---------\n"];
    [dump appendFormat: @"Name: %@\n", exception.name ?: @"unknown"];
    [dump appendFormat: @"Reason: %@\n", exception.reason ?: @"none"];
    [dump appendFormat: @"Source file: %@\n", [exception.userInfo objectForKey: @"file"] ?: @"unknown"];
    [dump appendFormat: @"Function: %@\n", [exception.userInfo objectForKey: @"function"] ?: @"unknown"];
    [dump appendFormat: @"Line: %@\n", [exception.userInfo objectForKey: @"line"] ?: @"unknown"];
    
    [dump appendString: @"\nException call stack symbols\n"];
    [dump appendString: @"----------------------------\n"];
    if (exception.callStackSymbols.count)
        [dump appendFormat: @"%@\n", [exception.callStackSymbols componentsJoinedByString: @"\n"]];
    else
        [dump appendString: @"none\n"];
    
    [dump appendString: @"\nCurrent thread call stack symbols\n"];
    [dump appendString: @"---------------------------------\n"];
    [dump appendFormat: @"%@\n", [NSThread.callStackSymbols componentsJoinedByString: @"\n"]];
    
    NSError *writeError = nil;
    if (![dump writeToURL: dumpURL
               atomically: YES
                 encoding: NSUTF8StringEncoding
                    error: &writeError])
    {
        NSLog(@"Could not write Boxer fallback crash dump to %@: %@", dumpURL.path, writeError);
        return nil;
    }
    
    NSLog(@"Saved Boxer fallback crash dump to %@", dumpURL.path);
    return dumpURL;
}

static BOOL BXApplicationWriteLocalReportFromLegacyBugReportURL(NSURL *URL)
{
    if (![[URL.host lowercaseString] isEqualToString: @"boxerapp.com"] || ![URL.path isEqualToString: @"/report-an-issue"])
        return NO;
    
    NSURLComponents *components = [NSURLComponents componentsWithURL: URL resolvingAgainstBaseURL: NO];
    NSString *title = nil;
    NSString *body = nil;
    for (NSURLQueryItem *item in components.queryItems)
    {
        if ([item.name isEqualToString: @"title"])
            title = item.value;
        else if ([item.name isEqualToString: @"body"])
            body = item.value;
    }
    
    BXBaseAppController *controller = (BXBaseAppController *)NSApp.delegate;
    if ([controller respondsToSelector: @selector(reportIssueWithTitle:body:)])
    {
        [controller reportIssueWithTitle: title body: body];
        return YES;
    }
    
    return NO;
}

@implementation NSWorkspace (BXLocalReports)

+ (void) load
{
    Method originalMethod = class_getInstanceMethod(self, @selector(openURL:));
    Method replacementMethod = class_getInstanceMethod(self, @selector(bx_openURL:));
    method_exchangeImplementations(originalMethod, replacementMethod);
}

- (BOOL) bx_openURL: (NSURL *)URL
{
    if (BXApplicationWriteLocalReportFromLegacyBugReportURL(URL))
        return YES;
    
    return [self bx_openURL: URL];
}

@end

@implementation BXApplication

- (void) reportException: (NSException *)exception
{
    if ([exception.name isEqualToString: BXEmulatorUnrecoverableException] && !BXApplicationIsReportingEmulatorExceptionFromSession())
    {
        BXApplicationWriteFallbackCrashDumpForException(exception);
    }
    
    [super reportException: exception];
}

- (void) sendEvent: (NSEvent *)theEvent
{
    //Dispatch media key events.
    if (self.delegate && theEvent.type == NSEventTypeSystemDefined && theEvent.subtype == 8)
    {
        [(BXBaseAppController *)self.delegate mediaKeyPressed: theEvent];
        return;
    }
    
    //Fix Cmd-modified key-up events not being dispatched to the key window.
    else if (self.keyWindow && theEvent.type == NSEventTypeKeyUp && (theEvent.modifierFlags & NSEventModifierFlagCommand) == NSEventModifierFlagCommand)
    {
        //NOTE: unlike a regular keyUp, the event will have a nil window.
        //If this becomes an issue, we could recreate the event and dispatch the copy.
		[self.keyWindow sendEvent: theEvent];
	}
    
    else
    {
		[super sendEvent: theEvent];
	}
}

@end
