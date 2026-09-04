//
//  MPSectionFolderTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPSectionFolder.h"
#import "MPMarkerHider.h"
#import "MPEditorView.h"
#import "MPDocument.h"


/// Private, and what the editor is handed when a document is loaded.
@interface MPDocument (Testing)
@property (strong) MPSectionFolder *sectionFolder;
@property (unsafe_unretained) NSTextView *editor;
@end


/// Private, and the record of where a click would land.
@interface MPEditorView (Testing)
@property (strong, nonatomic) NSMutableArray *foldMarks;
@end


@interface MPSectionFolderTests : XCTestCase
@property (strong) MPSectionFolder *folder;
@end


@implementation MPSectionFolderTests

- (void)setUp
{
    [super setUp];
    self.folder = [[MPSectionFolder alloc] init];
}

/// The titles of the sections found, in order.
- (NSArray *)titles
{
    NSMutableArray *titles = [NSMutableArray array];
    for (MPSection *section in self.folder.sections)
        [titles addObject:section.title];
    return titles;
}

- (MPSection *)sectionNamed:(NSString *)title
{
    for (MPSection *section in self.folder.sections)
    {
        if ([section.title isEqualToString:title])
            return section;
    }
    return nil;
}


#pragma mark - Reading the headings

- (void)testTheHeadingsAndWhatHangsUnderThem
{
    NSString *text =
        @"# Verbale\n"          // 0
        @"\n"
        @"Premessa.\n"
        @"\n"
        @"## Collaudo\n"
        @"\n"
        @"Prima prova.\n"
        @"Seconda prova.\n"
        @"\n"
        @"## Esito\n"
        @"\n"
        @"Positivo.\n";
    [self.folder updateWithText:text];

    XCTAssertEqualObjects([self titles],
                          (@[@"Verbale", @"Collaudo", @"Esito"]));

    // A section runs to the next heading that is not under it, so the
    // first one holds the other two.
    MPSection *verbale = [self sectionNamed:@"Verbale"];
    XCTAssertEqual(verbale.level, 1u);
    XCTAssertEqualObjects([text substringWithRange:verbale.headingRange],
                          @"# Verbale");
    XCTAssertTrue([[text substringWithRange:verbale.bodyRange]
        containsString:@"## Esito"]);

    MPSection *collaudo = [self sectionNamed:@"Collaudo"];
    XCTAssertEqual(collaudo.level, 2u);
    XCTAssertEqualObjects([text substringWithRange:collaudo.bodyRange],
                          @"\nPrima prova.\nSeconda prova.\n\n");
    // What a folded heading says about itself: lines with something on them.
    XCTAssertEqual(collaudo.bodyLines, 2u);
}

- (void)testWhatIsNotAHeading
{
    NSString *text =
        @"# Vero\n"
        @"\n"
        @"#hashtag non è un titolo\n"
        @"\n"
        @"```sh\n"
        @"# nemmeno questo, è un commento\n"
        @"```\n"
        @"\n"
        @"####### sette cancelletti non sono un titolo\n";
    [self.folder updateWithText:text];
    XCTAssertEqualObjects([self titles], @[@"Vero"]);
}

- (void)testASectionWithNothingUnderItFoldsNothing
{
    [self.folder updateWithText:@"# Uno\n## Due\n"];
    MPSection *uno = [self sectionNamed:@"Uno"];
    MPSection *due = [self sectionNamed:@"Due"];

    // "Uno" holds the line of "Due"; "Due" holds nothing at all.
    XCTAssertTrue([self.folder fold:uno]);
    XCTAssertFalse([self.folder fold:due]);
    XCTAssertEqual(due.bodyLines, 0u);
}


#pragma mark - Folding

