//
//  MPEpubExport.m
//  MacDown
//

#import "MPEpubExport.h"
#import "MPZipArchive.h"


@implementation MPEpubMetadata
@end


#pragma mark - Escaping

/** Turns the entities in rendered HTML back into the characters they stand
 *  for, so that escaping them for XML escapes them once and not twice.
 *
 * A heading's text is taken from the HTML, where an apostrophe is already
 * `&#39;`. Escaped again it becomes `&amp;#39;`, and a reader shows the
 * contents entry with the entity spelled out in it.
 */
NS_INLINE NSString *MPEpubDecoded(NSString *text)
{
    if ([text rangeOfString:@"&"].location == NSNotFound)
        return text;

    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    NSDictionary *named = @{@"amp": @"&", @"lt": @"<", @"gt": @">",
                            @"quot": @"\"", @"apos": @"'", @"nbsp": @"\u00a0"};
    NSUInteger i = 0;
    while (i < text.length)
    {
        unichar c = [text characterAtIndex:i];
        if (c != '&')
        {
            [out appendFormat:@"%C", c];
            i++;
            continue;
        }

        NSRange window = NSMakeRange(i, MIN((NSUInteger)10, text.length - i));
        NSRange end = [text rangeOfString:@";" options:0 range:window];
        if (end.location == NSNotFound || end.location == i + 1)
        {
            [out appendString:@"&"];
            i++;
            continue;
        }

        NSString *name = [text substringWithRange:
            NSMakeRange(i + 1, end.location - i - 1)];
        NSString *value = named[name.lowercaseString];
        if (value)
        {
            [out appendString:value];
        }
        else if ([name hasPrefix:@"#"])
        {
            NSString *digits = [name substringFromIndex:1];
            BOOL hex = [digits.lowercaseString hasPrefix:@"x"];
            unsigned int point = 0;
            unsigned long long decimal = 0;
            NSScanner *scanner = [NSScanner scannerWithString:
                hex ? [digits substringFromIndex:1] : digits];
            BOOL ok = hex ? [scanner scanHexInt:&point]
                          : [scanner scanUnsignedLongLong:&decimal];
            uint32_t code = (uint32_t)(hex ? point : decimal);
            NSString *character = nil;
            if (ok && code && code <= 0x10FFFF)
                character = [[NSString alloc] initWithBytes:&code
                    length:sizeof(code)
                  encoding:NSUTF32LittleEndianStringEncoding];
            [out appendString:character ?: @""];
        }
        else
        {
            [out appendString:[text substringWithRange:
                NSMakeRange(i, end.location - i + 1)]];
        }
        i = end.location + 1;
    }
    return out;
}

NS_INLINE NSString *MPEpubEscaped(NSString *text)
{
    NSMutableString *out = [text mutableCopy] ?: [NSMutableString string];
    NSArray *pairs = @[@[@"&", @"&amp;"], @[@"<", @"&lt;"], @[@">", @"&gt;"],
                       @[@"\"", @"&quot;"]];
    for (NSArray *pair in pairs)
    {
        [out replaceOccurrencesOfString:pair[0] withString:pair[1] options:0
                                  range:NSMakeRange(0, out.length)];
    }
    return out;
}


#pragma mark - XHTML

/** Makes the rendered HTML into the XHTML an EPUB content document must be.
 *
 * Done by parsing it as HTML and writing it back out as XML, rather than by
 * patching up the markup by hand. Hand-patching means keeping a list of void
 * elements and a list of named entities, and the second list is the problem:
 * HTML has upwards of two thousand, a document may use any of them, and each
 * one missing from the list is an EPUB that no reader will open.
 *
 * Returns nil if the markup cannot be parsed at all.
 */
