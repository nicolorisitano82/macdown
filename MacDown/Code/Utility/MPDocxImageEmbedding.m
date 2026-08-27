//
//  MPDocxImageEmbedding.m
//  MacDown
//
//  A .docx is a zip of XML parts. Foundation has no zip API, so this carries
//  the little of the format it needs: read the central directory, inflate the
//  three parts that get edited, and write the archive back out. Parts that are
//  not edited are copied across with their compressed bytes untouched, so the
//  only codec needed is an inflater, which libcompression provides.
//

#import "MPDocxImageEmbedding.h"
#import <compression.h>

#pragma mark - CRC32

static uint32_t MPCRC32(NSData *data)
{
    static uint32_t table[256];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (uint32_t i = 0; i < 256; i++)
        {
            uint32_t c = i;
            for (int k = 0; k < 8; k++)
                c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            table[i] = c;
        }
    });

    uint32_t crc = 0xFFFFFFFFu;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++)
        crc = table[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

#pragma mark - Little-endian access

NS_INLINE uint16_t MPRead16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
NS_INLINE uint32_t MPRead32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
NS_INLINE void MPAppend16(NSMutableData *d, uint16_t v) {
    uint8_t b[2] = {(uint8_t)(v & 0xFF), (uint8_t)(v >> 8)};
    [d appendBytes:b length:2];
}
NS_INLINE void MPAppend32(NSMutableData *d, uint32_t v) {
    uint8_t b[4] = {(uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF),
                    (uint8_t)((v >> 16) & 0xFF), (uint8_t)((v >> 24) & 0xFF)};
    [d appendBytes:b length:4];
}

#pragma mark - Entries

@interface MPZipEntry : NSObject
@property (copy) NSString *name;
@property uint16_t method;      // 0 stored, 8 deflated
@property uint32_t crc;
@property (copy) NSData *payload;   // as stored, matching method
@property uint32_t uncompressedSize;
@end
@implementation MPZipEntry
@end

/// Reads the central directory. Sizes and CRCs come from there rather than
/// from the local headers, which may defer them to a data descriptor.
static NSArray<MPZipEntry *> *MPZipRead(NSData *zip)
{
    const uint8_t *base = zip.bytes;
    NSUInteger length = zip.length;
    if (length < 22)
        return nil;

    // End of central directory, scanning back past any trailing comment.
    NSInteger eocd = -1;
    NSUInteger lowest = length > 65557 ? length - 65557 : 0;
    for (NSInteger i = (NSInteger)length - 22; i >= (NSInteger)lowest; i--)
    {
        if (MPRead32(base + i) == 0x06054b50) { eocd = i; break; }
    }
    if (eocd < 0)
        return nil;

    uint16_t count = MPRead16(base + eocd + 10);
    uint32_t cdOffset = MPRead32(base + eocd + 16);

    NSMutableArray<MPZipEntry *> *entries = [NSMutableArray array];
    NSUInteger p = cdOffset;
    for (uint16_t i = 0; i < count; i++)
    {
        if (p + 46 > length || MPRead32(base + p) != 0x02014b50)
            return nil;
        uint16_t method = MPRead16(base + p + 10);
        uint32_t crc = MPRead32(base + p + 16);
        uint32_t csize = MPRead32(base + p + 20);
        uint32_t usize = MPRead32(base + p + 24);
        uint16_t nameLen = MPRead16(base + p + 28);
        uint16_t extraLen = MPRead16(base + p + 30);
        uint16_t commentLen = MPRead16(base + p + 32);
        uint32_t localOffset = MPRead32(base + p + 42);

        NSString *name = [[NSString alloc]
            initWithBytes:base + p + 46 length:nameLen
                 encoding:NSUTF8StringEncoding];

        // Local header, to find where the payload actually starts.
        if (localOffset + 30 > length
            || MPRead32(base + localOffset) != 0x04034b50)
            return nil;
        uint16_t localNameLen = MPRead16(base + localOffset + 26);
        uint16_t localExtraLen = MPRead16(base + localOffset + 28);
        NSUInteger dataStart = localOffset + 30 + localNameLen + localExtraLen;
        if (dataStart + csize > length)
            return nil;

        MPZipEntry *entry = [MPZipEntry new];
        entry.name = name;
        entry.method = method;
        entry.crc = crc;
        entry.uncompressedSize = usize;
        entry.payload = [zip subdataWithRange:NSMakeRange(dataStart, csize)];
        [entries addObject:entry];

        p += 46 + nameLen + extraLen + commentLen;
    }
    return entries;
}

/// Raw DEFLATE, which is what zip method 8 holds.
static NSData *MPInflate(NSData *deflated, uint32_t expectedSize)
{
    if (!expectedSize)
        return [NSData data];
    NSMutableData *out = [NSMutableData dataWithLength:expectedSize];
    size_t written = compression_decode_buffer(
        out.mutableBytes, expectedSize,
        deflated.bytes, deflated.length, NULL, COMPRESSION_ZLIB);
    if (written != expectedSize)
        return nil;
    return out;
}

/// Writes entries back out. Anything rebuilt is stored uncompressed, which a
/// zip reader handles the same as deflated and spares us an encoder.
static NSData *MPZipWrite(NSArray<MPZipEntry *> *entries)
{
    NSMutableData *out = [NSMutableData data];
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray array];

    for (MPZipEntry *e in entries)
    {
        [offsets addObject:@(out.length)];
        NSData *nameData = [e.name dataUsingEncoding:NSUTF8StringEncoding];
        MPAppend32(out, 0x04034b50);
        MPAppend16(out, 20);            // version needed
        MPAppend16(out, 0);             // flags
        MPAppend16(out, e.method);
        MPAppend16(out, 0);             // time
        MPAppend16(out, 0x21);          // date: 1980-01-01
        MPAppend32(out, e.crc);
        MPAppend32(out, (uint32_t)e.payload.length);
        MPAppend32(out, e.uncompressedSize);
        MPAppend16(out, (uint16_t)nameData.length);
        MPAppend16(out, 0);             // extra
        [out appendData:nameData];
        [out appendData:e.payload];
    }

    NSUInteger cdStart = out.length;
    NSUInteger i = 0;
    for (MPZipEntry *e in entries)
    {
        NSData *nameData = [e.name dataUsingEncoding:NSUTF8StringEncoding];
        MPAppend32(out, 0x02014b50);
        MPAppend16(out, 20);            // version made by
        MPAppend16(out, 20);            // version needed
        MPAppend16(out, 0);             // flags
        MPAppend16(out, e.method);
        MPAppend16(out, 0);
        MPAppend16(out, 0x21);
        MPAppend32(out, e.crc);
        MPAppend32(out, (uint32_t)e.payload.length);
        MPAppend32(out, e.uncompressedSize);
        MPAppend16(out, (uint16_t)nameData.length);
        MPAppend16(out, 0);             // extra
        MPAppend16(out, 0);             // comment
        MPAppend16(out, 0);             // disk
        MPAppend16(out, 0);             // internal attrs
        MPAppend32(out, 0);             // external attrs
        MPAppend32(out, (uint32_t)offsets[i++].unsignedLongLongValue);
        [out appendData:nameData];
    }

    // Measured before the record itself is appended, or it counts its own
    // bytes as part of the directory.
    NSUInteger cdSize = out.length - cdStart;

    MPAppend32(out, 0x06054b50);
    MPAppend16(out, 0);
    MPAppend16(out, 0);
    MPAppend16(out, (uint16_t)entries.count);
    MPAppend16(out, (uint16_t)entries.count);
    MPAppend32(out, (uint32_t)cdSize);
    MPAppend32(out, (uint32_t)cdStart);
    MPAppend16(out, 0);
    return out;
}
// --- docx transform -------------------------------------------------------

