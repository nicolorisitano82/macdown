//
//  MPTaskList.h
//  MacDown
//

#import <Foundation/Foundation.h>


/** Moves the finished items of a task list to the end of that list.
 *
 * `index` says which list: the one the caret is in. `replaced` comes back
 * with the range the answer stands in for.
 *
 * Nil when there is nothing to do — no list at that point, or one whose
 * items are already in that order — so the caller can leave the document
 * alone rather than writing it out identical to itself.
 *
 * A command and not an automatism, unlike Bear's: reordering somebody's
 * lines while they are typing them is invasive, and a list is often in the
 * order it is in on purpose.
 *
 * The order within each half is kept — finished items stay in the order
 * they were finished in, as far as the document knows — and an item takes
 * its continuation lines and its nested items with it, since those are
 * part of what it says.
 */
extern NSString *MPTasksMovedToEnd(NSString *text, NSUInteger index,
                                   NSRange *replaced);

/// Whether a line is a task item, of either sort.
extern BOOL MPLineIsTaskItem(NSString *line, BOOL *outDone);