NS_INLINE NSString *MPXHTMLFromHTML(NSString *html)
{
    // Tidy is an HTML tidier, and it discards elements HTML does not have —
    // <svg> among them, which is how a typeset formula disappears between
    // the preview and the package. SVG is already well formed XML and needs
    // none of the repair the rest of the markup does, so it is lifted out,
    // kept aside, and put back afterwards.
    NSMutableArray<NSString *> *svgs = [NSMutableArray array];
    NSRegularExpression *svgRegex = [NSRegularExpression
        regularExpressionWithPattern:@"<svg[\\s\\S]*?</svg>"
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];
    NSMutableString *guarded = [html mutableCopy];
    NSArray<NSTextCheckingResult *> *svgMatches =
        [svgRegex matchesInString:guarded options:0
                            range:NSMakeRange(0, guarded.length)];
    for (NSInteger i = (NSInteger)svgMatches.count - 1; i >= 0; i--)
    {
        NSRange range = svgMatches[(NSUInteger)i].range;
        [svgs insertObject:[guarded substringWithRange:range] atIndex:0];
        NSString *token = [NSString stringWithFormat:
            @"<span id=\"mp-svg-%ld\"></span>", (long)i];
        [guarded replaceCharactersInRange:range withString:token];
    }
    html = guarded;

    NSString *wrapped = [NSString stringWithFormat:
        @"<html><body>%@</body></html>", html];

    NSError *error = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc]
        initWithXMLString:wrapped
                  options:NSXMLDocumentTidyHTML | NSXMLNodePreserveWhitespace
                    error:&error];
    if (!document)
        return nil;

    NSArray *bodies = [document.rootElement elementsForName:@"body"];
    NSXMLElement *body = bodies.firstObject ?: document.rootElement;

    NSMutableString *out = [NSMutableString string];
    for (NSXMLNode *child in body.children)
    {
        // Compact, not PreserveAll: the latter carries
        // NSXMLNodePreserveEmptyElements with it, which writes a line break
        // as <br></br>. Well formed, but not what anyone expects to read.
        [out appendString:
            [child XMLStringWithOptions:NSXMLNodeCompactEmptyElement]];
    }
    // Void elements come back as <br></br>: the parser was told to preserve
    // whitespace, so the newline after the tag ends up inside it, and an
    // element with a child cannot be written compactly. Well formed either
    // way, but nothing that reads XHTML expects to see a closing </br>.
    NSRegularExpression *voids = [NSRegularExpression
        regularExpressionWithPattern:
            @"<(br|hr|img|meta|link|input|col|area|base|source|wbr)"
            @"((?:[^<>]*?))>\\s*</\\1>"
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];
    [voids replaceMatchesInString:out options:0
                            range:NSMakeRange(0, out.length)
                     withTemplate:@"<$1$2/>"];

    for (NSUInteger i = 0; i < svgs.count; i++)
    {
        // Written either way round depending on whether tidy kept the span
        // as an empty element or gave it a closing tag.
        NSString *empty = [NSString stringWithFormat:
            @"<span id=\"mp-svg-%lu\"/>", (unsigned long)i];
        NSString *paired = [NSString stringWithFormat:
            @"<span id=\"mp-svg-%lu\"></span>", (unsigned long)i];
        NSRange all = NSMakeRange(0, out.length);
        [out replaceOccurrencesOfString:empty withString:svgs[i]
                                options:0 range:all];
        all = NSMakeRange(0, out.length);
        [out replaceOccurrencesOfString:paired withString:svgs[i]
                                options:0 range:all];
    }
    return out;
}


#pragma mark - Headings

@interface MPEpubHeading : NSObject
@property (copy, nonatomic) NSString *title;
@property (copy, nonatomic) NSString *anchor;
@property (assign, nonatomic) NSInteger level;
@end

@implementation MPEpubHeading
@end

/** Finds the headings and gives each one an id to be linked to.
 *
 * The ids are added to the markup as it goes, so the table of contents and
 * the content document cannot disagree about them.
 */
