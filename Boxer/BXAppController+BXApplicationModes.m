/* 
 Boxer is copyright 2010-2011 Alun Bestor and contributors.
 Boxer is released under the GNU General Public License 2.0. A full copy of this license can be
 found in this XCode project at Resources/English.lproj/GNU General Public License.txt, or read
 online at [http://www.gnu.org/licenses/gpl-2.0.txt].
 */

#import "BXAppController+BXApplicationModes.h"
#import "BXInspectorController.h"
#import "BXDOSWindowController.h"
#import "BXInputController.h"
#import "BXSession.h"

#import "SystemEvents.h"
#import <Carbon/Carbon.h> //For SetSystemUIMode()


#pragma mark -
#pragma mark Internal constants

//We use a short delay before syncing spaces shortcuts,
//to avoid toggling them needlessly when switching from
//one DOS window to another
//(e.g. during transitions to/from fullscreen mode)
#define BXSpacesShortcutOverrideDelay 0.1

//The user defaults key under which we store any Spaces arrow-key modifiers that we have overridden.
NSString * const BXPreviousSpacesArrowKeyModifiersKey = @"previousSpacesArrowKeyModifiers";


@implementation BXAppController (BXApplicationModes)

+ (NSArray *) safeKeyModifiersFromModifiers: (NSArray *)modifiers
{	
	NSArray *safeModifiers = modifiers;
	
	//If there's more than one modifier key required, or none required,
	//then the original set is safe already.
	if ([modifiers count] == 1)
	{
		SystemEventsEpmd soleModifier = [[modifiers lastObject] unsignedIntegerValue];
		
		//If the sole modifier is the Ctrl, Opt or Shift key, then it'll likely conflict.
		if (soleModifier == SystemEventsEpmdControl || soleModifier == SystemEventsEpmdOption || soleModifier == SystemEventsEpmdShift)
		{
			//We can make the modifiers safe by combining with the Command key.
			safeModifiers = [modifiers arrayByAddingObject: [NSNumber numberWithUnsignedInteger: SystemEventsEpmdCommand]];
		}		
	}
	return safeModifiers;
}

- (void) addApplicationModeObservers
{
	//Listen out for UI notifications so that we can coordinate window behaviour
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	
	[center addObserver: self selector: @selector(windowDidBecomeKey:)
				   name: NSWindowDidBecomeKeyNotification
				 object: nil];
	
	[center addObserver: self selector: @selector(windowDidResignKey:)
				   name: NSWindowDidResignKeyNotification
				 object: nil];
	
	[center addObserver: self selector: @selector(syncApplicationPresentationMode)
				   name: BXSessionWillEnterFullScreenNotification
				 object: nil];
	
	[center addObserver: self selector: @selector(syncApplicationPresentationMode)
				   name: BXSessionDidExitFullScreenNotification
				 object: nil];
	
	[center addObserver: self selector: @selector(sessionDidLockMouse:)
				   name: BXSessionDidLockMouseNotification
				 object: nil];
	
	[center addObserver: self selector: @selector(sessionDidUnlockMouse:)
				   name: BXSessionDidUnlockMouseNotification
				 object: nil];
}

- (void) syncApplicationPresentationMode
{
	BXDOSWindowController *currentController = [[self currentSession] DOSWindowController];
	
	if ([currentController isFullScreen])
	{
		if ([[currentController inputController] mouseLocked])
		{
			//When the session is fullscreen and mouse-locked, hide all UI components
			SetSystemUIMode(kUIModeAllHidden, 0);
		}
		else
		{
			//When the session is fullscreen but the mouse is unlocked,
			//show the OS X menu but hide the Dock until it is moused over
			SetSystemUIMode(kUIModeContentSuppressed, 0);
		}
	}
	else
	{
		//When there is no fullscreen session, show all UI components normally.
		SetSystemUIMode(kUIModeNormal, 0);
	}
}

