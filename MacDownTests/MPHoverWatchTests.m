//
//  MPHoverWatchTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import <WebKit/WebKit.h>
#import "MPLinkPreview.h"


/// The wait the shipped script is given here. The script itself is the one
/// the application injects; only the number of milliseconds differs, because
/// a test that sat still for five seconds four times over would be a test
/// nobody runs.
static const NSTimeInterval kMPTestWait = 0.25;

/// Long enough for the wait to pass several times over, so "nothing was
/// reported" means it, and short enough not to hold the suite up.
static const NSTimeInterval kMPPatience = 3.0;

static NSString * const kMPPage =
    @"<html><body style='height:3000px'>"
    @"<p><a id='uno' href='uno.md'>primo</a></p>"
    @"<p><a id='due' href='due.md'>secondo</a></p>"
    @"<p id='fuori'>testo che non è un link</p>"
    @"</body></html>";


#pragma mark - What the page says

@interface MPHoverListener : NSObject <WKScriptMessageHandler>
@property (strong) NSMutableArray<NSDictionary *> *messages;
@property (copy) void (^onMessage)(NSDictionary *body);
@end

@implementation MPHoverListener

- (instancetype)init
{
    self = [super init];
    if (self)
        _messages = [NSMutableArray array];
    return self;
}

- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    if (![message.body isKindOfClass:[NSDictionary class]])
        return;
    [self.messages addObject:message.body];
    if (self.onMessage)
        self.onMessage(message.body);
}

/// The last message that says something about a link, ignoring the ones
/// that only say the pointer has left.
- (NSDictionary *)lastReport
{
    for (NSDictionary *body in self.messages.reverseObjectEnumerator)
    {
        if (body[@"href"])
            return body;
    }
    return nil;
}

- (BOOL)saidTheCardShouldGoAway
{
    for (NSDictionary *body in self.messages)
    {
        if ([body[@"away"] boolValue])
            return YES;
    }
    return NO;
}

@end


#pragma mark - The tests

@interface MPHoverWatchTests : XCTestCase <WKNavigationDelegate>
@property (strong) WKWebView *webView;
@property (strong) MPHoverListener *listener;
@property (strong) XCTestExpectation *loaded;
@end


@implementation MPHoverWatchTests

- (void)setUp
{
    [super setUp];
    self.listener = [[MPHoverListener alloc] init];

    WKWebViewConfiguration *configuration =
        [[WKWebViewConfiguration alloc] init];
    WKUserContentController *content = configuration.userContentController;
    [content addScriptMessageHandler:self.listener name:MPHoverMessageName];
    [content addUserScript:[[WKUserScript alloc]
        initWithSource:MPHoverWatchScript(kMPTestWait)
         injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
      forMainFrameOnly:YES]];

    self.webView = [[WKWebView alloc]
        initWithFrame:NSMakeRect(0.0, 0.0, 600.0, 400.0)
        configuration:configuration];
    self.webView.navigationDelegate = self;

    self.loaded = [self expectationWithDescription:@"pagina caricata"];
    [self.webView loadHTMLString:kMPPage
                        baseURL:[NSURL fileURLWithPath:@"/tmp/verbale.md"]];
    [self waitForExpectations:@[self.loaded] timeout:10.0];
}

- (void)tearDown
{
    [self.webView.configuration.userContentController
        removeScriptMessageHandlerForName:MPHoverMessageName];
    self.webView.navigationDelegate = nil;
    self.webView = nil;
    [super tearDown];
}

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation
{
    [self.loaded fulfill];
}


#pragma mark - Driving the pointer

/// Runs script in the page and waits for it, so the steps of a gesture
/// happen in the order they are written.
- (void)run:(NSString *)javaScript
{
    XCTestExpectation *done = [self expectationWithDescription:javaScript];
    [self.webView evaluateJavaScript:javaScript
                   completionHandler:^(id result, NSError *error) {
        XCTAssertNil(error, @"«%@» non è andato: %@", javaScript, error);
        [done fulfill];
    }];
    [self waitForExpectations:@[done] timeout:5.0];
}

- (void)pointerOnto:(NSString *)identifier
{
    [self run:[NSString stringWithFormat:
        @"document.getElementById('%@').dispatchEvent("
        @"new MouseEvent('mouseover',{bubbles:true}));", identifier]];
}

