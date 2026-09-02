//
//  MPRemoteImageFetch.m
//  MacDown
//

#import "MPRemoteImageFetch.h"
#import "MPUtilities.h"

/// How long one picture is waited for before the export goes on without it.
static const NSTimeInterval kMPRemoteImageTimeout = 20.0;

/// At once. Enough to keep a slow line busy, few enough to be polite.
static const NSInteger kMPRemoteImageConcurrency = 4;


#pragma mark - Reading the markup

/// The `src` of one `<img>` tag, in the tag's own coordinates.
static NSRange MPSourceRangeInTag(NSString *tag)
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"src\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
                                                          options:
            NSRegularExpressionCaseInsensitive error:NULL];
    });

    NSTextCheckingResult *match =
        [regex firstMatchInString:tag options:0
                            range:NSMakeRange(0, tag.length)];
    if (!match)
        return NSMakeRange(NSNotFound, 0);

    NSRange quoted = [match rangeAtIndex:1];
    if (quoted.location == NSNotFound)
        quoted = [match rangeAtIndex:2];
    return quoted;
}

/// Whether a source is one this has to go and get.
static BOOL MPIsRemoteSource(NSString *source)
{
    NSString *lower = source.lowercaseString;
    return [lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"];
}

/** Every remote `<img src>` in `html`, with where each one is written.
 *
 * The ranges are into `html` and come out in document order; the caller
 * puts its replacements back to front so the earlier ones stay valid.
 */
static NSArray<NSValue *> *MPRemoteSourceRanges(NSString *html,
                                                NSMutableArray<NSString *> *urls)
{
    static NSRegularExpression *imgRegex = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        imgRegex = [NSRegularExpression regularExpressionWithPattern:
            @"<img[^>]*>" options:NSRegularExpressionCaseInsensitive
                                                              error:NULL];
    });

    NSMutableArray<NSValue *> *found = [NSMutableArray array];
    NSArray<NSTextCheckingResult *> *tags =
        [imgRegex matchesInString:html options:0
                            range:NSMakeRange(0, html.length)];

    for (NSTextCheckingResult *tag in tags)
    {
        NSString *body = [html substringWithRange:tag.range];
        NSRange inTag = MPSourceRangeInTag(body);
        if (inTag.location == NSNotFound || !inTag.length)
            continue;

        NSRange range = NSMakeRange(tag.range.location + inTag.location,
                                    inTag.length);
        // The address is written as HTML, so a query string arrives with
        // its separators as `&amp;` and would be fetched as a different
        // address from the one the writer meant.
        NSString *source = MPStringByUnescapingHTMLEntities(
            [html substringWithRange:range]);
        if (!MPIsRemoteSource(source))
            continue;

        [found addObject:[NSValue valueWithRange:range]];
        [urls addObject:source];
    }
    return found;
}


NSArray<NSString *> *MPRemoteImageSourcesInHTML(NSString *html)
{
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    MPRemoteSourceRanges(html, urls);
    return urls;
}

NSString *MPHTMLByReplacingRemoteImageSources(
    NSString *html,
    NSDictionary<NSString *, NSString *> *replacements,
    NSMutableArray<NSString *> *unreplaced)
{
    NSMutableArray<NSString *> *urls = [NSMutableArray array];
    NSArray<NSValue *> *ranges = MPRemoteSourceRanges(html, urls);
    if (!ranges.count)
        return html;

    NSMutableString *out = [html mutableCopy];

    // Back to front, so each replacement leaves the earlier ranges valid.
    for (NSInteger i = (NSInteger)ranges.count - 1; i >= 0; i--)
    {
        NSString *address = urls[(NSUInteger)i];
        NSString *replacement = replacements[address];
        if (!replacement)
        {
            // Once per address, however many tags use it.
            if (![unreplaced containsObject:address])
                [unreplaced addObject:address];
            continue;
        }
        [out replaceCharactersInRange:ranges[(NSUInteger)i].rangeValue
                           withString:replacement];
    }
    return out;
}


#pragma mark - The sheet

/** A sheet saying the export is waiting on the network.
 *
 * Built here rather than in a nib: it is a label, a spinner and a button,
 * and a nib for it would be one more file to keep in step with 26
 * localisations for the sake of three controls.
 */
@interface MPRemoteImageSheet : NSWindowController
@property (copy, nonatomic) void (^onCancel)(void);
@end

@implementation MPRemoteImageSheet