NS_INLINE NSArray<MPEpubHeading *> *MPHeadingsByAnchoring(NSMutableString *html)
{
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<h([1-6])([^>]*)>([\\s\\S]*?)</h\\1>"
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];
    NSRegularExpression *tags = [NSRegularExpression
        regularExpressionWithPattern:@"<[^>]+>" options:0 error:NULL];

    NSMutableArray<MPEpubHeading *> *headings = [NSMutableArray array];
    NSArray<NSTextCheckingResult *> *matches =
        [regex matchesInString:html options:0
                         range:NSMakeRange(0, html.length)];

    // Back to front, so each rewrite leaves the earlier ranges valid.
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--)
    {
        NSTextCheckingResult *match = matches[(NSUInteger)i];
        NSString *level = [html substringWithRange:[match rangeAtIndex:1]];
        NSString *attributes = [html substringWithRange:[match rangeAtIndex:2]];
        NSString *inner = [html substringWithRange:[match rangeAtIndex:3]];

        NSString *text = [tags stringByReplacingMatchesInString:inner options:0
            range:NSMakeRange(0, inner.length) withTemplate:@""];
        text = [text stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!text.length)
            continue;

        // hoedown gives headings an id of its own when the table of
        // contents extension is on. Adding a second one makes the element
        // ill-formed, the parser drops one of them, and the contents end up
        // pointing at an anchor that is not there.
        NSRegularExpression *existing = [NSRegularExpression
            regularExpressionWithPattern:@"\\bid=\"([^\"]+)\""
                                 options:NSRegularExpressionCaseInsensitive
                                   error:NULL];
        NSTextCheckingResult *found =
            [existing firstMatchInString:attributes options:0
                                   range:NSMakeRange(0, attributes.length)];

        NSString *anchor;
        NSString *replacement;
        if (found)
        {
            anchor = [attributes substringWithRange:[found rangeAtIndex:1]];
            replacement = nil;      // nothing to rewrite
        }
        else
        {
            anchor = [NSString stringWithFormat:@"heading-%ld", (long)i];
            replacement = [NSString stringWithFormat:
                @"<h%@ id=\"%@\"%@>%@</h%@>",
                level, anchor, attributes, inner, level];
        }

        MPEpubHeading *heading = [[MPEpubHeading alloc] init];
        heading.title = MPEpubDecoded(text);
        heading.anchor = anchor;
        heading.level = level.integerValue;
        [headings insertObject:heading atIndex:0];

        if (replacement)
            [html replaceCharactersInRange:match.range withString:replacement];
    }
    return headings;
}


#pragma mark - Images

@interface MPEpubImage : NSObject
@property (copy, nonatomic) NSString *href;      // inside the package
@property (copy, nonatomic) NSString *mediaType;
@property (strong, nonatomic) NSData *data;
@property (copy, nonatomic) NSString *identifier;
@end

@implementation MPEpubImage
@end

NS_INLINE NSString *MPMediaTypeForExtension(NSString *extension)
{
    static NSDictionary *types = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        types = @{@"png": @"image/png", @"jpg": @"image/jpeg",
                  @"jpeg": @"image/jpeg", @"gif": @"image/gif",
                  @"svg": @"image/svg+xml", @"webp": @"image/webp"};
    });
    return types[extension.lowercaseString];
}

/** Copies the images into the package and repoints the markup at them.
 *
 * Anything that cannot be read — a remote URL, a missing file, a format an
 * EPUB may not carry — is left alone rather than dropped, so the document
 * still says an image belongs there.
 */
NS_INLINE NSArray<MPEpubImage *> *MPImagesByRewriting(NSMutableString *html,
                                                      NSURL *baseURL)
{
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<img\\b[^>]*?\\bsrc=\"([^\"]+)\""
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];

    NSMutableArray<MPEpubImage *> *images = [NSMutableArray array];
    NSArray<NSTextCheckingResult *> *matches =
        [regex matchesInString:html options:0
                         range:NSMakeRange(0, html.length)];

    NSUInteger index = 0;
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--)
    {
        NSTextCheckingResult *match = matches[(NSUInteger)i];
        NSRange sourceRange = [match rangeAtIndex:1];
        NSString *source = [html substringWithRange:sourceRange];

        NSData *data = nil;
        NSString *extension = nil;

        if ([source hasPrefix:@"data:"])
        {
            NSRange comma = [source rangeOfString:@","];
            NSRange semicolon = [source rangeOfString:@";"];
            if (comma.location == NSNotFound)
                continue;
            NSString *payload =
                [source substringFromIndex:NSMaxRange(comma)];
            data = [[NSData alloc] initWithBase64EncodedString:payload
                options:NSDataBase64DecodingIgnoreUnknownCharacters];
            if (semicolon.location != NSNotFound && semicolon.location > 5)
            {
                NSString *type = [source substringWithRange:
                    NSMakeRange(5, semicolon.location - 5)];
                extension = [type componentsSeparatedByString:@"/"].lastObject;
            }
        }
        else
        {
            NSURL *url = [NSURL URLWithString:source relativeToURL:baseURL];
            if (!url.isFileURL)
                continue;
            data = [NSData dataWithContentsOfURL:url];
            extension = url.pathExtension;
        }

        NSString *mediaType = MPMediaTypeForExtension(extension);
        if (!data.length || !mediaType)
            continue;

        MPEpubImage *image = [[MPEpubImage alloc] init];
        image.identifier = [NSString stringWithFormat:@"img-%lu",
                            (unsigned long)index];
        image.href = [NSString stringWithFormat:@"images/%@.%@",
                      image.identifier, extension.lowercaseString];
        image.mediaType = mediaType;
        image.data = data;
        [images insertObject:image atIndex:0];
        index++;

        [html replaceCharactersInRange:sourceRange withString:image.href];
    }
    return images;
}


