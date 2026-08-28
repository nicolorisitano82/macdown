//
//  MPSemanticStyler.h
//  MacDown
//

#import <Cocoa/Cocoa.h>
#import "pmh_definitions.h"

/** Draws the Markdown source as what it means.
 *
 * A heading is set larger, emphasis is italic, strong text is bold, code is
 * monospaced. The markup itself is still there and still visible: this is
 * the presentation layer of a WYSIWYG editor without the part that hides
 * anything, which is the part that raises hard questions about where the
 * caret is.
 *
 * Everything is applied as layout manager temporary attributes, so none of
 * it reaches the text storage. The document on disk is the string, and no
 * amount of styling here can change a byte of it. It also keeps the styling
 * out of the undo stack, and lets the whole thing be switched off by
 * dropping the attributes.
 *
 * Colour is deliberately left alone. The syntax highlighter puts the user's
 * chosen theme colours into the text storage, and competing with that would
 * mean picking the theme's fights for it.
 */
@interface MPSemanticStyler : NSObject

- (instancetype)initWithTextView:(NSTextView *)textView;

/// The size everything is scaled from. Set from the editor's base font.
@property (strong, nonatomic) NSFont *baseFont;

/// When off, -applyToElements: removes what it applied and does nothing more.
@property (assign, nonatomic) BOOL enabled;

/** Restyles the whole document from a fresh parse.
 *
 * The list belongs to the highlighter and is read, not kept.
 */
- (void)applyToElements:(pmh_element **)elements;

/// Drops every attribute this styler applied, leaving the rest untouched.
- (void)removeStyling;

@end
