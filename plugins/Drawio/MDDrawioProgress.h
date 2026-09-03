//
//  MDDrawioProgress.h
//  MacDown Next — draw.io plug-in
//

#import <Cocoa/Cocoa.h>


/** Says which page is being drawn, and lets you stop.
 *
 * A diagram of one page is drawn in about a second and a file of twenty
 * takes twenty: without this the application sits there having apparently
 * ignored the request, which is the difference between slow and broken.
 */
@interface MDDrawioProgress : NSObject

/// Shown as a sheet on `window`, or as a panel of its own if there is none.
- (void)showOnWindow:(NSWindow *)window title:(NSString *)title;

/// Which page, out of how many, and what it is called.
- (void)showPage:(NSUInteger)index of:(NSUInteger)count
            named:(NSString *)name;

/// Whether the button was pressed. The pages left are then not drawn.
@property (readonly, nonatomic) BOOL isCancelled;

/// What the button does, so that stopping can be tried without a click.
- (void)cancel:(id)sender;

- (void)finish;

@end