#pragma mark - Package

NS_INLINE NSString *MPEpubTimestamp(void)
{
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    // The form EPUB asks for, to the second, with no fraction.
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    return [formatter stringFromDate:[NSDate date]];
}

NS_INLINE NSString *MPNavXHTML(NSArray<MPEpubHeading *> *headings,
                               NSString *title, NSString *language)
{
    NSMutableString *list = [NSMutableString string];
    if (headings.count)
    {
        [list appendString:@"<ol>\n"];
        for (MPEpubHeading *heading in headings)
        {
            [list appendFormat:
                @"<li><a href=\"content.xhtml#%@\">%@</a></li>\n",
                MPEpubEscaped(heading.anchor), MPEpubEscaped(heading.title)];
        }
        [list appendString:@"</ol>\n"];
    }
    else
    {
        // A nav document must carry a toc, even for a document with no
        // headings at all, so it points at the one content file.
        [list appendFormat:@"<ol>\n<li><a href=\"content.xhtml\">%@</a></li>\n"
                           @"</ol>\n", MPEpubEscaped(title)];
    }

    return [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" "
        @"xmlns:epub=\"http://www.idpf.org/2007/ops\" xml:lang=\"%@\">\n"
        @"<head><title>%@</title>"
        @"<meta charset=\"utf-8\"/></head>\n"
        @"<body>\n<nav epub:type=\"toc\" id=\"toc\">\n<h1>%@</h1>\n%@</nav>\n"
        @"</body>\n</html>\n",
        MPEpubEscaped(language ?: @"en"),
        MPEpubEscaped(title), MPEpubEscaped(title), list];
}

NS_INLINE NSString *MPPackageOPF(MPEpubMetadata *metadata,
                                 NSArray<MPEpubImage *> *images,
                                 BOOL contentHasSVG)
{
    NSMutableString *manifest = [NSMutableString string];
    // A reading system is told in the manifest what it will find inside a
    // document before it opens it, and a formula rendered as inline SVG has
    // to be declared or the book does not conform.
    [manifest appendFormat:
        @"<item id=\"nav\" href=\"nav.xhtml\" "
        @"media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n"
        @"<item id=\"content\" href=\"content.xhtml\" "
        @"media-type=\"application/xhtml+xml\"%@/>\n"
        @"<item id=\"style\" href=\"style.css\" media-type=\"text/css\"/>\n",
        contentHasSVG ? @" properties=\"svg\"" : @""];
    for (MPEpubImage *image in images)
    {
        [manifest appendFormat:
            @"<item id=\"%@\" href=\"%@\" media-type=\"%@\"/>\n",
            MPEpubEscaped(image.identifier), MPEpubEscaped(image.href),
            image.mediaType];
    }

    NSMutableString *author = [NSMutableString string];
    if (metadata.author.length)
    {
        [author appendFormat:@"<dc:creator>%@</dc:creator>\n",
            MPEpubEscaped(metadata.author)];
    }

    return [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" "
        @"unique-identifier=\"pub-id\" xml:lang=\"%@\">\n"
        @"<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
        @"<dc:identifier id=\"pub-id\">%@</dc:identifier>\n"
        @"<dc:title>%@</dc:title>\n"
        @"<dc:language>%@</dc:language>\n"
        @"%@"
        @"<meta property=\"dcterms:modified\">%@</meta>\n"
        @"</metadata>\n"
        @"<manifest>\n%@</manifest>\n"
        @"<spine>\n<itemref idref=\"content\"/>\n</spine>\n"
        @"</package>\n",
        MPEpubEscaped(metadata.language), MPEpubEscaped(metadata.identifier),
        MPEpubEscaped(metadata.title), MPEpubEscaped(metadata.language),
        author, MPEpubTimestamp(), manifest];
}


