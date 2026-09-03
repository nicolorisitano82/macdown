//
//  MPUtilityTests.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 23/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPUtilities.h"
#import "MPGlobals.h"

@interface MPUtilityTests : XCTestCase
@end


@implementation MPUtilityTests

- (void)testGetObjectFromJavaScript
{
    NSString *code = (
        @"var obj = { foo: 'bar', baz: 42 };"
        @"var arr = [0, null, {}];"
    );
    id obj = MPGetObjectFromJavaScript(code, @"obj");
    id objx = @{@"foo": @"bar", @"baz": @42};
    XCTAssertEqualObjects(obj, objx, @"JavaScript object to NSDictionary");

    id arr = MPGetObjectFromJavaScript(code, @"arr");
    id arrx = @[@0, [NSNull null], @{}];
    XCTAssertEqualObjects(arr, arrx, @"JavaScript object to NSDictionary");
}

/** Whether `index` falls between the two halves of a surrogate pair.
 *
 * Not a position: a text view will not put the caret there, and the system
 * encoder refuses such a prefix outright — it answers zero bytes, which is
 * why the comparison below has to skip these rather than trust it.
 */
- (BOOL)index:(NSUInteger)index splitsAPairIn:(NSString *)text
{
    if (!index || index >= text.length)
        return NO;
    unichar previous = [text characterAtIndex:index - 1];
    unichar current = [text characterAtIndex:index];
    return previous >= 0xD800 && previous <= 0xDBFF
        && current >= 0xDC00 && current <= 0xDFFF;
}

/** The conversion the preview's block marks depend on.
 *
 * Checked against what an encoder actually produces rather than against a
 * count worked out by hand, since the point of the pair is to agree with
 * the file on disk.
 */
- (void)testUTF8ByteOffsets
{
    NSArray<NSString *> *samples = @[
        @"plain ascii only",
        @"perch\u00e9 \u00e8 cos\u00ec, per\u00f2",
        @"emoji \U0001F600 and more \U0001F1EE\U0001F1F9 text",
        @"",
        @"\u00e8",
        @"a\u00e8b",
    ];

    for (NSString *sample in samples)
    {
        for (NSUInteger i = 0; i <= sample.length; i++)
        {
            if ([self index:i splitsAPairIn:sample])
                continue;
            NSUInteger expected = [[sample substringToIndex:i]
                lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            NSUInteger got = MPUTF8ByteOffsetForCharacterIndex(sample, i);
            XCTAssertEqual(got, expected,
                           @"byte offset of %lu in %@", (unsigned long)i,
                           sample);
        }
    }
}

- (void)testUTF8ByteOffsetsRoundTrip
{
    NSString *sample = @"perch\u00e9 \U0001F600 cos\u00ec, per\u00f2 \u2014 fine";
    for (NSUInteger i = 0; i <= sample.length; i++)
    {
        if ([self index:i splitsAPairIn:sample])
            continue;
        NSUInteger bytes = MPUTF8ByteOffsetForCharacterIndex(sample, i);
        NSUInteger back = MPCharacterIndexForUTF8ByteOffset(sample, bytes);
        XCTAssertEqual(back, i, @"round trip of %lu", (unsigned long)i);
    }
}

/// Past the end in either direction clamps rather than reading off it.
- (void)testUTF8ByteOffsetsOutOfRange
{
    NSString *sample = @"per\u00f2";
    XCTAssertEqual(MPUTF8ByteOffsetForCharacterIndex(sample, 999),
                   [sample lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertEqual(MPCharacterIndexForUTF8ByteOffset(sample, 999),
                   sample.length);
    XCTAssertEqual(MPUTF8ByteOffsetForCharacterIndex(@"", 0), (NSUInteger)0);
    XCTAssertEqual(MPCharacterIndexForUTF8ByteOffset(@"", 5), (NSUInteger)0);
}

#pragma mark - Link targets

/// A file beside the document is linked by name, so the pair can be moved.
- (void)testAFileInsideTheDocumentFolderIsRelative
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];
    NSURL *file = [NSURL fileURLWithPath:@"/Users/x/Note/allegati/piano.pdf"];
    XCTAssertEqualObjects(
        MPMarkdownLinkTargetForFileURL(file, document),
        @"allegati/piano.pdf");
}

/// A space in the name ends the link target, so it has to be escaped.
- (void)testSpacesAndAccentsAreEncoded
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];
    NSURL *file = [NSURL fileURLWithPath:
        @"/Users/x/Note/Screenshot 2026-09-02 alle 12.49.24.png"];
    NSString *target = MPMarkdownLinkTargetForFileURL(file, document);

    XCTAssertEqual([target rangeOfString:@" "].location,
                   (NSUInteger)NSNotFound, @"nessuno spazio nudo");
    XCTAssertEqualObjects(target,
        @"Screenshot%202026-09-02%20alle%2012.49.24.png");
}

