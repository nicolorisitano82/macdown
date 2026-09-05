//
//  MPInstructionsViewController.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

@class MPInstructionFile;
@class MPInstructionNode;
@class MPInstructionIssue;


/** What an agent would read, for the document in front.
 *
 * Three lists in one: the files that apply and in what order, the tree of
 * what they import, and what is wrong with the set. Clicking a row opens
 * that file — including one that is not there yet, which is where you would
 * write it.
 */
@interface MPInstructionsViewController : NSViewController

- (instancetype)initWithHierarchy:(NSArray<MPInstructionFile *> *)hierarchy
                             tree:(MPInstructionNode *)tree
                           issues:(NSArray<MPInstructionIssue *> *)issues
                           chosen:(void (^)(NSURL *fileURL))chosen;

@end
