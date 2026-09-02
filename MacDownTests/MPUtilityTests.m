//
//  MPUtilityTests.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 23/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <XCTest/XCTest.h>
#import "MPUtilities.h"

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

@end
