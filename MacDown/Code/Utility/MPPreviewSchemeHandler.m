//
//  MPPreviewSchemeHandler.m
//  MacDown
//

#import "MPPreviewSchemeHandler.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSString * const MPPreviewURLScheme = @"macdown-preview";

NSURL *MPPreviewURLForPath(NSString *path)
{
    if (!path.length)
        return nil;

    // Built through URLComponents rather than by pasting the path into a
    // string: a document may sit in a directory with a space or a hash in
    // its name, and either would end the URL early.
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = MPPreviewURLScheme;
    components.host = @"";
    components.path = path.stringByStandardizingPath;
    return components.URL;
}

@implementation MPPreviewSchemeHandler

- (void)webView:(WKWebView *)webView
    startURLSchemeTask:(id<WKURLSchemeTask>)task
{
    NSURL *url = task.request.URL;
    NSString *path = url.path.stringByRemovingPercentEncoding;

    NSData *data = path.length
        ? [NSData dataWithContentsOfFile:path] : nil;
    if (!data)
    {
        // A missing file is ordinary here — a document can link to an image
        // that is not there yet — so it is answered rather than treated as a
        // failure of the scheme.
        NSHTTPURLResponse *missing = [[NSHTTPURLResponse alloc]
            initWithURL:url statusCode:404 HTTPVersion:@"HTTP/1.1"
           headerFields:nil];
        [task didReceiveResponse:missing];
        [task didFinish];
        return;
    }

    NSString *mime = nil;
    NSString *extension = path.pathExtension;
    if (extension.length)
    {
        UTType *type = [UTType typeWithFilenameExtension:extension];
        mime = type.preferredMIMEType;
    }
    if (!mime.length)
        mime = @"application/octet-stream";

    // Every asset is local and regenerated on each render, so nothing here
    // should ever be served from a cache.
    NSDictionary *headers = @{
        @"Content-Type": mime,
        @"Content-Length": [@(data.length) stringValue],
        @"Cache-Control": @"no-store",
        @"Access-Control-Allow-Origin": @"*",
    };
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
        initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1"
       headerFields:headers];

    [task didReceiveResponse:response];
    [task didReceiveData:data];
    [task didFinish];
}

- (void)webView:(WKWebView *)webView
    stopURLSchemeTask:(id<WKURLSchemeTask>)task
{
    // Everything is read from disk in one go, so there is nothing in flight
    // to cancel.
}

@end
