//
//  MPRichExportTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPRichExport.h"
#import "MPZipArchive.h"


/// What AppKit's OpenDocument and RTF writers leave out, and what putting it
/// back looks like in each format.
@interface MPRichExportTests : XCTestCase
@property (strong) MPDocxImage *picture;
@end


@implementation MPRichExportTests

- (void)setUp
{
    [super setUp];

    NSImage *red = [[NSImage alloc] initWithSize:NSMakeSize(8.0, 8.0)];
    [red lockFocus];
    [[NSColor redColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 8.0, 8.0));
    [red unlockFocus];
    NSData *png = [[[NSBitmapImageRep alloc] initWithCGImage:
        [red CGImageForProposedRect:NULL context:nil hints:nil]]
        representationUsingType:NSBitmapImageFileTypePNG properties:@{}];

    self.picture = [[MPDocxImage alloc] init];
    self.picture.placeholder = @"MPIMGPLACEHOLDER0END";
    self.picture.pngData = png;
    self.picture.pointSize = NSMakeSize(72.0, 72.0);
    self.picture.source = @"rete.png";
}

/// The document AppKit writes for that markup, in the format asked for.
- (NSData *)write:(NSString *)html as:(NSString *)type
{
    NSAttributedString *rich = [[NSAttributedString alloc]
        initWithData:[html dataUsingEncoding:NSUTF8StringEncoding]
             options:@{
        NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
        NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding),
    } documentAttributes:NULL error:NULL];
    XCTAssertNotNil(rich);
    return [rich dataFromRange:NSMakeRange(0, rich.length)
            documentAttributes:@{NSDocumentTypeDocumentAttribute: type}
                         error:NULL];
}


#pragma mark - OpenDocument

- (void)testThePictureIsPutBackIntoTheOpenDocument
{
    NSData *odt = [self write:@"<p>Prima. MPIMGPLACEHOLDER0END Dopo.</p>"
                           as:NSOpenDocumentTextDocumentType];
    XCTAssertNotNil(odt);

    NSMutableArray *unplaced = [NSMutableArray array];
    NSData *withPicture = MPOdtDataByEmbeddingImages(odt, @[self.picture],
                                                     unplaced);
    XCTAssertNotNil(withPicture);
    XCTAssertEqual(unplaced.count, 0u);

    NSArray<MPZipEntry *> *entries = MPZipRead(withPicture);
    NSMutableArray *names = [NSMutableArray array];
    for (MPZipEntry *entry in entries)
        [names addObject:entry.name];

    // The picture itself, where ODF keeps pictures.
    XCTAssertTrue([names containsObject:@"Pictures/image1.png"], @"%@", names);
    // The mimetype entry stays first, which the format insists on.
    XCTAssertEqualObjects(names.firstObject, @"mimetype");

    NSString *content = MPStringFromEntry(entries, @"content.xml");
    XCTAssertTrue([content containsString:
        @"<draw:image xlink:href=\"Pictures/image1.png\""], @"%@", content);
    XCTAssertFalse([content containsString:@"MPIMGPLACEHOLDER0END"],
                   @"il segnaposto è rimasto nel documento");
    // Declared at the size it should be drawn, not at its pixels.
    XCTAssertTrue([content containsString:@"svg:width=\"1.000in\""],
                  @"%@", content);

    // And listed in the manifest, or the reader refuses to show it.
    NSString *manifest = MPStringFromEntry(entries,
                                           @"META-INF/manifest.xml");
    XCTAssertTrue([manifest containsString:@"Pictures/image1.png"],
                  @"%@", manifest);
    XCTAssertTrue([manifest containsString:@"image/png"]);
}

- (void)testWhatTheOpenDocumentWriterKeepsIsLeftAlone
{
    // Tables and bold survive AppKit's own writer — measured, and the reason
    // the Word export's repairs are not repeated here.
    NSData *odt = [self write:@"<table><tr><td>pane</td><td>2</td></tr></table>"
                              @"<p><strong>grassetto</strong></p>"
                           as:NSOpenDocumentTextDocumentType];
    NSString *content = MPStringFromEntry(MPZipRead(odt), @"content.xml");
    XCTAssertTrue([content containsString:@"<table:table"], @"%@", content);
    XCTAssertTrue([content containsString:@"bold"], @"%@", content);
}


#pragma mark - RTF

- (void)testThePictureIsPutBackIntoTheRTF
{
    NSData *rtf = [self write:@"<p>Prima. MPIMGPLACEHOLDER0END Dopo.</p>"
                           as:NSRTFTextDocumentType];
    XCTAssertNotNil(rtf);

    NSMutableArray *unplaced = [NSMutableArray array];
    NSData *withPicture = MPRtfDataByEmbeddingImages(rtf, @[self.picture],
                                                     unplaced);
    XCTAssertNotNil(withPicture);
    XCTAssertEqual(unplaced.count, 0u);

    NSString *text = [[NSString alloc] initWithData:withPicture
                                           encoding:NSISOLatin1StringEncoding];
    XCTAssertTrue([text containsString:@"{\\pict\\pngblip"], @"niente picture");
    // Drawn at 72 points, which RTF counts in twentieths.
    XCTAssertTrue([text containsString:@"\\picwgoal1440"], @"%@",
                  [text substringWithRange:NSMakeRange(0,
                      MIN(400u, text.length))]);
    XCTAssertFalse([text containsString:@"MPIMGPLACEHOLDER0END"]);
    // The bytes of the picture, in the hexadecimal RTF wants.
    XCTAssertTrue([text containsString:@"89504e470d0a1a0a"],
                  @"i primi byte di un PNG non ci sono");

    // And it is still an RTF file that reads back.
    NSAttributedString *back = [[NSAttributedString alloc]
        initWithRTF:withPicture documentAttributes:NULL];
    XCTAssertNotNil(back, @"il file non si rilegge");
    XCTAssertTrue([back.string containsString:@"Prima."], @"%@", back.string);
}


#pragma mark - When it cannot be done

- (void)testAPictureWithNoMarkerIsReported
{
    self.picture.placeholder = @"MPIMGPLACEHOLDER9END";   // not in the text
    NSData *rtf = [self write:@"<p>Solo testo.</p>" as:NSRTFTextDocumentType];

    NSMutableArray *unplaced = [NSMutableArray array];
    NSData *out = MPRtfDataByEmbeddingImages(rtf, @[self.picture], unplaced);
    XCTAssertEqualObjects(out, rtf, @"niente da piantare, niente da cambiare");
    XCTAssertEqualObjects(unplaced.firstObject, @"rete.png");
}

- (void)testNothingToPlant
{
    NSData *rtf = [self write:@"<p>Testo.</p>" as:NSRTFTextDocumentType];
    XCTAssertEqualObjects(MPRtfDataByEmbeddingImages(rtf, @[], nil), rtf);

    NSData *odt = [self write:@"<p>Testo.</p>"
                           as:NSOpenDocumentTextDocumentType];
    XCTAssertEqualObjects(MPOdtDataByEmbeddingImages(odt, @[], nil), odt);

    XCTAssertNil(MPRtfDataByEmbeddingImages(nil, @[self.picture], nil));
    XCTAssertNil(MPOdtDataByEmbeddingImages(nil, @[self.picture], nil));
}

@end
