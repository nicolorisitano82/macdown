//
//  MPProseIssuesViewController.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

@class MPProseIssue;


/** The list behind the tally: every flagged word, and where it is.
 *
 * The tally said "spie del passivo: 3" and left the finding of the three to
 * you, in a document where the underlines may be pages apart. Clicking a
 * line here goes to it.
 */
@interface MPProseIssuesViewController : NSViewController

/** `chosen` is called with the one clicked, for the editor to go there.
 *
 * `text` is the document as it is now: the line numbers are worked out from
 * it, and they are what makes a list of "è stato" tellable apart.
 */
- (instancetype)initWithIssues:(NSArray<MPProseIssue *> *)issues
                        inText:(NSString *)text
                       summary:(NSString *)summary
                        chosen:(void (^)(MPProseIssue *issue))chosen;

@end
