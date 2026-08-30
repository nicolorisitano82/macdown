//
//  MPTableSourceTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPTableSource.h"

@interface MPTableSourceTests : XCTestCase
@end

@implementation MPTableSourceTests

static NSString *const kTable =
    @"prima\n"
    @"\n"
    @"| Trimestre | Ricavi |\n"
    @"|---|---:|\n"
    @"| Q1 | 12400 |\n"
    @"| Q2 | 15900 |\n"
    @"\n"
    @"dopo\n";

/// The whole document with one edit applied, which is how the view uses this.
- (NSString *)apply:(NSString *)replacement to:(MPTableSource *)table
                 in:(NSString *)text
{
    NSMutableString *out = [text mutableCopy];
    [out replaceCharactersInRange:table.range withString:replacement];
    return out;
}

- (MPTableSource *)tableAtWord:(NSString *)word in:(NSString *)text
{
    NSRange found = [text rangeOfString:word];
    XCTAssertNotEqual(found.location, NSNotFound, @"%@ non c'è", word);
    return [MPTableSource tableCoveringIndex:found.location inText:text];
}


#pragma mark - Reading

- (void)testFindsTheTableAndItsShape
{
    MPTableSource *t = [self tableAtWord:@"Q1" in:kTable];
    XCTAssertNotNil(t);
    XCTAssertEqual(t.rowCount, (NSUInteger)4);      // header, separator, two
    XCTAssertEqual(t.columnCount, (NSUInteger)2);
    XCTAssertEqual(t.separatorRow, (NSUInteger)1);
    XCTAssertFalse(t.separatorIsBroken);

    // The range covers the table and nothing around it.
    NSString *block = [kTable substringWithRange:t.range];
    XCTAssertTrue([block hasPrefix:@"| Trimestre"]);
    XCTAssertTrue([block hasSuffix:@"15900 |"]);
}

- (void)testLocatesRowsAndColumns
{
    MPTableSource *t = [self tableAtWord:@"Q1" in:kTable];
    XCTAssertEqual([t rowContainingIndex:[kTable rangeOfString:@"Q1"].location],
                   (NSUInteger)2);
    XCTAssertEqual([t columnContainingIndex:
        [kTable rangeOfString:@"Q1"].location], (NSUInteger)0);
    XCTAssertEqual([t columnContainingIndex:
        [kTable rangeOfString:@"12400"].location], (NSUInteger)1);
    XCTAssertEqual([t alignmentOfColumn:1], MPTableAlignmentRight);
    XCTAssertEqual([t alignmentOfColumn:0], MPTableAlignmentNone);
}

- (void)testTextWithNoBarsIsNotATable
{
    XCTAssertNil([MPTableSource tableCoveringIndex:2 inText:@"solo prosa\n"]);
}


#pragma mark - Editing

- (void)testInsertsARowWhereAsked
{
    MPTableSource *t = [self tableAtWord:@"Q1" in:kTable];
    NSUInteger caret = 0;
    NSString *out = [self apply:[t textByInsertingRowAt:3 caret:&caret]
                             to:t in:kTable];
    NSArray<NSString *> *lines = [out componentsSeparatedByString:@"\n"];
    XCTAssertTrue([lines[4] hasPrefix:@"| Q1"]);
    XCTAssertTrue([lines[6] hasPrefix:@"| Q2"]);

    // The new line between them: two cells, both empty. Asserted on its
    // shape rather than its spacing, which is the serialiser's business and
    // would make this test break for the wrong reason.
    MPTableSource *after = [self tableAtWord:@"Q1" in:out];
    XCTAssertEqual(after.rowCount, (NSUInteger)5);
    NSString *blank = [lines[5] stringByReplacingOccurrencesOfString:@" "
                                                          withString:@""];
    XCTAssertEqualObjects(blank, @"|||");
}

/// A row asked for above the header would become the header, so it goes below.
- (void)testARowIsNeverInsertedAboveTheHeader
{
    MPTableSource *t = [self tableAtWord:@"Trimestre" in:kTable];
    NSUInteger caret = 0;
    NSString *out = [self apply:[t textByInsertingRowAt:0 caret:&caret]
                             to:t in:kTable];
    NSArray<NSString *> *lines = [out componentsSeparatedByString:@"\n"];
    XCTAssertTrue([lines[2] hasPrefix:@"| Trimestre"], @"intestazione intatta");
    XCTAssertTrue([lines[3] hasPrefix:@"| ---"], @"separatore subito sotto");
}

- (void)testDeletesARowButNotTheSeparator
{
    MPTableSource *t = [self tableAtWord:@"Q1" in:kTable];
    NSUInteger caret = 0;
    NSString *out = [self apply:[t textByDeletingRow:2 caret:&caret]
                             to:t in:kTable];
    XCTAssertEqual([out rangeOfString:@"Q1"].location, (NSUInteger)NSNotFound);
    XCTAssertNotEqual([out rangeOfString:@"Q2"].location,
                      (NSUInteger)NSNotFound);

    MPTableSource *again = [self tableAtWord:@"Q1" in:kTable];
    XCTAssertNil([again textByDeletingRow:again.separatorRow caret:&caret]);
}

