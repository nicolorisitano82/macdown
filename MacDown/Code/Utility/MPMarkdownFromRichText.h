//
//  MPMarkdownFromRichText.h
//  MacDown
//

#import <Foundation/Foundation.h>

/** Turns what a browser or a word processor puts on the pasteboard into
 *  Markdown.
 *
 * Copying a heading out of a web page and pasting it here should give a
 * heading, not a line of text that used to be one. The formatting is on the
 * pasteboard — every browser puts the HTML there alongside the plain text —
 * and this reads it back into the markup that means the same thing.
 *
 * It is deliberately not a general HTML converter. Anything it does not
 * recognise contributes its text and nothing else, which is the same result
 * as pasting plain text: no worse than not trying, and never a page of
 * angle brackets in the document.
 */
@interface MPMarkdownFromRichText : NSObject

/// Markdown for an HTML fragment, as found on the pasteboard.
+ (NSString *)markdownFromHTML:(NSString *)html;

/** Markdown for a styled string, for the sources that offer no HTML.
 *
 * Reads the attributes rather than tags: bold and italic from the font,
 * links from the link attribute, lists from the paragraph style. Less than
 * the HTML path can tell, which is why it is the second choice.
 */
+ (NSString *)markdownFromAttributedString:(NSAttributedString *)text;

@end
