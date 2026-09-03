//
//  MPCodeIndenterTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPCodeIndenter.h"
#import "MPCodeLanguages.h"


@interface MPCodeIndenterTests : XCTestCase
@end


@implementation MPCodeIndenterTests

#pragma mark - Finding the block that was clicked

- (void)testTheBlockUnderAPlaceInTheText
{
    NSString *text = @"prima\n\n```python\nx = 1\n```\n\ndopo\n";
    //                 0      6 7          17      23

    MPFencedCodeBlock *block =
        [MPFencedCodeBlock blockCoveringIndex:19 inText:text];
    XCTAssertNotNil(block);
    XCTAssertEqualObjects(block.language, @"python");
    XCTAssertEqualObjects([text substringWithRange:block.bodyRange],
                          @"x = 1");
    XCTAssertEqualObjects([text substringWithRange:block.range],
                          @"```python\nx = 1\n```");

    // The fence lines belong to the block too, since that is where a
    // right-click often lands.
    XCTAssertNotNil([MPFencedCodeBlock blockCoveringIndex:8 inText:text]);
    // Outside it there is nothing.
    XCTAssertNil([MPFencedCodeBlock blockCoveringIndex:2 inText:text]);
    XCTAssertNil([MPFencedCodeBlock blockCoveringIndex:text.length
                                                inText:text]);
}

- (void)testTheSecondBlockIsNotTheFirst
{
    NSString *text = @"```js\na\n```\n\n```python\nb\n```\n";
    MPFencedCodeBlock *first =
        [MPFencedCodeBlock blockCoveringIndex:6 inText:text];
    MPFencedCodeBlock *second =
        [MPFencedCodeBlock blockCoveringIndex:23 inText:text];

    XCTAssertEqualObjects(first.language, @"js");
    XCTAssertEqualObjects(second.language, @"python");
    XCTAssertEqualObjects([text substringWithRange:second.bodyRange], @"b");
    // Between the two there is no block.
    XCTAssertNil([MPFencedCodeBlock blockCoveringIndex:12 inText:text]);
}

- (void)testTildeFencesAndAnEmptyBlock
{
    NSString *text = @"~~~yaml\na: 1\n~~~\n";
    MPFencedCodeBlock *block =
        [MPFencedCodeBlock blockCoveringIndex:9 inText:text];
    XCTAssertEqualObjects(block.language, @"yaml");
    XCTAssertEqualObjects([text substringWithRange:block.bodyRange], @"a: 1");

    NSString *empty = @"```c\n```\n";
    MPFencedCodeBlock *none =
        [MPFencedCodeBlock blockCoveringIndex:2 inText:empty];
    XCTAssertEqual(none.bodyRange.length, (NSUInteger)0);

    // A fence that never closes is not a block: there is nothing to lay out.
    XCTAssertNil([MPFencedCodeBlock blockCoveringIndex:8
                                                inText:@"```c\nx;\ny;\n"]);
}

- (void)testAWrittenNameFindsItsRuleAndItsTitle
{
    // Through the alias map, both of them.
    XCTAssertEqualObjects(MPCanonicalCodeLanguage(@"JS"), @"javascript");
    XCTAssertEqualObjects(MPTitleOfCodeLanguage(@"c++"), @"C++");
    XCTAssertNotNil(MPCodeIndentRuleForLanguage(@"js"));
    XCTAssertNotNil(MPCodeIndentRuleForLanguage(@"c++"));

    // Highlighting knows this one; laying it out is another matter, and
    // claiming otherwise would be the way to mangle someone's code.
    XCTAssertNil(MPCodeIndentRuleForLanguage(@"abap"));
    XCTAssertNil(MPCodeIndentRuleForLanguage(@""));
}


#pragma mark - Brackets say the depth

- (void)testBracketsAreCountedAndTheUnitIsTheLanguages
{
    NSString *body = @"function f() {\nif (x) {\nreturn 1;\n}\n}";
    // JavaScript: two spaces.
    XCTAssertEqualObjects(MPReindentedCode(body, @"javascript"),
        @"function f() {\n  if (x) {\n    return 1;\n  }\n}");
    // Java: four, and the same structure.
    XCTAssertEqualObjects(MPReindentedCode(body, @"java"),
        @"function f() {\n    if (x) {\n        return 1;\n    }\n}");
    // Go: tabs.
    XCTAssertEqualObjects(MPReindentedCode(body, @"go"),
        @"function f() {\n\tif (x) {\n\t\treturn 1;\n\t}\n}");
}

- (void)testAClosingBraceSitsWithItsOpening
{
    XCTAssertEqualObjects(
        MPReindentedCode(@"if (x) {\na;\n} else {\nb;\n}", @"c"),
        @"if (x) {\n    a;\n} else {\n    b;\n}");
}

