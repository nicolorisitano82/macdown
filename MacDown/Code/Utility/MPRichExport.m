//
//  MPRichExport.m
//  MacDown
//

#import "MPRichExport.h"

#import "MPZipArchive.h"


#pragma mark - Shared

/// The pixels a PNG actually holds, for the formats that want both that and
/// the size it should be drawn at.
static NSSize MPPixelSizeOfPNG(NSData *png, NSSize fallback)
{
    NSImage *image = png.length ? [[NSImage alloc] initWithData:png] : nil;
    NSInteger wide = 0;
    NSInteger high = 0;
    for (NSImageRep *rep in image.representations)
    {
        wide = MAX(wide, rep.pixelsWide);
        high = MAX(high, rep.pixelsHigh);
    }
    if (wide > 0 && high > 0)
        return NSMakeSize((CGFloat)wide, (CGFloat)high);
    return fallback;
}

NS_INLINE BOOL MPUsablePicture(MPDocxImage *image)
{
    return image.pngData.length && image.placeholder.length
        && image.pointSize.width > 0.0 && image.pointSize.height > 0.0;
}


#pragma mark - OpenDocument

/// The XML for one picture, anchored in the line where its marker stood.
static NSString *MPOdtFrameForImage(MPDocxImage *image, NSString *path)
{
    // Inches rather than points: ODF wants a unit, and every reader agrees
    // about `in`. Three decimals is a thousandth of an inch, which is finer
    // than any screen this is read on.
    return [NSString stringWithFormat:
        @"<draw:frame text:anchor-type=\"as-char\" draw:z-index=\"0\" "
        @"svg:width=\"%.3fin\" svg:height=\"%.3fin\">"
        @"<draw:image xlink:href=\"%@\" xlink:type=\"simple\" "
        @"xlink:show=\"embed\" xlink:actuate=\"onLoad\"/></draw:frame>",
        image.pointSize.width / 72.0, image.pointSize.height / 72.0, path];
}


NSData *MPOdtDataByEmbeddingImages(NSData *odtData,
                                   NSArray<MPDocxImage *> *images,
                                   NSMutableArray<NSString *> *unplaced)
{
    if (!odtData.length)
        return nil;
    if (!images.count)
        return odtData;

    NSMutableArray<MPZipEntry *> *entries = [MPZipRead(odtData) mutableCopy];
    if (!entries.count)
        return nil;

    NSString *content = MPStringFromEntry(entries, @"content.xml");
    NSString *manifest = MPStringFromEntry(entries,
                                           @"META-INF/manifest.xml");
    if (!content.length)
        return nil;

    NSMutableString *xml = [content mutableCopy];
    NSMutableString *listed = [(manifest ?: @"") mutableCopy];
    NSMutableArray<MPZipEntry *> *pictures = [NSMutableArray array];

    NSUInteger planted = 0;
    for (MPDocxImage *image in images)
    {
        if (!MPUsablePicture(image))
            continue;

        NSRange marker = [xml rangeOfString:image.placeholder];
        if (marker.location == NSNotFound)
        {
            if (image.source.length)
                [unplaced addObject:image.source];
            continue;
        }

        NSString *path = [NSString stringWithFormat:@"Pictures/image%lu.png",
                          (unsigned long)pictures.count + 1];
        [xml replaceCharactersInRange:marker
                           withString:MPOdtFrameForImage(image, path)];
        [pictures addObject:MPStoredEntry(path, image.pngData)];

        // A file the manifest does not list is a file the reader refuses to
        // show, however correct the reference to it is.
        NSRange end = [listed rangeOfString:@"</manifest:manifest>"];
        if (end.location != NSNotFound)
        {
            NSString *line = [NSString stringWithFormat:
                @"<manifest:file-entry manifest:full-path=\"%@\" "
                @"manifest:media-type=\"image/png\"/>", path];
            [listed insertString:line atIndex:end.location];
        }
        planted++;
    }

    if (!planted)
        return odtData;

    for (NSUInteger i = 0; i < entries.count; i++)
    {
        if ([entries[i].name isEqualToString:@"content.xml"])
        {
            entries[i] = MPStoredEntry(@"content.xml",
                [xml dataUsingEncoding:NSUTF8StringEncoding]);
        }
        else if ([entries[i].name isEqualToString:@"META-INF/manifest.xml"]
                 && listed.length)
        {
            entries[i] = MPStoredEntry(@"META-INF/manifest.xml",
                [listed dataUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    // Appended, so that `mimetype` keeps the first place the format demands.
    [entries addObjectsFromArray:pictures];

    return MPZipWrite(entries);
}


#pragma mark - RTF

/// One picture, as RTF says a picture is written.
static NSString *MPRtfPictureForImage(MPDocxImage *image)
{
    NSSize pixels = MPPixelSizeOfPNG(image.pngData, image.pointSize);

    NSMutableString *hex =
        [NSMutableString stringWithCapacity:image.pngData.length * 2 + 64];
    const unsigned char *bytes = image.pngData.bytes;
    for (NSUInteger i = 0; i < image.pngData.length; i++)
    {
        [hex appendFormat:@"%02x", bytes[i]];
        // Long lines are legal and awkward; readers and diff tools alike
        // prefer a document they can look at.
        if ((i + 1) % 64 == 0)
            [hex appendString:@"\n"];
    }

    // picw/pich are the picture's own pixels; the goal sizes are how big it
    // should be drawn, in twips — a twentieth of a point.
    return [NSString stringWithFormat:
        @"{\\pict\\pngblip\\picw%ld\\pich%ld\\picwgoal%ld\\pichgoal%ld\n%@}",
        (long)lround(pixels.width), (long)lround(pixels.height),
        (long)lround(image.pointSize.width * 20.0),
        (long)lround(image.pointSize.height * 20.0), hex];
}


NSData *MPRtfDataByEmbeddingImages(NSData *rtfData,
                                   NSArray<MPDocxImage *> *images,
                                   NSMutableArray<NSString *> *unplaced)
{
    if (!rtfData.length)
        return nil;
    if (!images.count)
        return rtfData;

    // RTF is seven-bit text with its own escapes for everything else, and
    // Latin-1 maps every byte to a character and back without loss, which is
    // what a search and replace over the stream needs.
    NSString *text = [[NSString alloc] initWithData:rtfData
                                           encoding:NSISOLatin1StringEncoding];
    if (!text.length)
        return nil;

    NSMutableString *out = [text mutableCopy];
    NSUInteger planted = 0;
    for (MPDocxImage *image in images)
    {
        if (!MPUsablePicture(image))
            continue;

        NSRange marker = [out rangeOfString:image.placeholder];
        if (marker.location == NSNotFound)
        {
            if (image.source.length)
                [unplaced addObject:image.source];
            continue;
        }
        [out replaceCharactersInRange:marker
                           withString:MPRtfPictureForImage(image)];
        planted++;
    }

    if (!planted)
        return rtfData;
    return [out dataUsingEncoding:NSISOLatin1StringEncoding];
}
