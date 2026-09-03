//
//  MPLlamaGenerator.m
//  MacDown
//

#import "MPLlamaGenerator.h"
#import "llama.h"

NSString * const MPTextGeneratorErrorDomain = @"MPTextGeneratorErrorDomain";

/// Room for the prompt and the answer together. A selection is a paragraph.
static const uint32_t kMPLlamaContextTokens = 4096;


NS_INLINE NSError *MPGeneratorError(MPTextGeneratorError code,
                                    NSString *description)
{
    return [NSError errorWithDomain:MPTextGeneratorErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey: description}];
}


@interface MPLlamaGenerator ()
@property (strong, nonatomic) dispatch_queue_t queue;
/// Set from any thread to stop the loop at its next token.
@property (assign, atomic) BOOL cancelled;
@property (assign, atomic) BOOL working;
@end


@implementation MPLlamaGenerator
{
    struct llama_model *_model;
    const struct llama_vocab *_vocab;
    /* Made once, on the first generation, and kept.
     *
     * Not because building one is slow — measured, it is not — but because
     * it allocates the attention cache for the whole context window, and
     * doing that per request is buying the same buffers over and over. Its
     * memory is cleared between requests instead, which also keeps one
     * command from being answered in the light of the last.
     *
     * What *is* slow is the first generation in the life of an install:
     * around three and a half seconds, while Metal compiles the shaders
     * embedded in the library. The system caches them afterwards and every
     * run from then on starts in a tenth of a second. Worth knowing before
     * anybody tries to explain that pause with this code.
     */
    struct llama_context *_context;
}

/// Where the library's running commentary about tensors goes: nowhere.
static void MPLlamaSwallowLog(enum ggml_log_level level, const char *text,
                              void *user)
{
    (void)level; (void)text; (void)user;
}

+ (void)initialize
{
    if (self != [MPLlamaGenerator class])
        return;
    // Once per process, and before any model is opened.
    llama_backend_init();
    // A no-op rather than NULL: NULL means "put the default back", and the
    // default is several hundred lines of metadata on stderr per model.
    llama_log_set(MPLlamaSwallowLog, NULL);
}

- (instancetype)initWithModelURL:(NSURL *)url error:(NSError **)error
{
    self = [super init];
    if (!self)
        return nil;

    if (!url.isFileURL
            || ![[NSFileManager defaultManager] fileExistsAtPath:url.path])
    {
        if (error)
        {
            *error = MPGeneratorError(MPTextGeneratorErrorNoModel,
                NSLocalizedString(@"There is no model file at that path.",
                                  @"Text generation failure"));
        }
        return nil;
    }

    struct llama_model_params parameters = llama_model_default_params();
    // Everything the GPU will take. On a Mac the model sits in the same
    // memory either way, so there is nothing to be gained by holding layers
    // back — and a great deal of speed to be lost.
    parameters.n_gpu_layers = 999;

    _model = llama_model_load_from_file(url.path.fileSystemRepresentation,
                                        parameters);
    if (!_model)
    {
        if (error)
        {
            *error = MPGeneratorError(MPTextGeneratorErrorLoadFailed,
                NSLocalizedString(@"The model could not be loaded. It may be "
                                  @"of a kind this version does not know, or "
                                  @"the file may be incomplete.",
                                  @"Text generation failure"));
        }
        return nil;
    }
    _vocab = llama_model_get_vocab(_model);

    _modelURL = [url copy];
    _maximumTokens = 512;
    _temperature = 0.3f;
    // Serial: one model, one generation at a time. A second request waits
    // rather than fighting the first for the GPU.
    _queue = dispatch_queue_create("com.nicolorisitano82.macdown.llama",
                                   DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)dealloc
{
    if (_context)
        llama_free(_context);
    if (_model)
        llama_model_free(_model);
}


- (void)warmUp
{
    // Straight through the same road a command takes, so whatever it
    // compiles is what a command will need. One token is enough: the cost
    // is in the first pass, not in the length of the answer.
    NSUInteger limit = self.maximumTokens;
    self.maximumTokens = 1;
    [self runPrompt:@"." limit:1 temperature:0.0f onChunk:nil];
    self.maximumTokens = limit;
}


#pragma mark - MPTextGenerator

- (NSString *)displayName
{
    return self.modelURL.lastPathComponent.stringByDeletingPathExtension;
}

- (BOOL)isAvailable
{
    return _model != NULL;
}

- (void)cancel
{
    self.cancelled = YES;
}


#pragma mark - Generating

/** The prompt in the shape this particular model expects.
 *
 * Out of the GGUF's own metadata rather than a table here: every family
 * writes its turns differently, and a model that carries its template is a
 * model that keeps working when a new family appears.
 */
- (NSString *)promptForInstruction:(NSString *)instruction
                              text:(NSString *)text
{
    const char *template = llama_model_chat_template(_model, NULL);

    struct llama_chat_message messages[2];
    messages[0].role = "system";
    messages[0].content = instruction.UTF8String;
    messages[1].role = "user";
    messages[1].content = text.UTF8String;

    // Twice the characters is what the library asks for; a template adds
    // markers, not prose.
    int32_t capacity = (int32_t)(2 * (instruction.length + text.length) + 512);
    char *buffer = malloc((size_t)capacity);
    if (!buffer)
        return nil;

    int32_t written = llama_chat_apply_template(template, messages, 2, true,
                                                buffer, capacity);
    if (written > capacity)
    {
        char *grown = realloc(buffer, (size_t)written);
        if (!grown)
        {
            free(buffer);
            return nil;
        }
        buffer = grown;
        capacity = written;
        written = llama_chat_apply_template(template, messages, 2, true,
                                            buffer, capacity);
    }

    NSString *prompt = nil;
    if (written > 0)
    {
        prompt = [[NSString alloc] initWithBytes:buffer
                                          length:(NSUInteger)written
                                        encoding:NSUTF8StringEncoding];
    }
    free(buffer);

    // No template in the file: fall back to the markers most instruction
    // models are trained on, which is better than sending the two strings
    // glued together and hoping.
    if (!prompt.length)
    {
        prompt = [NSString stringWithFormat:
            @"<|im_start|>system\n%@<|im_end|>\n"
            @"<|im_start|>user\n%@<|im_end|>\n"
            @"<|im_start|>assistant\n", instruction, text];
    }
    return prompt;
}

- (void)generateWithInstruction:(NSString *)instruction
                         onText:(NSString *)text
                        onChunk:(MPTextGeneratorChunk)chunk
                     completion:(MPTextGeneratorCompletion)completion
{
    NSParameterAssert(completion);
    self.cancelled = NO;

    if (!self.isAvailable)
    {
        completion(MPGeneratorError(MPTextGeneratorErrorNoModel,
            NSLocalizedString(@"No model is loaded.",
                              @"Text generation failure")));
        return;
    }

    NSString *prompt = [self promptForInstruction:instruction text:text];
    NSUInteger limit = self.maximumTokens;
    float temperature = self.temperature;

    __weak MPLlamaGenerator *weakSelf = self;
    dispatch_async(self.queue, ^{
        MPLlamaGenerator *generator = weakSelf;
        if (!generator)
            return;
        NSError *error = [generator runPrompt:prompt limit:limit
                                  temperature:temperature onChunk:chunk];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(error);
        });
    });
}

