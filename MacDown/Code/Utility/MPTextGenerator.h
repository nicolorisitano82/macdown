//
//  MPTextGenerator.h
//  MacDown
//

#import <Foundation/Foundation.h>

/// One piece of the answer, as it arrives.
typedef void (^MPTextGeneratorChunk)(NSString *piece);

/// The end of it: nil on success, otherwise why it stopped.
typedef void (^MPTextGeneratorCompletion)(NSError *error);

extern NSString * const MPTextGeneratorErrorDomain;

typedef NS_ENUM(NSInteger, MPTextGeneratorError) {
    MPTextGeneratorErrorNoModel = 1,
    MPTextGeneratorErrorLoadFailed,
    MPTextGeneratorErrorContextFailed,
    MPTextGeneratorErrorTooLong,
    MPTextGeneratorErrorCancelled,
};


/** Something that can rewrite a piece of text on instruction.
 *
 * The one narrow thing every writing command needs, and the reason it is a
 * protocol rather than a class: what generates the words is going to change
 * more than once. A local GGUF through llama.cpp is one implementation and
 * the system's own model is another, and the commands in the editor should
 * not be able to tell which of them answered.
 *
 * Streaming, because a paragraph takes a second or two and text that
 * appears as it is written reads as an application doing something, while
 * the same wait behind a spinner reads as one that has stopped.
 */
@protocol MPTextGenerator <NSObject>

/// What to call it where a reader has to choose, or see which one answered.
@property (readonly, copy, nonatomic) NSString *displayName;

/// Whether it could answer right now. False needs no explaining to the user.
@property (readonly, nonatomic, getter=isAvailable) BOOL available;

/** Answers `instruction` about `text`, a piece at a time.
 *
 * `instruction` is what to do — "rewrite this formally" — and `text` is
 * what to do it to, which is usually the selection. They are separate
 * because the model is told them separately: the instruction is the system
 * message and the text is the user's, which is what keeps a document that
 * happens to contain instructions from being read as one.
 *
 * Both blocks are called on the main queue. `chunk` may be called any
 * number of times, including none, and `completion` exactly once.
 */
- (void)generateWithInstruction:(NSString *)instruction
                        onText:(NSString *)text
                       onChunk:(MPTextGeneratorChunk)chunk
                    completion:(MPTextGeneratorCompletion)completion;

/// Stops the generation in progress, if there is one. Safe to call always.
- (void)cancel;

@end
