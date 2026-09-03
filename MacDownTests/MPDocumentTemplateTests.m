//
//  MPDocumentTemplateTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPDocumentTemplate.h"

@interface MPDocumentTemplateTests : XCTestCase
@end

@implementation MPDocumentTemplateTests

/// The ones that ship have to be there, and have to be Markdown.
- (void)testTheBundledTemplatesAreInstalled
{
    NSArray<MPDocumentTemplate *> *templates =
        [MPDocumentTemplate installedTemplates];
    XCTAssertTrue(templates.count >= 4, @"%lu trovati",
                  (unsigned long)templates.count);

    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (MPDocumentTemplate *template in templates)
        [names addObject:template.name];

    XCTAssertTrue([names containsObject:@"Verbale di collaudo"]);
    XCTAssertTrue([names containsObject:@"Piano di test software"]);
}

/// By name, so a menu built from them is in an order a reader can predict.
- (void)testTheyComeBackSorted
{
    NSArray<MPDocumentTemplate *> *templates =
        [MPDocumentTemplate installedTemplates];
    for (NSUInteger i = 1; i < templates.count; i++)
    {
        XCTAssertTrue([templates[i - 1].name
            localizedStandardCompare:templates[i].name] <= 0,
            @"%@ prima di %@", templates[i - 1].name, templates[i].name);
    }
}

/** Every one of them has to read, and be a document rather than a note.
 *
 * The measured reason they are files at all: a structure has one right
 * shape. So the shapes are checked — a heading to start, and the tables
 * the ones with tables are for.
 */
- (void)testEveryTemplateIsAUsableDocument
{
    for (MPDocumentTemplate *template in
            [MPDocumentTemplate installedTemplates])
    {
        NSString *markdown = template.markdown;
        XCTAssertTrue(markdown.length > 100, @"%@ è troppo corto",
                      template.name);
        XCTAssertTrue([markdown hasPrefix:@"# "],
                      @"%@ non comincia con un titolo", template.name);
        XCTAssertNotEqual([markdown rangeOfString:@"\n## "].location,
                          (NSUInteger)NSNotFound,
                          @"%@ non ha sezioni", template.name);
    }
}

/// The two that are forms need their separator rows to be real tables.
- (void)testTheTablesInThemAreTables
{
    for (MPDocumentTemplate *template in
            [MPDocumentTemplate installedTemplates])
    {
        NSString *markdown = template.markdown;
        if ([markdown rangeOfString:@"|"].location == NSNotFound)
            continue;
        // A row of hyphens between bars: without it a table is just lines
        // with bars in them, which is the mistake this app has a repair
        // command for.
        XCTAssertNotEqual([markdown rangeOfString:@"|---"].location,
                          (NSUInteger)NSNotFound,
                          @"%@ ha barre ma nessuna riga separatrice",
                          template.name);
        // Only in a separator row. An em dash in prose is prose — the
        // rule is about the row that declares the table, and a test that
        // forbade the character outright failed on a sentence.
        NSCharacterSet *ruleCharacters = [NSCharacterSet
            characterSetWithCharactersInString:@"|-—: \t"];
        for (NSString *line in [markdown componentsSeparatedByString:@"\n"])
        {
            if ([line rangeOfString:@"|"].location == NSNotFound)
                continue;
            NSString *left = [line stringByTrimmingCharactersInSet:
                ruleCharacters];
            if (left.length)
                continue;   // there is prose on this line: not a rule row
            XCTAssertEqual([line rangeOfString:@"—"].location,
                           (NSUInteger)NSNotFound,
                           @"%@ ha una riga separatrice col trattino lungo: "
                           @"«%@»", template.name, line);
        }
    }
}

- (void)testTheCustomFolderIsThere
{
    NSURL *folder = [MPDocumentTemplate customDirectory];
    XCTAssertTrue(folder.isFileURL);
    BOOL directory = NO;
    XCTAssertTrue([[NSFileManager defaultManager]
        fileExistsAtPath:folder.path isDirectory:&directory]);
    XCTAssertTrue(directory);
    XCTAssertEqualObjects(folder.lastPathComponent, @"Templates");
}

@end