- (void)testACallSplitOverLinesIsNotABlockBeingClosed
{
    // `b);` closes the call, but it does not begin the line's own
    // structure, so it stays where the first argument is.
    XCTAssertEqualObjects(
        MPReindentedCode(@"foo(\na,\nb);\nnext();", @"javascript"),
        @"foo(\n  a,\n  b);\nnext();");
}

- (void)testBracketsInStringsAndCommentsDoNotCount
{
    XCTAssertEqualObjects(
        MPReindentedCode(@"a = \"{\";\nb = 1;", @"javascript"),
        @"a = \"{\";\nb = 1;");
    XCTAssertEqualObjects(
        MPReindentedCode(@"a(); // {\nb();", @"javascript"),
        @"a(); // {\nb();");
    XCTAssertEqualObjects(
        MPReindentedCode(@"a(); /* { */\nb();", @"javascript"),
        @"a(); /* { */\nb();");
}

- (void)testWhatRunsOverLinesIsLeftAsWritten
{
    // A template literal is text: moving its lines would change it.
    NSString *body = @"const s = `\n    keep    me\n`;\nif (x) {\nq();\n}";
    XCTAssertEqualObjects(MPReindentedCode(body, @"javascript"),
        @"const s = `\n    keep    me\n`;\nif (x) {\n  q();\n}");

    // A comment's asterisks keep their column for the same reason.
    NSString *comment = @"/**\n * nota\n */\nf();";
    XCTAssertEqualObjects(MPReindentedCode(comment, @"javascript"), comment);
}

- (void)testJSONIsLaidOutByItsBrackets
{
    XCTAssertEqualObjects(
        MPReindentedCode(@"{\n\"a\": [\n1,\n2\n],\n\"b\": 3\n}", @"json"),
        @"{\n  \"a\": [\n    1,\n    2\n  ],\n  \"b\": 3\n}");
}

- (void)testBlankLinesStayBlank
{
    XCTAssertEqualObjects(
        MPReindentedCode(@"if (x) {\na;\n\nb;\n}", @"c"),
        @"if (x) {\n    a;\n\n    b;\n}");
}


#pragma mark - Tags say the depth

- (void)testMarkupFollowsItsTags
{
    XCTAssertEqualObjects(
        MPReindentedCode(@"<div>\n<p>ciao</p>\n<br>\n<img src=\"x\">\n</div>",
                         @"html"),
        @"<div>\n  <p>ciao</p>\n  <br>\n  <img src=\"x\">\n</div>");

    // A comment that spans lines, and a declaration, move nothing.
    XCTAssertEqualObjects(
        MPReindentedCode(@"<ul>\n<!-- nota\nsu due righe -->\n<li>a</li>\n</ul>",
                         @"html"),
        @"<ul>\n  <!-- nota\nsu due righe -->\n  <li>a</li>\n</ul>");
}


#pragma mark - Where the indentation is the syntax

- (void)testPythonKeepsItsStructureAndChangesItsStep
{
    // Two spaces to four: the depths are the block's own, only the step
    // changes.
    XCTAssertEqualObjects(
        MPReindentedCode(@"def f():\n  if x:\n    return 1\n  return 0",
                         @"python"),
        @"def f():\n    if x:\n        return 1\n    return 0");

    // Already four: nothing to do, and nothing is done — which is what
    // keeps the contents of a docstring out of it.
    NSString *already = @"def f():\n    return \"\"\"\n  testo\n\"\"\"";
    XCTAssertEqualObjects(MPReindentedCode(already, @"python"), already);
}

- (void)testCodeThatIsAlignedRatherThanIndentedIsLeftAlone
{
    // The 11 columns line up with the open bracket above. There is no step
    // that measures both 4 and 11, so the block comes back as it was.
    NSString *body = @"def f():\n    g(a,\n           b)\n    return 1";
    XCTAssertEqualObjects(MPReindentedCode(body, @"python"), body);
}

- (void)testTabsAndSpacesTogetherAreLeftAlone
{
    NSString *body = @"def f():\n\tif x:\n        return 1";
    XCTAssertEqualObjects(MPReindentedCode(body, @"python"), body);
}

- (void)testARecipeLineGetsItsTab
{
    // A makefile with spaces does not work at all, which makes this the
    // one case where the step is not a matter of taste.
    XCTAssertEqualObjects(
        MPReindentedCode(@"all:\n  echo ciao\n", @"makefile"),
        @"all:\n\techo ciao\n");
}

- (void)testALanguageWithNoRuleComesBackUntouched
{
    NSString *body = @"MOVE 'x' TO y.\n  WRITE y.";
    XCTAssertEqualObjects(MPReindentedCode(body, @"abap"), body);
    XCTAssertEqualObjects(MPReindentedCode(body, @""), body);
}

@end
