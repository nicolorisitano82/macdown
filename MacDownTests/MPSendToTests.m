//
//  MPSendToTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPSendTo.h"


/// Handing a document to Claude or to ChatGPT: where the link goes, and
/// whether it carries the text or the clipboard has to.
@interface MPSendToTests : XCTestCase
@end


@implementation MPSendToTests

- (void)testClaudeOpensItsOwnApplicationWithThePromptFilledIn
{
    NSURL *url = MPSendToURL(MPSendToClaude, @"Verbale della riunione", YES);
    XCTAssertEqualObjects(url.scheme, @"claude");
    XCTAssertTrue([url.absoluteString hasPrefix:@"claude://claude.ai/new?q="],
                  @"%@", url);
    XCTAssertTrue([url.absoluteString containsString:@"Verbale%20della"],
                  @"%@", url);
    XCTAssertTrue(MPSendToLinkCarriesText(MPSendToClaude, @"Verbale", YES));
}

- (void)testWithoutTheApplicationClaudeGetsAPlainLink
{
    // The web dropped the prefill, so the clipboard is what carries it.
    NSURL *url = MPSendToURL(MPSendToClaude, @"Verbale", NO);
    XCTAssertEqualObjects(url.absoluteString, @"https://claude.ai/new");
    XCTAssertFalse(MPSendToLinkCarriesText(MPSendToClaude, @"Verbale", NO));
}

- (void)testADocumentTooLongForTheLinkIsNotTruncated
{
    NSString *huge = [@"" stringByPaddingToLength:20000 withString:@"a"
                                  startingAtIndex:0];
    XCTAssertFalse(MPSendToLinkCarriesText(MPSendToClaude, huge, YES),
                   @"meglio niente nel link che mezzo documento");
    NSURL *url = MPSendToURL(MPSendToClaude, huge, YES);
    XCTAssertEqualObjects(url.absoluteString, @"claude://claude.ai/new");
}

- (void)testChatGPTPrefillsOnTheWeb
{
    NSURL *url = MPSendToURL(MPSendToChatGPT, @"Rete interna", NO);
    XCTAssertTrue([url.absoluteString hasPrefix:@"https://chatgpt.com/?q="],
                  @"%@", url);
    XCTAssertTrue([url.absoluteString containsString:@"Rete%20interna"]);
}

- (void)testAccentsAndPunctuationSurviveTheLink
{
    NSURL *url = MPSendToURL(MPSendToChatGPT, @"Perché? Così & tutto", NO);
    XCTAssertNotNil(url, @"un'URL non valida non apre niente");
    XCTAssertFalse([url.absoluteString containsString:@" "]);
    XCTAssertTrue([url.absoluteString containsString:@"%26"], @"%@", url);
}

- (void)testALongDocumentGoesToChatGPTThroughTheClipboard
{
    NSString *long_ = [@"" stringByPaddingToLength:9000 withString:@"parola "
                                   startingAtIndex:0];
    XCTAssertFalse(MPSendToLinkCarriesText(MPSendToChatGPT, long_, NO));
    XCTAssertEqualObjects(MPSendToURL(MPSendToChatGPT, long_, NO)
                              .absoluteString, @"https://chatgpt.com/");
}

- (void)testNothingToSend
{
    XCTAssertFalse(MPSendToLinkCarriesText(MPSendToClaude, @"   \n", YES));
    XCTAssertEqualObjects(MPSendToURL(MPSendToClaude, @"", YES).absoluteString,
                          @"claude://claude.ai/new");
}

@end
