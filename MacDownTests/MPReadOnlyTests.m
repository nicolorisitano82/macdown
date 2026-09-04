//
//  MPReadOnlyTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPDocument.h"


@interface MPDocument (Testing)
@property (assign, nonatomic) BOOL readOnly;
@property (unsafe_unretained) NSTextView *editor;
- (IBAction)toggleReadOnly:(id)sender;
@end


/** A document being read rather than written.
 *
 * A signed report or a closed evidence file is not meant to be edited, and
 * the only defence until now was remembering that.
 */
@interface MPReadOnlyTests : XCTestCase
@property (strong) MPDocument *document;
@end


@implementation MPReadOnlyTests

- (void)setUp
{
    [super setUp];
    NSError *error = nil;
    self.document = [[NSDocumentController sharedDocumentController]
        openUntitledDocumentAndDisplay:YES error:&error];
    XCTAssertNotNil(self.document, @"%@", error);
    self.document.markdown = @"# Verbale\n\nUna riga.\n";
}

- (void)tearDown
{
    [self.document close];
    self.document = nil;
    [super tearDown];
}

/// Whether the menu would offer a command right now.
- (BOOL)offers:(SEL)action
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:action
                                          keyEquivalent:@""];
    return [self.document validateUserInterfaceItem:item];
}

- (void)testItStartsOffAndIsOfferedEitherWay
{
    XCTAssertFalse(self.document.readOnly);
    XCTAssertTrue(self.document.editor.editable);
    XCTAssertTrue([self offers:@selector(toggleReadOnly:)]);
}

- (void)testTheTextViewRefusesWhatIsTyped
{
    [self.document toggleReadOnly:nil];
    XCTAssertTrue(self.document.readOnly);
    XCTAssertFalse(self.document.editor.editable);
    // Still selectable: reading means selecting and copying.
    XCTAssertTrue(self.document.editor.selectable);

    // And back again, since a document read today may be corrected
    // tomorrow.
    [self.document toggleReadOnly:nil];
    XCTAssertTrue(self.document.editor.editable);
}

/** And the commands are refused too.
 *
 * The text view refuses what is typed into it but not what is done to it:
 * insertText:replacementRange: is the programmatic path and never asks
 * whether the view is editable. Without this the lock would be a lie —
 * ⌘B would still put asterisks in a document that says it cannot change.
 */
- (void)testTheCommandsThatEditAreRefused
{
    NSArray *edits = @[@"toggleStrong:", @"toggleEmphasis:",
                       @"insertCode:", @"toggleLink:", @"insertTable:",
                       @"convertToH2:", @"toggleBlockquote:"];
    for (NSString *name in edits)
        XCTAssertTrue([self offers:NSSelectorFromString(name)],
                      @"%@ dovrebbe essere offerto su un documento normale",
                      name);

    [self.document toggleReadOnly:nil];
    for (NSString *name in edits)
        XCTAssertFalse([self offers:NSSelectorFromString(name)],
                       @"%@ è ancora offerto in sola lettura", name);

    // The writing help is in the list too. Not checked the other way
    // round, since it is refused anyway without a model installed and a
    // selection to work on — a test that cannot fail proves nothing.
    XCTAssertFalse([self offers:@selector(improveWriting:)]);

    // What only reads is untouched: copying, exporting, looking.
    XCTAssertTrue([self offers:@selector(copyHtml:)]);
    XCTAssertTrue([self offers:@selector(toggleReadOnly:)]);
}

- (void)testNothingIsWrittenToTheDocument
{
    NSString *before = self.document.markdown;
    [self.document toggleReadOnly:nil];
    // The state is the window's, not the file's: a lock that changed the
    // text would be a lock that has to be saved.
    XCTAssertEqualObjects(self.document.markdown, before);
    XCTAssertFalse(self.document.isDocumentEdited);
}

@end
