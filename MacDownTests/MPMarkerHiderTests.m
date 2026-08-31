//
//  MPMarkerHiderTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPMarkerHider.h"
#import "pmh_parser.h"

@interface MPMarkerHiderTests : XCTestCase
@property (strong, nonatomic) NSTextView *textView;
@property (strong, nonatomic) MPMarkerHider *hider;
@end

@implementation MPMarkerHiderTests

/** A hider over `text`, parsed and ready to be asked about.
 *
 * ASCII only in these tests: the parser counts bytes and the index set
 * counts UTF-16 units, and the two agree just as long as nothing here is
 * outside ASCII. Keeping to it means the offsets in the assertions are the
 * ones anybody can count off the string.
 */
- (void)load:(NSString *)text
{
    self.textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
    self.textView.string = text;
    self.hider = [[MPMarkerHider alloc] initWithTextView:self.textView];
    self.hider.enabled = YES;

    pmh_element **elements = NULL;
    pmh_markdown_to_elements((char *)text.UTF8String, 0, &elements);
    pmh_sort_elements_by_pos(elements);
    [self.hider updateWithElements:elements];
    pmh_free_elements(elements);
}

/// Puts the caret where a click or an arrow key would leave it.
- (void)caretAt:(NSUInteger)index
{
    self.textView.selectedRange = NSMakeRange(index, 0);
    [self.hider selectionDidChange];
}

- (void)assertHidden:(BOOL)hidden at:(NSArray<NSNumber *> *)indexes
{
    for (NSNumber *index in indexes)
    {
        XCTAssertEqual([self.hider
                           isHiddenMarkerAtIndex:index.unsignedIntegerValue],
                       hidden, @"indice %@", index);
    }
}


//  0:x 1:  2:_ 3:p 4:i 5:p 6:p 7:o 8:_ 9:  10:y
static NSString *const kEmphasis = @"x _pippo_ y";

- (void)testTheMarkersAreHiddenWithTheCaretAway
{
    [self load:kEmphasis];
    [self caretAt:0];
    [self assertHidden:YES at:@[@2, @8]];
}

/** The report this was written for.
 *
 * The underscores take no width, so index 2 is where the caret goes when
 * someone clicks at the front of the word — and there it has to show them.
 */
- (void)testTheFrontEdgeCountsAsBeingInIt
{
    [self load:kEmphasis];
    [self caretAt:2];
    [self assertHidden:NO at:@[@2, @8]];
}

- (void)testTheBackEdgeCountsAsBeingInIt
{
    [self load:kEmphasis];
    [self caretAt:9];       // Right after the closing underscore.
    [self assertHidden:NO at:@[@2, @8]];
}

- (void)testInsideTheWordTheyAreStillShown
{
    [self load:kEmphasis];
    [self caretAt:5];
    [self assertHidden:NO at:@[@2, @8]];
}

- (void)testOnePastTheEdgeTheyGoAway
{
    [self load:kEmphasis];
    [self caretAt:10];
    [self assertHidden:YES at:@[@2, @8]];
    [self caretAt:1];
    [self assertHidden:YES at:@[@2, @8]];
}

/// A construct at the very start of the document has nowhere further left.
- (void)testAConstructAtTheStartOfTheDocument
{
    //  **grassetto** dopo — asterischi in 0, 1, 11, 12; lo spazio in 13 è
    //  la fine del costrutto e conta ancora come dentro.
    [self load:@"**grassetto** dopo"];
    [self caretAt:0];
    [self assertHidden:NO at:@[@0, @1, @11, @12]];
    [self caretAt:14];
    [self assertHidden:YES at:@[@0, @1, @11, @12]];
}

/// A selection that covers part of it shows all of it.
- (void)testASelectionOverTheWord
{
    [self load:kEmphasis];
    self.textView.selectedRange = NSMakeRange(3, 5);    // pippo
    [self.hider selectionDidChange];
    [self assertHidden:NO at:@[@2, @8]];
}

/** With a marker drawn, backspace over it is ordinary editing.
 *
 * The editor asks this before taking a whole construct away, so a visible
 * underscore can be deleted on its own — which is the point of showing it.
 */
- (void)testAVisibleMarkerIsNotTreatedAsAWholeConstruct
{
    [self load:kEmphasis];
    NSRange construct = NSMakeRange(NSNotFound, 0);
    NSRange content = NSMakeRange(NSNotFound, 0);

    [self caretAt:0];
    XCTAssertTrue([self.hider construct:&construct content:&content
                  coveringMarkerAtIndex:8], @"nascosto: il costrutto intero");
    XCTAssertEqual(construct.location, (NSUInteger)2);
    XCTAssertEqual(construct.length, (NSUInteger)7);
    XCTAssertEqualObjects([kEmphasis substringWithRange:content], @"pippo");

    [self caretAt:9];
    XCTAssertFalse([self.hider construct:&construct content:&content
                   coveringMarkerAtIndex:8], @"visibile: testo come un altro");
}

/// Nothing is hidden while the feature is off.
- (void)testDisabledHidesNothing
{
    [self load:kEmphasis];
    self.hider.enabled = NO;
    [self caretAt:0];
    [self assertHidden:NO at:@[@2, @8]];
}

@end
