//
//  MPTaskListTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPTaskList.h"


@interface MPTaskListTests : XCTestCase
@end


@implementation MPTaskListTests

/// The text with the list at `index` reordered, or nil when nothing moves.
- (NSString *)sorted:(NSString *)text at:(NSUInteger)index
{
    NSRange replaced = NSMakeRange(NSNotFound, 0);
    NSString *out = MPTasksMovedToEnd(text, index, &replaced);
    if (!out)
        return nil;
    XCTAssertNotEqual(replaced.location, (NSUInteger)NSNotFound);
    return [text stringByReplacingCharactersInRange:replaced withString:out];
}

- (void)testWhatIsATaskItem
{
    BOOL done = NO;
    XCTAssertTrue(MPLineIsTaskItem(@"- [ ] da fare", &done));
    XCTAssertFalse(done);
    XCTAssertTrue(MPLineIsTaskItem(@"* [x] fatto", &done));
    XCTAssertTrue(done);
    // Either case, which is what this editor's parser accepts too.
    XCTAssertTrue(MPLineIsTaskItem(@"  + [X] fatto", &done));
    XCTAssertTrue(done);

    XCTAssertFalse(MPLineIsTaskItem(@"- una voce normale", NULL));
    XCTAssertFalse(MPLineIsTaskItem(@"[ ] senza trattino", NULL));
    XCTAssertFalse(MPLineIsTaskItem(@"testo", NULL));
}

- (void)testTheFinishedOnesGoLast
{
    NSString *text =
        @"# Collaudo\n"
        @"\n"
        @"- [x] preparare l'ambiente\n"
        @"- [ ] provare la stampa\n"
        @"- [x] verificare i log\n"
        @"- [ ] firmare il verbale\n";

    // With the caret anywhere in the list.
    NSString *sorted = [self sorted:text at:[text rangeOfString:@"provare"].location];
    XCTAssertEqualObjects(sorted,
        @"# Collaudo\n"
        @"\n"
        @"- [ ] provare la stampa\n"
        @"- [ ] firmare il verbale\n"
        @"- [x] preparare l'ambiente\n"
        @"- [x] verificare i log\n");
}

- (void)testTheOrderWithinEachHalfIsKept
{
    NSString *text =
        @"- [x] prima fatta\n"
        @"- [ ] prima da fare\n"
        @"- [x] seconda fatta\n"
        @"- [ ] seconda da fare\n";
    XCTAssertEqualObjects([self sorted:text at:0],
        @"- [ ] prima da fare\n"
        @"- [ ] seconda da fare\n"
        @"- [x] prima fatta\n"
        @"- [x] seconda fatta\n");
}

- (void)testAnItemTakesWhatHangsUnderItWithIt
{
    NSString *text =
        @"- [x] fatta, con una nota\n"
        @"      la nota, che è parte della voce\n"
        @"  - [ ] e una figlia da fare\n"
        @"- [ ] da fare\n";
    // The done parent goes last, and its continuation and its child go
    // with it: they are part of what it says.
    XCTAssertEqualObjects([self sorted:text at:0],
        @"- [ ] da fare\n"
        @"- [x] fatta, con una nota\n"
        @"      la nota, che è parte della voce\n"
        @"  - [ ] e una figlia da fare\n");
}

- (void)testWhenThereIsNothingToDo
{
    // Already in that order.
    XCTAssertNil([self sorted:@"- [ ] a\n- [ ] b\n- [x] c\n" at:0]);
    // All finished, or none.
    XCTAssertNil([self sorted:@"- [x] a\n- [x] b\n" at:0]);
    XCTAssertNil([self sorted:@"- [ ] a\n- [ ] b\n" at:0]);
    // One item is not a list to reorder.
    XCTAssertNil([self sorted:@"- [x] sola\n" at:0]);
    // No list at the caret at all.
    XCTAssertNil([self sorted:@"# Titolo\n\ntesto\n" at:2]);
    XCTAssertNil([self sorted:@"" at:0]);
}

- (void)testOnlyTheListTheCaretIsIn
{
    NSString *text =
        @"- [x] prima lista, fatta\n"
        @"- [ ] prima lista, da fare\n"
        @"\n"
        @"Testo fra le due.\n"
        @"\n"
        @"- [x] seconda lista, fatta\n"
        @"- [ ] seconda lista, da fare\n";

    // The caret in the second list: the first is left exactly as it was.
    NSString *sorted = [self sorted:text
        at:[text rangeOfString:@"seconda lista, da fare"].location];
    XCTAssertTrue([sorted hasPrefix:
        @"- [x] prima lista, fatta\n- [ ] prima lista, da fare\n"]);
    XCTAssertTrue([sorted hasSuffix:
        @"- [ ] seconda lista, da fare\n- [x] seconda lista, fatta\n"]);
}

- (void)testTheRangeItStandsInForIsJustTheList
{
    NSString *text = @"prima\n\n- [x] a\n- [ ] b\n\ndopo\n";
    NSRange replaced = NSMakeRange(NSNotFound, 0);
    NSString *out = MPTasksMovedToEnd(text, [text rangeOfString:@"[x]"].location,
                                      &replaced);
    XCTAssertNotNil(out);
    XCTAssertEqualObjects([text substringWithRange:replaced],
                          @"- [x] a\n- [ ] b");
    XCTAssertEqualObjects(out, @"- [ ] b\n- [x] a");
}

@end