- (void)testFoldingHidesTheBodyAndNotTheHeading
{
    NSString *text = @"# Verbale\n\nPremessa.\n\n## Collaudo\n\nEsito.\n";
    [self.folder updateWithText:text];

    MPSection *collaudo = [self sectionNamed:@"Collaudo"];
    XCTAssertTrue([self.folder fold:collaudo]);
    XCTAssertTrue([self.folder isFolded:collaudo]);

    // The heading stays drawn; what is under it does not.
    XCTAssertFalse([self.folder
        isHiddenIndex:collaudo.headingRange.location]);
    XCTAssertTrue([self.folder isHiddenIndex:collaudo.bodyRange.location]);
    XCTAssertEqual(self.folder.hiddenIndexes.count,
                   collaudo.bodyRange.length);
    XCTAssertEqualObjects(self.folder.foldedSections, @[collaudo]);

    XCTAssertTrue([self.folder unfold:collaudo]);
    XCTAssertEqual(self.folder.hiddenIndexes.count, 0u);
}

- (void)testAFoldSurvivesTheDocumentBeingWrittenInAboveIt
{
    [self.folder updateWithText:@"# Uno\n\nA.\n\n## Due\n\nB.\n"];
    XCTAssertTrue([self.folder fold:[self sectionNamed:@"Due"]]);

    // Two lines added at the top: every range has moved.
    [self.folder updateWithText:@"# Zero\n\nX.\n\n# Uno\n\nA.\n\n## Due\n\nB.\n"];
    MPSection *due = [self sectionNamed:@"Due"];
    XCTAssertTrue([self.folder isFolded:due],
                  @"la piega non ha seguito il titolo");
    XCTAssertTrue([self.folder isHiddenIndex:due.bodyRange.location]);

    // Renamed, and the fold does not follow a heading that is not there.
    [self.folder updateWithText:@"# Uno\n\nA.\n\n## Tre\n\nB.\n"];
    XCTAssertFalse([self.folder isFolded:[self sectionNamed:@"Tre"]]);
    XCTAssertEqual(self.folder.hiddenIndexes.count, 0u);
}

- (void)testFoldingAllOfItAndOpeningAllOfIt
{
    [self.folder updateWithText:@"# Uno\n\nA.\n\n# Due\n\nB.\n\n# Tre\n\nC.\n"];
    XCTAssertTrue([self.folder foldAll]);
    XCTAssertEqual(self.folder.foldedSections.count, 3u);
    XCTAssertFalse([self.folder foldAll], @"la seconda volta non cambia niente");

    XCTAssertTrue([self.folder unfoldAll]);
    XCTAssertEqual(self.folder.hiddenIndexes.count, 0u);
    XCTAssertFalse([self.folder unfoldAll]);
}

- (void)testTheSelectionIsNeverLeftInTheDark
{
    NSString *text = @"# Uno\n\nA.\n\n## Due\n\nB.\n";
    [self.folder updateWithText:text];
    MPSection *uno = [self sectionNamed:@"Uno"];
    MPSection *due = [self sectionNamed:@"Due"];
    [self.folder fold:uno];
    [self.folder fold:due];

    // Reaching into the inner one opens both: opening a section inside a
    // folded parent would show nothing.
    XCTAssertTrue([self.folder
        revealRange:NSMakeRange(due.bodyRange.location, 1)]);
    XCTAssertFalse([self.folder isFolded:due]);
    XCTAssertFalse([self.folder isFolded:uno]);

    // And nothing to do when the selection is in plain sight.
    XCTAssertFalse([self.folder revealRange:NSMakeRange(0, 1)]);
}

- (void)testWithThePreferenceOffNothingFolds
{
    [self.folder updateWithText:@"# Uno\n\nA.\n"];
    self.folder.enabled = NO;

    XCTAssertFalse([self.folder fold:[self sectionNamed:@"Uno"]]);
    XCTAssertFalse([self.folder foldAll]);
    XCTAssertEqual(self.folder.hiddenIndexes.count, 0u);

    // And what was folded before it was switched off is shown again.
    self.folder.enabled = YES;
    XCTAssertTrue([self.folder fold:[self sectionNamed:@"Uno"]]);
    XCTAssertGreaterThan(self.folder.hiddenIndexes.count, 0u);
    self.folder.enabled = NO;
    XCTAssertEqual(self.folder.hiddenIndexes.count, 0u);
}

/** A folded section has to take no room, not merely draw nothing.
 *
 * Suppressed glyphs keep their place in the text; whether the line
 * fragments they were on collapse is a TextKit question, and the answer
 * decides whether folding works at all or leaves a hole of empty lines.
 * Measured, because it cannot be reasoned about.
 */
