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

#pragma mark - Where the card is hung

- (void)testAFlippedViewCountsTheSameWayThePageDoes
{
    // WKWebView is flipped: the page's own top is the view's top, and only
    // the zoom has to be allowed for.
    NSDictionary *report = @{@"left": @40.0, @"top": @30.0,
                             @"width": @120.0, @"height": @18.0};
    NSRect where = MPLinkRectInView(report, 1.0, YES, 400.0);

    XCTAssertEqualWithAccuracy(NSMinX(where), 40.0, 0.001);
    XCTAssertEqualWithAccuracy(NSMinY(where), 30.0, 0.001);
    XCTAssertEqualWithAccuracy(NSWidth(where), 120.0, 0.001);
    XCTAssertEqualWithAccuracy(NSHeight(where), 18.0, 0.001);
}

- (void)testAnUnflippedViewCountsFromTheBottom
{
    NSDictionary *report = @{@"left": @40.0, @"top": @30.0,
                             @"width": @120.0, @"height": @18.0};
    NSRect where = MPLinkRectInView(report, 1.0, NO, 400.0);
    XCTAssertEqualWithAccuracy(NSMinY(where), 400.0 - 30.0 - 18.0, 0.001);
}

- (void)testTheZoomIsAllowedFor
{
    NSDictionary *report = @{@"left": @40.0, @"top": @30.0,
                             @"width": @120.0, @"height": @18.0};
    NSRect where = MPLinkRectInView(report, 2.0, YES, 400.0);
    XCTAssertEqualWithAccuracy(NSMinX(where), 80.0, 0.001);
    XCTAssertEqualWithAccuracy(NSMinY(where), 60.0, 0.001);
    XCTAssertEqualWithAccuracy(NSWidth(where), 240.0, 0.001);
    // A zoom of nothing is a zoom of one, not a rectangle at the origin.
    XCTAssertEqualWithAccuracy(NSMinX(MPLinkRectInView(report, 0.0, YES, 400.0)),
                               40.0, 0.001);
}

/** The whole round trip, in a real web view.
 *
 * The rectangle is turned into view coordinates and then handed back to the
 * page as a point: whatever is at that point has to be the link itself. This
 * is the assertion the first version of the card would have failed — it hung
 * the card where the link was not.
 */
- (void)testThePointTheCardIsHungFromIsOnTheLink
{
    XCTestExpectation *asked = [self expectationWithDescription:@"rettangolo"];
    __block NSDictionary *report = nil;
    [self.webView evaluateJavaScript:
        @"(function(){var r=document.getElementById('due')"
        @".getBoundingClientRect();"
        @"return {left:r.left,top:r.top,width:r.width,height:r.height};})();"
                   completionHandler:^(id result, NSError *error) {
        report = result;
        [asked fulfill];
    }];
    [self waitForExpectations:@[asked] timeout:5.0];
    XCTAssertNotNil(report);

    NSRect where = MPLinkRectInView(report, self.webView.pageZoom,
                                    self.webView.isFlipped,
                                    NSHeight(self.webView.bounds));

    // Back to the page: in a flipped view the two agree, so the middle of
    // that rectangle is the middle of the link.
    XCTestExpectation *hit = [self expectationWithDescription:@"elemento"];
    __block NSString *found = nil;
    NSString *ask = [NSString stringWithFormat:
        @"(document.elementFromPoint(%f, %f)||{}).id || '';",
        NSMidX(where), NSMidY(where)];
    [self.webView evaluateJavaScript:ask
                   completionHandler:^(id result, NSError *error) {
        found = result;
        [hit fulfill];
    }];
    [self waitForExpectations:@[hit] timeout:5.0];

    XCTAssertEqualObjects(found, @"due",
                          @"la cartolina finirebbe dove il link non è");
}

@end
