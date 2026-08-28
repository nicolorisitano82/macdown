//
//  MPPlugInsWindowController.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

/** The plug-in manager.
 *
 * Plug-ins were previously invisible unless you knew the folder they live in
 * and restarted the application after touching it. This lists what is
 * installed, lets each one be switched off without deleting it, and puts
 * adding and removing behind buttons.
 */
@interface MPPlugInsWindowController : NSWindowController

+ (instancetype)sharedController;
- (void)showPanel:(id)sender;

@end
