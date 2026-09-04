//
//  MPSectionFolderTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPSectionFolder.h"
#import "MPMarkerHider.h"


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
