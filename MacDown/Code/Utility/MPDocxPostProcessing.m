//
//  MPDocxPostProcessing.m
//  MacDown
//
//  Repairs a .docx after AppKit has written it, for the things its Word
//  writer leaves out: pictures, shading, list indents and tables.
//
//  A .docx is a zip of XML parts. Foundation has no zip API, so this carries
//  the little of the format it needs: read the central directory, inflate the
//  three parts that get edited, and write the archive back out. Parts that are
//  not edited are copied across with their compressed bytes untouched, so the
//  only codec needed is an inflater, which libcompression provides.
//

#import "MPDocxPostProcessing.h"
#import "MPZipArchive.h"

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


/// Embeds PNGs into a .docx that AppKit wrote, in place of text placeholders.
NSData *MPDocxDataByEmbeddingImages(NSData *docxData,
                                    NSArray<MPDocxImage *> *images,
                                    NSMutableArray<NSString *> *unplaced)
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
        {
            // The marker is not in the document. Skip rather than dangle a
            // relationship — and say which picture, since this is one the
            // reader will not find where they put it.
            [unplaced addObject:image.source ?: image.placeholder];
            continue;
        }

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


#pragma mark - Tables

@implementation MPDocxTextRun
@end

@implementation MPDocxTableCell
@end

@implementation MPDocxTable
@end

#pragma mark - Heading styles

/// Where a `<w:p>` element starts, searching back from `index`.
static NSUInteger MPParagraphStartBefore(NSString *xml, NSUInteger index)
{
    // Not just "<w:p", which is also how <w:pPr> and <w:pStyle> begin, and
    // both of those sit between a paragraph's start and its text.
    NSRange before = NSMakeRange(0, index);
    NSRange plain = [xml rangeOfString:@"<w:p>" options:NSBackwardsSearch
                                 range:before];
    NSRange attributed = [xml rangeOfString:@"<w:p " options:NSBackwardsSearch
                                      range:before];

    if (plain.location == NSNotFound)
        return attributed.location;
    if (attributed.location == NSNotFound)
        return plain.location;
    return MAX(plain.location, attributed.location);
}

/** Removes one token and names the style of the paragraph it was in.
 *
 * Returns NO only when there is no token left to find, which is what ends
 * the loop over a level.
 */
static BOOL MPStyleParagraphContaining(NSMutableString *xml, NSString *token,
                                       NSUInteger level)
{
    NSRange hit = [xml rangeOfString:token];
    if (hit.location == NSNotFound)
        return NO;
    [xml deleteCharactersInRange:hit];

    NSUInteger start = MPParagraphStartBefore(xml, hit.location);
    if (start == NSNotFound)
        return YES;     // The token is gone either way.

    NSRange rest = NSMakeRange(start, xml.length - start);
    NSRange tagEnd = [xml rangeOfString:@">" options:0 range:rest];
    if (tagEnd.location == NSNotFound)
        return YES;

    NSString *style = [NSString stringWithFormat:
        @"<w:pStyle w:val=\"Heading%lu\"/>", (unsigned long)level];

    // Properties the writer already gave the paragraph, or none at all. The
    // style has to be the first thing inside them either way: the schema
    // fixes the order of a paragraph's properties, and this one leads.
    NSUInteger after = NSMaxRange(tagEnd);
    NSRange properties = NSMakeRange(after, MIN((NSUInteger)8,
                                                xml.length - after));
    if ([[xml substringWithRange:properties] hasPrefix:@"<w:pPr>"])
        [xml insertString:style atIndex:after + 7];
    else
        [xml insertString:[NSString stringWithFormat:@"<w:pPr>%@</w:pPr>",
                           style] atIndex:after];
    return YES;
}

