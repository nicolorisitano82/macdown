//
//  MDDrawioPlugInTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
// For the declarations only — the classes are reached by name, the way the
// application reaches them, so nothing here is linked against the plug-in.
#import "MDDrawioFile.h"
#import "MDDrawioRenderer.h"
#import "MDDrawioPlugIn.h"

/// The domain, written out rather than linked, for the same reason.
static NSString * const kMDExpectedDomain = @"MDDrawioErrorDomain";


/** The draw.io plug-in, tested through the bundle that ships.
 *
 * Loaded by name rather than linked, which is how the application loads it
 * too: what is checked here is the artefact — the principal class is
 * reachable, the viewer is inside it, a diagram comes out as a picture —
 * and not a copy of its sources compiled into the tests.
 */
@interface MDDrawioPlugInTests : XCTestCase
@property (strong, nonatomic) NSBundle *plugin;
@end


@implementation MDDrawioPlugInTests

- (void)setUp
{
    [super setUp];

    // Beside the application, which is what these tests run inside: the
    // plug-in is built with it, into the same folder. Not beside the test
    // bundle — a hosted test bundle lives inside the app itself.
    NSURL *products = [NSBundle mainBundle].bundleURL
        .URLByDeletingLastPathComponent;
    NSURL *url = [products URLByAppendingPathComponent:@"Drawio.plugin"];
    self.plugin = [NSBundle bundleWithURL:url];

    NSError *error = nil;
    if (![self.plugin loadAndReturnError:&error])
    {
        // Built on its own, the application is there and the plug-in is
        // not. Say which, rather than failing eleven assertions.
        XCTFail(@"Drawio.plugin non si è caricato da %@: %@",
                url.path, error.localizedDescription);
    }
}

- (Class)classNamed:(NSString *)name
{
    Class found = NSClassFromString(name);
    XCTAssertNotNil(found, @"%@ non è nel plug-in caricato", name);
    return found;
}

- (id)fileFromString:(NSString *)xml error:(NSError **)error
{
    Class file = [self classNamed:@"MDDrawioFile"];
    return [file fileWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]
                        error:error];
}


#pragma mark - The bundle itself

