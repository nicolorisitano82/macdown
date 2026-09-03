//
//  MDDrawioLog.h
//  MacDown Next — draw.io plug-in
//

#import <Cocoa/Cocoa.h>


/** What the import did, step by step, for when it does not work.
 *
 * An import touches a file it did not write, a renderer it does not
 * control and a folder it may not be able to write to. "Non si è potuta
 * disegnare" is true and useless; this is what was actually attempted.
 */
@interface MDDrawioLog : NSObject

/// Adds a line, with the seconds since the import began.
- (void)note:(NSString *)line;
- (void)noteFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

/// Everything noted so far, one line each.
@property (readonly, copy, nonatomic) NSString *text;

/// Shows it in a panel of its own, with a way to copy it.
- (void)showOnWindow:(NSWindow *)window;

@end