- (void)testAFoldedSectionTakesNoRoom
{
    NSString *text =
        @"# Uno\n\nA.\n\n## Due\n\nB.\nC.\nD.\nE.\nF.\n";
    NSTextView *view = [[NSTextView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 600.0, 400.0)];
    view.string = text;

    MPMarkerHider *hider = [[MPMarkerHider alloc] initWithTextView:view];
    [self.folder updateWithText:text];

    // Asked for before it is measured: an untouched layout manager has laid
    // nothing out, and the height of nothing is zero.
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    CGFloat before = NSHeight([view.layoutManager
        usedRectForTextContainer:view.textContainer]);
    XCTAssertGreaterThan(before, 0.0);

    MPSection *due = [self sectionNamed:@"Due"];
    XCTAssertTrue([self.folder fold:due]);
    hider.foldedIndexes = self.folder.hiddenIndexes;
    [view.layoutManager invalidateGlyphsForCharacterRange:
        NSMakeRange(0, text.length) changeInLength:0
                                     actualCharacterRange:NULL];
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];

    CGFloat after = NSHeight([view.layoutManager
        usedRectForTextContainer:view.textContainer]);
    // Five lines of body gone: the text has to be shorter by about that
    // much, not by nothing.
    XCTAssertLessThan(after, before * 0.7,
        @"piegando cinque righe l'altezza è passata da %g a %g", before, after);

    hider.foldedIndexes = nil;
    [view.layoutManager invalidateGlyphsForCharacterRange:
        NSMakeRange(0, text.length) changeInLength:0
                                     actualCharacterRange:NULL];
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    XCTAssertEqualWithAccuracy(NSHeight([view.layoutManager
        usedRectForTextContainer:view.textContainer]), before, 0.5);
}

/** The triangles are drawn, and something can be clicked.
 *
 * A shortcut nobody has been told about is not a feature, so every heading
 * with something under it gets a triangle in the margin. Counted rather
 * than looked at: the drawing pass is the only thing that knows where a
 * heading ended, and it is also the only place a click can be aimed at.
 */
- (void)testEveryFoldableHeadingGetsSomethingToClick
{
    NSString *text =
        @"# Uno\n\nA.\n\n## Due\n\nB.\n\n## Vuota\n";
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 600.0, 400.0)];
    view.string = text;
    view.textContainerInset = NSMakeSize(24.0, 10.0);

    [self.folder updateWithText:text];
    view.sectionFolder = self.folder;
    XCTAssertEqual(self.folder.sections.count, 3u);

    NSBitmapImageRep *canvas =
        [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];

    // "Uno" and "Due" have something under them; "Vuota" is the last
    // heading with nothing after it, and folding it would hide nothing.
    XCTAssertEqual(view.foldMarks.count, 2u);
    for (NSDictionary *mark in view.foldMarks)
    {
        XCTAssertTrue([mark[@"toggles"] boolValue],
                      @"un triangolo va in entrambi i versi");
        NSRect rect = [mark[@"rect"] rectValue];
        XCTAssertGreaterThan(NSWidth(rect), 10.0, @"troppo piccolo da colpire");
        XCTAssertTrue(NSMinX(rect) < 24.0,
                      @"il triangolo deve stare nel margine, non nel testo");
    }

    // Folded, and the count appears beside the heading as a second thing
    // to click.
    [self.folder fold:[self sectionNamed:@"Due"]];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];
    XCTAssertEqual(view.foldMarks.count, 3u);

    // With the preference off there is nothing in the margin at all.
    self.folder.enabled = NO;
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];
    XCTAssertEqual(view.foldMarks.count, 0u);
}

/** A real document finds its headings, which is where this went wrong.
 *
 * Everything above tests the folder; nothing tested that a document ever
 * hands it any text. It did not — the update hung off the syntax parse's
 * callback, which belongs to the highlighter, so with highlighting off the
 * margin stayed empty for ever. The text changing is the one thing that
 * always happens, and that is what feeds it now.
 */
