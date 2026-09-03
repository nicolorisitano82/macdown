//
//  MPModelStore.m
//  MacDown
//

#import "MPModelStore.h"
#import "MPLlamaGenerator.h"
#import "MPUtilities.h"

NSString * const kMPModelsDirectoryName = @"Models";
static NSString * const kMPSelectedModelKey = @"aiSelectedModelName";


@implementation MPModelFile

- (instancetype)initWithURL:(NSURL *)url size:(unsigned long long)size
{
    self = [super init];
    if (!self)
        return nil;
    _url = [url copy];
    _name = url.lastPathComponent.stringByDeletingPathExtension;
    _byteSize = size;
    return self;
}

@end


/// How long a model stays in memory after the last command that used it.
static const NSTimeInterval kMPModelIdleTimeout = 10.0 * 60.0;


@interface MPModelStore ()
@property (strong, nonatomic) id<MPTextGenerator> generator;
@property (strong, nonatomic) NSURL *loadedURL;
@property (strong, nonatomic) dispatch_queue_t loadQueue;
@property (strong, nonatomic) NSTimer *idleTimer;
@property (strong, nonatomic) NSMutableArray *waiting;
@end


@implementation MPModelStore

+ (instancetype)sharedStore
{
    static MPModelStore *store = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[MPModelStore alloc] init];
    });
    return store;
}

- (NSURL *)directory
{
    NSString *path = MPDataDirectory(kMPModelsDirectoryName);
    NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
    // Made on being asked for, not at launch: somebody who never opens the
    // writing commands should not find a folder they did not ask for.
    [[NSFileManager defaultManager] createDirectoryAtURL:url
                             withIntermediateDirectories:YES
                                              attributes:nil error:NULL];
    return url;
}

- (NSArray<MPModelFile *> *)installedModels
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSArray<NSURL *> *contents = [files
        contentsOfDirectoryAtURL:self.directory
      includingPropertiesForKeys:@[NSURLFileSizeKey]
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:NULL];

    NSMutableArray<MPModelFile *> *found = [NSMutableArray array];
    for (NSURL *url in contents)
    {
        if (![url.pathExtension.lowercaseString isEqualToString:@"gguf"])
            continue;
        NSNumber *size = nil;
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        [found addObject:[[MPModelFile alloc]
            initWithURL:url size:size.unsignedLongLongValue]];
    }

    [found sortUsingComparator:^NSComparisonResult(MPModelFile *a,
                                                   MPModelFile *b) {
        return [a.name localizedStandardCompare:b.name];
    }];
    return found;
}

- (MPModelFile *)selectedModel
{
    NSArray<MPModelFile *> *installed = self.installedModels;
    if (!installed.count)
        return nil;

    NSString *chosen = [[NSUserDefaults standardUserDefaults]
        stringForKey:kMPSelectedModelKey];
    for (MPModelFile *model in installed)
    {
        if ([model.name isEqualToString:chosen])
            return model;
    }
    // The choice is gone, or was never made. One installed model needs no
    // choosing.
    return installed.firstObject;
}

- (void)setSelectedModel:(MPModelFile *)model
{
    [[NSUserDefaults standardUserDefaults] setObject:model.name
                                              forKey:kMPSelectedModelKey];
}

- (BOOL)removeModel:(MPModelFile *)model error:(NSError **)error
{
    if (!model)
        return NO;
    // Whatever is in memory came from a file, and this may be that file.
    if ([self.loadedURL isEqual:model.url])
        [self unloadGenerator];
    return [[NSFileManager defaultManager] removeItemAtURL:model.url
                                                     error:error];
}


#pragma mark - The loaded model

- (BOOL)isGeneratorLoaded
{
    return self.generator != nil;
}

- (void)generatorWithCompletion:
    (void (^)(id<MPTextGenerator>, NSError *))completion
{
    NSParameterAssert(completion);

    MPModelFile *chosen = self.selectedModel;
    if (!chosen)
    {
        completion(nil, [NSError errorWithDomain:MPTextGeneratorErrorDomain
            code:MPTextGeneratorErrorNoModel userInfo:@{
                NSLocalizedDescriptionKey: NSLocalizedString(
                    @"No model is installed. Put a .gguf file in the Models "
                    @"folder, or download one from the Models panel.",
                    @"Text generation failure")}]);
        return;
    }

    // The chosen model changed under a loaded one.
    if (self.generator && ![self.loadedURL isEqual:chosen.url])
        [self unloadGenerator];

    [self restartIdleTimer];

    if (self.generator)
    {
        completion(self.generator, nil);
        return;
    }

    // A second caller during a load waits for the first rather than
    // reading two gigabytes twice.
    if (!self.waiting)
        self.waiting = [NSMutableArray array];
    [self.waiting addObject:completion];
    if (self.waiting.count > 1)
        return;

    if (!self.loadQueue)
    {
        self.loadQueue = dispatch_queue_create(
            "com.nicolorisitano82.macdown.model-load", DISPATCH_QUEUE_SERIAL);
    }

    NSURL *url = chosen.url;
    __weak MPModelStore *weakSelf = self;
    dispatch_async(self.loadQueue, ^{
        NSError *error = nil;
        MPLlamaGenerator *loaded =
            [[MPLlamaGenerator alloc] initWithModelURL:url error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            MPModelStore *store = weakSelf;
            if (!store)
                return;
            if (loaded)
            {
                store.generator = loaded;
                store.loadedURL = url;
            }
            NSArray *callbacks = [store.waiting copy];
            [store.waiting removeAllObjects];
            for (void (^callback)(id<MPTextGenerator>, NSError *) in callbacks)
                callback(loaded, loaded ? nil : error);
        });
    });
}

- (void)unloadGenerator
{
    [self.idleTimer invalidate];
    self.idleTimer = nil;
    self.generator = nil;
    self.loadedURL = nil;
}

- (void)restartIdleTimer
{
    [self.idleTimer invalidate];
    __weak MPModelStore *weakSelf = self;
    self.idleTimer = [NSTimer
        scheduledTimerWithTimeInterval:kMPModelIdleTimeout repeats:NO
                                 block:^(NSTimer *timer) {
        [weakSelf unloadGenerator];
    }];
}

@end
