//
//  AppDelegate.h
//  SoundPusher
//
//  Created by Daniel Vollmer on 14/12/2015.
//
//

#import <Cocoa/Cocoa.h>

/// Posted (on the main thread) whenever an audio chain starts or stops. Added for SurroundBridge.
extern NSNotificationName const SBChainsDidChangeNotification;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>

/// Name of the output device audio is currently being sent to, or nil if nothing is running. Added for SurroundBridge.
- (nullable NSString *)activeOutputName;

@end