- (void)testThePlugInLoadsAndCarriesTheViewer
{
    XCTAssertTrue(self.plugin.isLoaded);
    XCTAssertEqualObjects(self.plugin.infoDictionary[@"NSPrincipalClass"],
                          @"MDDrawioPlugIn");

    // What the application asks of a plug-in, and what this one answers.
    id plugin = [[self.plugin.principalClass alloc] init];
    XCTAssertTrue([plugin respondsToSelector:@selector(run:)]);
    XCTAssertGreaterThan([[plugin name] length], 0u);

    NSURL *viewer = [self.plugin URLForResource:@"viewer.min"
                                  withExtension:@"js"];
    XCTAssertNotNil(viewer);
    NSNumber *size = nil;
    [viewer getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    // Two and a half megabytes of it. A stub would pass everything else.
    XCTAssertGreaterThan(size.integerValue, 1000000);
}


#pragma mark - Reading the file

- (void)testAPageWrittenAsPlainXML
{
    NSString *xml =
        @"<mxfile><diagram id=\"a\" name=\"Flusso\">"
        @"<mxGraphModel dx=\"800\"><root><mxCell id=\"0\"/>"
        @"</root></mxGraphModel></diagram></mxfile>";

    NSError *error = nil;
    id file = [self fileFromString:xml error:&error];
    XCTAssertNil(error);

    NSArray *pages = [file pages];
    XCTAssertEqual(pages.count, 1u);
    XCTAssertEqualObjects([pages.firstObject name], @"Flusso");
    XCTAssertTrue([[pages.firstObject xml] containsString:@"<mxGraphModel"]);
}

- (void)testAPageWrittenTheWayDrawioWritesIt
{
    // base64 of the raw-deflated, URI-escaped model: what a saved .drawio
    // actually holds. Frozen here so the three steps are tested together.
    NSString *payload =
        @"jVFBDsIgEHwNdwrGeBarJx9BwqaQ0NJQqvB7wQWrhyZeyO7MzsAOhIsx3r"
        @"yc9d0psIRRFQm/EMZOlOazAAmBYwMGbxRCXQF4T7jwzgWsxijAFqM2hKrr"
        @"Dtuh5yw9TOEfAUPBQ9oVEBHOWrkqh8QSkq2Ed+ukoOg6ws9VBz5A3L172y"
        @"jHAm6E4FMeqYJDTSD9tk+jgq76+nqqwQw6tOQQkwv2w8d42zMXddXWbpG+"
        @"ua9P4v0L";

    NSString *xml = [NSString stringWithFormat:
        @"<mxfile><diagram id=\"a\" name=\"Compressa\">%@</diagram></mxfile>",
        payload];

    NSError *error = nil;
    id file = [self fileFromString:xml error:&error];
    XCTAssertNil(error);

    NSArray *pages = [file pages];
    XCTAssertEqual(pages.count, 1u);
    XCTAssertEqualObjects([pages.firstObject name], @"Compressa");
    NSString *model = [pages.firstObject xml];
    XCTAssertTrue([model containsString:@"<mxGraphModel"]);
    // Through base64, inflate and unescaping, the text arrives whole.
    XCTAssertTrue([model containsString:@"Collaudo"]);

    // A payload that is not one is a page that cannot be read, and a file
    // with no readable page is an error rather than an empty picture.
    NSError *bad = nil;
    XCTAssertNil([self fileFromString:
        @"<mxfile><diagram name=\"Rotta\">non-base64-##</diagram></mxfile>"
                                error:&bad]);
    XCTAssertEqual(bad.code, MDDrawioErrorNoPages);
}

- (void)testEveryPageBecomesItsOwn
{
    NSString *xml =
        @"<mxfile>"
        @"<diagram name=\"Uno\"><mxGraphModel><root/></mxGraphModel></diagram>"
        @"<diagram name=\"Due\"><mxGraphModel><root/></mxGraphModel></diagram>"
        @"<diagram name=\"Tre\"><mxGraphModel><root/></mxGraphModel></diagram>"
        @"</mxfile>";

    NSArray *pages = [[self fileFromString:xml error:NULL] pages];
    XCTAssertEqual(pages.count, 3u);
    XCTAssertEqualObjects([pages[2] name], @"Tre");
}

- (void)testAModelOnItsOwnIsOnePage
{
    NSArray *pages = [[self fileFromString:
        @"<mxGraphModel dx=\"100\"><root/></mxGraphModel>" error:NULL] pages];
    XCTAssertEqual(pages.count, 1u);
    XCTAssertEqualObjects([pages.firstObject name], @"");
}

- (void)testWhatIsNotADiagramSaysSo
{
    NSError *error = nil;
    XCTAssertNil([self fileFromString:@"ciao" error:&error]);
    XCTAssertEqualObjects(error.domain, kMDExpectedDomain);
    XCTAssertGreaterThan(error.localizedDescription.length, 0u);

    // XML, but with nothing in it that can be drawn.
    error = nil;
    XCTAssertNil([self fileFromString:@"<mxfile></mxfile>" error:&error]);
    XCTAssertEqual(error.code, MDDrawioErrorNoPages);
}

- (void)testAnEditablePNGCarriesTheFileInAChunk
{
    NSString *inside =
        @"<mxfile><diagram name=\"Dentro\">"
        @"<mxGraphModel><root/></mxGraphModel></diagram></mxfile>";
    NSString *escaped = [inside
        stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet alphanumericCharacterSet]];

    NSMutableData *png = [NSMutableData data];
    const unsigned char signature[8] =
        {0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a};
    [png appendBytes:signature length:sizeof(signature)];

    NSMutableData *chunk = [NSMutableData data];
    [chunk appendData:[@"mxfile" dataUsingEncoding:NSASCIIStringEncoding]];
    [chunk appendBytes:"\0" length:1];
    [chunk appendData:[escaped dataUsingEncoding:NSUTF8StringEncoding]];

    uint32_t length = (uint32_t)chunk.length;
    unsigned char header[4] = {(length >> 24) & 0xff, (length >> 16) & 0xff,
                               (length >> 8) & 0xff, length & 0xff};
    [png appendBytes:header length:4];
    [png appendData:[@"tEXt" dataUsingEncoding:NSASCIIStringEncoding]];
    [png appendData:chunk];
    [png appendBytes:"\0\0\0\0" length:4];   // where the checksum goes

    Class file = [self classNamed:@"MDDrawioFile"];
    NSArray *pages = [[file fileWithData:png error:NULL] pages];
    XCTAssertEqual(pages.count, 1u);
    XCTAssertEqualObjects([pages.firstObject name], @"Dentro");

    // A PNG without the chunk is a picture, not a diagram.
    NSError *error = nil;
    XCTAssertNil([file fileWithData:[NSData dataWithBytes:signature length:8]
                              error:&error]);
    XCTAssertEqual(error.code, MDDrawioErrorNotADiagram);
}


