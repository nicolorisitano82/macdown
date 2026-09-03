//
//  MPPreferencePaneTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPHtmlPreferencesViewController.h"

/** That the Rendering pane fits on a screen, and can be made taller.
 *
 * It grew a section at a time — every switch added to it made the
 * preferences window taller, because the window takes its height from the
 * pane — until it was taller than the screen it had to open on and the
 * bottom of it could not be reached. Nothing noticed, because nothing was
 * looking at the number.
 */
@interface MPPreferencePaneTests : XCTestCase
@end

@implementation MPPreferencePaneTests

- (MPHtmlPreferencesViewController *)loadedPane
{
    MPHtmlPreferencesViewController *pane =
        [[MPHtmlPreferencesViewController alloc] init];
    XCTAssertNotNil(pane.view, @"il pannello non si carica");
    return pane;
}

- (NSScrollView *)scrollViewIn:(NSView *)view
{
    if ([view isKindOfClass:[NSScrollView class]])
        return (NSScrollView *)view;
    for (NSView *sub in view.subviews)
    {
        NSScrollView *found = [self scrollViewIn:sub];
        if (found)
            return found;
    }
    return nil;
}


- (void)testItOpensAtASizeThatFitsALaptop
{
    NSView *view = [self loadedPane].view;
    XCTAssertTrue(NSHeight(view.frame) > 200.0,
                  @"%.0f: troppo piccolo per contenere qualcosa",
                  NSHeight(view.frame));
    XCTAssertTrue(NSHeight(view.frame) <= 560.0,
                  @"%.0f punti: la finestra prende l'altezza da qui, e uno "
                  @"schermo di portatile non ne ha tanti",
                  NSHeight(view.frame));
}

/// And the content really is taller than that, or the cap proves nothing.
- (void)testTheContentIsTallerThanThePaneAndScrolls
{
    MPHtmlPreferencesViewController *pane = [self loadedPane];
    NSScrollView *scroll = [self scrollViewIn:pane.view];
    XCTAssertNotNil(scroll, @"senza contenitore che scorre non si arriva "
                            @"in fondo");
    XCTAssertTrue(scroll.hasVerticalScroller);

    [pane.view layoutSubtreeIfNeeded];
    NSView *content = scroll.documentView;
    XCTAssertNotNil(content);
    XCTAssertTrue(content.fittingSize.height > NSHeight(pane.view.frame),
                  @"contenuto %.0f, pannello %.0f: il limite non serve a "
                  @"niente se il contenuto ci sta comunque",
                  content.fittingSize.height, NSHeight(pane.view.frame));
}

/// MASPreferences reads these to decide the window's maximum size.
- (void)testTheHeightCanBeDragged
{
    MPHtmlPreferencesViewController *pane = [self loadedPane];
    XCTAssertTrue([pane respondsToSelector:@selector(hasResizableHeight)]);
    XCTAssertTrue([(id)pane hasResizableHeight]);
    // In larghezza no: è una colonna di interruttori, e allargarla dà
    // soltanto righe più lunghe da seguire con l'occhio.
    XCTAssertFalse([(id)pane hasResizableWidth]);
}

@end
