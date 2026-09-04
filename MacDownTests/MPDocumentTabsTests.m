//
//  MPDocumentTabsTests.m
//  MacDown
//

#import <XCTest/XCTest.h>

/** That two open documents really are tabs of one window.
 *
 * The tests run inside the application, so the document controller and a
 * real window server are both here — which makes this checkable, and it is
 * worth checking: the whole feature is two lines of window configuration,
 * and two lines that were never run are two lines that do nothing.
 */
@interface MPDocumentTabsTests : XCTestCase
@property (strong, nonatomic) NSMutableArray<NSDocument *> *opened;
@end

@implementation MPDocumentTabsTests

- (void)setUp
{
    [super setUp];
    self.opened = [NSMutableArray array];
}

- (void)tearDown
{
    // Closed without asking: an untitled document with no edits goes
    // quietly, and a test that leaves windows open poisons the next one.
    for (NSDocument *document in self.opened)
        [document close];
    self.opened = nil;
    [super tearDown];
}

- (NSDocument *)openUntitled
{
    NSError *error = nil;
    NSDocument *document = [[NSDocumentController sharedDocumentController]
        openUntitledDocumentAndDisplay:YES error:&error];
    XCTAssertNotNil(document, @"%@", error);
    if (document)
        [self.opened addObject:document];
    return document;
}

- (NSWindow *)windowOf:(NSDocument *)document
{
    return document.windowControllers.firstObject.window;
}


- (void)testADocumentWindowAsksToBeTabbed
{
    NSWindow *window = [self windowOf:[self openUntitled]];
    XCTAssertNotNil(window);
    XCTAssertEqual(window.tabbingMode, NSWindowTabbingModePreferred,
                   @"Automatic segue l'impostazione di sistema, che di "
                   @"norma non mette i documenti in tab");
    XCTAssertTrue(window.tabbingIdentifier.length > 0,
                  @"senza identificatore ogni finestra sta per sé");
}

/// Two of them, and the second joins the first rather than standing alone.
- (void)testTwoDocumentsBecomeTwoTabsOfOneWindow
{
    NSWindow *first = [self windowOf:[self openUntitled]];
    // A new window joins the tab group of the window in front, and in a
    // test run there may be nothing in front at all: without this the test
    // measures the window server's mood rather than the application's
    // configuration, and fails on the same code that passed an hour ago.
    [first makeKeyAndOrderFront:nil];

    NSWindow *second = [self windowOf:[self openUntitled]];
    XCTAssertNotEqual(first, second, @"sono due finestre, e due tab");

    XCTAssertEqualObjects(first.tabbingIdentifier, second.tabbingIdentifier);
    XCTAssertNotNil(second.tabGroup, @"la seconda non è in nessun gruppo");
    XCTAssertEqual(first.tabGroup, second.tabGroup,
                   @"in gruppi diversi sono due finestre separate");

    // Appartenenza, non totale: l'applicazione apre già un documento
    // all'avvio, e anche quello entra nel gruppo — che è il comportamento
    // voluto. Contando i tab, questo test affermava una macchina pulita
    // invece della cosa che gli interessa.
    XCTAssertTrue([first.tabGroup.windows containsObject:first]);
    XCTAssertTrue([first.tabGroup.windows containsObject:second]);
    XCTAssertTrue(first.tabGroup.windows.count >= 2,
                  @"%lu nel gruppo",
                  (unsigned long)first.tabGroup.windows.count);
}

/** And showing a document selects its tab.
 *
 * Which is what a link to an already-open file relies on: the document is
 * found, `showWindows` is called, and the reader is looking at it.
 */
- (void)testShowingADocumentSelectsItsTab
{
    NSDocument *first = [self openUntitled];
    NSDocument *second = [self openUntitled];

    NSWindow *firstWindow = [self windowOf:first];
    NSWindow *secondWindow = [self windowOf:second];
    XCTAssertEqual(secondWindow.tabGroup.selectedWindow, secondWindow,
                   @"l'ultima aperta è quella in vista");

    [first showWindows];
    XCTAssertEqual(firstWindow.tabGroup.selectedWindow, firstWindow,
                   @"mostrare un documento deve portare al suo tab");
}

/** The plus in the tab bar needs somebody to answer for it.
 *
 * AppKit shows the button only if the responder chain implements this, and
 * a document-based application implements nothing of the sort by itself —
 * so without this the bar appears with no way to add to it.
 */
- (void)testSomethingAnswersForThePlusButton
{
    NSDocument *document = [self openUntitled];
    XCTAssertTrue([document respondsToSelector:@selector(newWindowForTab:)]);

    NSUInteger before =
        [NSDocumentController sharedDocumentController].documents.count;
    [(id)document newWindowForTab:nil];
    NSArray<NSDocument *> *after =
        [NSDocumentController sharedDocumentController].documents;
    XCTAssertEqual(after.count, before + 1, @"il più deve aggiungere un tab");

    // Da chiudere come gli altri.
    for (NSDocument *open in after)
        if (![self.opened containsObject:open])
            [self.opened addObject:open];
}

@end