- (void)testADocumentFindsItsOwnHeadings
{
    NSError *error = nil;
    MPDocument *document = [[NSDocumentController sharedDocumentController]
        openUntitledDocumentAndDisplay:YES error:&error];
    XCTAssertNotNil(document, @"%@", error);

    document.markdown = @"# Verbale\n\nPremessa.\n\n## Collaudo\n\nEsito.\n";

    MPSectionFolder *folder = document.sectionFolder;
    XCTAssertNotNil(folder, @"il documento non ha una piegatura");
    XCTAssertEqual(folder.sections.count, 2u,
                   @"il documento non ha letto i suoi titoli");
    XCTAssertTrue(folder.enabled, @"la preferenza è attiva di suo");

    // And the editor draws them: the closest thing to looking at it.
    MPEditorView *editor = (MPEditorView *)document.editor;
    XCTAssertNotNil(editor);
    XCTAssertEqualObjects(editor.sectionFolder, folder,
                          @"l'editor non conosce la piegatura del documento");
    NSBitmapImageRep *canvas =
        [editor bitmapImageRepForCachingDisplayInRect:editor.bounds];
    [editor cacheDisplayInRect:editor.bounds toBitmapImageRep:canvas];
    XCTAssertEqual(editor.foldMarks.count, 2u,
                   @"niente da cliccare nel margine (inset %g)",
                   editor.textContainerInset.width);

    [document close];
}

/** A document opened from a file finds its headings too.
 *
 * The one that got away. Text arrives two ways — typed, or loaded — and the
 * loading does not go through -setMarkdown:, so hooking that one left every
 * opened document with no sections at all until its first keystroke. The
 * test above passed the whole time, because it set the text the other way.
 */
- (void)testADocumentOpenedFromAFileFindsItsHeadings
{
    NSURL *file = [[[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSUUID UUID].UUIDString]
        URLByAppendingPathExtension:@"md"];
    NSString *text =
        @"# Verbale\n\nPremessa.\n\n## Collaudo\n\nEsito.\n";
    XCTAssertTrue([text writeToURL:file atomically:YES
                          encoding:NSUTF8StringEncoding error:NULL]);

    XCTestExpectation *opened = [self expectationWithDescription:@"aperto"];
    __block MPDocument *document = nil;
    [[NSDocumentController sharedDocumentController]
        openDocumentWithContentsOfURL:file display:YES
                    completionHandler:^(NSDocument *made, BOOL wasOpen,
                                        NSError *error) {
        document = (MPDocument *)made;
        XCTAssertNil(error, @"%@", error);
        [opened fulfill];
    }];
    [self waitForExpectations:@[opened] timeout:20.0];

    // The text is put into the editor after the opening has been reported,
    // so the question is whether the headings are there a moment later —
    // not whether they are there in the same breath.
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while (!document.sectionFolder.sections.count
           && [until timeIntervalSinceNow] > 0.0)
    {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:
            [NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    XCTAssertEqual(document.sectionFolder.sections.count, 2u,
                   @"un documento aperto da file non ha letto i suoi titoli");
    XCTAssertGreaterThan(document.editor.string.length, 0u);

    [document close];
    [[NSFileManager defaultManager] removeItemAtURL:file error:NULL];
}

/** The triangle has to be visible against the editor's own background.
 *
 * Twice it was not: a system label colour is dark when macOS is light, and
 * the editor's theme can be dark at the same time — a dark triangle on a
 * dark margin. Measured against the background it is drawn on, which is
 * the only thing that settles it.
 */
- (void)testTheTriangleStandsOutFromTheBackgroundItIsDrawnOn
{
    NSString *text = @"# Uno\n\nA.\nB.\n";
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 400.0, 200.0)];
    view.string = text;
    view.textContainerInset = NSMakeSize(24.0, 8.0);

    // A dark theme, which is the case that failed: light text on a dark
    // ground while the system may be in either mode.
    NSColor *ground = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
    view.backgroundColor = ground;
    view.textColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];

    [self.folder updateWithText:text];
    view.sectionFolder = self.folder;

    NSBitmapImageRep *canvas =
        [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];
    XCTAssertEqual(view.foldMarks.count, 1u);

    // The brightest pixel where the triangle was drawn, against the
    // background it sits on. Read off the samples: asking a colour for its
    // brightness means knowing its colour space, and bytes do not care.
    // The chevron's own area: the clickable rectangle is padded, and with
    // a wide inset the padding reaches under the heading's first letters —
    // whose ink would answer the question instead of the chevron's.
    NSRect rect = NSInsetRect(
        [view.foldMarks.firstObject[@"rect"] rectValue], 5.0, 5.0);
    const unsigned char *bytes = canvas.bitmapData;
    NSInteger scale = canvas.pixelsWide / (NSInteger)NSWidth(view.bounds);
    unsigned char brightest = 0;
    for (NSInteger y = NSMinY(rect) * scale; y < NSMaxY(rect) * scale; y++)
    {
        for (NSInteger x = NSMinX(rect) * scale; x < NSMaxX(rect) * scale; x++)
        {
            if (x < 0 || y < 0
                    || x >= canvas.pixelsWide || y >= canvas.pixelsHigh)
                continue;
            const unsigned char *pixel =
                bytes + y * canvas.bytesPerRow + x * canvas.samplesPerPixel;
            brightest = MAX(brightest, pixel[0]);
        }
    }

    // The ground is 0.12 white, about 31 of 255. Anything drawn on it has
    // to be plainly lighter than that, and half-strength ink is about 130.
    XCTAssertGreaterThan(brightest, 90,
        @"il triangolo non si distingue dal fondo (max %d su 255)",
        (int)brightest);
}