/// The stylesheet AppKit never writes, holding the six heading styles.
static NSString *MPHeadingStylesXML(void)
{
    NSMutableString *styles = [NSMutableString string];
    [styles appendString:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        @"<w:styles xmlns:w=\"http://schemas.openxmlformats.org/"
        @"wordprocessingml/2006/main\">"
        @"<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\">"
        @"<w:name w:val=\"Normal\"/><w:qFormat/></w:style>"];

    for (NSUInteger level = 1; level <= 6; level++)
    {
        // The name is what marks these as Word's own built-in headings
        // rather than six styles that happen to be called Heading; the
        // outline level is what the navigation pane reads.
        [styles appendFormat:
            @"<w:style w:type=\"paragraph\" w:styleId=\"Heading%lu\">"
            @"<w:name w:val=\"heading %lu\"/>"
            @"<w:basedOn w:val=\"Normal\"/>"
            @"<w:next w:val=\"Normal\"/>"
            @"<w:uiPriority w:val=\"9\"/>"
            @"<w:qFormat/>"
            @"<w:pPr><w:outlineLvl w:val=\"%lu\"/></w:pPr>"
            @"</w:style>",
            (unsigned long)level, (unsigned long)level,
            (unsigned long)(level - 1)];
    }
    [styles appendString:@"</w:styles>"];
    return styles;
}

NSData *MPDocxDataByStylingHeadings(NSData *docxData, NSString *tokenPrefix)
{
    if (!tokenPrefix.length)
        return docxData;

    NSArray<MPZipEntry *> *entries = MPZipRead(docxData);
    if (!entries)
        return nil;

    NSMutableString *xml =
        [MPStringFromEntry(entries, @"word/document.xml") mutableCopy];
    if (!xml)
        return nil;

    BOOL any = NO;
    for (NSUInteger level = 1; level <= 6; level++)
    {
        NSString *token = [NSString stringWithFormat:@"%@%lu", tokenPrefix,
                           (unsigned long)level];
        while (MPStyleParagraphContaining(xml, token, level))
            any = YES;
    }
    if (!any)
        return docxData;

    NSMutableString *rels =
        [MPStringFromEntry(entries, @"word/_rels/document.xml.rels")
            mutableCopy];
    NSMutableString *types =
        [MPStringFromEntry(entries, @"[Content_Types].xml") mutableCopy];
    if (!rels || !types)
        return nil;

    NSRange relsClose = [rels rangeOfString:@"</Relationships>"];
    NSRange typesClose = [types rangeOfString:@"</Types>"];
    if (relsClose.location == NSNotFound || typesClose.location == NSNotFound)
        return nil;

    [rels replaceCharactersInRange:relsClose withString:
        @"<Relationship Id=\"rIdStyles\" Type=\"http://schemas."
        @"openxmlformats.org/officeDocument/2006/relationships/styles\" "
        @"Target=\"styles.xml\"/></Relationships>"];
    [types replaceCharactersInRange:typesClose withString:
        @"<Override PartName=\"/word/styles.xml\" ContentType=\""
        @"application/vnd.openxmlformats-officedocument.wordprocessingml."
        @"styles+xml\"/></Types>"];

    NSMutableArray<MPZipEntry *> *out = [NSMutableArray array];
    for (MPZipEntry *e in entries)
    {
        if ([e.name isEqualToString:@"word/document.xml"])
        {
            [out addObject:MPStoredEntry(e.name,
                [xml dataUsingEncoding:NSUTF8StringEncoding])];
        }
        else if ([e.name isEqualToString:@"word/_rels/document.xml.rels"])
        {
            [out addObject:MPStoredEntry(e.name,
                [rels dataUsingEncoding:NSUTF8StringEncoding])];
        }
        else if ([e.name isEqualToString:@"[Content_Types].xml"])
        {
            [out addObject:MPStoredEntry(e.name,
                [types dataUsingEncoding:NSUTF8StringEncoding])];
        }
        else
        {
            [out addObject:e];
        }
    }
    [out addObject:MPStoredEntry(@"word/styles.xml",
        [MPHeadingStylesXML() dataUsingEncoding:NSUTF8StringEncoding])];

    return MPZipWrite(out);
}


