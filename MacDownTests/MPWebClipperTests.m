//
//  MPWebClipperTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPWebClipper.h"
#import "MPUtilities.h"


@interface MPWebClipperTests : XCTestCase
@end


@implementation MPWebClipperTests

#pragma mark - What is kept, and what is thrown

- (void)testWhatSurroundsThePageIsNotThePage
{
    NSString *html =
        @"<html><head><title>Verbale</title>"
        @"<style>body{color:red}</style>"
        @"<script>alert('no')</script></head><body>"
        @"<nav>Menù, Chi siamo, Contatti</nav>"
        @"<header>Intestazione del sito</header>"
        @"<p>Il testo che conta.</p>"
        @"<aside>Articoli correlati</aside>"
        @"<footer>Cookie, privacy, 2026</footer>"
        @"</body></html>";

    NSString *kept = MPReadableHTMLFragment(html);
    XCTAssertTrue([kept containsString:@"Il testo che conta"]);
    for (NSString *gone in @[@"alert", @"color:red", @"Chi siamo",
                             @"Intestazione", @"correlati", @"Cookie"])
    {
        XCTAssertFalse([kept containsString:gone],
                       @"«%@» è rimasto", gone);
    }
}

- (void)testWhenThePageSaysWhichPartIsTheArticle
{
    NSMutableString *body = [NSMutableString string];
    for (NSUInteger i = 0; i < 20; i++)
        [body appendString:@"<p>Una riga dell'articolo vero.</p>"];

    NSString *html = [NSString stringWithFormat:
        @"<html><body><div>Barra laterale</div>"
        @"<article>%@</article>"
        @"<div>Piede della pagina</div></body></html>", body];

    NSString *kept = MPReadableHTMLFragment(html);
    XCTAssertTrue([kept containsString:@"articolo vero"]);
    XCTAssertFalse([kept containsString:@"Barra laterale"]);
    XCTAssertFalse([kept containsString:@"Piede"]);
}

- (void)testACommentedOutScriptIsStillAScript
{
    NSString *kept = MPReadableHTMLFragment(
        @"<body><!-- <script>alert(1)</script> --><p>Testo.</p></body>");
    XCTAssertFalse([kept containsString:@"alert"]);
    XCTAssertTrue([kept containsString:@"Testo."]);
}


#pragma mark - What the page is called

- (void)testTheTitle
{
    XCTAssertEqualObjects(MPTitleOfHTML(
        @"<html><head><title>Verbale di collaudo</title></head></html>"),
        @"Verbale di collaudo");
    // Its first heading, when it has no title.
    XCTAssertEqualObjects(MPTitleOfHTML(
        @"<body><h1>Solo un <em>titolo</em></h1></body>"),
        @"Solo un titolo");
    // Entities and stray whitespace, since a title is one line.
    XCTAssertEqualObjects(MPTitleOfHTML(
        @"<title>Ricerca &amp;\n   Sviluppo</title>"),
        @"Ricerca & Sviluppo");
    XCTAssertNil(MPTitleOfHTML(@"<body><p>niente</p></body>"));
}

- (void)testTheFileItWouldBeCalled
{
    NSURL *url = [NSURL URLWithString:@"https://esempio.it/a/b?c=d"];
    XCTAssertEqualObjects(MPFileNameForClipping(@"Verbale di collaudo", url),
                          @"Verbale di collaudo.md");
    // A separator in a title would make a folder out of nothing.
    XCTAssertEqualObjects(MPFileNameForClipping(@"AWS: rete/interna", url),
                          @"AWS- rete-interna.md");
    // Nothing usable, and it still has to be called something.
    XCTAssertEqualObjects(MPFileNameForClipping(nil, url), @"esempio.it.md");
    XCTAssertEqualObjects(MPFileNameForClipping(@"///", url), @"esempio.it.md");
}


#pragma mark - The file that gets written

- (void)testTheClippingCarriesItsSource
{
    NSString *html =
        @"<html><head><title>Sicurezza di rete</title></head><body>"
        @"<h2>Firewall</h2><p>Il testo dell'articolo.</p>"
        @"<ul><li>Primo</li><li>Secondo</li></ul></body></html>";
    NSURL *url = [NSURL URLWithString:@"https://esempio.it/rete"];
    NSDate *when = [NSDate dateWithTimeIntervalSince1970:1788000000];

    NSString *clipped = MPClippedMarkdown(html, url, when);
    XCTAssertNotNil(clipped);

    // Front matter, which this editor already reads, so the source
    // survives the text being moved into another document.
    XCTAssertTrue([clipped hasPrefix:@"---\n"]);
    XCTAssertTrue([clipped containsString:
        @"title: \"Sicurezza di rete\""]);
    XCTAssertTrue([clipped containsString:
        @"source: https://esempio.it/rete"]);
    XCTAssertTrue([clipped containsString:@"clipped: 2026-"],
                  @"manca la data: %@",
                  [clipped substringToIndex:MIN(120u, clipped.length)]);

    // And the page as Markdown, by the same conversion as pasting.
    XCTAssertTrue([clipped containsString:@"# Sicurezza di rete"]);
    XCTAssertTrue([clipped containsString:@"Il testo dell'articolo."]);
    XCTAssertTrue([clipped containsString:@"Primo"]);
}

- (void)testAPageWithNoTextIsNotAClipping
{
    // Nothing to keep is an answer, not an empty file.
    XCTAssertNil(MPClippedMarkdown(
        @"<html><body><script>x()</script></body></html>",
        [NSURL URLWithString:@"https://esempio.it"], nil));
    XCTAssertNil(MPClippedMarkdown(@"", [NSURL URLWithString:@"https://x.it"],
                                   nil));
}


#pragma mark - How long it takes to read

- (void)testTheReadingTime
{
    // Two hundred words a minute, and never nought minutes for a document
    // that has words in it.
    XCTAssertEqual(MPReadingMinutesForWords(0), 0u);
    XCTAssertEqual(MPReadingMinutesForWords(1), 1u);
    XCTAssertEqual(MPReadingMinutesForWords(200), 1u);
    XCTAssertEqual(MPReadingMinutesForWords(400), 2u);
    XCTAssertEqual(MPReadingMinutesForWords(500), 3u);
    XCTAssertEqual(MPReadingMinutesForWords(2000), 10u);
}

@end