- (instancetype)initWithCount:(NSUInteger)count
{
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0.0, 0.0, 360.0, 108.0)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:panel];
    if (!self)
        return nil;

    NSTextField *label = [NSTextField labelWithString:
        [NSString stringWithFormat:NSLocalizedString(
            @"Fetching %lu images from the network…",
            @"Export waiting on remote images"), (unsigned long)count]];
    label.font = [NSFont systemFontOfSize:
        [NSFont systemFontSizeForControlSize:NSControlSizeRegular]];

    NSProgressIndicator *spinner =
        [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    spinner.style = NSProgressIndicatorStyleBar;
    spinner.indeterminate = YES;
    [spinner startAnimation:nil];

    NSButton *cancel = [NSButton buttonWithTitle:
        NSLocalizedString(@"Cancel", @"Export waiting on remote images")
                                          target:self
                                          action:@selector(cancelled:)];
    cancel.keyEquivalent = @"\033";

    NSView *content = panel.contentView;
    for (NSView *view in @[label, spinner, cancel])
    {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                           constant:20.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:
            content.trailingAnchor constant:-20.0],
        [label.topAnchor constraintEqualToAnchor:content.topAnchor
                                        constant:20.0],
        [spinner.leadingAnchor constraintEqualToAnchor:label.leadingAnchor],
        [spinner.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                              constant:-20.0],
        [spinner.topAnchor constraintEqualToAnchor:label.bottomAnchor
                                          constant:12.0],
        [cancel.trailingAnchor constraintEqualToAnchor:spinner.trailingAnchor],
        [cancel.topAnchor constraintEqualToAnchor:spinner.bottomAnchor
                                         constant:12.0],
        [cancel.bottomAnchor constraintEqualToAnchor:content.bottomAnchor
                                            constant:-16.0],
    ]];
    return self;
}

- (void)cancelled:(id)sender
{
    void (^cancel)(void) = self.onCancel;
    self.onCancel = nil;
    if (cancel)
        cancel();
}

@end


#pragma mark - Fetching

/// The extension a data: URI should claim, from what the server said.
static NSString *MPMediaTypeForResponse(NSURLResponse *response,
                                        NSString *url)
{
    NSString *type = response.MIMEType.lowercaseString;
    if ([type hasPrefix:@"image/"])
    {
        // Some servers add `; charset=`, which a data: URI must not carry
        // into its own type.
        return [type componentsSeparatedByString:@";"].firstObject;
    }

    NSString *extension = url.pathExtension.lowercaseString;
    NSDictionary<NSString *, NSString *> *known = @{
        @"png": @"image/png", @"jpg": @"image/jpeg", @"jpeg": @"image/jpeg",
        @"gif": @"image/gif", @"webp": @"image/webp", @"svg": @"image/svg+xml",
        @"bmp": @"image/bmp", @"tif": @"image/tiff", @"tiff": @"image/tiff",
        @"heic": @"image/heic",
    };
    return known[extension] ?: @"image/png";
}

void MPFetchRemoteImagesInHTML(NSString *html,
                               NSWindow *sheetParent,
                               void (^completion)(NSString *html,
                                                  NSArray<NSString *> *unreachable))
{
    NSArray<NSString *> *urls = MPRemoteImageSourcesInHTML(html);
    if (!urls.count)
    {
        completion(html, @[]);
        return;
    }

    // One fetch per address, however many times it is used.
    NSMutableOrderedSet<NSString *> *wanted =
        [NSMutableOrderedSet orderedSetWithArray:urls];

    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = kMPRemoteImageTimeout;
    configuration.timeoutIntervalForResource = kMPRemoteImageTimeout;
    configuration.HTTPMaximumConnectionsPerHost = kMPRemoteImageConcurrency;
    NSURLSession *session =
        [NSURLSession sessionWithConfiguration:configuration];

    NSMutableDictionary<NSString *, NSString *> *fetched =
        [NSMutableDictionary dictionary];
    // The tasks answer on the session's own queue, so the table they write
    // into needs a lock of its own.
    NSLock *lock = [[NSLock alloc] init];

    MPRemoteImageSheet *sheet = sheetParent
        ? [[MPRemoteImageSheet alloc] initWithCount:wanted.count] : nil;

    dispatch_group_t group = dispatch_group_create();
    for (NSString *address in wanted)
    {
        NSURL *url = [NSURL URLWithString:address];
        if (!url)
            continue;

        dispatch_group_enter(group);
        NSURLSessionDataTask *task = [session dataTaskWithURL:url
            completionHandler:^(NSData *data, NSURLResponse *response,
                                NSError *error) {
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
                ? [(NSHTTPURLResponse *)response statusCode] : 200;
            if (data.length && !error && status >= 200 && status < 300)
            {
                NSString *uri = [NSString stringWithFormat:
                    @"data:%@;base64,%@",
                    MPMediaTypeForResponse(response, address),
                    [data base64EncodedStringWithOptions:0]];
                [lock lock];
                fetched[address] = uri;
                [lock unlock];
            }
            dispatch_group_leave(group);
        }];
        [task resume];
    }

    // Cancelling gives up on what has not arrived and lets the export
    // finish: the reader asked for a file, not for an argument about it.
    sheet.onCancel = ^{
        [session invalidateAndCancel];
    };

    if (sheet)
    {
        [sheetParent beginSheet:sheet.window completionHandler:nil];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [session finishTasksAndInvalidate];
        if (sheet)
            [sheetParent endSheet:sheet.window];

        NSMutableArray<NSString *> *unreachable = [NSMutableArray array];
        NSString *out = MPHTMLByReplacingRemoteImageSources(html, fetched,
                                                            unreachable);
        completion(out, unreachable);
    });
}
