//
//  MPSemanticStyler.h
//  MacDown
//

#import <Cocoa/Cocoa.h>
#import "pmh_definitions.h"

@class HGMarkdownHighlightingStyle;

/** Makes an editor theme's heading sizes follow the reader's font size.
 *
 * A theme states its sizes in points — Tomorrow+ sets H1 to 24, H2 to 20,
 * and so on — and the highlighter applies them exactly as written. That is
 * fine at the default 14pt body, which is what theme authors design against,
 * and wrong everywhere else: at 20pt the headings barely stand out, and past
 * 24pt a heading is smaller than the text around it. The theme cannot fix
 * this itself, because nothing in the format records the body size its
 * numbers were chosen for.
 *
 * So the theme's proportions are kept and re-scaled: a heading the author
 * made 1.7 times the body stays 1.7 times the body. At the default size
 * nothing changes at all, which is the point — this corrects a defect
 * rather than imposing a look.
 *
 * Nothing else is touched. Weight, slant, colour and the code background are
 * all expressible in the theme format, and belong to whoever wrote the
 * theme. Written into the text storage, the way the highlighter writes
 * the theme itself: layout manager temporary attributes are display only
 * and cannot change a size. It never reaches the file — the document is
 * saved as its string.
 */
@interface MPSemanticStyler : NSObject

- (instancetype)initWithTextView:(NSTextView *)textView;

/// The reader's editor font. Sizes are scaled relative to it.
@property (strong, nonatomic) NSFont *baseFont;

/// The highlighter's parsed theme, read for the sizes it declares.
@property (copy, nonatomic) NSArray<HGMarkdownHighlightingStyle *> *themeStyles;

/// When off, -applyToElements: removes what it applied and stops.
@property (assign, nonatomic) BOOL enabled;

/** Restyles the document from a fresh parse.
 *
 * The list belongs to the highlighter and is read, not kept.
 */
- (void)applyToElements:(pmh_element **)elements;

/// Drops every attribute this styler applied, leaving the rest untouched.
- (void)removeStyling;

@end