#pragma mark - Entry point

NSData *MPEpubDataFromHTML(NSString *html, NSString *css, NSURL *baseURL,
                           MPEpubMetadata *metadata)
{
    if (!html.length)
        return nil;

    MPEpubMetadata *info = metadata ?: [[MPEpubMetadata alloc] init];
    if (!info.title.length)
        info.title = baseURL.lastPathComponent.stringByDeletingPathExtension;
    if (!info.title.length)
        info.title = NSLocalizedString(@"Untitled", @"fallback EPUB title");
    if (!info.language.length)
        info.language = [NSLocale currentLocale].languageCode ?: @"en";
    if (!info.identifier.length)
    {
        info.identifier = [NSString stringWithFormat:@"urn:uuid:%@",
            [NSUUID UUID].UUIDString.lowercaseString];
    }

    // The body only. A whole HTML document would nest one inside another.
    NSRegularExpression *bodyRegex = [NSRegularExpression
        regularExpressionWithPattern:@"<body[^>]*>([\\s\\S]*)</body>"
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];
    NSTextCheckingResult *bodyMatch =
        [bodyRegex firstMatchInString:html options:0
                                range:NSMakeRange(0, html.length)];
    NSString *inner = bodyMatch
        ? [html substringWithRange:[bodyMatch rangeAtIndex:1]] : html;

    NSMutableString *body = [inner mutableCopy];

    // Out with the scripts. A reading system is not obliged to run them and
    // most will not, and the bundled MathJax alone is two megabytes — in
    // every exported file, to no purpose.
    NSRegularExpression *scripts = [NSRegularExpression
        regularExpressionWithPattern:@"<script\\b[^>]*>[\\s\\S]*?</script>"
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];
    [scripts replaceMatchesInString:body options:0
                              range:NSMakeRange(0, body.length)
                       withTemplate:@""];

    NSArray<MPEpubImage *> *images = MPImagesByRewriting(body, baseURL);
    NSArray<MPEpubHeading *> *headings = MPHeadingsByAnchoring(body);

    NSString *xhtmlBody = MPXHTMLFromHTML(body);
    if (!xhtmlBody)
        return nil;

    NSString *content = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"%@\">\n"
        @"<head>\n<meta charset=\"utf-8\"/>\n<title>%@</title>\n"
        @"<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/>\n"
        @"</head>\n<body>\n%@\n</body>\n</html>\n",
        MPEpubEscaped(info.language), MPEpubEscaped(info.title), xhtmlBody];

    NSMutableArray<MPZipEntry *> *entries = [NSMutableArray array];

    // First, and stored rather than deflated: a reader identifies the file
    // by finding this at a fixed offset.
    [entries addObject:MPStoredEntry(@"mimetype",
        [@"application/epub+zip" dataUsingEncoding:NSUTF8StringEncoding])];

    NSString *container =
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        @"<container version=\"1.0\" "
        @"xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n"
        @"<rootfiles>\n<rootfile full-path=\"EPUB/package.opf\" "
        @"media-type=\"application/oebps-package+xml\"/>\n"
        @"</rootfiles>\n</container>\n";

    NSDictionary<NSString *, NSString *> *documents = @{
        @"META-INF/container.xml": container,
        @"EPUB/package.opf": MPPackageOPF(info, images,
            [content rangeOfString:@"<svg"].location != NSNotFound),
        @"EPUB/nav.xhtml": MPNavXHTML(headings, info.title, info.language),
        @"EPUB/content.xhtml": content,
        @"EPUB/style.css": css ?: @"",
    };
    for (NSString *name in @[@"META-INF/container.xml", @"EPUB/package.opf",
                             @"EPUB/nav.xhtml", @"EPUB/content.xhtml",
                             @"EPUB/style.css"])
    {
        [entries addObject:MPStoredEntry(name,
            [documents[name] dataUsingEncoding:NSUTF8StringEncoding])];
    }

    for (MPEpubImage *image in images)
    {
        [entries addObject:MPStoredEntry(
            [@"EPUB/" stringByAppendingString:image.href], image.data)];
    }

    return MPZipWrite(entries);
}