NS_INLINE NSString *MPXMLEscaped(NSString *text)
{
    NSMutableString *out = [text mutableCopy];
    NSRange all = NSMakeRange(0, out.length);
    [out replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0
                              range:all];
    all = NSMakeRange(0, out.length);
    [out replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0
                              range:all];
    all = NSMakeRange(0, out.length);
    [out replaceOccurrencesOfString:@">" withString:@"&gt;" options:0
                              range:all];
    return out;
}

/// Width of the text column on a portrait page with one inch margins, in
/// twips. Tables are laid out to fill it rather than to fit their content,
/// which is what makes a two column table look deliberate.
static const NSInteger kMPDocxContentWidthTwips = 9360;

// Twips are twentieths of a point, so the same column in the unit the
// picture sizing works in.
const CGFloat MPDocxContentWidthPoints = 9360.0 / 20.0;

static NSString *MPRunXML(MPDocxTextRun *run, NSString *bodyFamily,
                          NSString *monospaceFamily, CGFloat pointSize)
{
    NSString *family = run.monospaced ? monospaceFamily : bodyFamily;
    NSMutableString *properties = [NSMutableString string];
    [properties appendFormat:
        @"<w:rFonts w:ascii=\"%@\" w:hAnsi=\"%@\" w:cs=\"%@\"/>",
        family, family, family];
    // Half-points, which is how w:sz measures.
    [properties appendFormat:@"<w:sz w:val=\"%ld\"/>",
        (long)lround(pointSize * 2.0)];
    if (run.bold)
        [properties appendString:@"<w:b/>"];
    if (run.italic)
        [properties appendString:@"<w:i/>"];

    return [NSString stringWithFormat:
        @"<w:r><w:rPr>%@</w:rPr><w:t xml:space=\"preserve\">%@</w:t></w:r>",
        properties, MPXMLEscaped(run.text)];
}

static NSString *MPCellXML(MPDocxTableCell *cell, NSInteger widthTwips,
                           NSString *bodyFamily, NSString *monospaceFamily,
                           CGFloat pointSize)
{
    NSMutableString *runs = [NSMutableString string];
    for (MPDocxTextRun *run in cell.runs)
    {
        if (!run.text.length)
            continue;
        [runs appendString:MPRunXML(run, bodyFamily, monospaceFamily,
                                    pointSize)];
    }
    // A cell must hold at least one paragraph, even when it is empty.
    NSMutableString *properties = [NSMutableString string];
    [properties appendString:@"<w:spacing w:after=\"0\"/>"];
    if (cell.alignment.length)
        [properties appendFormat:@"<w:jc w:val=\"%@\"/>", cell.alignment];

    NSMutableString *cellProperties = [NSMutableString string];
    [cellProperties appendFormat:
        @"<w:tcW w:w=\"%ld\" w:type=\"dxa\"/>", (long)widthTwips];
    if (cell.header)
    {
        [cellProperties appendString:
            @"<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"ECECEC\"/>"];
    }

    return [NSString stringWithFormat:
        @"<w:tc><w:tcPr>%@</w:tcPr><w:p><w:pPr>%@</w:pPr>%@</w:p></w:tc>",
        cellProperties, properties, runs];
}

