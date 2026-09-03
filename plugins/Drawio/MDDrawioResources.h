//
//  MDDrawioResources.h
//  MacDown Next — draw.io plug-in
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>


/** Serves the page, and everything the viewer asks for, out of the bundle.
 *
 * The shape libraries — AWS, Cisco, Azure, BPMN and forty-odd more — are
 * not inside the viewer: they are files it loads when a diagram uses one,
 * and its own addresses for them are on diagrams.net. They are in here
 * instead, gzipped, and this hands them over under a scheme of its own.
 *
 * A scheme rather than `file:`, because a page loaded from a string has no
 * origin a local file may be read from, and copying the libraries into a
 * temporary folder per picture is worse than reading them where they are.
 * The page itself is served too, so it and the libraries share an origin
 * and the viewer's own requests for them are not cross-origin.
 *
 * Nothing here can reach outside the bundle's resources, and nothing here
 * touches the network.
 */
@interface MDDrawioResources : NSObject <WKURLSchemeHandler>

/// The scheme the web view is told to hand to this.
+ (NSString *)scheme;
/// What the paths in the page are built from: `drawio-res://render`.
+ (NSString *)base;
/// The page to load.
+ (NSURL *)pageURL;

- (instancetype)initWithBundle:(NSBundle *)bundle page:(NSString *)page;

/// What has been handed over, in order: found in the bundle, and inflated.
@property (readonly, copy, nonatomic) NSArray<NSString *> *servedPaths;
/// What was asked for and refused — not in the bundle, or not readable.
@property (readonly, copy, nonatomic) NSArray<NSString *> *failedPaths;

@end
