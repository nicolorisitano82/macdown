//
//  MPLinkPreview.m
//  MacDown
//

#import "MPLinkPreview.h"
#import "MPUtilities.h"
#import "MPBacklinks.h"

/// Enough to tell one document from another, and no more.
static const NSUInteger kMPPreviewLines = 4;
/// A document worth previewing is not a megabyte of it.
static const unsigned long long kMPPreviewSizeLimit = 4 * 1024 * 1024;


NSString * const MPHoverMessageName = @"macdownHover";

/// Five seconds, because a card that appears while the pointer is merely
/// crossing the page is a card in the way.
const NSTimeInterval MPHoverDelay = 5.0;


NSString *MPHoverWatchScript(NSTimeInterval seconds)
{
    /* Reports a link the pointer has been resting on, and when it leaves.
     *
     * The timer is cancelled by leaving the link, by scrolling, and by
     * moving to another one — the last of which matters in a list of links,
     * where the pointer passes over several on its way to the one it wants.
     */
    static NSString * const source =
        @"(function(){"
        @"var timer=null,current=null;"
        @"function forget(){if(timer){clearTimeout(timer);timer=null;}"
        @"if(current){current=null;"
        @"window.webkit.messageHandlers.macdownHover.postMessage({away:true});}}"
        @"document.addEventListener('mouseover',function(e){"
        @"var a=e.target&&e.target.closest?e.target.closest('a[href]'):null;"
        @"if(!a){forget();return;}"
        @"if(a===current)return;"
        @"forget();current=a;"
        @"timer=setTimeout(function(){"
        @"if(current!==a)return;"
        @"var r=a.getBoundingClientRect();"
        @"window.webkit.messageHandlers.macdownHover.postMessage({"
        @"href:a.getAttribute('href')||'',text:(a.textContent||'').slice(0,200),"
        @"left:r.left,top:r.top,width:r.width,height:r.height});"
        @"},%.0f);"
        @"},true);"
        @"document.addEventListener('mouseout',function(e){"
        @"var a=e.target&&e.target.closest?e.target.closest('a[href]'):null;"
        @"if(a&&a===current)forget();"
        @"},true);"
        @"window.addEventListener('scroll',forget);"
        @"window.addEventListener('blur',forget);"
        @"})();";
    return [NSString stringWithFormat:source, seconds * 1000.0];
}


@interface MPLinkPreview ()
@property (nonatomic) MPLinkPreviewKind kind;
@property (copy, nonatomic) NSString *title;
@property (copy, nonatomic) NSString *body;
@property (copy, nonatomic) NSString *footnote;
@property (copy, nonatomic) NSURL *fileURL;
@end


@implementation MPLinkPreview

/// The first few lines that say something, without their markup removed.
static NSString *MPOpeningLinesOf(NSString *text, NSString *skipping)
{
    NSMutableArray *kept = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"])
    {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        if (!trimmed.length)
            continue;
        // The title is shown above; repeating it is not a preview.
        if (skipping.length && [trimmed hasSuffix:skipping])
            continue;
        // Front matter says where a clipping came from, not what it says.
        if ([trimmed isEqualToString:@"---"])
            continue;
        [kept addObject:trimmed];
        if (kept.count >= kMPPreviewLines)
            break;
    }
    return [kept componentsJoinedByString:@"\n"];
}