/** A subsection inside a folded parent gets no mark of its own.
 *
 * Its heading is not on the page — the parent hid it — and its glyphs are
 * suppressed, so asking where they are answers with the line above. Two
 * marks then land on one line, and clicking toggles whichever was drawn
 * second: a section that vanishes and cannot be opened again, which is
 * what was reported.
 */
- (void)testAHiddenHeadingGetsNoMark
{
    NSString *text =
        @"# Uno\n\nA.\n\n## Due\n\nB.\n\n### Tre\n\nC.\n";
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 500.0, 400.0)];
    view.string = text;
    view.textContainerInset = NSMakeSize(24.0, 8.0);

    [self.folder updateWithText:text];
    view.sectionFolder = self.folder;

    NSBitmapImageRep *canvas =
        [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];
    // Three headings, each with something under it.
    XCTAssertEqual(view.foldMarks.count, 3u);

    // Fold the middle one: its subsection's heading goes with it, and so
    // does that subsection's mark.
    XCTAssertTrue([self.folder fold:[self sectionNamed:@"Due"]]);
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];

    // Two chevrons — "Tre" has lost its own, since its heading is inside
    // what "Due" hid — plus the count beside the folded heading.
    NSUInteger chevrons = 0;
    for (NSDictionary *mark in view.foldMarks)
    {
        if ([mark[@"toggles"] boolValue])
            chevrons++;
    }
    XCTAssertEqual(chevrons, 2u, @"la sottosezione nascosta ha ancora un segno");
    XCTAssertEqual(view.foldMarks.count, 3u);

    // And nothing lands on top of anything else, which is what made a
    // click toggle the wrong section.
    for (NSUInteger i = 0; i < view.foldMarks.count; i++)
    {
        for (NSUInteger j = i + 1; j < view.foldMarks.count; j++)
        {
            NSRect a = [view.foldMarks[i][@"rect"] rectValue];
            NSRect b = [view.foldMarks[j][@"rect"] rectValue];
            XCTAssertFalse(NSIntersectsRect(a, b),
                @"segni sovrapposti: %@ e %@",
                NSStringFromRect(a), NSStringFromRect(b));
        }
    }

    // Opening the parent brings the subsection's mark back.
    XCTAssertTrue([self.folder unfold:[self sectionNamed:@"Due"]]);
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];
    XCTAssertEqual(view.foldMarks.count, 3u);
}

/** Whether there is ink at a place inside a rectangle.
 *
 * Given as fractions of it, and sampled over a couple of points, so the
 * answer does not turn on one antialiased pixel.
 */
- (BOOL)inkAt:(NSPoint)fraction
           in:(NSRect)rect
           of:(NSBitmapImageRep *)canvas
{
    return [self inkAt:fraction in:rect of:canvas above:90];
}

