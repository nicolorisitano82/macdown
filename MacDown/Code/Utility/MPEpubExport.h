//
//  MPEpubExport.h
//  MacDown
//
//  Builds an EPUB 3.3 package from rendered HTML.
//

#import <Foundation/Foundation.h>


@interface MPEpubMetadata : NSObject
/// Falls back to the file name, and then to "Untitled".
@property (copy, nonatomic) NSString *title;
@property (copy, nonatomic) NSString *author;
/// BCP 47. Defaults to the language the user reads macOS in.
@property (copy, nonatomic) NSString *language;
/// Any unique string. A UUID is generated when this is nil.
@property (copy, nonatomic) NSString *identifier;
@end


/** Packages `html` as an EPUB.
 *
 * The document travels as one content file rather than being cut into
 * chapters. Splitting on top-level headings reads well for a book and badly
 * for everything else — notes, a README, a page with no headings at all —
 * and a reader navigates a single file perfectly well through the table of
 * contents, which is built here from the headings.
 *
 * `baseURL` is where relative image paths are resolved from; images that
 * resolve are copied into the package, since an EPUB that points at files on
 * the author's disk is broken everywhere else.
 *
 * Returns nil if the package cannot be built.
 */
NSData *MPEpubDataFromHTML(NSString *html,
                           NSString *css,
                           NSURL *baseURL,
                           MPEpubMetadata *metadata);
