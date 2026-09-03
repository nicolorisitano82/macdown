//
//  MPCodeLanguageTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPCodeLanguages.h"


@interface MPCodeLanguageTests : XCTestCase
@end


@implementation MPCodeLanguageTests

/// The identifiers of a list, in the order the list has them.
- (NSArray *)identifiersOf:(NSArray<MPCodeLanguage *> *)languages
{
    NSMutableArray *found = [NSMutableArray array];
    for (MPCodeLanguage *language in languages)
        [found addObject:language.identifier];
    return found;
}

- (void)testOnlyLanguagesWithAComponentAreOffered
{
    NSDictionary *index = @{
        @"meta": @{@"path": @"components/prism-{id}.min.js"},
        @"python": @{@"title": @"Python"},
        @"abap": @{@"title": @"ABAP"},
        @"toml": @{@"title": @"TOML"},
    };
    NSArray *languages = MPCodeLanguagesFromIndex(
        index, [NSSet setWithArray:@[@"python", @"abap"]], @{});

    // TOML is in the catalogue but not in this build, and `meta` is not a
    // language at all.
    XCTAssertEqualObjects([self identifiersOf:languages],
                          (@[@"python", @"abap"]));
}

- (void)testCommonLanguagesComeFirstAndTheRestByTitle
{
    NSDictionary *index = @{
        @"abap": @"ABAP",
        @"apl": @"APL",
        @"python": @"Python",
        @"bash": @"Bash",
    };
    NSSet *available = [NSSet setWithArray:index.allKeys];
    NSArray *languages = MPCodeLanguagesFromIndex(index, available, @{});

    // Bash and Python are common, so they lead, in title order; ABAP and
    // APL follow, also in title order.
    XCTAssertEqualObjects([self identifiersOf:languages],
                          (@[@"bash", @"python", @"abap", @"apl"]));
}

- (void)testTitleFallsBackToWhatIsWritten
{
    NSArray *languages = MPCodeLanguagesFromIndex(
        @{@"apl": @"APL", @"nim": @{}}, [NSSet setWithArray:@[@"apl", @"nim"]],
        @{});

    NSMutableDictionary *titles = [NSMutableDictionary dictionary];
    for (MPCodeLanguage *language in languages)
        titles[language.identifier] = language.title;
    XCTAssertEqualObjects(titles[@"apl"], @"APL");
    XCTAssertEqualObjects(titles[@"nim"], @"nim");
}

- (void)testAnAliasIsOfferedOnlyWhenNamedAndResolved
{
    NSDictionary *index = @{
        @"markup": @{@"title": @"Markup",
                     @"aliasTitles": @{@"html": @"HTML", @"svg": @"SVG"}},
    };
    // The renderer sends `html` to markup and knows nothing of `svg`, so a
    // fence marked svg would come out grey: it is not offered.
    NSArray *languages = MPCodeLanguagesFromIndex(
        index, [NSSet setWithObject:@"markup"], @{@"html": @"markup"});

    NSMutableDictionary *titles = [NSMutableDictionary dictionary];
    for (MPCodeLanguage *language in languages)
        titles[language.identifier] = language.title;

    XCTAssertEqualObjects([NSSet setWithArray:titles.allKeys],
                          ([NSSet setWithArray:@[@"markup", @"html"]]));
    XCTAssertEqualObjects(titles[@"html"], @"HTML");
}

- (void)testThisBuildOffersWhatItCanHighlight
{
    NSArray *languages = MPAvailableCodeLanguages();
    XCTAssertGreaterThan(languages.count, 100u);

    NSArray *identifiers = [self identifiersOf:languages];
    XCTAssertTrue([identifiers containsObject:@"python"]);
    // HTML through the alias the renderer resolves…
    XCTAssertTrue([identifiers containsObject:@"html"]);
    // …and JSON in its own right, which it was not while the alias map
    // sent it to JavaScript.
    XCTAssertTrue([identifiers containsObject:@"json"]);

    // The first entries are the ones worth reaching first.
    XCTAssertTrue(((MPCodeLanguage *)languages.firstObject).isCommon);
}

/** No alias may take a name away from the component that owns it.
 *
 * `json` was sent to JavaScript by an alias written before Prism had a JSON
 * component, so ```json was coloured as JavaScript for years. The list
 * offers `json` either way — the component is there — so only this catches
 * the alias coming back.
 */
- (void)testNoAliasStealsANameThatHasItsOwnComponent
{
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"syntax_highlighting"
                                         withExtension:@"json"];
    NSDictionary *info = [NSJSONSerialization
        JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0
                     error:NULL];
    NSDictionary *aliases = info[@"aliases"];
    XCTAssertGreaterThan(aliases.count, 0u);

    NSMutableSet *offered = [NSMutableSet set];
    for (MPCodeLanguage *language in MPAvailableCodeLanguages())
        [offered addObject:language.identifier];

    NSArray *files = [[NSBundle mainBundle]
        URLsForResourcesWithExtension:@"js" subdirectory:@"Prism/components"];
    NSMutableSet *components = [NSMutableSet set];
    for (NSURL *file in files)
    {
        NSString *name = file.lastPathComponent;
        if ([name hasPrefix:@"prism-"] && [name hasSuffix:@".min.js"])
        {
            NSUInteger start = @"prism-".length;
            [components addObject:[name substringWithRange:NSMakeRange(start,
                name.length - start - @".min.js".length)]];
        }
    }

    for (NSString *alias in aliases)
    {
        if (![components containsObject:alias])
            continue;
        XCTAssertEqualObjects(aliases[alias], alias,
            @"«%@» ha un componente suo, ma l'alias lo manda a «%@»",
            alias, aliases[alias]);
    }
    XCTAssertTrue([offered containsObject:@"json"]);
}

