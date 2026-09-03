//
//  MDDrawioResources.m
//  MacDown Next — draw.io plug-in
//

#import "MDDrawioResources.h"
#import "MDDrawioFile.h"

static NSString * const kMDScheme = @"drawio-res";
static NSString * const kMDHost = @"render";
static NSString * const kMDPagePath = @"/index.html";


@interface MDDrawioResources ()
@property (strong, nonatomic) NSBundle *bundle;
@property (copy, nonatomic) NSString *page;
@property (strong, nonatomic) NSMutableArray<NSString *> *served;
@property (strong, nonatomic) NSMutableArray<NSString *> *failed;
@end


@implementation MDDrawioResources

+ (NSString *)scheme
{
    return kMDScheme;
}

+ (NSString *)base
{
    return [NSString stringWithFormat:@"%@://%@", kMDScheme, kMDHost];
}

+ (NSURL *)pageURL
{
    return [NSURL URLWithString:
        [[self base] stringByAppendingString:kMDPagePath]];
}

- (instancetype)initWithBundle:(NSBundle *)bundle page:(NSString *)page
{
    self = [super init];
    if (!self)
        return nil;
    _bundle = bundle;
    _page = [page copy];
    _served = [NSMutableArray array];
    _failed = [NSMutableArray array];
    return self;
}

- (NSArray<NSString *> *)servedPaths
{
    return [self.served copy];
}

- (NSArray<NSString *> *)failedPaths
{
    return [self.failed copy];
}

/// What a browser needs to be told a file is, from what it is called.
static NSString *MDTypeOfPath(NSString *path)
{
    static NSDictionary *types = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        types = @{
            @"html": @"text/html; charset=utf-8",
            @"xml": @"text/xml; charset=utf-8",
            @"js": @"application/javascript; charset=utf-8",
            @"css": @"text/css; charset=utf-8",
            @"json": @"application/json; charset=utf-8",
            @"svg": @"image/svg+xml",
            @"png": @"image/png",
            @"gif": @"image/gif",
            @"jpg": @"image/jpeg",
        };
    });
    return types[path.pathExtension.lowercaseString]
        ?: @"application/octet-stream";
}

/** The file for a path under the bundle's resources, inflated.
 *
 * Nil for anything that would climb out of the resources: the viewer only
 * ever asks for what it was told about, but a handler that trusts the
 * request is a handler that reads whatever a diagram tells it to.
 */
- (NSData *)dataForRelativePath:(NSString *)relative
{
    if (!relative.length || [relative hasPrefix:@"/"]
            || [relative.pathComponents containsObject:@".."])
        return nil;

    NSURL *root = self.bundle.resourceURL.URLByStandardizingPath;
    NSURL *file = [[root URLByAppendingPathComponent:
        [relative stringByAppendingPathExtension:@"gz"]]
        URLByStandardizingPath];
    if (![file.path hasPrefix:root.path])
        return nil;

    NSData *stored = [NSData dataWithContentsOfURL:file];
    return stored ? MDDrawioInflate(stored, NO) : nil;
}

- (void)webView:(WKWebView *)webView
    startURLSchemeTask:(id<WKURLSchemeTask>)task
{
    NSURL *url = task.request.URL;
    NSString *path = url.path.length ? url.path : kMDPagePath;

    NSData *data = nil;
    if ([path isEqualToString:kMDPagePath])
        data = [self.page dataUsingEncoding:NSUTF8StringEncoding];
    else
        data = [self dataForRelativePath:[path substringFromIndex:1]];

    if (!data)
    {
        // The viewer asks for libraries that are no longer published, and
        // carries on when they are not there. So does this — but the two
        // lists are kept apart, because "asked for" and "handed over" are
        // the difference between a library that works and one that does
        // not, and a picture looks plausible either way.
        [self.failed addObject:path];
        [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
            code:NSURLErrorFileDoesNotExist userInfo:@{
            NSURLErrorFailingURLStringErrorKey: url.absoluteString}]];
        return;
    }

    [self.served addObject:path];

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
        initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1"
         headerFields:@{
            @"Content-Type": MDTypeOfPath(path),
            @"Content-Length": [NSString stringWithFormat:@"%lu",
                                (unsigned long)data.length],
            // The page is served from here too, so this is same-origin
            // already; stated because the viewer loads some of it by XHR
            // and a refusal there is silent.
            @"Access-Control-Allow-Origin": @"*",
        }];

    [task didReceiveResponse:response];
    [task didReceiveData:data];
    [task didFinish];
}

- (void)webView:(WKWebView *)webView
    stopURLSchemeTask:(id<WKURLSchemeTask>)task
{
    // Everything is answered in one go, so there is nothing to stop.
}

@end
