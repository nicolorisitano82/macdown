//
//  MPRemoteImageFetch.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

/** Brings the pictures an export cannot reach on disk into the markup.
 *
 * A .docx and an EPUB are packages: whatever they show has to be inside
 * them. An `<img>` pointing at a web address is the one source neither
 * exporter can carry, and until now it was simply left out — the document
 * arrived with a hole where a diagram had been.
 *
 * Each http(s) source is fetched once, however many times it appears, and
 * written back into the markup as a `data:` URI. Every export path already
 * knows how to read one of those, so nothing downstream has to change.
 *
 * The work is done off the main thread with a sheet on `sheetParent` while
 * it runs, because a document with a dozen pictures on a slow line is
 * several seconds of an application that would otherwise look asleep. The
 * sheet can be cancelled, and cancelling finishes the export without the
 * pictures rather than abandoning it — the reader asked for a file.
 *
 * `completion` is called on the main queue with the rewritten markup and
 * the addresses that could not be had — the addresses rather than a count,
 * because "five pictures are missing" tells a reader nothing they can act
 * on. Given markup with no remote pictures in it, it is called straight
 * away with the markup unchanged.
 */
void MPFetchRemoteImagesInHTML(NSString *html,
                               NSWindow *sheetParent,
                               void (^completion)(NSString *html,
                                                  NSArray<NSString *> *unreachable));


/** The http(s) `<img src>` addresses in `html`, in the order they appear.
 *
 * One entry per tag, not per address: a picture used twice is listed twice,
 * because what the caller replaces is the two places it is written. The
 * addresses come back unescaped, ready to be fetched.
 *
 * Separate from the fetching so that the scanning can be tested without a
 * network, which is where the mistakes live.
 */
NSArray<NSString *> *MPRemoteImageSourcesInHTML(NSString *html);

/** `html` with every remote `<img src>` swapped for what `replacements` says.
 *
 * Keyed by the address as -MPRemoteImageSourcesInHTML returns it. A tag
 * whose address is not in the table is left as it is, and its address
 * added once to `unreplaced`, if one is given.
 */
NSString *MPHTMLByReplacingRemoteImageSources(
    NSString *html,
    NSDictionary<NSString *, NSString *> *replacements,
    NSMutableArray<NSString *> *unreplaced);