- (BOOL)inkAt:(NSPoint)fraction
           in:(NSRect)rect
           of:(NSBitmapImageRep *)canvas
        above:(unsigned char)threshold
{
    NSInteger scale = MAX(1, canvas.pixelsWide / 400);
    const unsigned char *bytes = canvas.bitmapData;
    NSInteger centreX = (NSMinX(rect) + fraction.x * NSWidth(rect)) * scale;
    NSInteger centreY = (NSMinY(rect) + fraction.y * NSHeight(rect)) * scale;

    for (NSInteger y = centreY - 1; y <= centreY + 1; y++)
    {
        for (NSInteger x = centreX - 1; x <= centreX + 1; x++)
        {
            if (x < 0 || y < 0
                    || x >= canvas.pixelsWide || y >= canvas.pixelsHigh)
                continue;
            const unsigned char *pixel =
                bytes + y * canvas.bytesPerRow + x * canvas.samplesPerPixel;
            if (pixel[0] > threshold)
                return YES;
        }
    }
    return NO;
}

/** The chevron points the way it says it does.
 *
 * A text view is flipped — y grows downwards — and drawn the other way
 * round the open chevron came out as a caret pointing up, which is what
 * was on the screen. A rectangle cannot tell the two apart; where the ink
 * is inside it can. Not the centre of the ink either: the middle of a V is
 * the middle of its rectangle, which is what my first attempt measured and
 * why it disagreed with a picture of a perfectly good V.
 *
 * The vertex is the thing: a V has ink at the bottom middle and none at the
 * top middle, and a > has ink at the right middle and none at the left.
 */
- (void)testTheChevronPointsDownWhenOpenAndRightWhenFolded
{
    NSString *text = @"# Uno\n\nA.\nB.\n";
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 400.0, 200.0)];
    view.string = text;
    view.textContainerInset = NSMakeSize(24.0, 8.0);
    view.backgroundColor = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
    view.textColor = [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];

    [self.folder updateWithText:text];
    view.sectionFolder = self.folder;

    NSBitmapImageRep *canvas =
        [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];
    XCTAssertEqual(view.foldMarks.count, 1u);

    // The chevron's own area: the clickable rectangle is padded, and with
    // a wide inset that padding reaches under the heading's first letters,
    // whose ink would answer instead of the chevron's.
    NSRect rect = NSInsetRect(
        [view.foldMarks.firstObject[@"rect"] rectValue], 5.0, 5.0);

    XCTAssertTrue([self inkAt:NSMakePoint(0.5, 0.85) in:rect of:canvas],
                  @"il chevron aperto non ha la punta in basso");
    XCTAssertFalse([self inkAt:NSMakePoint(0.5, 0.1) in:rect of:canvas],
                   @"c'è inchiostro in cima al mezzo: non è una V");

    [self.folder fold:[self sectionNamed:@"Uno"]];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];

    XCTAssertTrue([self inkAt:NSMakePoint(0.85, 0.5) in:rect of:canvas],
                  @"il chevron piegato non ha la punta a destra");
    XCTAssertFalse([self inkAt:NSMakePoint(0.1, 0.5) in:rect of:canvas],
                   @"c'è inchiostro a sinistra al mezzo: non è un >");
}

/// Small, and out of the text: a mark in a margin, not a control.
- (void)testTheMarkIsSmallAndStaysInTheMargin
{
    NSString *text = @"# Uno\n\nA.\n";
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 400.0, 200.0)];
    view.string = text;
    view.textContainerInset = NSMakeSize(15.0, 8.0);

    [self.folder updateWithText:text];
    view.sectionFolder = self.folder;
    NSBitmapImageRep *canvas =
        [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];

    NSRect rect = [view.foldMarks.firstObject[@"rect"] rectValue];
    // The rectangle is the clickable one, ten points of padding around a
    // chevron of eleven at most.
    XCTAssertLessThan(NSWidth(rect) - 10.0, 12.0);
    // Clear of the window's edge, and not over the text.
    XCTAssertGreaterThanOrEqual(NSMinX(rect) + 5.0, 3.0);
    XCTAssertLessThanOrEqual(NSMaxX(rect) - 5.0, 15.0);
}