/// Outside the folder there is no relative path worth writing.
- (void)testAFileElsewhereIsAbsolute
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];
    NSURL *file = [NSURL fileURLWithPath:@"/Volumes/Disco/relazione.pdf"];
    XCTAssertTrue([MPMarkdownLinkTargetForFileURL(file, document)
        hasPrefix:@"file:///Volumes/Disco/"]);
}

/// An unsaved document has no folder, so nothing can be relative to it.
- (void)testAnUnsavedDocumentGetsAnAbsoluteTarget
{
    NSURL *file = [NSURL fileURLWithPath:@"/Users/x/Note/piano.pdf"];
    XCTAssertTrue([MPMarkdownLinkTargetForFileURL(file, nil)
        hasPrefix:@"file://"]);
}

/// A folder that happens to share a prefix is not the document's folder.
- (void)testASiblingFolderIsNotInsideIt
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];
    NSURL *file = [NSURL fileURLWithPath:@"/Users/x/Notebook/piano.pdf"];
    XCTAssertTrue([MPMarkdownLinkTargetForFileURL(file, document)
        hasPrefix:@"file://"], @"Notebook non sta dentro Note");
}

#pragma mark - The file a new link makes

/// The selection is prose, and a folder will not take prose as a name.
- (void)testASelectionBecomesAFileNameBesideTheDocument
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];
    NSURL *made = MPNewMarkdownFileURLForName(@"Piano di test", document);
    XCTAssertEqualObjects(made.path, @"/Users/x/Note/Piano di test.md");
}

- (void)testWhatAFolderWillNotTakeIsTakenOut
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];

    // Una barra farebbe una cartella, i due punti un volume.
    XCTAssertEqualObjects(
        MPNewMarkdownFileURLForName(@"prima/seconda", document).lastPathComponent,
        @"prima seconda.md");
    XCTAssertEqualObjects(
        MPNewMarkdownFileURLForName(@"a: b", document).lastPathComponent,
        @"a b.md");
    // Una selezione su due righe porta con sé l'interruzione.
    XCTAssertEqualObjects(
        MPNewMarkdownFileURLForName(@"prima\nseconda", document).lastPathComponent,
        @"prima seconda.md");
    // E gli spazi non si accumulano in mezzo.
    XCTAssertEqualObjects(
        MPNewMarkdownFileURLForName(@"a  \n  b", document).lastPathComponent,
        @"a b.md");
}

/// A name that is already a Markdown file keeps its extension, not two.
- (void)testTheExtensionIsNotDoubled
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];
    XCTAssertEqualObjects(
        MPNewMarkdownFileURLForName(@"piano.md", document).lastPathComponent,
        @"piano.md");
    XCTAssertEqualObjects(
        MPNewMarkdownFileURLForName(@"piano.markdown", document).lastPathComponent,
        @"piano.markdown");
    // Ma un punto in mezzo non è un'estensione da rispettare.
    XCTAssertEqualObjects(
        MPNewMarkdownFileURLForName(@"versione 1.2", document).lastPathComponent,
        @"versione 1.2.md");
}

/// A leading dot hides the file, which a link never meant to do.
- (void)testItDoesNotMakeAHiddenFile
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];
    XCTAssertEqualObjects(
        MPNewMarkdownFileURLForName(@".nascosto", document).lastPathComponent,
        @"nascosto.md");
}

