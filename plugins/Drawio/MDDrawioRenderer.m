//
//  MDDrawioRenderer.m
//  MacDown Next — draw.io plug-in
//

#import "MDDrawioRenderer.h"
#import <WebKit/WebKit.h>

/// Long enough for a page of a few hundred cells; short enough to give up.
static const NSTimeInterval kMDRenderTimeout = 20.0;
/// How often the page is asked whether the drawing has appeared.
static const NSTimeInterval kMDPollInterval = 0.1;


@interface MDDrawioRenderer () <WKNavigationDelegate>
@property (strong, nonatomic) NSBundle *bundle;
@property (strong, nonatomic) WKWebView *webView;
@property (copy, nonatomic) MDDrawioRenderHandler handler;
@property (nonatomic) CGFloat scale;
@property (strong, nonatomic) NSDate *deadline;
/// The viewer, read once: it is two and a half megabytes of JavaScript.
@property (copy, nonatomic) NSString *viewer;
@end


@implementation MDDrawioRenderer

- (instancetype)initWithBundle:(NSBundle *)bundle
{
    self = [super init];
    if (!self)
        return nil;
    _bundle = bundle;
    return self;
}

- (NSString *)viewer
{
    if (_viewer)
        return _viewer;
    NSURL *url = [self.bundle URLForResource:@"viewer.min" withExtension:@"js"];
    _viewer = url ? [NSString stringWithContentsOfURL:url
                                             encoding:NSUTF8StringEncoding
                                                error:NULL] : nil;
    return _viewer;
}

/** The page that draws one diagram, with the viewer written into it.
 *
 * Inline rather than linked: a page loaded from a string has no folder to
 * resolve a `src` against, and copying two and a half megabytes into a
 * temporary folder for every picture is worse than holding it in a string
 * for a moment.
 *
 * The eight addresses below are the viewer's own defaults, every one of
 * them on diagrams.net. Emptied, the page reaches for nothing; left alone,
 * it fetches the shape sets and images a diagram asks for. Two of the eight
 * were emptied here at first, which is the same as none: a diagram drawn
 * with the AWS library would have gone out for its stencils and the plug-in
 * would have said it was working offline.
 */
+ (NSString *)pageForXML:(NSString *)xml
                stencils:(BOOL)stencils
                  viewer:(NSString *)viewer
{
    NSDictionary *settings = @{
        @"xml": xml,
        @"editable": @NO,
        @"toolbar": [NSNull null],
        @"resize": @YES,
        @"border": @8,
        @"zoom": @1,
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:settings
                                                   options:0 error:NULL];
    NSString *config = [[NSString alloc] initWithData:json
                                            encoding:NSUTF8StringEncoding];
    // The attribute is quoted with apostrophes, so any apostrophe inside
    // the diagram has to stop being one.
    config = [config stringByReplacingOccurrencesOfString:@"'"
                                               withString:@"&#39;"];

    NSDictionary *defaults = @{
        @"STYLE_PATH": @"/styles",
        @"SHAPES_PATH": @"/shapes",
        @"STENCIL_PATH": @"/stencils",
        @"DRAW_MATH_URL": @"/math4/es5",
        @"GRAPH_IMAGE_PATH": @"/img",
        @"mxImageBasePath": @"/mxgraph/images",
        @"mxBasePath": @"/mxgraph/",
    };
    // Empty, not relative: a path of "/stencils" against a page with no
    // base is a request that fails quietly instead of one never made.
    NSMutableString *paths = [NSMutableString stringWithString:
        @"window.PROXY_URL='';"];
    for (NSString *name in defaults)
    {
        NSString *value = stencils
            ? [@"https://viewer.diagrams.net"
                stringByAppendingString:defaults[name]]
            : @"";
        [paths appendFormat:@"window.%@='%@';", name, value];
    }
    [paths appendString:@"window.mxLoadStylesheets=false;"];

    return [NSString stringWithFormat:
        @"<!doctype html><html><head><meta charset=\"utf-8\">"
        @"<style>html,body{margin:0;padding:0;background:#fff}</style>"
        @"<script>%@</script></head><body>"
        @"<div class=\"mxgraph\" data-mxgraph='%@'></div>"
        @"<script>%@</script></body></html>",
        paths, config, viewer];
}

- (void)renderPage:(MDDrawioPage *)page
             scale:(CGFloat)scale
          stencils:(BOOL)stencils
        completion:(MDDrawioRenderHandler)handler
{
    if (!self.viewer.length)
    {
        handler(nil, [NSError errorWithDomain:MDDrawioErrorDomain
            code:MDDrawioErrorRenderFailed userInfo:@{
            NSLocalizedDescriptionKey: NSLocalizedString(
                @"Il visualizzatore draw.io non è nel plug-in: "
                @"manca viewer.min.js.", @"Drawio plug-in")}]);
        return;
    }

    self.handler = handler;
    self.scale = scale;
    self.deadline = [NSDate dateWithTimeIntervalSinceNow:kMDRenderTimeout];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    // A diagram is a document, not a program: nothing here should be able
    // to open a window or run a plug-in of its own.
    config.suppressesIncrementalRendering = YES;
    self.webView = [[WKWebView alloc]
        initWithFrame:NSMakeRect(0.0, 0.0, 1600.0, 1200.0)
        configuration:config];
    self.webView.navigationDelegate = self;

    [self.webView loadHTMLString:
        [[self class] pageForXML:page.xml stencils:stencils
                          viewer:self.viewer] baseURL:nil];
}

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation
{
    [self waitForDrawing];
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self finishWithData:nil error:error];
}

