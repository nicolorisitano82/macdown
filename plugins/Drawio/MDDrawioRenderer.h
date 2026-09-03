//
//  MDDrawioRenderer.h
//  MacDown Next — draw.io plug-in
//

#import <Cocoa/Cocoa.h>
#import "MDDrawioFile.h"

typedef void (^MDDrawioRenderHandler)(NSData *png, NSError *error);


/** Turns a page of a diagram into a PNG.
 *
 * Two ways, and the difference is not speed. **On this Mac** the drawing is
 * done by draw.io's own viewer, which travels inside this plug-in: the
 * diagram never leaves the machine, and it works with no connection at
 * all. **On an export server** the diagram is sent to a URL you give — your
 * own `jgraph/export-server`, say — which is the way to render the shape
 * libraries that fetch their pictures from somewhere.
 *
 * The public service at diagrams.net is deliberately not one of the
 * choices: it answers `Referer not allowed: this service only accepts
 * requests from draw.io applications`, and getting round that by claiming
 * to be draw.io is not something to ship.
 */
@interface MDDrawioRenderer : NSObject

/// The plug-in bundle, which is where the viewer is kept.
- (instancetype)initWithBundle:(NSBundle *)bundle;

/// Drawn here, by the bundled viewer. Nothing is sent anywhere.
- (void)renderPage:(MDDrawioPage *)page
             scale:(CGFloat)scale
        completion:(MDDrawioRenderHandler)handler;

/** Drawn by an export server at `service`, which is sent the diagram.
 *
 * The form the servlet expects: `format`, `xml`, `scale`. Both the docker
 * image draw.io publishes and the servlet it grew out of take it.
 */
- (void)renderPage:(MDDrawioPage *)page
             scale:(CGFloat)scale
         onService:(NSURL *)service
        completion:(MDDrawioRenderHandler)handler;

@end
