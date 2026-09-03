//
//  MDDrawioRenderer.h
//  MacDown Next — draw.io plug-in
//

#import <Cocoa/Cocoa.h>
#import "MDDrawioFile.h"

@class MDDrawioResources;

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

/// The plug-in bundle, which is where the viewer and the libraries are.
- (instancetype)initWithBundle:(NSBundle *)bundle;

/// What served the last drawing: which libraries it wanted, and got.
@property (readonly, nonatomic) MDDrawioResources *resources;

/** Drawn here, by the bundled viewer.
 *
 * Every address in the page points back into the plug-in — the viewer, and
 * the shape libraries it loads when a diagram uses AWS or Cisco or BPMN.
 * Nothing is fetched, and nothing needs to be.
 */
- (void)renderPage:(MDDrawioPage *)page
             scale:(CGFloat)scale
        completion:(MDDrawioRenderHandler)handler;

/** The page that draws one diagram, with the viewer written into it.
 *
 * Out here so that what it does and does not reach for can be read off it
 * without a window and without a network.
 */
+ (NSString *)pageForXML:(NSString *)xml
                    base:(NSString *)base
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
