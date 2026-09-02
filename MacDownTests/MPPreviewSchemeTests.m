//
//  MPPreviewSchemeTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPPreviewSchemeHandler.h"

@interface MPPreviewSchemeTests : XCTestCase
@end

@implementation MPPreviewSchemeTests

/// What a link followed out of the preview has to become.
- (void)testAPreviewURLBecomesTheFileItStandsFor
{
    NSURL *preview = MPPreviewURLForPath(@"/Users/x/Note/verbale.md");
    XCTAssertEqualObjects(preview.scheme, @"macdown-preview");

    NSURL *file = MPFileURLFromPreviewURL(preview);
    XCTAssertTrue(file.isFileURL);
    XCTAssertEqualObjects(file.path, @"/Users/x/Note/verbale.md");
}

/** The path comes back out of its encoding.
 *
 * A URL carries `%20` where the file on disk has a space, and asking the
 * workspace to open the encoded name finds nothing.
 */
- (void)testTheEncodingComesOff
{
    NSURL *preview =
        MPPreviewURLForPath(@"/Users/x/Note/VERBALE 2026-09-02.md");
    XCTAssertNotEqual([preview.absoluteString rangeOfString:@"%20"].location,
                      (NSUInteger)NSNotFound, @"nell'URL è codificato");

    NSURL *file = MPFileURLFromPreviewURL(preview);
    XCTAssertEqualObjects(file.path, @"/Users/x/Note/VERBALE 2026-09-02.md");
}

/// A link into a heading of another document is still a link into it.
- (void)testAFragmentSurvives
{
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"macdown-preview";
    components.host = @"";
    components.path = @"/Users/x/Note/verbale.md";
    components.fragment = @"decisioni";

    NSURL *file = MPFileURLFromPreviewURL(components.URL);
    XCTAssertEqualObjects(file.path, @"/Users/x/Note/verbale.md");
    XCTAssertEqualObjects(file.fragment, @"decisioni");
}

/// Anything else is somebody else's business and comes back untouched.
- (void)testOtherSchemesAreLeftAlone
{
    NSURL *web = [NSURL URLWithString:@"https://esempio.it/pagina"];
    XCTAssertEqualObjects(MPFileURLFromPreviewURL(web), web);

    NSURL *file = [NSURL fileURLWithPath:@"/Users/x/Note/verbale.md"];
    XCTAssertEqualObjects(MPFileURLFromPreviewURL(file), file);

    NSURL *mail = [NSURL URLWithString:@"mailto:nessuno@esempio.it"];
    XCTAssertEqualObjects(MPFileURLFromPreviewURL(mail), mail);

    XCTAssertNil(MPFileURLFromPreviewURL(nil));
}

/** There and back, which is the pair the preview actually uses.
 *
 * Compared precomposed. A path with an accent comes back decomposed —
 * `é` as `e` plus a combining acute — because that is the form the URL
 * machinery works in. It is the same file either way, since the file
 * system compares names without regard to which form they are written in,
 * so the assertion is about the name and not about its bytes.
 */
- (void)testTheRoundTrip
{
    for (NSString *path in @[@"/tmp/a.md",
                             @"/Users/x/Con spazi/e #cancelletto/b.md",
                             @"/Users/x/perché/così.md"])
    {
        NSURL *back = MPFileURLFromPreviewURL(MPPreviewURLForPath(path));
        XCTAssertEqualObjects(back.path.precomposedStringWithCanonicalMapping,
                              path.precomposedStringWithCanonicalMapping,
                              @"%@", path);
    }
}

@end