- (void) syncSpacesKeyboardShortcuts
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray *oldModifiers = [defaults arrayForKey: BXPreviousSpacesArrowKeyModifiersKey];
	
	BOOL DOSWindowIsKey	= [[[NSApp keyWindow] windowController] isKindOfClass: [BXDOSWindowController class]];
	
	//IMPLEMENTATION NOTE: if we crashed while Boxer had suppressed the shortcuts,
	//then hasSyncedSpacesShortcuts will initially be false, but we'll still have
	//leftover modifiers that we'll want to restore.
	BOOL isSynced = hasSyncedSpacesShortcuts || (oldModifiers != nil);
	
	//If we're already in sync, then don't bother continuing further.
	if (DOSWindowIsKey != isSynced)
	{
		SystemEventsApplication *systemEvents = [SBApplication applicationWithBundleIdentifier: @"com.apple.systemevents"];
		SystemEventsSpacesShortcut *arrowKeyPrefs = systemEvents.exposePreferences.spacesPreferences.arrowKeyModifiers;
		
		//IMPLEMENTATION NOTE: in an ideal world we'd access the keyModifiers property of arrowKeyPrefs.
		//However, this has been defined in the System Events header as a single OSType constant, when in
		//fact the real property returns an array of constants. In order to set and get this array,
		//we need to use a direct reference to the property as seen below.
		SBObject *keyMods = [arrowKeyPrefs propertyWithCode: 'spky'];
		
		
		//A Boxer session has the keyboard focus, but we haven't yet suppressed the Spaces shortcuts:
		//if we need to, apply the suppression now, and keep a record of the old values
		if (DOSWindowIsKey && !isSynced)
		{
			[systemEvents setSendMode: kAEWaitReply];
			 //In case System Events has stopped responding, don't wait forever for it
			[systemEvents setTimeout: 0.1f];
			
			//The key modifiers are returned as an array of NSAppleEventDescriptors: getting the enumCodeValue
			//from each of these yields an array of NSNumbers, which are easier for us to work with.
			NSArray *currentModifiers = [(SBElementArray *)[keyMods get] valueForKey: @"enumCodeValue"];
			NSArray *safeModifiers = [[self class] safeKeyModifiersFromModifiers: currentModifiers];
			
			if (![safeModifiers isEqualToArray: currentModifiers])
			{
				[systemEvents setSendMode: kAENoReply];
				
				[keyMods setTo: safeModifiers];
				[defaults setObject: currentModifiers forKey: BXPreviousSpacesArrowKeyModifiersKey];
				
				//IMPLEMENTATION NOTE: we commit the user defaults to disk immediately, in case
				//we crash while we still have keyboard focus. This way, when the user next starts
				//up Boxer, it will notice that there's an overridden modifier and restore it below.
				[defaults synchronize];
			}
			//Flag that we've synced even if we didn't need to make any changes, so that we don't
			//have to keep checking the shortcuts each time.
			hasSyncedSpacesShortcuts = YES;
		}
		
		//A Boxer session has lost keyboard focus, but we're still suppressing Spaces shortcuts:
		//remove the suppression, revert the shortcuts to what they were, and erase our User Defaults
		//backup of the key modifiers.
		else if (!DOSWindowIsKey && isSynced)
		{
			[systemEvents setSendMode: kAENoReply];
			[keyMods setTo: oldModifiers];
			[defaults removeObjectForKey: BXPreviousSpacesArrowKeyModifiersKey];
			[defaults synchronize];
			
			hasSyncedSpacesShortcuts = NO;
		}
	}
}

- (void) windowDidBecomeKey: (NSNotification *)notification
{
	[self performSelector: @selector(syncSpacesKeyboardShortcuts) withObject: nil afterDelay: BXSpacesShortcutOverrideDelay];
}

- (void) windowDidResignKey: (NSNotification *)notification
{
	[self performSelector: @selector(syncSpacesKeyboardShortcuts) withObject: nil afterDelay: BXSpacesShortcutOverrideDelay];
}

- (void) sessionDidUnlockMouse: (NSNotification *)notification
{
	[self syncApplicationPresentationMode];
	
	//If we were previously concealing the Inspector, then reveal it now
	[[BXInspectorController controller] revealIfHidden];
}

- (void) sessionDidLockMouse: (NSNotification *)notification
{
	[self syncApplicationPresentationMode];
	
	//Conceal the Inspector panel while the mouse is locked
	[[BXInspectorController controller] hideIfVisible];
}

@end
