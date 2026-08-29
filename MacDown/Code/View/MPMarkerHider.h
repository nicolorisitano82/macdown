//
//  MPMarkerHider.h
//  MacDown
//

#import <Cocoa/Cocoa.h>
#import "pmh_definitions.h"

/** Hides the Markdown markers, and shows them back when the caret arrives.
 *
 * `**bold**` reads as bold with no asterisks around it, until you put the
 * caret in it — then the asterisks come back, because you cannot edit what
 * you cannot see. That reveal is the whole design: a marker is hidden only
 * while nobody is working on it.
 *
 * The characters are still there. Nothing is deleted, nothing is inserted,
 * and the document on disk is the same string it always was: the glyphs are
 * suppressed at layout time, through the layout manager's glyph generation
 * hook. That is also why this needs TextKit 1, which the editor is already
 * using — TextKit 2 has no equivalent.
 *
 * Emphasis, strong and inline code only. Links and images have two parts, a
 * text and a destination, and hiding either raises a question this does not
 * answer yet.
 */
@interface MPMarkerHider : NSObject <NSLayoutManagerDelegate>

- (instancetype)initWithTextView:(NSTextView *)textView;

/// When off, every marker is visible and this costs nothing.
@property (assign, nonatomic) BOOL enabled;

/** Recomputes which characters are markers, from a fresh parse.
 *
 * The list belongs to the highlighter and is read, not kept.
 */
- (void)updateWithElements:(pmh_element **)elements;

/// Reveals the markers around the caret and hides the rest. Cheap.
- (void)selectionDidChange;

/** The construct whose delimiter covers `index`, if one does.
 *
 * Lets the editor treat a marker as one thing when it is deleted: pressing
 * backspace over the last asterisk of `**bold**` should leave `bold`, not
 * `**bold*`. Returns the whole construct and the length of one delimiter,
 * which is all that is needed to rebuild it without them.
 */
- (BOOL)construct:(NSRange *)outRange
     markerLength:(NSUInteger *)outLength
    coveringMarkerAtIndex:(NSUInteger)index;

@end
