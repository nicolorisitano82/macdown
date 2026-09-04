//
//  MPWritingAidsTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPEditorView.h"


/** The two writing modes, measured rather than looked at.
 *
 * Both are drawing and scrolling, so both can be asked directly: which
 * characters carry the dimmed colour, and where the clip view ended up.
 */
@interface MPWritingAidsTests : XCTestCase
@property (strong) MPEditorView *editor;
@property (strong) NSScrollView *scroll;
@end


@implementation MPWritingAidsTests

- (void)setUp
{
    [super setUp];
    self.scroll = [[NSScrollView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 400.0, 120.0)];
    self.editor = [[MPEditorView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 400.0, 120.0)];
    self.editor.textColor = [NSColor colorWithCalibratedWhite:0.9 alpha:1.0];
    self.scroll.documentView = self.editor;
    self.scroll.hasVerticalScroller = YES;
}

/// Whether the character at `index` is drawn dimmed.
- (BOOL)isDimmedAt:(NSUInteger)index
{
    NSDictionary *temporary = [self.editor.layoutManager
        temporaryAttributesAtCharacterIndex:index effectiveRange:NULL];
    return temporary[NSForegroundColorAttributeName] != nil;
}


#pragma mark - Focus

- (void)testOnlyTheParagraphBeingWrittenIsNotDimmed
{
    NSString *text = @"Primo paragrafo.\n\nSecondo paragrafo.\n\nTerzo.\n";
    self.editor.string = text;
    NSRange second = [text rangeOfString:@"Secondo"];

    self.editor.selectedRange = NSMakeRange(second.location, 0);
    self.editor.focusModeEnabled = YES;

    XCTAssertFalse([self isDimmedAt:second.location],
                   @"il paragrafo dove si scrive non va attenuato");
    XCTAssertTrue([self isDimmedAt:0], @"quello sopra sì");
    XCTAssertTrue([self isDimmedAt:[text rangeOfString:@"Terzo"].location],
                  @"e quello sotto");
}

- (void)testTheDimmingFollowsTheCaret
{
    NSString *text = @"Primo.\n\nSecondo.\n";
    self.editor.string = text;
    self.editor.selectedRange = NSMakeRange(0, 0);
    self.editor.focusModeEnabled = YES;
    XCTAssertFalse([self isDimmedAt:0]);

    NSRange second = [text rangeOfString:@"Secondo"];
    self.editor.selectedRange = NSMakeRange(second.location, 0);
    [self.editor updateWritingAids];
    XCTAssertTrue([self isDimmedAt:0], @"il primo ora è quello vecchio");
    XCTAssertFalse([self isDimmedAt:second.location]);
}

- (void)testSwitchingItOffLeavesNothingBehind
{
    self.editor.string = @"Primo.\n\nSecondo.\n";
    self.editor.selectedRange = NSMakeRange(12, 0);
    self.editor.focusModeEnabled = YES;
    XCTAssertTrue([self isDimmedAt:0]);

    // Nothing may survive it: the dimming is drawing, and drawing that
    // outlives its mode is a document that looks broken.
    self.editor.focusModeEnabled = NO;
    XCTAssertFalse([self isDimmedAt:0]);
    XCTAssertFalse([self isDimmedAt:12]);
}

- (void)testTheDocumentItselfIsUntouched
{
    NSString *text = @"Primo.\n\nSecondo.\n";
    self.editor.string = text;
    self.editor.selectedRange = NSMakeRange(0, 0);
    self.editor.focusModeEnabled = YES;

    // Temporary attributes belong to the layout manager, not to the text:
    // nothing here can reach the file. The colour in the storage is the
    // editor's own, at full strength, and not the dimmed one.
    XCTAssertEqualObjects(self.editor.string, text);
    NSColor *stored = [self.editor.textStorage
        attribute:NSForegroundColorAttributeName atIndex:0
        effectiveRange:NULL];
    XCTAssertEqualWithAccuracy(stored.alphaComponent, 1.0, 0.001);
    // Asked where something *is* dimmed: at the caret's own paragraph
    // there is nothing to find, which is the point of the mode.
    NSUInteger elsewhere = [text rangeOfString:@"Secondo"].location;
    NSColor *drawn = [self.editor.layoutManager
        temporaryAttributesAtCharacterIndex:elsewhere effectiveRange:NULL]
        [NSForegroundColorAttributeName];
    XCTAssertEqualWithAccuracy(drawn.alphaComponent, 0.35, 0.001);
}


#pragma mark - Typewriter

- (void)testTheLineBeingWrittenIsKeptOffTheBottom
{
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < 60; i++)
        [text appendFormat:@"riga %lu\n", (unsigned long)i];
    self.editor.string = text;
    [self.editor.layoutManager
        ensureLayoutForTextContainer:self.editor.textContainer];

    // The caret near the end, and no scrolling of its own yet.
    NSRange far = [text rangeOfString:@"riga 50"];
    self.editor.selectedRange = NSMakeRange(far.location, 0);
    self.editor.typewriterEnabled = YES;

    NSClipView *clip = self.scroll.contentView;
    NSRange glyphs = [self.editor.layoutManager
        glyphRangeForCharacterRange:NSMakeRange(far.location, 1)
               actualCharacterRange:NULL];
    NSRect line = [self.editor.layoutManager
        lineFragmentRectForGlyphAtIndex:glyphs.location effectiveRange:NULL];

    // Where the line ended up on the screen, as a fraction of the window.
    CGFloat onScreen = NSMinY(line) + self.editor.textContainerInset.height
        - NSMinY(clip.bounds);
    CGFloat fraction = onScreen / NSHeight(clip.bounds);
    XCTAssertEqualWithAccuracy(fraction, 0.42, 0.12,
        @"la riga scritta è finita al %g%% della finestra", fraction * 100.0);
}

- (void)testItDoesNotScrollWhenItIsOff
{
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < 60; i++)
        [text appendFormat:@"riga %lu\n", (unsigned long)i];
    self.editor.string = text;
    [self.editor.layoutManager
        ensureLayoutForTextContainer:self.editor.textContainer];

    CGFloat before = NSMinY(self.scroll.contentView.bounds);
    self.editor.selectedRange = NSMakeRange(
        [text rangeOfString:@"riga 50"].location, 0);
    [self.editor updateWritingAids];
    XCTAssertEqualWithAccuracy(NSMinY(self.scroll.contentView.bounds),
                               before, 0.5);
}

@end
