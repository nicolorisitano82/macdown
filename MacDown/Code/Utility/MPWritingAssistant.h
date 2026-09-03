//
//  MPWritingAssistant.h
//  MacDown
//

#import <Cocoa/Cocoa.h>
#import "MPTextGenerator.h"

/// What to do to the text. Each is one instruction to the model.
typedef NS_ENUM(NSUInteger, MPWritingCommand) {
    /// Same meaning, said better. The one most people want most of the time.
    MPWritingCommandImprove,
    /// Spelling, agreement and punctuation only — the wording left alone.
    MPWritingCommandCorrect,
    MPWritingCommandFormal,
    MPWritingCommandPlain,
    MPWritingCommandShorter,
    MPWritingCommandLonger,
};

/// Every command, in the order they should appear in a menu.
extern const MPWritingCommand MPWritingCommandsInOrder[6];
extern const NSUInteger MPWritingCommandCount;


/** Runs a writing command over what is selected in the editor.
 *
 * Takes the generator rather than making one, which is what lets the whole
 * interaction — the replacing, the single step of undo, the cancelling — be
 * tested against a generator that returns fixed words, with no model on
 * disk and no GPU involved.
 */
@interface MPWritingAssistant : NSObject

- (instancetype)initWithGenerator:(id<MPTextGenerator>)generator;

@property (readonly, strong, nonatomic) id<MPTextGenerator> generator;

/// True between starting a command and its completion. One at a time.
@property (readonly, nonatomic, getter=isWorking) BOOL working;

/** What the model is told, with the language of the text named in it.
 *
 * `language` is the English name of a language — "Italian" — and it is not
 * decoration. Measured on a 3B model: told to "answer in the same language
 * as the text", it rewrote an Italian paragraph into Spanish. Told the
 * language by name, it answers in it, for Italian, English and German.
 *
 * Nil `language` leaves the naming out, which is the best that can be done
 * when the text is too short to tell.
 */
+ (NSString *)instructionForCommand:(MPWritingCommand)command
                         inLanguage:(NSString *)language;

/// The English name of the language a piece of text is written in, or nil.
+ (NSString *)languageNameOfText:(NSString *)text;

/// What the menu item says.
+ (NSString *)titleForCommand:(MPWritingCommand)command;

/** The text a command would work on, in `textView`.
 *
 * The selection, or — with nothing selected — the paragraph the caret is
 * in, the way ⌘B takes the word under the caret rather than refusing. An
 * empty range means there is nothing to do.
 */
+ (NSRange)rangeForCommandInTextView:(NSTextView *)textView;

/** Runs `command`, replacing the text as the answer arrives.
 *
 * Returns NO without doing anything if there is nothing to work on, or if
 * a command is already running. `completion` is called on the main queue
 * exactly once, unless NO was returned.
 */
- (BOOL)runCommand:(MPWritingCommand)command
        onTextView:(NSTextView *)textView
        completion:(void (^)(NSError *error))completion;

/// Stops the command in progress. What has arrived stays, and one undo
/// takes the whole thing back.
- (void)cancel;

@end
