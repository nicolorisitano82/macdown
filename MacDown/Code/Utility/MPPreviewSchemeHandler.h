//
//  MPPreviewSchemeHandler.h
//  MacDown
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

/// The scheme the preview is served over. See the class comment.
extern NSString * const MPPreviewURLScheme;

/// Wraps a filesystem path as a URL this handler will serve.
NSURL *MPPreviewURLForPath(NSString *path);

/** Serves the preview and everything it asks for.
 *
 * The preview is a local page that pulls its stylesheet out of Application
 * Support, its scripts out of the bundle, and its images from beside the
 * document — three places with no common parent. Served over file://, WebKit2
 * gives such a page an opaque origin and refuses all of it: the stylesheet is
 * ignored, and a script is fetched, reported as loaded, and then silently
 * never run.
 *
 * The ways around that are all worse than this one. Loosening file access
 * through the undocumented preference keys does not work. Inlining the assets
 * does, until a script contains the characters that close a script tag —
 * mermaid is nearly three megabytes and contains them.
 *
 * A custom scheme gives the page an ordinary origin, and everything below it
 * loads and runs as it would on the web. The URLs carry an absolute path, so
 * relative links in a document resolve to the file beside it.
 */
@interface MPPreviewSchemeHandler : NSObject <WKURLSchemeHandler>
@end
