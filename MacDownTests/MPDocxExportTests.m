//
//  MPDocxExportTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPDocxPostProcessing.h"
#import "MPZipArchive.h"

@interface MPDocxExportTests : XCTestCase
@end

@implementation MPDocxExportTests

/// A .docx written the way the export writes one, from the given body HTML.
- (NSData *)docxFromHTML:(NSString *)html
{
    NSData *in = [[NSString stringWithFormat:@"<html><body>%@</body></html>",
                   html] dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSAttributedString *rich = [[NSAttributedString alloc]
        initWithData:in
             options:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
                       NSCharacterEncodingDocumentAttribute:
                           @(NSUTF8StringEncoding)}
  documentAttributes:NULL error:&error];
    XCTAssertNotNil(rich, @"%@", error);

    NSData *docx = [rich dataFromRange:NSMakeRange(0, rich.length)
                    documentAttributes:@{NSDocumentTypeDocumentAttribute:
                        NSOfficeOpenXMLTextDocumentType} error:&error];
    XCTAssertNotNil(docx, @"%@", error);
    return docx;
}

- (MPDocxImage *)imageWithPlaceholder:(NSString *)placeholder
{
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:8 pixelsHigh:6
                   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:0 bitsPerPixel:0];
    MPDocxImage *image = [[MPDocxImage alloc] init];
    image.placeholder = placeholder;
    image.pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG
                                         properties:@{}];
    image.pointSize = NSMakeSize(8.0, 6.0);
    return image;
}

- (NSArray<NSString *> *)namesIn:(NSData *)docx
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (MPZipEntry *entry in MPZipRead(docx))
        [names addObject:entry.name];
    return names;
}

- (NSString *)documentXMLIn:(NSData *)docx
{
    return MPStringFromEntry(MPZipRead(docx), @"word/document.xml");
}


- (void)testAPictureReplacesItsMarker
{
    NSData *docx = [self docxFromHTML:@"<p>MPIMGPLACEHOLDER0END</p>"];
    NSMutableArray<NSString *> *unplaced = [NSMutableArray array];
    NSData *out = MPDocxDataByEmbeddingImages(
        docx, @[[self imageWithPlaceholder:@"MPIMGPLACEHOLDER0END"]],
        unplaced);

    XCTAssertNotNil(out);
    XCTAssertEqualObjects(unplaced, @[]);
    XCTAssertTrue([[self namesIn:out] containsObject:@"word/media/image1.png"]);

    NSString *document = [self documentXMLIn:out];
    XCTAssertNotEqual([document rangeOfString:@"<w:drawing>"].location,
                      (NSUInteger)NSNotFound);
    XCTAssertEqual([document rangeOfString:@"MPIMGPLACEHOLDER"].location,
                   (NSUInteger)NSNotFound, @"nessun segnaposto in vista");
}

/** A marker that is not in the document has to be reported.
 *
 * It used to be dropped in silence, which is a picture missing from the
 * reader's document with nothing said about it.
 */
- (void)testAMissingMarkerIsCounted
{
    NSData *docx = [self docxFromHTML:@"<p>Nessun segnaposto qui.</p>"];
    MPDocxImage *image = [self imageWithPlaceholder:@"MPIMGPLACEHOLDER0END"];
    image.source = @"immagini/schema.png";

    NSMutableArray<NSString *> *unplaced = [NSMutableArray array];
    NSData *out = MPDocxDataByEmbeddingImages(docx, @[image], unplaced);

    XCTAssertEqualObjects(unplaced, @[@"immagini/schema.png"],
                          @"il rapporto deve poter dire quale file");
    XCTAssertFalse([[self namesIn:out]
        containsObject:@"word/media/image1.png"]);
}

/// The marker for picture 1 must not be found inside the marker for 10.
- (void)testTheTenthPictureDoesNotSwallowTheSecond
{
    NSData *docx = [self docxFromHTML:
        @"<p>MPIMGPLACEHOLDER10END</p><p>MPIMGPLACEHOLDER1END</p>"];
    NSMutableArray<NSString *> *unplaced = [NSMutableArray array];
    NSData *out = MPDocxDataByEmbeddingImages(docx, @[
        [self imageWithPlaceholder:@"MPIMGPLACEHOLDER1END"],
        [self imageWithPlaceholder:@"MPIMGPLACEHOLDER10END"],
    ], unplaced);

    XCTAssertEqualObjects(unplaced, @[]);
    NSArray<NSString *> *names = [self namesIn:out];
    XCTAssertTrue([names containsObject:@"word/media/image1.png"]);
    XCTAssertTrue([names containsObject:@"word/media/image2.png"]);

    NSString *document = [self documentXMLIn:out];
    XCTAssertEqual([document rangeOfString:@"MPIMGPLACEHOLDER"].location,
                   (NSUInteger)NSNotFound, @"entrambi sostituiti");
}

