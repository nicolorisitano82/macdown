//
//  MPModelsWindowController.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

/** The models panel: what is installed, what can be fetched, and which one
 *  the writing commands use.
 *
 * Built in code rather than in a nib. The list in it is as long as the
 * number of models installed plus the number offered, which is not known
 * when a nib is drawn; and a nib would be one more file to keep in step
 * with twenty-six localisations for the sake of a window that is a list
 * and four buttons.
 */
@interface MPModelsWindowController : NSWindowController

+ (instancetype)sharedController;

/// Brings it up, and refreshes what it shows.
- (void)showPanel;

@end