- (void)testInsertsAndDeletesAColumn
{
    MPTableSource *t = [self tableAtWord:@"Q1" in:kTable];
    NSUInteger caret = 0;
    NSString *widened = [self apply:[t textByInsertingColumnAt:1 caret:&caret]
                                 to:t in:kTable];
    MPTableSource *w = [self tableAtWord:@"Q1" in:widened];
    XCTAssertEqual(w.columnCount, (NSUInteger)3);
    XCTAssertEqual([w alignmentOfColumn:2], MPTableAlignmentRight,
                   @"l'allineamento resta con la sua colonna");

    NSString *narrowed = [self apply:[w textByDeletingColumn:0 caret:&caret]
                                  to:w in:widened];
    MPTableSource *n = [self tableAtWord:@"12400" in:narrowed];
    XCTAssertEqual(n.columnCount, (NSUInteger)2);
    XCTAssertEqual([narrowed rangeOfString:@"Trimestre"].location,
                   (NSUInteger)NSNotFound);
}

- (void)testTheLastColumnCannotBeDeleted
{
    NSString *one = @"| solo |\n|---|\n| a |\n";
    MPTableSource *t = [self tableAtWord:@"solo" in:one];
    NSUInteger caret = 0;
    XCTAssertNil([t textByDeletingColumn:0 caret:&caret]);
}

- (void)testSetsTheAlignment
{
    MPTableSource *t = [self tableAtWord:@"Q1" in:kTable];
    NSUInteger caret = 0;
    NSString *out = [self apply:
        [t textBySettingAlignment:MPTableAlignmentCenter forColumn:0
                            caret:&caret] to:t in:kTable];
    MPTableSource *after = [self tableAtWord:@"Q1" in:out];
    XCTAssertEqual([after alignmentOfColumn:0], MPTableAlignmentCenter);
    XCTAssertEqual([after alignmentOfColumn:1], MPTableAlignmentRight);
}


#pragma mark - Repairs

- (void)testAddsTheSeparatorRowATableIsMissing
{
    NSString *without = @"| a | b |\n| 1 | 2 |\n";
    MPTableSource *t = [self tableAtWord:@"a" in:without];
    XCTAssertEqual(t.separatorRow, (NSUInteger)NSNotFound);

    NSUInteger caret = 0;
    NSString *out = [self apply:[t textByAddingSeparatorRowWithCaret:&caret]
                             to:t in:without];
    MPTableSource *after = [self tableAtWord:@"a" in:out];
    XCTAssertEqual(after.separatorRow, (NSUInteger)1);
    XCTAssertEqual(after.rowCount, (NSUInteger)3);
    XCTAssertFalse(after.separatorIsBroken);
}

/// The em dash that a substitution leaves behind, which stops it being a table.
- (void)testRepairsASeparatorRowOfEmDashes
{
    NSString *broken = @"| a | b |\n|—|—|\n| 1 | 2 |\n";
    MPTableSource *t = [self tableAtWord:@"a" in:broken];
    XCTAssertEqual(t.separatorRow, (NSUInteger)1);
    XCTAssertTrue(t.separatorIsBroken);

    NSUInteger caret = 0;
    NSString *out = [self apply:[t textByRepairingSeparatorRowWithCaret:&caret]
                             to:t in:broken];
    XCTAssertEqual([out rangeOfString:@"—"].location,
                   (NSUInteger)NSNotFound, @"nessun trattino lungo rimasto");

    MPTableSource *after = [self tableAtWord:@"a" in:out];
    XCTAssertFalse(after.separatorIsBroken);
    XCTAssertEqual(after.rowCount, (NSUInteger)3, @"nessuna riga in più");
}

/// Any edit re-emits the separator row, so any edit repairs it.
- (void)testAnEditAlsoRepairsABrokenSeparator
{
    NSString *broken = @"| a | b |\n|—|—|\n| 1 | 2 |\n";
    MPTableSource *t = [self tableAtWord:@"1" in:broken];
    NSUInteger caret = 0;
    NSString *out = [self apply:[t textByInsertingRowAt:3 caret:&caret]
                             to:t in:broken];
    XCTAssertEqual([out rangeOfString:@"—"].location,
                   (NSUInteger)NSNotFound);
}

/// Escaped bars are content, not cell boundaries.
- (void)testAnEscapedBarDoesNotSplitACell
{
    NSString *text = @"| a | b\\|c |\n|---|---|\n| 1 | 2 |\n";
    MPTableSource *t = [self tableAtWord:@"b" in:text];
    XCTAssertEqual(t.columnCount, (NSUInteger)2);
}

@end
