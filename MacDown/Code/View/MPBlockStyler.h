//
//  MPBlockStyler.h
//  MacDown
//

#import <Cocoa/Cocoa.h>
#import "pmh_definitions.h"

/** Lays out the blocks: indents, spacing, and the bar beside a quotation.
 *
 * The part of a WYSIWYG editor that an editor theme cannot reach. A theme
 * can colour a list marker but not indent the lines under it, and there is
 * nothing in its format that draws anything.
 *
 * Paragraph styles go into the text storage, because that is the only place
 * they affect layout, and they are derived from whatever style is already
 * there rather than replacing it — the highlighter puts the reader's line
 * spacing in the same attribute, and overwriting it would quietly undo a
 * setting from the preferences.
 *
 * As with everything else here, the document is still the string: none of
 * this reaches the file.
 */
@interface MPBlockStyler : NSObject

- (instancetype)initWithTextView:(NSTextView *)textView;

/// When off, -applyToElements: puts the plain paragraph style back.
@property (assign, nonatomic) BOOL enabled;

/// The reader's editor font. Indents are measured in its character widths.
@property (strong, nonatomic) NSFont *baseFont;


/** Restyles the blocks from a fresh parse.
 *
 * The list belongs to the highlighter and is read, not kept.
 */
- (void)applyToElements:(pmh_element **)elements;

@end