/// A picture in a table cell: the marker is there once the table is built.
- (void)testAPictureInsideATable
{
    NSData *docx = [self docxFromHTML:@"<p>MPTBLPLACEHOLDER0</p>"];

    MPDocxTextRun *run = [[MPDocxTextRun alloc] init];
    run.text = @"MPIMGPLACEHOLDER0END";
    MPDocxTableCell *cell = [[MPDocxTableCell alloc] init];
    cell.runs = @[run];
    MPDocxTable *table = [[MPDocxTable alloc] init];
    table.placeholder = @"MPTBLPLACEHOLDER0";
    table.rows = @[@[cell]];

    NSData *tabled = MPDocxDataByBuildingTables(docx, @[table],
                                                @"Helvetica Neue", @"Menlo",
                                                10.0);
    XCTAssertNotNil(tabled);

    NSMutableArray<NSString *> *unplaced = [NSMutableArray array];
    NSData *out = MPDocxDataByEmbeddingImages(
        tabled, @[[self imageWithPlaceholder:@"MPIMGPLACEHOLDER0END"]],
        unplaced);
    XCTAssertEqualObjects(unplaced, @[],
                          @"le tabelle vanno costruite prima delle immagini");
    XCTAssertTrue([[self namesIn:out]
        containsObject:@"word/media/image1.png"]);

    // Inside the table, not floated out of it.
    NSString *document = [self documentXMLIn:out];
    NSRange table_ = [document rangeOfString:@"<w:tbl>"];
    NSRange end = [document rangeOfString:@"</w:tbl>"];
    XCTAssertNotEqual(table_.location, (NSUInteger)NSNotFound);
    XCTAssertNotEqual(end.location, (NSUInteger)NSNotFound);
    NSRange inside = NSMakeRange(table_.location,
                                 end.location - table_.location);
    XCTAssertNotEqual([document rangeOfString:@"<w:drawing>"
                                      options:0 range:inside].location,
                      (NSUInteger)NSNotFound);
}

/** Five screenshots written one per line are one paragraph, and one run.
 *
 * Replacing the whole run for the first marker took the others away with
 * it, and they were then reported as pictures with nowhere to go — which
 * is exactly what a reader saw who could see all five in their document.
 */
- (void)testSeveralPicturesInOneRun
{
    NSData *docx = [self docxFromHTML:
        @"<p>MPIMGPLACEHOLDER0END\nMPIMGPLACEHOLDER1END\n"
        @"MPIMGPLACEHOLDER2END</p>"];

    NSMutableArray<MPDocxImage *> *images = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++)
    {
        NSString *placeholder = [NSString stringWithFormat:
            @"MPIMGPLACEHOLDER%luEND", (unsigned long)i];
        MPDocxImage *image = [self imageWithPlaceholder:placeholder];
        image.source = [NSString stringWithFormat:@"foto%lu.png",
                        (unsigned long)i];
        [images addObject:image];
    }

    NSMutableArray<NSString *> *unplaced = [NSMutableArray array];
    NSData *out = MPDocxDataByEmbeddingImages(docx, images, unplaced);
    XCTAssertEqualObjects(unplaced, @[]);

    NSArray<NSString *> *names = [self namesIn:out];
    for (NSUInteger i = 1; i <= 3; i++)
    {
        // Out of the macro: a comma inside its first argument would be read
        // as the start of the message format.
        NSString *name = [NSString stringWithFormat:@"word/media/image%lu.png",
                          (unsigned long)i];
        XCTAssertTrue([names containsObject:name], @"%@", name);
    }

    NSString *document = [self documentXMLIn:out];
    XCTAssertEqual([document componentsSeparatedByString:@"<w:drawing>"].count,
                   (NSUInteger)4, @"tre disegni");
    XCTAssertEqual([document rangeOfString:@"MPIMGPLACEHOLDER"].location,
                   (NSUInteger)NSNotFound);
}

/// The prose either side of an inline picture used to be deleted with the run.
- (void)testTheTextAroundAPictureSurvives
{
    NSData *docx = [self docxFromHTML:
        @"<p>Testo prima MPIMGPLACEHOLDER0END testo dopo.</p>"];
    NSMutableArray<NSString *> *unplaced = [NSMutableArray array];
    NSData *out = MPDocxDataByEmbeddingImages(
        docx, @[[self imageWithPlaceholder:@"MPIMGPLACEHOLDER0END"]],
        unplaced);

    XCTAssertEqualObjects(unplaced, @[]);
    NSString *document = [self documentXMLIn:out];
    XCTAssertNotEqual([document rangeOfString:@"Testo prima"].location,
                      (NSUInteger)NSNotFound, @"il testo prima resta");
    XCTAssertNotEqual([document rangeOfString:@"testo dopo."].location,
                      (NSUInteger)NSNotFound, @"e anche quello dopo");
    XCTAssertNotEqual([document rangeOfString:@"<w:drawing>"].location,
                      (NSUInteger)NSNotFound);

    // In order: prose, picture, prose.
    NSUInteger first = [document rangeOfString:@"Testo prima"].location;
    NSUInteger picture = [document rangeOfString:@"<w:drawing>"].location;
    NSUInteger last = [document rangeOfString:@"testo dopo."].location;
    XCTAssertLessThan(first, picture);
    XCTAssertLessThan(picture, last);
}

@end
