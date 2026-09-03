//
//  MPModelStore.m
//  MacDown
//

#import "MPModelStore.h"
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
    return [[NSFileManager defaultManager] removeItemAtURL:model.url
                                                     error:error];
}

@end
