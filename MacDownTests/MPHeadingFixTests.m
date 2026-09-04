//
//  MPHeadingFixTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPProseChecker.h"


/// The findings about hashes stuck to their heading, and the one correction
/// the panel offers for them.
@interface MPHeadingFixTests : XCTestCase
@end


@implementation MPHeadingFixTests

- (NSArray<MPProseIssue *> *)headingIssuesIn:(NSString *)text
{
    NSMutableArray *found = [NSMutableArray array];
    for (MPProseIssue *issue in
         [[MPProseChecker sharedChecker] issuesInString:text])
    {
        if ([issue.categoryIdentifier isEqualToString:@"heading-space"])
            [found addObject:issue];
    }
    return found;
}


- (void)testTheLineThatStartedThis
{
    NSString *text = @"##Trump: la proposta per la fine della guerra\n";
    NSArray *issues = [self headingIssuesIn:text];

    XCTAssertEqual(issues.count, 1u);
    MPProseIssue *issue = issues.firstObject;
    // The finding sits on the hashes, which is what has to change.
    XCTAssertEqualObjects(issue.text, @"##");
    XCTAssertEqual(issue.range.location, 0u);
    XCTAssertEqual(issue.range.length, 2u);
    XCTAssertEqualObjects(issue.replacement, @"## ");
    XCTAssertGreaterThan(issue.categoryName.length, 0u);
}

- (void)testTheCorrectionIsTheWholeOfIt
{
    NSString *text = @"testo\n\n###Riunione di lunedì\n\naltro\n";
    MPProseIssue *issue = [self headingIssuesIn:text].firstObject;
    XCTAssertNotNil(issue);

    // Applying it to the document is a replacement of that range, and this
    // is what the document would then say.
    NSMutableString *fixed = [text mutableCopy];
    [fixed replaceCharactersInRange:issue.range withString:issue.replacement];
    XCTAssertTrue([fixed containsString:@"### Riunione di lunedì"], @"%@",
                  fixed);
}

- (void)testAHeadingWithItsSpaceIsNotAFinding
{
    XCTAssertEqual([self headingIssuesIn:@"## Trump: la proposta\n"].count, 0u);
    XCTAssertEqual([self headingIssuesIn:@"# Titolo\n\ntesto\n"].count, 0u);
}

- (void)testAHashtagIsLeftAlone
{
    // One hash and one word: a tag, and a common one.
    XCTAssertEqual([self headingIssuesIn:@"#riunione\n"].count, 0u);
    XCTAssertEqual([self headingIssuesIn:@"#verbale\n#riunione\n"].count, 0u);
    // One hash and a sentence: a heading that lost its space.
    XCTAssertEqual([self headingIssuesIn:@"#Verbale della riunione\n"].count,
                   1u);
}

- (void)testHashesInsideALineAreNotHeadings
{
    XCTAssertEqual([self headingIssuesIn:@"Il numero #4 non è un titolo.\n"]
                       .count, 0u);
    XCTAssertEqual([self headingIssuesIn:@"testo ##ancora testo\n"].count, 0u);
}

- (void)testCodeIsNotProse
{
    NSString *text = @"```sh\n#!/bin/bash\n#commento che spiega tutto\n```\n";
    XCTAssertEqual([self headingIssuesIn:text].count, 0u,
                   @"dentro un recinto di codice i cancelletti sono codice");
}

- (void)testSevenHashesAreNotAHeadingInAnyMarkdown
{
    // Six is the deepest heading there is; seven is prose that starts oddly.
    XCTAssertEqual([self headingIssuesIn:@"#######Troppo profondo\n"].count,
                   0u);
}

- (void)testEveryOtherFindingIsLeftToTheWriter
{
    // The panel only offers a button where there is one obvious answer.
    for (MPProseIssue *issue in
         [[MPProseChecker sharedChecker] issuesInString:
          @"Questo è stato fatto in modo abbastanza chiaro.\n"])
    {
        if (![issue.categoryIdentifier isEqualToString:@"heading-space"])
            XCTAssertNil(issue.replacement, @"%@", issue.categoryIdentifier);
    }
}

@end