static NSString *MPTableXML(MPDocxTable *table, NSString *bodyFamily,
                            NSString *monospaceFamily, CGFloat pointSize)
{
    NSUInteger columns = 0;
    for (NSArray<MPDocxTableCell *> *row in table.rows)
        columns = MAX(columns, row.count);
    if (!columns || !table.rows.count)
        return nil;

    NSInteger columnWidth = kMPDocxContentWidthTwips / (NSInteger)columns;

    NSMutableString *xml = [NSMutableString string];
    [xml appendString:@"<w:tbl><w:tblPr>"
        @"<w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders>"];
    for (NSString *edge in @[@"top", @"left", @"bottom", @"right",
                             @"insideH", @"insideV"])
    {
        // sz is eighths of a point, so 4 is a half point hairline.
        [xml appendFormat:@"<w:%@ w:val=\"single\" w:sz=\"4\" w:space=\"0\" "
                          @"w:color=\"BFBFBF\"/>", edge];
    }
    [xml appendString:@"</w:tblBorders><w:tblCellMar>"
        @"<w:top w:w=\"60\" w:type=\"dxa\"/>"
        @"<w:left w:w=\"100\" w:type=\"dxa\"/>"
        @"<w:bottom w:w=\"60\" w:type=\"dxa\"/>"
        @"<w:right w:w=\"100\" w:type=\"dxa\"/>"
        @"</w:tblCellMar></w:tblPr><w:tblGrid>"];
    for (NSUInteger i = 0; i < columns; i++)
        [xml appendFormat:@"<w:gridCol w:w=\"%ld\"/>", (long)columnWidth];
    [xml appendString:@"</w:tblGrid>"];

    for (NSArray<MPDocxTableCell *> *row in table.rows)
    {
        BOOL headerRow = row.firstObject.header;
        [xml appendString:@"<w:tr>"];
        // Repeats the header if the table breaks across pages.
        if (headerRow)
            [xml appendString:@"<w:trPr><w:tblHeader/></w:trPr>"];

        for (NSUInteger i = 0; i < columns; i++)
        {
            MPDocxTableCell *cell = i < row.count ? row[i] : nil;
            if (!cell)
            {
                // Short row: pad it, or Word renders a ragged table.
                cell = [[MPDocxTableCell alloc] init];
                cell.runs = @[];
                cell.header = headerRow;
            }
            [xml appendString:MPCellXML(cell, columnWidth, bodyFamily,
                                        monospaceFamily, pointSize)];
        }
        [xml appendString:@"</w:tr>"];
    }
    [xml appendString:@"</w:tbl>"];

    // A table has to be followed by a paragraph, or Word treats the document
    // as malformed when it is the last thing in the body.
    [xml appendString:@"<w:p/>"];
    return xml;
}

/// Replaces the whole <w:p> holding `token` with `replacement`. A w:tbl is a
/// sibling of w:p, not something that can live inside one, so the paragraph
/// has to go rather than be edited.
static BOOL MPReplaceParagraphContaining(NSMutableString *xml, NSString *token,
                                         NSString *replacement)
{
    NSRange hit = [xml rangeOfString:token];
    if (hit.location == NSNotFound)
        return NO;

    NSRange open = [xml rangeOfString:@"<w:p>" options:NSBackwardsSearch
                                range:NSMakeRange(0, hit.location)];
    NSUInteger tail = NSMaxRange(hit);
    NSRange close = [xml rangeOfString:@"</w:p>" options:0
                                 range:NSMakeRange(tail, xml.length - tail)];
    if (open.location == NSNotFound || close.location == NSNotFound)
        return NO;

    [xml replaceCharactersInRange:
        NSMakeRange(open.location, NSMaxRange(close) - open.location)
                       withString:replacement];
    return YES;
}