/** Folding a section takes its subsections with it.
 *
 * Reported as: press on the parent and the child's heading stays on the
 * page. The body of a section runs to the next heading that is not under
 * it, so a subsection's heading is inside it and should go dark with the
 * rest.
 */
- (void)testFoldingASectionHidesTheSubsectionsHeadingToo
{
    NSString *text =
        @"# Uno\n\nA.\n\n## Due\n\nB.\n\n### Tre\n\nC.\n\n## Quattro\n";
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 500.0, 400.0)];
    view.string = text;
    MPMarkerHider *hider = [[MPMarkerHider alloc] initWithTextView:view];

    [self.folder updateWithText:text];
    view.sectionFolder = self.folder;

    MPSection *due = [self sectionNamed:@"Due"];
    MPSection *tre = [self sectionNamed:@"Tre"];
    // The child's heading is inside the parent's body: that is the model.
    XCTAssertTrue(NSLocationInRange(tre.headingRange.location,
                                    due.bodyRange),
                  @"il titolo del figlio non è nel corpo del genitore");

    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    CGFloat before = NSHeight([view.layoutManager
        usedRectForTextContainer:view.textContainer]);

    XCTAssertTrue([self.folder fold:due]);
    XCTAssertTrue([self.folder isHiddenIndex:tre.headingRange.location],
                  @"il titolo del figlio non è fra i caratteri nascosti");

    hider.foldedIndexes = self.folder.hiddenIndexes;
    [view.layoutManager invalidateGlyphsForCharacterRange:
        NSMakeRange(0, text.length) changeInLength:0
                                     actualCharacterRange:NULL];
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];

    // And it is off the page: the glyphs of that heading take no room.
    NSRange glyphs = [view.layoutManager
        glyphRangeForCharacterRange:tre.headingRange
               actualCharacterRange:NULL];
    // One glyph, not the range: a range that ends a line measures as wide
    // as the container whether or not anything is drawn in it.
    NSRect drawn = [view.layoutManager boundingRectForGlyphRange:
        NSMakeRange(glyphs.location, 1) inTextContainer:view.textContainer];
    XCTAssertLessThan(NSWidth(drawn), 1.0,
        @"il titolo del figlio occupa ancora %g punti di larghezza",
        NSWidth(drawn));

    CGFloat after = NSHeight([view.layoutManager
        usedRectForTextContainer:view.textContainer]);
    XCTAssertLessThan(after, before * 0.75,
        @"l'altezza è passata da %g a %g", before, after);
}

/** Standing on a heading means that heading, whatever else ends there.
 *
 * A section's body ends exactly where the next heading begins, so the first
 * character of a heading was claimed twice: by that heading, and by the end
 * of the section above it. At equal level the earlier one won — press the
 * chevron beside one section and the one above it folded.
 */
- (void)testTheFirstCharacterOfAHeadingBelongsToThatHeading
{
    NSString *text =
        @"# Uno\n\nA.\n\n## Due\n\nB.\n\n## Tre\n\nC.\n";
    [self.folder updateWithText:text];

    for (NSString *name in @[@"Due", @"Tre"])
    {
        MPSection *section = [self sectionNamed:name];
        NSUInteger first = section.headingRange.location;
        XCTAssertEqualObjects(
            [self.folder sectionCoveringIndex:first].title, name,
            @"il primo carattere di «%@» è stato attribuito a un'altra "
            @"sezione", name);
        // And the last character of its heading, which is where a caret at
        // the end of the line sits.
        XCTAssertEqualObjects([self.folder sectionCoveringIndex:
            NSMaxRange(section.headingRange) - 1].title, name);
    }

    // A subsection still wins over its parent inside its own body.
    [self.folder updateWithText:
        @"# Uno\n\nA.\n\n## Due\n\nB.\n\n### Tre\n\nC.\n"];
    MPSection *tre = [self sectionNamed:@"Tre"];
    XCTAssertEqualObjects([self.folder
        sectionCoveringIndex:tre.bodyRange.location].title, @"Tre");
}

/** The count does not move when the markers come and go.
 *
 * Placed after the heading's words it jumped sideways every time the caret
 * arrived at the heading, because hiding the hashes shifts the whole line.
 * Next to markers that already appear and disappear on their own, one more
 * thing moving is one thing too many.
 */