@implementation MPDocxImage
@end

/// 1pt = 12700 EMU, the unit DrawingML measures in.
NS_INLINE int64_t MPEMUFromPoints(CGFloat points)
{
    return (int64_t)llround((double)points * 12700.0);
}

static NSString *MPDrawingXML(NSString *relationshipId, NSUInteger index,
                              NSSize pointSize)
{
    int64_t cx = MPEMUFromPoints(pointSize.width);
    int64_t cy = MPEMUFromPoints(pointSize.height);
    NSUInteger docPrId = 1000 + index;

    // xmlns:a is declared here because the document root does not carry it,
    // unlike wp: and r: which it does.
    return [NSString stringWithFormat:
        @"<w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" "
        @"distR=\"0\"><wp:extent cx=\"%lld\" cy=\"%lld\"/>"
        @"<wp:docPr id=\"%lu\" name=\"Diagram %lu\"/>"
        @"<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/"
        @"drawingml/2006/main\"><a:graphicData uri=\"http://"
        @"schemas.openxmlformats.org/drawingml/2006/picture\">"
        @"<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/"
        @"drawingml/2006/picture\"><pic:nvPicPr>"
        @"<pic:cNvPr id=\"%lu\" name=\"image%lu.png\"/><pic:cNvPicPr/>"
        @"</pic:nvPicPr><pic:blipFill><a:blip r:embed=\"%@\"/>"
        @"<a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
        @"<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/>"
        @"<a:ext cx=\"%lld\" cy=\"%lld\"/></a:xfrm>"
        @"<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr>"
        @"</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>"
        @"</w:r>",
        cx, cy, (unsigned long)docPrId, (unsigned long)(index + 1),
        (unsigned long)docPrId, (unsigned long)(index + 1),
        relationshipId, cx, cy];
}

