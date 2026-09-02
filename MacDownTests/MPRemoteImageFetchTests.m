//
//  MPRemoteImageFetchTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPRemoteImageFetch.h"

@interface MPRemoteImageFetchTests : XCTestCase
@end

@implementation MPRemoteImageFetchTests

- (void)testFindsOnlyTheAddressesItHasToGoAndGet
{
    NSString *html =
        @"<p><img src=\"https://esempio.it/a.png\"></p>"
        @"<p><img src='http://esempio.it/b.jpg'></p>"
        @"<p><img src=\"immagini/locale.png\"></p>"
        @"<p><img src=\"file:///tmp/locale.png\"></p>"
        @"<p><img src=\"data:image/png;base64,AAAA\"></p>";

    XCTAssertEqualObjects(MPRemoteImageSourcesInHTML(html), (@[
        @"https://esempio.it/a.png", @"http://esempio.it/b.jpg",
    ]), @"le virgolette semplici contano, il locale no");
}

/// The address is written as HTML, so a query string arrives escaped.
- (void)testTheQueryStringIsUnescaped
{
    NSString *html =
        @"<img src=\"https://esempio.it/i?w=200&amp;h=100\">";
    XCTAssertEqualObjects(MPRemoteImageSourcesInHTML(html).firstObject,
                          @"https://esempio.it/i?w=200&h=100");
}

- (void)testAPictureUsedTwiceIsListedTwice
{
    NSString *html = @"<img src=\"https://e.it/a.png\">"
                     @"<img src=\"https://e.it/a.png\">";
    XCTAssertEqual(MPRemoteImageSourcesInHTML(html).count, (NSUInteger)2);
}

- (void)testNoRemotePicturesIsNoWork
{
    NSString *html = @"<p>Solo prosa, e un <a href=\"https://e.it\">link</a>.</p>";
    XCTAssertEqual(MPRemoteImageSourcesInHTML(html).count, (NSUInteger)0);

    NSMutableArray<NSString *> *unreplaced = [NSMutableArray array];
    XCTAssertEqualObjects(
        MPHTMLByReplacingRemoteImageSources(html, @{}, unreplaced), html);
    XCTAssertEqual(unreplaced.count, (NSUInteger)0);
}

- (void)testEveryOccurrenceIsReplaced
{
    NSString *html = @"<img src=\"https://e.it/a.png\">tra"
                     @"<img src='https://e.it/a.png'>";
    NSMutableArray<NSString *> *unreplaced = [NSMutableArray array];
    NSString *out = MPHTMLByReplacingRemoteImageSources(
        html, @{@"https://e.it/a.png": @"data:image/png;base64,QQ=="},
        unreplaced);

    XCTAssertEqual(unreplaced.count, (NSUInteger)0);
    XCTAssertEqual([out rangeOfString:@"https://"].location,
                   (NSUInteger)NSNotFound);
    XCTAssertEqual([out componentsSeparatedByString:@"data:image/png"].count,
                   (NSUInteger)3, @"due sostituzioni");
    XCTAssertNotEqual([out rangeOfString:@"tra"].location,
                      (NSUInteger)NSNotFound, @"il testo intorno resta");
}

/// What could not be had must come back *named*, not counted.
- (void)testWhatIsMissingIsNamed
{
    NSString *html = @"<img src=\"https://e.it/a.png\">"
                     @"<img src=\"https://e.it/b.png\">"
                     @"<img src=\"https://e.it/b.png\">";
    NSMutableArray<NSString *> *unreplaced = [NSMutableArray array];
    NSString *out = MPHTMLByReplacingRemoteImageSources(
        html, @{@"https://e.it/a.png": @"data:image/png;base64,QQ=="},
        unreplaced);

    XCTAssertEqualObjects(unreplaced, @[@"https://e.it/b.png"],
                          @"una volta per indirizzo, non per tag");
    XCTAssertNotEqual([out rangeOfString:@"https://e.it/b.png"].location,
                      (NSUInteger)NSNotFound, @"lasciato com'era");
}

@end
