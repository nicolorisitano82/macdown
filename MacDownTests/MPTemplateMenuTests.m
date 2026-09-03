//
//  MPTemplateMenuTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPMainController.h"
#import "MPDocumentTemplate.h"

/** That the template menu is actually found and actually filled.
 *
 * Written after it shipped empty. The templates were in the bundle and the
 * filling worked; what failed was finding the menu to fill. The lookup
 * required the item to have no action, and an item that owns a submenu has
 * one — `submenuAction:` — so nothing matched, the delegate was never set,
 * and the menu stayed as drawn.
 *
 * Nothing tested it because it looked like wiring rather than logic. The
 * tests run inside the application, so the menu bar is right there and the
 * lookup can be checked for what it is: the one link in the chain that had
 * no proof.
 */
@interface MPTemplateMenuTests : XCTestCase
@end

@implementation MPTemplateMenuTests

/// The same walk the controller makes, from the same tag.
- (NSMenuItem *)templateMenuItem
{
    for (NSMenuItem *top in [NSApp mainMenu].itemArray)
    {
        for (NSMenuItem *item in top.submenu.itemArray)
        {
            if (item.tag == kMPTemplateMenuTag && item.submenu)
                return item;
        }
    }
    return nil;
}

/** What the lookup used to trip over, written down as a fact.
 *
 * A menu item that owns a submenu is given `submenuAction:` by AppKit, so
 * a guard of `item.action == NULL` — which the first version of the lookup
 * had — never matches one. Measured here so the next person to write such
 * a walk does not repeat it.
 */
- (void)testASubmenuItemHasAnActionAfterAll
{
    NSMenuItem *item = [self templateMenuItem];
    XCTAssertNotNil(item);
    XCTAssertTrue(item.action == @selector(submenuAction:)
                  || item.action != NULL,
                  @"azione: %@", NSStringFromSelector(item.action));
    NSLog(@"azione della voce col sottomenu: %@",
          NSStringFromSelector(item.action));
}

- (void)testTheMenuBarIsLoaded
{
    XCTAssertNotNil([NSApp mainMenu],
                    @"senza barra dei menu questo test non prova niente");
    XCTAssertTrue([NSApp mainMenu].itemArray.count > 3);
}

/// The tag has to reach the built nib, which an identifier did not.
- (void)testTheTemplateMenuIsFoundByItsTag
{
    NSMenuItem *item = [self templateMenuItem];
    XCTAssertNotNil(item, @"il menu dei template non si trova col tag %ld",
                    (long)kMPTemplateMenuTag);
    XCTAssertNotNil(item.submenu);
}

/// Somebody has to be listening, or it is filled by nobody.
- (void)testSomebodyIsTheMenusDelegate
{
    NSMenuItem *item = [self templateMenuItem];
    XCTAssertNotNil(item.submenu.delegate,
                    @"nessun delegato: il menu resterebbe come nel nib");
}

/** And that asking it to update fills it with what is installed.
 *
 * The whole chain, in the order it runs: the delegate is asked, the folder
 * is read, the items appear.
 */
- (void)testAskingItToUpdateFillsIt
{
    NSMenuItem *item = [self templateMenuItem];
    NSMenu *menu = item.submenu;
    id<NSMenuDelegate> delegate = menu.delegate;
    XCTAssertTrue([delegate respondsToSelector:@selector(menuNeedsUpdate:)]);

    [delegate menuNeedsUpdate:menu];

    NSUInteger installed = [MPDocumentTemplate installedTemplates].count;
    XCTAssertTrue(installed > 0, @"nessun template nel bundle");
    // One per template, a separator, and the reveal.
    XCTAssertEqual(menu.itemArray.count, installed + 2,
                   @"%lu voci per %lu template",
                   (unsigned long)menu.itemArray.count,
                   (unsigned long)installed);

    NSMenuItem *first = menu.itemArray.firstObject;
    XCTAssertEqualObjects(first.title,
                          [MPDocumentTemplate installedTemplates].firstObject.name);
    XCTAssertTrue([first.representedObject
        isKindOfClass:[MPDocumentTemplate class]],
        @"la voce deve portarsi dietro il template che inserisce");
    XCTAssertEqual(first.action, @selector(insertDocumentTemplate:));
    XCTAssertNil(first.target, @"bersaglio nil, per arrivare al documento");
}

@end