- (void)testFenceCarriesTheLanguage
{
    XCTAssertEqualObjects(MPTextForFencedCodeBlock(@"python", @"print(1)"),
                          @"```python\nprint(1)\n```");
    XCTAssertEqualObjects(MPTextForFencedCodeBlock(@"", @""), @"```\n\n```");
    XCTAssertEqualObjects(MPTextForFencedCodeBlock(nil, @"x"), @"```\nx\n```");
}

- (void)testFenceIsLongerThanAnythingInsideIt
{
    NSString *body = @"```\ncode\n```";
    NSString *made = MPTextForFencedCodeBlock(@"markdown", body);
    XCTAssertEqualObjects(made, @"````markdown\n```\ncode\n```\n````");

    // And what comes out of it is what went in, fences and all.
    XCTAssertEqualObjects(MPBodyOfFencedCodeBlock(made), body);
}

- (void)testTakingABlockOffAgain
{
    XCTAssertEqualObjects(MPBodyOfFencedCodeBlock(@"```python\nprint(1)\n```"),
                          @"print(1)");
    XCTAssertEqualObjects(MPBodyOfFencedCodeBlock(@"```\nx\n```\n"), @"x");
    XCTAssertEqualObjects(MPBodyOfFencedCodeBlock(@"```\n```"), @"");

    // Not blocks: prose, one line, and a fence that never closes.
    XCTAssertNil(MPBodyOfFencedCodeBlock(@"just some text"));
    XCTAssertNil(MPBodyOfFencedCodeBlock(@"``x``"));
    XCTAssertNil(MPBodyOfFencedCodeBlock(@"```python\nprint(1)\n"));
    XCTAssertNil(MPBodyOfFencedCodeBlock(@"```\ncode\n``"));
}

#pragma mark - Where the fence goes

/// The text as it is after the edit, so the arithmetic is read in full.
- (NSString *)apply:(MPCodeFenceEdit *)edit to:(NSString *)text
{
    return [text stringByReplacingCharactersInRange:edit.replacedRange
                                         withString:edit.replacement];
}

- (void)testAnEmptyDocumentGetsABlockWithTheCaretInIt
{
    MPCodeFenceEdit *edit =
        MPCodeFenceEditForText(@"", NSMakeRange(0, 0), @"python");

    XCTAssertEqualObjects([self apply:edit to:@""], @"```python\n\n```");
    // On the empty line between the fences, ready to be typed on.
    XCTAssertEqual(edit.selectedRange.location, (NSUInteger)10);
    XCTAssertEqual(edit.selectedRange.length, (NSUInteger)0);
    XCTAssertFalse(edit.removesFence);
}

- (void)testPartOfALineTakesTheWholeLine
{
    NSString *text = @"prima\nx = 1\nterza\n";
    // Two characters in the middle of the second line.
    MPCodeFenceEdit *edit =
        MPCodeFenceEditForText(text, NSMakeRange(8, 2), @"python");

    XCTAssertEqualObjects([self apply:edit to:text],
                          @"prima\n```python\nx = 1\n```\nterza\n");
    // Past the block, on the line that follows it.
    XCTAssertEqual(edit.selectedRange.location, (NSUInteger)26);
}

- (void)testSeveralLinesGoInOneBlock
{
    NSString *text = @"uno\ndue\n";
    MPCodeFenceEdit *edit =
        MPCodeFenceEditForText(text, NSMakeRange(0, text.length), @"");

    XCTAssertEqualObjects([self apply:edit to:text],
                          @"```\nuno\ndue\n```\n");
}

- (void)testALineWithoutItsNewlineAtTheEndOfTheDocument
{
    NSString *text = @"prima\nx = 1";
    MPCodeFenceEdit *edit =
        MPCodeFenceEditForText(text, NSMakeRange(11, 0), @"bash");

    XCTAssertEqualObjects([self apply:edit to:text],
                          @"prima\n```bash\nx = 1\n```");
}

- (void)testTheSameCommandTakesTheBlockOffAgain
{
    NSString *text = @"prima\n```python\nx = 1\n```\nterza\n";
    // The block's own lines, fences included: that is what selecting it
    // gives, and what having just made it leaves selected.
    MPCodeFenceEdit *edit =
        MPCodeFenceEditForText(text, NSMakeRange(6, 20), @"python");

    XCTAssertTrue(edit.removesFence);
    XCTAssertEqualObjects([self apply:edit to:text],
                          @"prima\nx = 1\nterza\n");
    // What was in the block stays selected.
    XCTAssertEqual(edit.selectedRange.location, (NSUInteger)6);
    XCTAssertEqual(edit.selectedRange.length, (NSUInteger)5);
}

@end