/// Replaces the run holding `token` with `replacement`.
static BOOL MPReplaceRunContaining(NSMutableString *xml, NSString *token,
                                   NSString *replacement)
{
    NSRange hit = [xml rangeOfString:token];
    if (hit.location == NSNotFound)
        return NO;

    // Widen to the enclosing <w:r> … </w:r>, so the placeholder's own
    // formatting does not survive around the picture.
    NSRange before = NSMakeRange(0, hit.location);
    NSRange open = [xml rangeOfString:@"<w:r>" options:NSBackwardsSearch
                                range:before];
    NSUInteger tail = NSMaxRange(hit);
    NSRange close = [xml rangeOfString:@"</w:r>" options:0
                                 range:NSMakeRange(tail, xml.length - tail)];
    if (open.location == NSNotFound || close.location == NSNotFound)
        return NO;

    NSRange run = NSMakeRange(open.location,
                              NSMaxRange(close) - open.location);
    [xml replaceCharactersInRange:run withString:replacement];
    return YES;
}

static NSString *MPStringFromEntry(NSArray<MPZipEntry *> *entries,
                                   NSString *name)
{
    for (MPZipEntry *e in entries)
    {
        if (![e.name isEqualToString:name])
            continue;
        NSData *raw = e.method == 8
            ? MPInflate(e.payload, e.uncompressedSize)
            : e.payload;
        if (!raw)
            return nil;
        return [[NSString alloc] initWithData:raw
                                     encoding:NSUTF8StringEncoding];
    }
    return nil;
}

static MPZipEntry *MPStoredEntry(NSString *name, NSData *data)
{
    MPZipEntry *e = [MPZipEntry new];
    e.name = name;
    e.method = 0;
    e.crc = MPCRC32(data);
    e.payload = data;
    e.uncompressedSize = (uint32_t)data.length;
    return e;
}

