//
//  MPLlamaGenerator.h
//  MacDown
//

#import <Foundation/Foundation.h>
#import "MPTextGenerator.h"

/** Text generation from a GGUF model on disk, through llama.cpp.
 *
 * The model is opened once and kept: reading a couple of gigabytes off disk
 * takes long enough that doing it per request would be the whole cost of
 * the feature. A context is made per generation, which is cheap beside it
 * and means no state carries from one command to the next — the reader
 * asking for a formal rewrite has not started a conversation.
 *
 * The chat template comes out of the model's own metadata, so a GGUF
 * arrives knowing how it wants to be addressed and nothing here has to
 * hold a table of prompt formats.
 */
@interface MPLlamaGenerator : NSObject <MPTextGenerator>

/** Opens the model at `url`. Returns nil, with `error` set, if it will not.
 *
 * The reading happens here, on the calling thread: this is slow, and a
 * caller that wants it off the main queue has to say so, rather than being
 * handed an object that is not yet an object.
 */
- (instancetype)initWithModelURL:(NSURL *)url error:(NSError **)error;

/// Where the model was read from.
@property (readonly, copy, nonatomic) NSURL *modelURL;

/// How many tokens of answer at most. 512 unless set.
@property (assign, nonatomic) NSUInteger maximumTokens;

/// How much the answer may wander. 0 is the same words every time; 0.3 by default.
@property (assign, nonatomic) float temperature;

@end
