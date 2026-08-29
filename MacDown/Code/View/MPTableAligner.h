//
//  MPTableAligner.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

@class MPMarkerHider;

/** Lines up the columns of a pipe table without touching the source.
 *
 * A table you are still writing has its bars wherever the words left them,
 * and reading a column means counting bars. Every editor that fixes this
 * fixes it by rewriting the file — padding the cells with spaces until they
 * match. That works once and fights you afterwards: it rewrites lines you
 * did not touch, on a timer, while the caret is in them.
 *
 * This pads the drawing instead. Each cell is measured, each column is given
 * the width of its widest cell, and the difference is added to the advance
 * of the last character before the bar. The bars line up; the file still has
 * exactly the characters you typed.
 *
 * Kerning rather than tab stops, because tab stops need tabs and the source
 * has bars. Kerning goes into the text storage, where it can affect layout —
 * a temporary attribute would change nothing at all.
 */
@interface MPTableAligner : NSObject

- (instancetype)initWithTextView:(NSTextView *)textView;

/// When off, -align puts the natural spacing back.
@property (assign, nonatomic) BOOL enabled;

/** Consulted so that hidden markers are not measured.
 *
 * A cell reading `**totale**` is drawn four characters narrower than it is
 * written, and a column measured from the source would be padded to a width
 * nothing occupies.
 */
@property (weak, nonatomic) MPMarkerHider *markerHider;

/// Recomputes every table in the document. Cheap when there are none.
- (void)align;

@end
