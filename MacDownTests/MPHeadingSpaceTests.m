//
//  MPHeadingSpaceTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import <hoedown/document.h>
#import <hoedown/html.h>
#import "pmh_parser.h"


/** That the editor and the preview call the same lines headings.
 *
 * Two parsers read every document here: peg-markdown-highlight colours the
 * editor, hoedown draws the preview. When they disagree the reader is the
 * one who has to work out which is lying — and they did disagree, over the
 * space after the hashes: `##Trump` was a heading in the editor and a
 * paragraph in the preview.
 */
@interface MPHeadingSpaceTests : XCTestCase
@end


@implementation MPHeadingSpaceTests

/// Whether the editor's parser finds a heading in `text`.
- (BOOL)editorSeesAHeadingIn:(NSString *)text
{
    pmh_element **elements = NULL;
    pmh_markdown_to_elements((char *)text.UTF8String, 0, &elements);
    BOOL found = NO;
    for (int type = pmh_H1; type <= pmh_H6 && !found; type++)
        found = (elements[type] != NULL);
    pmh_free_elements(elements);
    return found;
}

/// Whether the preview's renderer draws one, with the flags the app uses.
- (BOOL)previewDrawsAHeadingIn:(NSString *)text
{
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
    hoedown_renderer *renderer = hoedown_html_renderer_new(0, 0);
    hoedown_document *document = hoedown_document_new(renderer,
        HOEDOWN_EXT_SPACE_HEADERS | HOEDOWN_EXT_FENCED_CODE, 16);
    hoedown_buffer *out = hoedown_buffer_new(64);
    hoedown_document_render(document, out, utf8.bytes, utf8.length);
    NSString *html = [[NSString alloc] initWithBytes:out->data
        length:out->size encoding:NSUTF8StringEncoding] ?: @"";
    hoedown_buffer_free(out);
    hoedown_document_free(document);
    hoedown_html_renderer_free(renderer);

    for (NSUInteger level = 1; level <= 6; level++)
    {
        if ([html containsString:[NSString stringWithFormat:@"<h%lu",
                                  (unsigned long)level]])
            return YES;
    }
    return NO;
}

- (void)assertBothAgreeOn:(NSString *)text heading:(BOOL)expected
{
    BOOL editor = [self editorSeesAHeadingIn:text];
    BOOL preview = [self previewDrawsAHeadingIn:text];
    XCTAssertEqual(editor, expected, @"l'editor su «%@»", text);
    XCTAssertEqual(preview, expected, @"l'anteprima su «%@»", text);
    XCTAssertEqual(editor, preview, @"le due viste non sono d'accordo su «%@»",
                   text);
}


- (void)testAHeadingIsAHeadingInBoth
{
    [self assertBothAgreeOn:@"# Titolo\n\ntesto\n" heading:YES];
    [self assertBothAgreeOn:@"## Trump: la proposta\n\ntesto\n" heading:YES];
    [self assertBothAgreeOn:@"###### Il sesto livello\n\ntesto\n" heading:YES];
}

- (void)testWithoutTheSpaceNeitherCallsItAHeading
{
    // The line that started this: hashes stuck to the word.
    [self assertBothAgreeOn:@"##Trump: la proposta\n\ntesto\n" heading:NO];
    [self assertBothAgreeOn:@"#Titolo\n\ntesto\n" heading:NO];
}

- (void)testAHashtagIsNotATitle
{
    [self assertBothAgreeOn:@"#riunione\n\ntesto\n" heading:NO];
    [self assertBothAgreeOn:@"#riunione #verbale\n\ntesto\n" heading:NO];
}

- (void)testTheOtherWayOfWritingAHeadingIsUntouched
{
    [self assertBothAgreeOn:@"Titolo\n======\n\ntesto\n" heading:YES];
    [self assertBothAgreeOn:@"Sottotitolo\n-----------\n\ntesto\n" heading:YES];
}

- (void)testHashesInsideALineAreJustHashes
{
    [self assertBothAgreeOn:@"Il numero #4 della lista.\n" heading:NO];
}

- (void)testAHeadingClosedWithHashesStillWorks
{
    [self assertBothAgreeOn:@"## Riunione ##\n\ntesto\n" heading:YES];
}

@end
