//
//  MPBacklinksViewController.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

@class MPBacklink;


/** The documents that cite this one, and going to one of them.
 *
 * A folder of reports that refer to each other can be read in one
 * direction only: a link says where it goes, and nothing says what points
 * here. That question was a `grep`.
 */
@interface MPBacklinksViewController : NSViewController

- (instancetype)initWithBacklinks:(NSArray<MPBacklink *> *)backlinks
                          counted:(NSUInteger)documentsRead
                           chosen:(void (^)(MPBacklink *link))chosen;

@end
