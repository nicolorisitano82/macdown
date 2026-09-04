//
//  MPUpdateController.h
//  MacDown
//

#import <Cocoa/Cocoa.h>


/** Looking for a newer MacDown Next, and fetching it when asked.
 *
 * The whole of it is four questions, in this order: is there one, shall I
 * fetch it, here it is — shall I open it, and then the application gets out
 * of the way. Nothing is installed behind anybody's back: the disk image
 * lands in Downloads like any other download, and dragging the application
 * across is still done by hand.
 */
@interface MPUpdateController : NSObject

+ (instancetype)sharedInstance;

/// Asked for out loud, from the menu or from Preferences: says so even when
/// there is nothing new, and shows what went wrong when something does.
- (IBAction)checkForUpdates:(id)sender;

/// At launch: only if the preference allows it, only once a day, and
/// silent unless there is something to say.
- (void)checkQuietlyIfDue;

/// Whether a check or a download is going on, so two do not start at once.
@property (readonly, nonatomic, getter=isBusy) BOOL busy;

@end