/** Nothing is reached for unless it is asked for.
 *
 * The viewer's own defaults put eight addresses on diagrams.net, and the
 * big shape libraries are files it fetches from them. Emptying two of the
 * eight — which is what this did at first — is the same as emptying none:
 * a diagram drawn with the AWS library would have gone out for its
 * stencils while the plug-in claimed to be working offline.
 */
- (void)testThePageAsksForNothingUnlessTheStencilsAreWanted
{
    Class renderer = [self classNamed:@"MDDrawioRenderer"];
    NSString *xml = @"<mxGraphModel><root/></mxGraphModel>";

    NSString *offline = [renderer pageForXML:xml stencils:NO
                                      viewer:@"/* il visualizzatore */"];
    XCTAssertFalse([offline containsString:@"diagrams.net"],
                   @"la pagina si porta dietro un indirizzo remoto");
    for (NSString *name in @[@"PROXY_URL", @"STYLE_PATH", @"SHAPES_PATH",
                             @"STENCIL_PATH", @"DRAW_MATH_URL",
                             @"GRAPH_IMAGE_PATH", @"mxImageBasePath",
                             @"mxBasePath"])
    {
        // Named and emptied, every one: an address left out is an address
        // left at the viewer's default, which is remote.
        NSString *emptied = [NSString stringWithFormat:@"window.%@=''", name];
        XCTAssertTrue([offline containsString:emptied],
                      @"%@ non è stato svuotato", name);
    }

    // And when they are wanted, they point somewhere.
    NSString *fetching = [renderer pageForXML:xml stencils:YES
                                       viewer:@"/* il visualizzatore */"];
    XCTAssertTrue([fetching containsString:
        @"window.STENCIL_PATH='https://viewer.diagrams.net/stencils'"]);

    // The diagram goes in as data for the viewer, whichever way round.
    XCTAssertTrue([offline containsString:@"class=\"mxgraph\""]);
    XCTAssertTrue([offline containsString:@"mxGraphModel"]);
    XCTAssertTrue([offline containsString:@"il visualizzatore"]);
}


#pragma mark - Names and links

- (void)testAPageNameBecomesAFileName
{
    Class naming = [self classNamed:@"MDDrawioNaming"];
    XCTAssertEqualObjects([naming fileNameSlugOf:@"Flusso di collaudo"],
                          @"Flusso di collaudo");
    // A separator in a page name would make a folder out of nothing.
    XCTAssertEqualObjects([naming fileNameSlugOf:@"rete/interna"],
                          @"rete-interna");
    XCTAssertEqualObjects([naming fileNameSlugOf:@"a:b?c"], @"a-b-c");
    XCTAssertEqualObjects([naming fileNameSlugOf:@"àèìòù"], @"àèìòù");
    // Nothing usable in it at all, and it still has to be called something.
    XCTAssertEqualObjects([naming fileNameSlugOf:@"///"], @"---");
    XCTAssertEqualObjects([naming fileNameSlugOf:@""], @"pagina");
}

