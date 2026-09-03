//
//  MPCodeLanguages.h
//  MacDown
//

#import <Foundation/Foundation.h>


/** One entry in the list of languages a fenced block can be marked with.
 *
 * The identifier is what is written after the backticks; the title is what
 * a person reads. They differ more often than not — `cpp` is C++, `csharp`
 * is C#, `markup` is HTML — and picking from titles while writing
 * identifiers is the whole point of offering a list.
 */
@interface MPCodeLanguage : NSObject

@property (readonly, copy, nonatomic) NSString *identifier;
@property (readonly, copy, nonatomic) NSString *title;
/// Whether this is one of the few that belong at the top of the list.
@property (readonly, nonatomic) BOOL isCommon;

- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                            common:(BOOL)common;

@end


/** The languages that can actually be highlighted, given what is at hand.
 *
 * `index` is Prism's own catalogue of languages, `available` the identifiers
 * whose component is really there, and `aliases` the map the renderer uses
 * to send a written name to a component. A language is offered only when
 * all three agree on it, so choosing from this list cannot produce a fence
 * that comes out grey.
 *
 * Common languages come first, then the rest; both groups by title, so the
 * list can be read as well as scrolled.
 */
extern NSArray<MPCodeLanguage *> *MPCodeLanguagesFromIndex(
    NSDictionary *index, NSSet<NSString *> *available, NSDictionary *aliases);

/// The same list for this build, read from the bundle once.
extern NSArray<MPCodeLanguage *> *MPAvailableCodeLanguages(void);

/** A fenced code block holding `body`, marked with `language`.
 *
 * The fence is made longer than the longest run of backticks inside the
 * body, because a block that quotes Markdown will contain fences of its
 * own and three backticks would end it early.
 *
 * No trailing newline: the caller knows whether the text it replaces ended
 * with one.
 */
extern NSString *MPTextForFencedCodeBlock(NSString *language, NSString *body);

/** What is inside `text`, if `text` is one fenced block, otherwise nil.
 *
 * Used to take a block off again, so the command undoes itself.
 */
extern NSString *MPBodyOfFencedCodeBlock(NSString *text);


/** One edit: the fence going on, or coming off, the lines that are selected.
 *
 * Kept apart from the editor so the arithmetic — which lines are taken,
 * where the caret lands afterwards — can be checked without a window.
 */
@interface MPCodeFenceEdit : NSObject
@property (readonly, nonatomic) NSRange replacedRange;
@property (readonly, copy, nonatomic) NSString *replacement;
/// Where to leave the selection once the replacement is in.
@property (readonly, nonatomic) NSRange selectedRange;
/// Whether this takes a fence off, rather than putting one on.
@property (readonly, nonatomic) BOOL removesFence;
@end

/** The edit that fences `selection` in `text`, or unfences it.
 *
 * Whole lines, since a fence cannot begin halfway through one: a selection
 * of part of a line takes that line with it, which is what asking for a
 * block out of it meant. Lines that are already a fenced block have the
 * fence taken off instead, so the command undoes itself.
 */
extern MPCodeFenceEdit *MPCodeFenceEditForText(NSString *text,
                                               NSRange selection,
                                               NSString *language);


/** A fenced code block in the text, found from a place inside it.
 *
 * Shaped like MPTableSource's lookup, and for the same reason: a command
 * on the menu has to know which construct was clicked, and the text may
 * have moved on by the time it runs, so it is read again.
 */
@interface MPFencedCodeBlock : NSObject
/// The whole block, both fence lines included.
@property (readonly, nonatomic) NSRange range;
/// What lies between the fences, without either newline.
@property (readonly, nonatomic) NSRange bodyRange;
/// The language written on the opening fence, as written; empty if none.
@property (readonly, copy, nonatomic) NSString *language;

/// The block covering `index`, fences included, or nil if there is none.
+ (instancetype)blockCoveringIndex:(NSUInteger)index
                            inText:(NSString *)text;
@end

/** The language a written name stands for, through the alias map.
 *
 * `js` is JavaScript and `c++` is cpp; a rule looked up under what was
 * written would miss both.
 */
extern NSString *MPCanonicalCodeLanguage(NSString *written);

/** The name a person reads for a written language, e.g. `cpp` is C++.
 *
 * What was written comes back when there is no better name for it, so a
 * menu built on this never shows a blank.
 */
extern NSString *MPTitleOfCodeLanguage(NSString *written);
