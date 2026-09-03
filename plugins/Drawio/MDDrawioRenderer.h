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
 * diagram never leaves the machine. **On an export server** the diagram is
 * sent to a URL you give — your own `jgraph/export-server`, say.
 *
 * The public service at diagrams.net is deliberately not one of the
 * choices: it answers `Referer not allowed: this service only accepts
 * requests from draw.io applications`, and getting round that by claiming
 * to be draw.io is not something to ship.
 */
@interface MDDrawioRenderer : NSObject

/// The plug-in bundle, which is where the viewer is kept.
- (instancetype)initWithBundle:(NSBundle *)bundle;

/** Drawn here, by the bundled viewer.
 *
 * `stencils` decides whether the viewer may fetch the shape sets it does
 * not carry — AWS, Cisco, BPMN and the other big libraries live in files it
 * loads when a diagram asks for them. Off, such a shape comes out as a
 * plain rectangle and **the page asks nothing of anybody**. On, those files
 * are fetched from diagrams.net: the diagram is still not sent anywhere,
 * but what it needs is named in the requests.
 */
- (void)renderPage:(MDDrawioPage *)page
             scale:(CGFloat)scale
          stencils:(BOOL)stencils
        completion:(MDDrawioRenderHandler)handler;

/** The page that draws one diagram, with the viewer written into it.
 *
 * Out here so that what it does and does not reach for can be read off it
 * without a window and without a network.
 */
+ (NSString *)pageForXML:(NSString *)xml
                stencils:(BOOL)stencils
                  viewer:(NSString *)viewer;

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