- (void)pointerOff:(NSString *)identifier
{
    [self run:[NSString stringWithFormat:
        @"document.getElementById('%@').dispatchEvent("
        @"new MouseEvent('mouseout',{bubbles:true}));", identifier]];
}

/// Waits for the page to report something about a link, or gives up.
- (NSDictionary *)waitForAReport
{
    XCTestExpectation *reported =
        [self expectationWithDescription:@"un link è stato riferito"];
    reported.assertForOverFulfill = NO;
    self.listener.onMessage = ^(NSDictionary *body) {
        if (body[@"href"])
            [reported fulfill];
    };
    [self waitForExpectations:@[reported] timeout:kMPPatience];
    return self.listener.lastReport;
}

/// Waits out several times the delay, to be able to say nothing happened.
- (void)waitOutTheDelay
{
    XCTestExpectation *never =
        [self expectationWithDescription:@"nessun rapporto"];
    never.inverted = YES;
    self.listener.onMessage = ^(NSDictionary *body) {
        if (body[@"href"])
            [never fulfill];
    };
    [self waitForExpectations:@[never] timeout:kMPTestWait * 8.0];
}


#pragma mark - Resting on a link

- (void)testAPointerLeftOnALinkIsAnswered
{
    [self pointerOnto:@"uno"];
    NSDictionary *report = [self waitForAReport];

    XCTAssertEqualObjects(report[@"href"], @"uno.md");
    XCTAssertEqualObjects(report[@"text"], @"primo");
    // The rectangle is what the card is hung on, so it has to be real.
    XCTAssertGreaterThan([report[@"width"] doubleValue], 0.0);
    XCTAssertGreaterThan([report[@"height"] doubleValue], 0.0);
    XCTAssertGreaterThanOrEqual([report[@"top"] doubleValue], 0.0);
}

- (void)testTheAnswerDoesNotComeBeforeTheWaitIsOver
{
    [self pointerOnto:@"uno"];
    // Straight away there is nothing: this is the whole point of the wait.
    XCTAssertNil(self.listener.lastReport);
    [self waitForAReport];
    XCTAssertNotNil(self.listener.lastReport);
}


#pragma mark - Changing one's mind

- (void)testLeavingTheLinkInTimeSaysNothingAboutIt
{
    [self pointerOnto:@"uno"];
    [self pointerOff:@"uno"];
    [self waitOutTheDelay];

    XCTAssertNil(self.listener.lastReport, @"la cartolina non doveva aprirsi");
    XCTAssertTrue(self.listener.saidTheCardShouldGoAway);
}

- (void)testScrollingPutsTheCardAway
{
    [self pointerOnto:@"uno"];
    [self run:@"window.dispatchEvent(new Event('scroll'));"];
    [self waitOutTheDelay];

    XCTAssertNil(self.listener.lastReport);
    XCTAssertTrue(self.listener.saidTheCardShouldGoAway);
}

- (void)testPassingOverALinkOnTheWayToAnotherAnswersAboutTheSecond
{
    // What happens in a list of links: the pointer crosses several.
    [self pointerOnto:@"uno"];
    [self pointerOnto:@"due"];
    NSDictionary *report = [self waitForAReport];

    XCTAssertEqualObjects(report[@"href"], @"due.md");
    // And only one link was ever reported.
    NSUInteger reports = 0;
    for (NSDictionary *body in self.listener.messages)
    {
        if (body[@"href"])
            reports++;
    }
    XCTAssertEqual(reports, 1u);
}

- (void)testRestingOnTheSameLinkTwiceDoesNotRestartTheWait
{
    [self pointerOnto:@"uno"];
    [self pointerOnto:@"uno"];   // The pointer moving within the link.
    NSDictionary *report = [self waitForAReport];
    XCTAssertEqualObjects(report[@"href"], @"uno.md");
    XCTAssertFalse(self.listener.saidTheCardShouldGoAway,
                   @"restare sullo stesso link non è andarsene");
}

- (void)testTextThatIsNotALinkIsNotWorthACard
{
    [self pointerOnto:@"fuori"];
    [self waitOutTheDelay];
    XCTAssertNil(self.listener.lastReport);
}

@end