- (void)testTheCountStaysPutWhenTheHashesAppear
{
    NSString *text = @"# Uno\n\nA.\nB.\n";
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 400.0, 200.0)];
    view.string = text;
    view.textContainerInset = NSMakeSize(15.0, 8.0);

    MPMarkerHider *hider = [[MPMarkerHider alloc] initWithTextView:view];
    [self.folder updateWithText:text];
    view.sectionFolder = self.folder;
    XCTAssertTrue([self.folder fold:[self sectionNamed:@"Uno"]]);
    hider.foldedIndexes = self.folder.hiddenIndexes;

    NSBitmapImageRep *canvas =
        [view bitmapImageRepForCachingDisplayInRect:view.bounds];

    // Twice: with the heading's hashes drawn, and with them suppressed.
    NSMutableArray *places = [NSMutableArray array];
    for (NSNumber *hides in @[@NO, @YES])
    {
        hider.enabled = hides.boolValue;
        [view.layoutManager invalidateGlyphsForCharacterRange:
            NSMakeRange(0, text.length) changeInLength:0
                                         actualCharacterRange:NULL];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];

        for (NSDictionary *mark in view.foldMarks)
        {
            if ([mark[@"toggles"] boolValue])
                continue;   // the chevron, which lives in the margin
            [places addObject:@(NSMinX([mark[@"rect"] rectValue]))];
        }
    }

    XCTAssertEqual(places.count, 2u, @"il conteggio non è stato disegnato");
    XCTAssertEqualObjects(places.firstObject, places.lastObject,
        @"il conteggio si è spostato di %g punti",
        [places.lastObject doubleValue] - [places.firstObject doubleValue]);
}

/// An idle chevron is drawn too, so nothing appears and disappears.
- (void)testAHeadingWithNothingUnderItStillGetsAChevron
{
    NSString *text = @"# Uno\n\nA.\n\n## Ultima\n";
    MPEditorView *view = [[MPEditorView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, 400.0, 200.0)];
    view.string = text;
    view.textContainerInset = NSMakeSize(15.0, 8.0);
    view.backgroundColor = [NSColor colorWithCalibratedWhite:0.12 alpha:1.0];
    view.textColor = [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];

    [self.folder updateWithText:text];
    view.sectionFolder = self.folder;
    MPSection *last = [self sectionNamed:@"Ultima"];
    XCTAssertEqual(last.bodyRange.length, 0u);

    NSBitmapImageRep *canvas =
        [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:canvas];

    // Only the one that can be folded is clickable…
    XCTAssertEqual(view.foldMarks.count, 1u);

    // …but the idle one is on the page. Its line, its margin, faintly.
    NSRange glyphs = [view.layoutManager
        glyphRangeForCharacterRange:last.headingRange
               actualCharacterRange:NULL];
    NSRect words = [view.layoutManager boundingRectForGlyphRange:
        NSMakeRange(glyphs.location, 1)
        inTextContainer:view.textContainer];
    NSRect margin = NSMakeRect(2.0, NSMinY(words) + 8.0 - 2.0, 13.0,
                               NSHeight(words) + 4.0);
    // Fainter than an active one, so asked for with a lower bar: the
    // ground is 31 of 255 and three tenths of the ink is about 94.
    XCTAssertTrue([self inkAt:NSMakePoint(0.5, 0.5) in:margin of:canvas
                        above:60],
                  @"niente nel margine accanto a un titolo senza corpo");
}

- (void)testTheInnermostSectionIsTheOneAsked
{
    NSString *text = @"# Uno\n\nA.\n\n## Due\n\nB.\n";
    [self.folder updateWithText:text];

    NSRange inner = [self sectionNamed:@"Due"].bodyRange;
    XCTAssertEqualObjects([self.folder sectionCoveringIndex:inner.location]
        .title, @"Due");
    XCTAssertEqualObjects([self.folder sectionCoveringIndex:0].title, @"Uno");
    // Before the first heading there is no section.
    [self.folder updateWithText:@"testo\n\n# Uno\n"];
    XCTAssertNil([self.folder sectionCoveringIndex:0]);
}

@end