/// Embeds PNGs into a .docx that AppKit wrote, in place of text placeholders.
NSData *MPDocxDataByEmbeddingImages(NSData *docxData,
                                    NSArray<MPDocxImage *> *images)
{
    if (!images.count)
        return docxData;

    NSArray<MPZipEntry *> *entries = MPZipRead(docxData);
    if (!entries)
        return nil;

    NSMutableString *document =
        [MPStringFromEntry(entries, @"word/document.xml") mutableCopy];
    NSMutableString *rels =
        [MPStringFromEntry(entries, @"word/_rels/document.xml.rels")
         mutableCopy];
    NSMutableString *types =
        [MPStringFromEntry(entries, @"[Content_Types].xml") mutableCopy];
    if (!document || !rels || !types)
        return nil;

    // A relationship id that cannot collide with the ones already in the file.
    NSMutableArray<MPZipEntry *> *media = [NSMutableArray array];
    NSMutableString *newRels = [NSMutableString string];

    for (NSUInteger i = 0; i < images.count; i++)
    {
        MPDocxImage *image = images[i];
        NSString *relId =
            [NSString stringWithFormat:@"rIdMPImg%lu", (unsigned long)i];
        NSString *file =
            [NSString stringWithFormat:@"image%lu.png", (unsigned long)(i + 1)];

        if (!MPReplaceRunContaining(document, image.placeholder,
                                    MPDrawingXML(relId, i, image.pointSize)))
            continue;   // placeholder gone; skip rather than dangle a rel.

        [newRels appendFormat:
            @"<Relationship Id=\"%@\" Type=\"http://schemas.openxmlformats"
            @".org/officeDocument/2006/relationships/image\" "
            @"Target=\"media/%@\"/>", relId, file];
        [media addObject:MPStoredEntry(
            [@"word/media/" stringByAppendingString:file], image.pngData)];
    }

    if (!media.count)
        return docxData;

    NSRange relsClose = [rels rangeOfString:@"</Relationships>"];
    if (relsClose.location == NSNotFound)
        return nil;
    [rels replaceCharactersInRange:relsClose withString:
        [newRels stringByAppendingString:@"</Relationships>"]];

    if ([types rangeOfString:@"Extension=\"png\""].location == NSNotFound)
    {
        NSRange typesOpen = [types rangeOfString:@"<Types"];
        if (typesOpen.location == NSNotFound)
            return nil;
        NSRange gt = [types rangeOfString:@">" options:0
            range:NSMakeRange(typesOpen.location,
                              types.length - typesOpen.location)];
        if (gt.location == NSNotFound)
            return nil;
        [types insertString:@"<Default Extension=\"png\" "
                            @"ContentType=\"image/png\"/>"
                    atIndex:NSMaxRange(gt)];
    }

    NSDictionary *rebuilt = @{
        @"word/document.xml": document,
        @"word/_rels/document.xml.rels": rels,
        @"[Content_Types].xml": types,
    };

    NSMutableArray<MPZipEntry *> *out = [NSMutableArray array];
    for (MPZipEntry *e in entries)
    {
        NSString *replacement = rebuilt[e.name];
        if (replacement)
        {
            [out addObject:MPStoredEntry(e.name,
                [replacement dataUsingEncoding:NSUTF8StringEncoding])];
        }
        else
        {
            [out addObject:e];   // carried over with its bytes untouched
        }
    }
    [out addObjectsFromArray:media];

    return MPZipWrite(out);
}


#pragma mark - Layout repair

/// Whether every run in a paragraph is set in the monospace family, which is
/// what separates a code block from a paragraph that merely mentions some
/// inline code. Shading on the latter would band the whole line of prose.
static BOOL MPIsAllMonospaceParagraph(NSString *paragraph,
                                      NSString *monospaceFamily)
{
    NSString *anyFont = @"w:ascii=\"";
    NSString *monoFont =
        [NSString stringWithFormat:@"w:ascii=\"%@\"", monospaceFamily];

    NSUInteger fonts = 0;
    NSUInteger monospaced = 0;
    NSUInteger cursor = 0;

    while (cursor < paragraph.length)
    {
        NSRange found = [paragraph rangeOfString:anyFont options:0
            range:NSMakeRange(cursor, paragraph.length - cursor)];
        if (found.location == NSNotFound)
            break;
        fonts++;
        if ([paragraph rangeOfString:monoFont options:0
                              range:NSMakeRange(found.location,
                                  MIN(monoFont.length,
                                      paragraph.length - found.location))
            ].location != NSNotFound)
        {
            monospaced++;
        }
        cursor = NSMaxRange(found);
    }

    return monospaced > 0 && monospaced == fonts;
}


