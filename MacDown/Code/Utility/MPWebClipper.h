//
//  MPWebClipper.h
//  MacDown
//

#import <Foundation/Foundation.h>


/** Saves a web page as a Markdown file.
 *
 * For collecting evidence: a page that backs up a statement in a report is
 * worth keeping beside the report, and keeping it as Markdown means it is
 * still readable when the page is not there any more. The address and the
 * date it was taken go at the top, since a clipping without them is a
 * quotation without a source.
 *
 * The conversion is the one the editor already uses for pasting, so what
 * arrives here is what would arrive by copying the page and pasting it —
 * and what it does not recognise contributes its text and nothing else.
 */
@interface MPWebClipper : NSObject

/// `done` is called on the main queue.
+ (void)clipURL:(NSURL *)url
     completion:(void (^)(NSString *markdown, NSString *title,
                          NSError *error))done;

@end


/** The part of a page worth keeping.
 *
 * Scripts, styles, navigation, headers, footers and asides are not the
 * page: they are what surrounds it. If the page says which part is the
 * article, that part is taken and the rest is left.
 */
extern NSString *MPReadableHTMLFragment(NSString *html);

/** The same fragment with every address in it made absolute.
 *
 * A page written with `/img/rete.png` and `../altro` means those relative
 * to itself. Once the text is a file in somebody's folder they mean
 * nothing, so they are resolved against the address the page came from
 * before the conversion sees them.
 */
extern NSString *MPHTMLWithAbsoluteAddresses(NSString *html, NSURL *base);

/// What the page calls itself: its title, or its first heading.
extern NSString *MPTitleOfHTML(NSString *html);

/// The file to write: front matter, the title, and the page as Markdown.
extern NSString *MPClippedMarkdown(NSString *html, NSURL *url, NSDate *when);

/// A file name for a clipping, from its title.
extern NSString *MPFileNameForClipping(NSString *title, NSURL *url);