/// The loop itself, on the serial queue. Returns nil when it finished.
- (NSError *)runPrompt:(NSString *)prompt
                 limit:(NSUInteger)limit
           temperature:(float)temperature
               onChunk:(MPTextGeneratorChunk)chunk
{
    self.working = YES;

    if (!_context)
    {
        struct llama_context_params contextParameters =
            llama_context_default_params();
        contextParameters.n_ctx = kMPLlamaContextTokens;
        contextParameters.n_batch = kMPLlamaContextTokens;
        _context = llama_init_from_model(_model, contextParameters);
    }
    if (!_context)
    {
        self.working = NO;
        return MPGeneratorError(MPTextGeneratorErrorContextFailed,
            NSLocalizedString(@"There was not enough memory to run the model.",
                              @"Text generation failure"));
    }
    struct llama_context *context = _context;

    // Nothing of the last request survives into this one.
    llama_memory_clear(llama_get_memory(context), true);

    const char *utf8 = prompt.UTF8String;
    int32_t length = (int32_t)strlen(utf8);

    // Asked for the count first, then given a buffer of it: the library
    // answers a negative number of the size it wanted.
    int32_t wanted = -llama_tokenize(_vocab, utf8, length, NULL, 0, true, true);
    if (wanted <= 0 || (uint32_t)wanted >= kMPLlamaContextTokens)
    {
        self.working = NO;
        return MPGeneratorError(MPTextGeneratorErrorTooLong,
            NSLocalizedString(@"The selection is too long for the model's "
                              @"context. Try a smaller piece of it.",
                              @"Text generation failure"));
    }

    llama_token *tokens = calloc((size_t)wanted, sizeof(llama_token));
    if (!tokens)
    {
        self.working = NO;
        return MPGeneratorError(MPTextGeneratorErrorContextFailed,
                                @"out of memory");
    }
    int32_t count = llama_tokenize(_vocab, utf8, length, tokens, wanted,
                                   true, true);

    struct llama_sampler *sampler =
        llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (temperature <= 0.0f)
    {
        // The same words for the same request, which is what someone
        // correcting a sentence wants.
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    }
    else
    {
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95f, 1));
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(sampler,
                                llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    }

    NSError *failure = nil;
    if (llama_decode(context, llama_batch_get_one(tokens, count)) != 0)
    {
        failure = MPGeneratorError(MPTextGeneratorErrorContextFailed,
            NSLocalizedString(@"The model failed while reading the text.",
                              @"Text generation failure"));
    }
    free(tokens);

    for (NSUInteger produced = 0; !failure && produced < limit; produced++)
    {
        if (self.cancelled)
        {
            failure = MPGeneratorError(MPTextGeneratorErrorCancelled, @"");
            break;
        }

        llama_token token = llama_sampler_sample(sampler, context, -1);
        if (llama_vocab_is_eog(_vocab, token))
            break;

        char piece[512];
        int32_t written = llama_token_to_piece(_vocab, token, piece,
                                               sizeof(piece), 0, true);
        if (written > 0 && chunk)
        {
            // A token is not a character: one can end mid-sequence, so the
            // bytes go across as they are and the caller joins them.
            NSString *text = [[NSString alloc]
                initWithBytes:piece length:(NSUInteger)written
                     encoding:NSUTF8StringEncoding];
            if (text.length)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    chunk(text);
                });
            }
        }

        if (llama_decode(context, llama_batch_get_one(&token, 1)) != 0)
        {
            failure = MPGeneratorError(MPTextGeneratorErrorContextFailed,
                NSLocalizedString(@"The model stopped part way through.",
                                  @"Text generation failure"));
            break;
        }
    }

    llama_sampler_free(sampler);
    self.working = NO;
    return failure;
}

@end