/// Inserts `insertion` into the properties of every <w:p> that is entirely
/// monospace, creating a <w:pPr> for paragraphs that have none.
///
/// Builds the result rather than mutating in place: editing a string while
/// scanning it means tracking how far every later offset has shifted, which
/// is the kind of bookkeeping that silently skips a paragraph.
static NSUInteger MPShadeMatchingParagraphs(NSMutableString *xml,
                                            NSString *monospaceFamily,
                                            NSString *insertion)
{
    NSMutableString *out = [NSMutableString stringWithCapacity:xml.length];
    NSUInteger cursor = 0;
    NSUInteger applied = 0;

    while (cursor < xml.length)
    {
        NSRange open = [xml rangeOfString:@"<w:p>" options:0
                                    range:NSMakeRange(cursor,
                                                      xml.length - cursor)];
        if (open.location == NSNotFound)
            break;

        NSUInteger after = NSMaxRange(open);
        NSRange close = [xml rangeOfString:@"</w:p>" options:0
                                     range:NSMakeRange(after,
                                                       xml.length - after)];
        if (close.location == NSNotFound)
            break;

        NSString *paragraph =
            [xml substringWithRange:NSMakeRange(after, close.location - after)];

        [out appendString:[xml substringWithRange:
            NSMakeRange(cursor, after - cursor)]];

        if (MPIsAllMonospaceParagraph(paragraph, monospaceFamily))
        {
            NSRange props = [paragraph rangeOfString:@"<w:pPr>"];
            if (props.location != NSNotFound)
            {
                [out appendString:
                    [paragraph substringToIndex:NSMaxRange(props)]];
                [out appendString:insertion];
                [out appendString:
                    [paragraph substringFromIndex:NSMaxRange(props)]];
            }
            else
            {
                [out appendFormat:@"<w:pPr>%@</w:pPr>", insertion];
                [out appendString:paragraph];
            }
            applied++;
        }
        else
        {
            [out appendString:paragraph];
        }

        [out appendString:@"</w:p>"];
        cursor = NSMaxRange(close);
    }

    if (!applied)
        return 0;

    [out appendString:[xml substringFromIndex:cursor]];
    [xml setString:out];
    return applied;
}


NSData *MPDocxDataByRepairingLayout(NSData *docxData,
                                    NSString *monospaceFamily,
                                    NSString *codeShadingHex)
{
    NSArray<MPZipEntry *> *entries = MPZipRead(docxData);
    if (!entries)
        return nil;

    NSMutableString *document =
        [MPStringFromEntry(entries, @"word/document.xml") mutableCopy];
    if (!document)
        return nil;

    NSUInteger changes = 0;

    // A bullet half an inch from its own text reads as two columns rather
    // than as a list. 240 twips of hang is enough to clear the marker.
    changes += [document replaceOccurrencesOfString:
        @"<w:ind w:left=\"720\" w:first-line=\"-720\"/>"
                                         withString:
        @"<w:ind w:left=\"360\" w:first-line=\"-240\"/>"
                                            options:0
                                              range:
        NSMakeRange(0, document.length)];

    if (monospaceFamily.length && codeShadingHex.length)
    {
        NSString *shading = [NSString stringWithFormat:
            @"<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"%@\"/>",
            codeShadingHex];
        changes += MPShadeMatchingParagraphs(document, monospaceFamily,
                                             shading);
    }

    if (!changes)
        return docxData;

    NSMutableArray<MPZipEntry *> *out = [NSMutableArray array];
    for (MPZipEntry *e in entries)
    {
        if ([e.name isEqualToString:@"word/document.xml"])
        {
            [out addObject:MPStoredEntry(e.name,
                [document dataUsingEncoding:NSUTF8StringEncoding])];
        }
        else
        {
            [out addObject:e];
        }
    }
    return MPZipWrite(out);
}
