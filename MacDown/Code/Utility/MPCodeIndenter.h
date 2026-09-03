//
//  MPCodeIndenter.h
//  MacDown
//

#import <Foundation/Foundation.h>


/** How a language's indentation is arrived at.
 *
 * Three answers, because there are three kinds of language here and one
 * rule for all of them would damage two of the three.
 */
typedef NS_ENUM(NSUInteger, MPCodeIndentFamily) {
    /// No rule: the block is left exactly as it is.
    MPCodeIndentFamilyNone = 0,
    /// Depth is what the brackets say, so it can be worked out from scratch.
    MPCodeIndentFamilyBrackets,
    /// Depth *is* the indentation, so only the unit can be changed.
    MPCodeIndentFamilyOffside,
    /// Depth is what the tags say.
    MPCodeIndentFamilyTags,
};


/// What one language wants, and what a scanner needs to read it.
@interface MPCodeIndentRule : NSObject
@property (readonly, nonatomic) MPCodeIndentFamily family;
/// One step of indentation: spaces, or a tab.
@property (readonly, copy, nonatomic) NSString *unit;
/// How many columns that step stands for, for reading tabs and spaces alike.
@property (readonly, nonatomic) NSUInteger width;
/// What starts a comment that runs to the end of the line.
@property (readonly, copy, nonatomic) NSArray<NSString *> *lineComments;
/// Whether `/* … */` is a comment here.
@property (readonly, nonatomic) BOOL blockComments;
/// The quote characters that hold a string.
@property (readonly, copy, nonatomic) NSString *quotes;
/// Whether a backtick opens a string that may run over several lines.
@property (readonly, nonatomic) BOOL rawStrings;
/// What opens and shuts a string that may run over several lines.
@property (readonly, copy, nonatomic) NSArray<NSString *> *multilineStrings;
@end


/** The rule for a language, or nil when there is none for it.
 *
 * Nil is the answer for most of the hundred-odd languages that can be
 * highlighted: highlighting needs a grammar of tokens, laying out code
 * needs a grammar of blocks, and only the second is claimed here.
 */
extern MPCodeIndentRule *MPCodeIndentRuleForLanguage(NSString *language);

/** `body` indented the way `language` wants it.
 *
 * Only the whitespace at the start of each line is touched — nothing is
 * joined, split, or moved. A block whose layout cannot be worked out with
 * confidence comes back unchanged rather than mangled.
 */
extern NSString *MPReindentedCode(NSString *body, NSString *language);