+ (instancetype)previewForHref:(NSString *)href
                    inDocument:(NSURL *)documentURL
{
    NSString *target = [href stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!target.length || [target hasPrefix:@"#"])
        return nil;   // an anchor inside the page: nowhere to go

    MPLinkPreview *preview = [[self alloc] init];
    NSURL *url = [NSURL URLWithString:target];

    // A file, whether it says so with file: or by being a path.
    NSURL *file = nil;
    if (url.isFileURL)
    {
        file = url;
    }
    else if (!url.scheme.length && documentURL.isFileURL)
    {
        NSString *path = target.stringByRemovingPercentEncoding ?: target;
        // An anchor or a query is not part of a file's name.
        for (NSString *cut in @[@"#", @"?"])
        {
            NSRange found = [path rangeOfString:cut];
            if (found.location != NSNotFound)
                path = [path substringToIndex:found.location];
        }
        if (!path.length)
            return nil;
        file = [path hasPrefix:@"/"] ? [NSURL fileURLWithPath:path]
            : [documentURL.URLByDeletingLastPathComponent
                URLByAppendingPathComponent:path];
        file = file.URLByStandardizingPath;
    }

    if (!file)
    {
        // Somewhere else. The address, taken apart so a long one reads.
        preview.kind = MPLinkPreviewKindAddress;
        preview.title = url.host ?: target;
        NSString *rest = url.path.length ? url.path : @"/";
        if (url.query.length)
            rest = [rest stringByAppendingFormat:@"?%@", url.query];
        preview.body = rest;
        preview.footnote = url.scheme.length
            ? [url.scheme stringByAppendingString:@"://…"] : nil;
        return preview;
    }

    preview.fileURL = file;
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *name = file.lastPathComponent.stringByDeletingPathExtension;

    // A WikiLink carries no extension, and the editor tries these when it
    // follows one; so does this, or every wiki link would read as missing.
    if (![manager fileExistsAtPath:file.path] && !file.pathExtension.length)
    {
        for (NSString *extension in @[@"md", @"markdown", @"txt"])
        {
            NSURL *candidate = [file URLByAppendingPathExtension:extension];
            if ([manager fileExistsAtPath:candidate.path])
            {
                file = candidate;
                preview.fileURL = candidate;
                break;
            }
        }
    }

    if (![manager fileExistsAtPath:file.path])
    {
        preview.kind = MPLinkPreviewKindMissingFile;
        preview.title = name;
        preview.body = NSLocalizedString(
            @"Questo file non c'è ancora.", @"Link preview");
        preview.footnote = file.URLByDeletingLastPathComponent.path;
        return preview;
    }

    NSNumber *size = nil;
    NSDate *changed = nil;
    [file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    [file getResourceValue:&changed forKey:NSURLContentModificationDateKey
                     error:NULL];

    NSString *when = changed ? [NSDateFormatter
        localizedStringFromDate:changed dateStyle:NSDateFormatterMediumStyle
                      timeStyle:NSDateFormatterShortStyle] : nil;
    NSString *howBig = [NSByteCountFormatter
        stringFromByteCount:size.longLongValue
                 countStyle:NSByteCountFormatterCountStyleFile];

    static NSSet *pictures = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        pictures = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg", @"gif",
                                         @"tiff", @"heic", @"webp", @"svg",
                                         @"pdf"]];
    });
    if ([pictures containsObject:file.pathExtension.lowercaseString])
    {
        preview.kind = MPLinkPreviewKindImage;
        preview.title = file.lastPathComponent;
        preview.footnote = when ? [NSString stringWithFormat:@"%@ · %@",
                                   howBig, when] : howBig;
        return preview;
    }

    if (size.unsignedLongLongValue > kMPPreviewSizeLimit)
    {
        preview.kind = MPLinkPreviewKindDocument;
        preview.title = name;
        preview.body = NSLocalizedString(
            @"Troppo grande per essere sbirciato.", @"Link preview");
        preview.footnote = howBig;
        return preview;
    }

    NSString *text = [NSString stringWithContentsOfURL:file
        encoding:NSUTF8StringEncoding error:NULL];
    if (!text)
    {
        preview.kind = MPLinkPreviewKindDocument;
        preview.title = file.lastPathComponent;
        preview.body = NSLocalizedString(
            @"Non è testo che si possa leggere.", @"Link preview");
        preview.footnote = howBig;
        return preview;
    }

    NSString *heading = MPFirstHeadingOfText(text);
    preview.kind = MPLinkPreviewKindDocument;
    preview.title = heading.length ? heading : name;
    preview.body = MPOpeningLinesOf(text, heading);

    NSUInteger words = 0;
    for (NSString *word in [text componentsSeparatedByCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]])
    {
        if (word.length)
            words++;
    }
    preview.footnote = [NSString stringWithFormat:
        NSLocalizedString(@"%lu parole · %@", @"Link preview"),
        (unsigned long)words, when ?: howBig];
    return preview;
}

@end