/** Asks the page how big the drawing is, until there is one.
 *
 * The viewer builds the SVG after the document has loaded, so the end of
 * the navigation is not the end of the work. Its size is what is waited
 * for, since it is also what the picture has to be.
 */
- (void)waitForDrawing
{
    NSString *ask =
        @"(function(){var s=document.querySelector('.mxgraph svg');"
        @"if(!s) return '';var b=s.getBoundingClientRect();"
        @"return Math.round(b.width)+'x'+Math.round(b.height);})()";

    [self.webView evaluateJavaScript:ask completionHandler:
        ^(id result, NSError *error) {
        NSString *size = [result isKindOfClass:[NSString class]] ? result : @"";
        NSArray *parts = [size componentsSeparatedByString:@"x"];
        CGFloat width = parts.count == 2 ? [parts[0] doubleValue] : 0.0;
        CGFloat height = parts.count == 2 ? [parts[1] doubleValue] : 0.0;

        if (width > 0.0 && height > 0.0)
        {
            [self snapshotWidth:width height:height];
            return;
        }
        if ([self.deadline timeIntervalSinceNow] <= 0.0)
        {
            [self finishWithData:nil error:
                [NSError errorWithDomain:MDDrawioErrorDomain
                    code:MDDrawioErrorRenderFailed userInfo:@{
                    NSLocalizedDescriptionKey: NSLocalizedString(
                        @"Il visualizzatore non ha disegnato niente entro "
                        @"venti secondi.", @"Drawio plug-in")}]];
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)(kMDPollInterval * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ [self waitForDrawing]; });
    }];
}

- (void)snapshotWidth:(CGFloat)width height:(CGFloat)height
{
    // The view is made exactly as big as the drawing, so the picture has no
    // white margin round it beyond the border the viewer was given.
    self.webView.frame = NSMakeRect(0.0, 0.0, width, height);

    WKSnapshotConfiguration *config = [[WKSnapshotConfiguration alloc] init];
    config.snapshotWidth = @(width * self.scale);

    // One turn of the run loop after the resize, so what is captured is the
    // laid-out page rather than the one before it.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView takeSnapshotWithConfiguration:config
                                 completionHandler:^(NSImage *image,
                                                     NSError *error) {
            if (!image)
            {
                [self finishWithData:nil error:error ?:
                    [NSError errorWithDomain:MDDrawioErrorDomain
                        code:MDDrawioErrorRenderFailed userInfo:nil]];
                return;
            }
            CGImageRef cg = [image CGImageForProposedRect:NULL context:nil
                                                    hints:nil];
            NSBitmapImageRep *rep =
                [[NSBitmapImageRep alloc] initWithCGImage:cg];
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                            properties:@{}];
            [self finishWithData:png error:nil];
        }];
    });
}

- (void)finishWithData:(NSData *)png error:(NSError *)error
{
    MDDrawioRenderHandler handler = self.handler;
    self.handler = nil;
    self.webView.navigationDelegate = nil;
    self.webView = nil;
    if (handler)
        handler(png, error);
}


#pragma mark - An export server of your own

- (void)renderPage:(MDDrawioPage *)page
             scale:(CGFloat)scale
         onService:(NSURL *)service
        completion:(MDDrawioRenderHandler)handler
{
    NSCharacterSet *safe = [NSCharacterSet
        characterSetWithCharactersInString:@"-._~"];
    NSString *xml = [page.xml
        stringByAddingPercentEncodingWithAllowedCharacters:safe];
    NSString *body = [NSString stringWithFormat:
        @"format=png&scale=%g&xml=%@", scale, xml];

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:service];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded"
        forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    request.timeoutInterval = 60.0;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request completionHandler:
        ^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error)
            {
                handler(nil, error);
                return;
            }
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            BOOL isPNG = data.length > 8
                && ((const unsigned char *)data.bytes)[1] == 'P';
            if (status != 200 || !isPNG)
            {
                // What the server said, rather than a code on its own: an
                // export server that refuses says why in the body.
                NSString *said = [[NSString alloc] initWithData:
                    [data subdataWithRange:NSMakeRange(0,
                        MIN((NSUInteger)200, data.length))]
                    encoding:NSUTF8StringEncoding];
                handler(nil, [NSError errorWithDomain:MDDrawioErrorDomain
                    code:MDDrawioErrorServiceRefused userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:
                        NSLocalizedString(@"Il server ha risposto %ld%@",
                                          @"Drawio plug-in"),
                        (long)status, said.length
                            ? [@": " stringByAppendingString:said] : @"."]}]);
                return;
            }
            handler(data, nil);
        });
    }];
    [task resume];
}

@end
