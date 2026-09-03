//
//  MPDocumentTemplate.m
//  MacDown
//

#import "MPDocumentTemplate.h"
#import "MPUtilities.h"

static NSString * const kMPTemplatesDirectoryName = @"Templates";
/// Where the ones that ship live, kept apart from the HTML export template.
static NSString * const kMPBundledTemplatesDirectory = @"DocumentTemplates";


@implementation MPDocumentTemplate

- (instancetype)initWithURL:(NSURL *)url custom:(BOOL)custom
{
    self = [super init];
    if (!self)
        return nil;
    _url = [url copy];
    _name = url.lastPathComponent.stringByDeletingPathExtension;
    _isCustom = custom;
    return self;
}

- (NSString *)markdown
{
    return [NSString stringWithContentsOfURL:self.url
                                    encoding:NSUTF8StringEncoding error:NULL];
}

+ (NSURL *)customDirectory
{
    NSURL *url = [NSURL fileURLWithPath:
        MPDataDirectory(kMPTemplatesDirectoryName) isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:url
                             withIntermediateDirectories:YES
                                              attributes:nil error:NULL];
    return url;
}

+ (NSArray<MPDocumentTemplate *> *)markdownInDirectory:(NSURL *)directory
                                                custom:(BOOL)custom
{
    if (!directory)
        return @[];

    NSArray<NSURL *> *contents = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:directory
      includingPropertiesForKeys:nil
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:NULL];

    NSMutableArray<MPDocumentTemplate *> *found = [NSMutableArray array];
    for (NSURL *url in contents)
    {
        NSString *extension = url.pathExtension.lowercaseString;
        if (![extension isEqualToString:@"md"]
                && ![extension isEqualToString:@"markdown"])
            continue;
        [found addObject:[[MPDocumentTemplate alloc] initWithURL:url
                                                          custom:custom]];
    }
    return found;
}

+ (NSArray<MPDocumentTemplate *> *)installedTemplates
{
    NSURL *bundled = [[NSBundle mainBundle]
        URLForResource:kMPBundledTemplatesDirectory withExtension:nil];

    NSMutableDictionary<NSString *, MPDocumentTemplate *> *byName =
        [NSMutableDictionary dictionary];
    for (MPDocumentTemplate *template in
            [self markdownInDirectory:bundled custom:NO])
        byName[template.name] = template;
    // The reader's own last, so one of theirs with the same name wins.
    for (MPDocumentTemplate *template in
            [self markdownInDirectory:[self customDirectory] custom:YES])
        byName[template.name] = template;

    return [byName.allValues sortedArrayUsingComparator:
        ^NSComparisonResult(MPDocumentTemplate *a, MPDocumentTemplate *b) {
        return [a.name localizedStandardCompare:b.name];
    }];
}

@end
