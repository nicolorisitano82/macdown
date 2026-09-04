//
//  MPSectionFolder.h
//  MacDown
//

#import <Cocoa/Cocoa.h>


/// A heading, and everything that hangs under it until the next one.
@interface MPSection : NSObject

/// One to six.
@property (readonly, nonatomic) NSUInteger level;
/// The heading's text, without its hashes.
@property (readonly, copy, nonatomic) NSString *title;
/// The heading's own line, without the line break that ends it.
@property (readonly, nonatomic) NSRange headingRange;
/// What hangs under it, line breaks included. Empty for an empty section.
@property (readonly, nonatomic) NSRange bodyRange;
/// How many lines that is — what a folded section says about itself.
@property (readonly, nonatomic) NSUInteger bodyLines;

@end


/** Folds a document by its headings, without touching a character of it.
 *
 * A commissioning report of forty pages is read a section at a time or it
 * is not read. Folding hides the body of a section and leaves its heading:
 * the glyphs are suppressed at layout time, the same way the markers are,
 * so the file on disk is the string it always was.
 *
 * A fold is remembered by the heading it belongs to rather than by where
 * that heading sits, so it survives the document being written in above it.
 * Two headings with the same name at the same level therefore fold and
 * unfold together, which is the price of not losing every fold on every
 * keystroke.
 */
@interface MPSectionFolder : NSObject

/// When off nothing folds and this costs nothing.
@property (assign, nonatomic) BOOL enabled;

/// The sections, in the order they appear.
@property (readonly, copy, nonatomic) NSArray<MPSection *> *sections;

/// The characters that are not to be drawn, because they are folded away.
@property (readonly, nonatomic) NSIndexSet *hiddenIndexes;

/// The folded sections, for whoever has to draw something in their place.
@property (readonly, copy, nonatomic) NSArray<MPSection *> *foldedSections;

/// Reads the headings again. Cheap enough for every parse.
- (void)updateWithText:(NSString *)text;

/// The innermost section whose heading or body covers `index`, or nil.
- (MPSection *)sectionCoveringIndex:(NSUInteger)index;

- (BOOL)isFolded:(MPSection *)section;
/// Whether `index` is inside something folded away, rather than merely in it.
- (BOOL)isHiddenIndex:(NSUInteger)index;

/// Folding a section with nothing under it would hide nothing: those say NO.
- (BOOL)fold:(MPSection *)section;
- (BOOL)unfold:(MPSection *)section;
- (BOOL)foldAll;
- (BOOL)unfoldAll;

/** Unfolds whatever hides any part of `range`.
 *
 * What keeps the caret out of the dark: a selection that reaches into a
 * folded section opens it, rather than leaving somebody typing into text
 * they cannot see.
 */
- (BOOL)revealRange:(NSRange)range;

@end