- (void)testALongSelectionIsCutToSomethingAFileSystemTakes
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];
    NSString *long_ = [@"" stringByPaddingToLength:400 withString:@"a"
                                startingAtIndex:0];
    NSString *name =
        MPNewMarkdownFileURLForName(long_, document).lastPathComponent;
    XCTAssertTrue(name.length <= 124, @"%lu", (unsigned long)name.length);
    XCTAssertTrue([name hasSuffix:@".md"]);
}

/// Nothing to name it after, and nowhere to put it: both answer nil.
- (void)testWhatCannotBeNamedIsRefused
{
    NSURL *document = [NSURL fileURLWithPath:@"/Users/x/Note/nota.md"];
    XCTAssertNil(MPNewMarkdownFileURLForName(@"", document));
    XCTAssertNil(MPNewMarkdownFileURLForName(@"   \n  ", document));
    XCTAssertNil(MPNewMarkdownFileURLForName(@"///", document));
    // Un documento mai salvato non ha un "accanto".
    XCTAssertNil(MPNewMarkdownFileURLForName(@"piano", nil));
}

#pragma mark - The shell utility's name

/** Two constants that have to agree, and nothing was checking that they do.
 *
 * The name is written once and the installation path is built from the same
 * word; if somebody changes one and not the other, the panel installs a
 * symlink under a name the app then looks for somewhere else, and says
 * nothing about it.
 */
- (void)testTheCommandNameAndItsPathAgree
{
    XCTAssertEqualObjects(kMPCommandName, @"macdownext");
    XCTAssertEqualObjects(MPCommandInstallationPath.lastPathComponent,
                          kMPCommandName);
    XCTAssertTrue([MPCommandInstallationPath hasPrefix:@"/usr/local/bin/"],
                  @"%@", MPCommandInstallationPath);
    // E non è quello dell'altra MacDown, che resta accanto senza scontrarsi.
    XCTAssertNotEqualObjects(kMPCommandName, @"macdown");
}

/** Which line something is on, for showing rather than for finding.
 *
 * The prose list is a column of "è stato" and "può essere": without the
 * line number the rows cannot be told apart at all.
 */
- (void)testTheLineSomethingIsOn
{
    NSString *text = @"prima\nseconda\n\nquarta";
    //                 0      6        14 15

    XCTAssertEqual(MPLineNumberForLocation(text, 0), 1u);
    XCTAssertEqual(MPLineNumberForLocation(text, 5), 1u);
    // The newline belongs to the line it ends, so what follows it is the
    // next one.
    XCTAssertEqual(MPLineNumberForLocation(text, 6), 2u);
    XCTAssertEqual(MPLineNumberForLocation(text, 13), 2u);
    XCTAssertEqual(MPLineNumberForLocation(text, 14), 3u);
    XCTAssertEqual(MPLineNumberForLocation(text, 15), 4u);
    XCTAssertEqual(MPLineNumberForLocation(text, text.length), 4u);

    // Nothing to count, and nowhere to be: still a first line.
    XCTAssertEqual(MPLineNumberForLocation(@"", 0), 1u);
    XCTAssertEqual(MPLineNumberForLocation(@"solo una riga", 99), 1u);
}

/** The plug-ins the application loads, from both of the places it looks.
 *
 * The one that ships inside is why nothing has to be installed; the test
 * bundle lives in the same folder and is not a plug-in.
 */
- (void)testThePlugInsTheApplicationLoads
{
    NSArray<NSURL *> *urls = MPPlugInBundleURLs();
    NSMutableArray *names = [NSMutableArray array];
    for (NSURL *url in urls)
        [names addObject:url.lastPathComponent];

    XCTAssertTrue([names containsObject:@"Drawio.plugin"],
                  @"il plug-in in dotazione non è fra %@", names);
    XCTAssertFalse([names containsObject:@"MacDownTests.xctest"],
                   @"il bundle dei test non è un plug-in");
    for (NSString *name in names)
        XCTAssertEqualObjects(name.pathExtension, @"plugin");
}

@end