- (void)testTheLinkIsRelativeWhenItCanBe
{
    Class naming = [self classNamed:@"MDDrawioNaming"];
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/note/verbale.md"];

    XCTAssertEqualObjects([naming
        linkTargetForFile:[NSURL fileURLWithPath:@"/Users/x/note/rete.png"]
           besideDocument:document], @"rete.png");
    XCTAssertEqualObjects([naming
        linkTargetForFile:[NSURL fileURLWithPath:@"/Users/x/note/img/rete.png"]
           besideDocument:document], @"img/rete.png");

    // A space is not a space in a link.
    XCTAssertEqualObjects([naming
        linkTargetForFile:[NSURL fileURLWithPath:@"/Users/x/note/a b.png"]
           besideDocument:document], @"a%20b.png");

    // Outside the document's folder there is nothing to be relative to, so
    // the whole path goes in rather than a link that points at nothing.
    XCTAssertEqualObjects([naming
        linkTargetForFile:[NSURL fileURLWithPath:@"/tmp/rete.png"]
           besideDocument:document], @"/tmp/rete.png");
}


#pragma mark - Drawing it

- (void)testADiagramIsDrawnHereWithNoConnection
{
    Class file = [self classNamed:@"MDDrawioFile"];
    NSString *xml =
        @"<mxfile><diagram name=\"Prova\"><mxGraphModel dx=\"400\" dy=\"300\">"
        @"<root><mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/>"
        @"<mxCell id=\"2\" value=\"Collaudo\" style=\"rounded=1;\" "
        @"vertex=\"1\" parent=\"1\"><mxGeometry x=\"40\" y=\"40\" "
        @"width=\"160\" height=\"80\" as=\"geometry\"/></mxCell>"
        @"</root></mxGraphModel></diagram></mxfile>";

    id diagram = [file fileWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]
                              error:NULL];
    id page = [[diagram pages] firstObject];
    XCTAssertNotNil(page);

    Class renderer = [self classNamed:@"MDDrawioRenderer"];
    id drawing = [[renderer alloc] initWithBundle:self.plugin];

    XCTestExpectation *done = [self expectationWithDescription:@"disegnato"];
    __block NSData *png = nil;
    __block NSError *failure = nil;
    [drawing renderPage:page scale:2.0 stencils:NO
            completion:^(NSData *data, NSError *error) {
        png = data;
        failure = error;
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:30.0];

    XCTAssertNil(failure, @"%@", failure);
    XCTAssertGreaterThan(png.length, 1000u);

    // A picture of the right size, and not a blank one: the cell is 160 by
    // 80 with a border of 8, drawn at twice the size.
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:png];
    XCTAssertNotNil(rep);
    XCTAssertGreaterThan(rep.pixelsWide, 300);
    XCTAssertGreaterThan(rep.pixelsHigh, 150);

    // Straight off the samples: asking a colour for its whiteness means
    // knowing which colour space it is in, and the bytes do not care.
    XCTAssertEqual(rep.bitsPerSample, 8);
    const unsigned char *bytes = rep.bitmapData;
    NSUInteger inked = 0;
    for (NSInteger y = 0; y < rep.pixelsHigh; y += 4)
    {
        for (NSInteger x = 0; x < rep.pixelsWide; x += 4)
        {
            const unsigned char *pixel =
                bytes + y * rep.bytesPerRow + x * rep.samplesPerPixel;
            if (pixel[0] < 230)
                inked++;
        }
    }
    XCTAssertGreaterThan(inked, 20u, @"la pagina è venuta bianca");
}

@end
