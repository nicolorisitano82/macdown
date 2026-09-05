//
//  MPLinkPreview.h
//  MacDown
//

#import <Cocoa/Cocoa.h>


/// What kind of thing a link leads to, which decides what can be shown.
typedef NS_ENUM(NSUInteger, MPLinkPreviewKind) {
    /// A document beside this one: its title and its first lines.
    MPLinkPreviewKindDocument,
    /// A picture, which shows itself.
    MPLinkPreviewKindImage,
    /// A file that is not there yet, which is worth saying.
    MPLinkPreviewKindMissingFile,
    /// Somewhere else entirely. Nothing is fetched to find out what.
    MPLinkPreviewKindAddress,
};


/** What can be said about a link without following it.
 *
 * Hovering a link in the preview should answer "what is over there" — and
 * for a document in the same folder the answer is in the file. For an
 * address it is the address itself, taken apart so a long one can be read:
 * nothing is fetched, because a tooltip that makes a network request is a
 * tooltip that tells somebody's server you hovered.
 */
@interface MPLinkPreview : NSObject

@property (readonly, nonatomic) MPLinkPreviewKind kind;
/// The document's first heading, the file's name, or the host.
@property (readonly, copy, nonatomic) NSString *title;
/// The first few lines of a document, or the parts of an address.
@property (readonly, copy, nonatomic) NSString *body;
/// How big it is and when it changed, for a file; nil otherwise.
@property (readonly, copy, nonatomic) NSString *footnote;
/// The file, when there is one.
@property (readonly, copy, nonatomic) NSURL *fileURL;

/** Reads what there is to know about `href`, as written in the preview.
 *
 * `documentURL` is what a relative address is relative to. Nil comes back
 * for a link there is nothing to say about — an anchor within the page.
 */
+ (instancetype)previewForHref:(NSString *)href
                    inDocument:(NSURL *)documentURL;

@end


/// The name the page uses to report a link the pointer is resting on.
extern NSString * const MPHoverMessageName;

/// How long the pointer has to rest on a link before the card is worth it.
extern const NSTimeInterval MPHoverDelay;

/** The script that watches the pointer, waiting `seconds` on each link.
 *
 * The wait belongs in the page rather than in a timer here: the page is the
 * one that knows when the pointer leaves, when the reader scrolls, and when
 * it has moved on to the next link in a list. Given as a function so that a
 * test can watch the same script with a wait it can afford.
 */
extern NSString *MPHoverWatchScript(NSTimeInterval seconds);

/** Where a link the page reported sits, in a view's own coordinates.
 *
 * The page measures with `getBoundingClientRect`: CSS pixels, from the top
 * left of the viewport. A view that is flipped counts the same way and only
 * the zoom has to be allowed for; one that is not counts from the bottom, so
 * the top has to be turned into a bottom against its height.
 *
 * WKWebView **is** flipped, which is the whole reason this is a function
 * with a test rather than four lines in the middle of a method: it was
 * written the other way, and a card that should sit under a link at the top
 * of the page appeared at the bottom of the window instead.
 */
extern NSRect MPLinkRectInView(NSDictionary *report, CGFloat zoom,
                               BOOL viewIsFlipped, CGFloat viewHeight);

/** What a page says about itself, for the card on a web link.
 *
 * Read out of markup that has already been fetched: the title, and the
 * summary the page offers — `og:description` first, since that is the line
 * a page writes for exactly this purpose, then the plain description, then
 * nothing rather than a guess.
 */
extern void MPPageSummaryFromHTML(NSString *html, NSString **title,
                                  NSString **summary);

/** Asks a page what it is, for the card.
 *
 * This is **the only thing in the preview that fetches anything**, it only
 * happens when the reader has switched it on, and it stops at half a
 * megabyte and four seconds. The completion runs on the main queue, with
 * nil for whatever could not be had.
 */
extern void MPFetchPageSummary(NSURL *url,
                               void (^completion)(NSString *title,
                                                  NSString *summary));