NSData *MPDocxDataByBuildingTables(NSData *docxData,
                                   NSArray<MPDocxTable *> *tables,
                                   NSString *bodyFamily,
                                   NSString *monospaceFamily,
                                   CGFloat pointSize)
{
    if (!tables.count)
        return docxData;

    NSArray<MPZipEntry *> *entries = MPZipRead(docxData);
    if (!entries)
        return nil;

    NSMutableString *document =
        [MPStringFromEntry(entries, @"word/document.xml") mutableCopy];
    if (!document)
        return nil;

    NSUInteger built = 0;
    for (MPDocxTable *table in tables)
    {
        NSString *xml = MPTableXML(table, bodyFamily, monospaceFamily,
                                    pointSize);
        if (!xml)
            continue;
        if (MPReplaceParagraphContaining(document, table.placeholder, xml))
            built++;
    }

    if (!built)
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


#pragma mark - Font table

/// Panose classifications. Word leans on these when the named font is
/// missing: the fourth byte is proportion, and 9 there means monospaced.
static NSString * const kMPPanoseMonospace = @"020B0609030804020204";
static NSString * const kMPPanoseSans      = @"020B0604020202020204";

static NSString *MPFontEntryXML(NSString *family, NSString *alternative,
                                BOOL fixedPitch)
{
    return [NSString stringWithFormat:
        @"<w:font w:name=\"%@\">"
        @"<w:altName w:val=\"%@\"/>"
        @"<w:panose1 w:val=\"%@\"/>"
        @"<w:charset w:val=\"00\"/>"
        @"<w:family w:val=\"%@\"/>"
        @"<w:pitch w:val=\"%@\"/>"
        @"</w:font>",
        MPXMLEscaped(family), MPXMLEscaped(alternative),
        fixedPitch ? kMPPanoseMonospace : kMPPanoseSans,
        fixedPitch ? @"modern" : @"swiss",
        fixedPitch ? @"fixed" : @"variable"];
}

NSData *MPDocxDataByDeclaringFonts(NSData *docxData,
                                   NSString *monospaceFamily,
                                   NSString *monospaceAlternative,
                                   NSString *bodyFamily,
                                   NSString *bodyAlternative)
{
    if (!monospaceFamily.length)
        return docxData;

    NSArray<MPZipEntry *> *entries = MPZipRead(docxData);
    if (!entries)
        return nil;

    for (MPZipEntry *e in entries)
    {
        if ([e.name isEqualToString:@"word/fontTable.xml"])
            return docxData;    // Already declared; leave it alone.
    }

    NSMutableString *table = [NSMutableString string];
    [table appendString:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        @"<w:fonts xmlns:w=\"http://schemas.openxmlformats.org/"
        @"wordprocessingml/2006/main\">"];
    [table appendString:MPFontEntryXML(monospaceFamily,
                                       monospaceAlternative.length
                                           ? monospaceAlternative
                                           : @"Courier New",
                                       YES)];
    if (bodyFamily.length)
    {
        [table appendString:MPFontEntryXML(bodyFamily,
                                           bodyAlternative.length
                                               ? bodyAlternative
                                               : @"Arial",
                                           NO)];
    }
    [table appendString:@"</w:fonts>"];

    NSMutableString *rels =
        [MPStringFromEntry(entries, @"word/_rels/document.xml.rels")
            mutableCopy];
    NSMutableString *types =
        [MPStringFromEntry(entries, @"[Content_Types].xml") mutableCopy];
    if (!rels || !types)
        return nil;

    NSString *relationship = [NSString stringWithFormat:
        @"<Relationship Id=\"rIdFontTable\" Type=\"http://schemas."
        @"openxmlformats.org/officeDocument/2006/relationships/fontTable\" "
        @"Target=\"fontTable.xml\"/>"];
    NSRange relsClose = [rels rangeOfString:@"</Relationships>"];
    if (relsClose.location == NSNotFound)
        return nil;
    [rels replaceCharactersInRange:relsClose withString:
        [relationship stringByAppendingString:@"</Relationships>"]];

    NSString *override = [NSString stringWithFormat:
        @"<Override PartName=\"/word/fontTable.xml\" ContentType=\""
        @"application/vnd.openxmlformats-officedocument.wordprocessingml."
        @"fontTable+xml\"/>"];
    NSRange typesClose = [types rangeOfString:@"</Types>"];
    if (typesClose.location == NSNotFound)
        return nil;
    [types replaceCharactersInRange:typesClose withString:
        [override stringByAppendingString:@"</Types>"]];

    NSMutableArray<MPZipEntry *> *out = [NSMutableArray array];
    for (MPZipEntry *e in entries)
    {
        if ([e.name isEqualToString:@"word/_rels/document.xml.rels"])
        {
            [out addObject:MPStoredEntry(e.name,
                [rels dataUsingEncoding:NSUTF8StringEncoding])];
        }
        else if ([e.name isEqualToString:@"[Content_Types].xml"])
        {
            [out addObject:MPStoredEntry(e.name,
                [types dataUsingEncoding:NSUTF8StringEncoding])];
        }
        else
        {
            [out addObject:e];
        }
    }
    [out addObject:MPStoredEntry(@"word/fontTable.xml",
        [table dataUsingEncoding:NSUTF8StringEncoding])];

    return MPZipWrite(out);
}
