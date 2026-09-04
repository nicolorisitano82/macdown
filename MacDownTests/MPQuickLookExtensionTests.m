//
//  MPQuickLookExtensionTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import <objc/message.h>
#import "MPQuickLookExtension.h"
#import "MPQuickLookPreferencesViewController.h"


/// What `pluginkit -m -i … -vvv` actually printed on this machine, with the
/// paths shortened. The mark at the left margin is the whole point: "+" is
/// on, "-" is switched off by hand, and a blank is nobody has been asked.
static NSString * const kMPListing =
    @"+    com.esempio.macdown.quicklook(0.21.0)\n"
    @"\t            Path = /Applications/MacDown Next.app/Contents/PlugIns/"
    @"MacDownQuickLook.appex\n"
    @"\t            UUID = 5D9CB991-035C-44C7-90C8-DF0F2D35679F\n"
    @"\t       Timestamp = 2026-09-04 18:28:09 +0000\n"
    @"\t             SDK = com.apple.quicklook.preview\n"
    @"\t   Parent Bundle = /Applications/MacDown Next.app\n"
    @"\t    Display Name = Anteprima Markdown\n";

static NSURL *MPBundled(void)
{
    return [NSURL fileURLWithPath:@"/Applications/MacDown Next.app/Contents/"
                                  @"PlugIns/MacDownQuickLook.appex"];
}


@interface MPQuickLookExtensionTests : XCTestCase
@end


@implementation MPQuickLookExtensionTests

#pragma mark - Reading what the system says

- (void)testTheRecordIsReadOutOfTheListing
{
    NSDictionary *record = MPQuickLookRecordInListing(
        kMPListing, @"com.esempio.macdown.quicklook");

    XCTAssertEqualObjects(record[@"version"], @"0.21.0");
    XCTAssertEqualObjects(record[@"path"],
        @"/Applications/MacDown Next.app/Contents/PlugIns/"
        @"MacDownQuickLook.appex");
    XCTAssertEqualObjects(record[@"parent"],
                          @"/Applications/MacDown Next.app");
    XCTAssertTrue([record[@"enabled"] boolValue]);
}

- (void)testAMarkOfMinusMeansSwitchedOff
{
    NSString *off = [kMPListing stringByReplacingOccurrencesOfString:@"+   "
        withString:@"-   " options:0 range:NSMakeRange(0, 4)];
    NSDictionary *record = MPQuickLookRecordInListing(
        off, @"com.esempio.macdown.quicklook");
    XCTAssertFalse([record[@"enabled"] boolValue]);
    // The rest of the record is read just the same.
    XCTAssertEqualObjects(record[@"version"], @"0.21.0");
}

- (void)testNoMarkAtAllIsStillOn
{
    NSString *never = [kMPListing stringByReplacingOccurrencesOfString:@"+   "
        withString:@"    " options:0 range:NSMakeRange(0, 4)];
    NSDictionary *record = MPQuickLookRecordInListing(
        never, @"com.esempio.macdown.quicklook");
    XCTAssertTrue([record[@"enabled"] boolValue],
                  @"chi non è stato interpellato non l'ha spenta");
}

- (void)testAnotherExtensionsRecordIsNotOurs
{
    NSString *listing =
        @"+    net.altro.anteprima(2.9.3)\n"
        @"\t            Path = /Applications/Altro.app/Contents/PlugIns/A.appex\n"
        @"\t   Parent Bundle = /Applications/Altro.app\n";
    XCTAssertNil(MPQuickLookRecordInListing(
        listing, @"com.esempio.macdown.quicklook"));
}

- (void)testOursIsFoundAmongOthersAndDoesNotSwallowTheNext
{
    NSString *listing = [NSString stringWithFormat:
        @"+    net.altro.anteprima(2.9.3)\n"
        @"\t            Path = /Applications/Altro.app/Contents/PlugIns/A.appex\n"
        @"%@"
        @"+    net.terzo.anteprima(1.0)\n"
        @"\t            Path = /Applications/Terzo.app/Contents/PlugIns/T.appex\n",
        kMPListing];

    NSDictionary *record = MPQuickLookRecordInListing(
        listing, @"com.esempio.macdown.quicklook");
    XCTAssertEqualObjects(record[@"path"],
        @"/Applications/MacDown Next.app/Contents/PlugIns/"
        @"MacDownQuickLook.appex",
        @"il percorso del record seguente non è il nostro");
    XCTAssertEqualObjects(record[@"version"], @"0.21.0");
}

- (void)testNothingToRead
{
    XCTAssertNil(MPQuickLookRecordInListing(@"", @"com.esempio.x"));
    XCTAssertNil(MPQuickLookRecordInListing(kMPListing, @""));
    XCTAssertNil(MPQuickLookRecordInListing(nil, nil));
}


#pragma mark - Where that leaves us

- (void)testRegisteredFromHereAndUpToDate
{
    NSDictionary *record = MPQuickLookRecordInListing(
        kMPListing, @"com.esempio.macdown.quicklook");
    XCTAssertEqual(MPQuickLookStateForRecord(record, MPBundled(), @"0.21.0"),
                   MPQuickLookExtensionStateInstalled);
}

- (void)testAnOlderBuildStillRegisteredIsWhatTheUpdateButtonIsFor
{
    NSDictionary *record = MPQuickLookRecordInListing(
        kMPListing, @"com.esempio.macdown.quicklook");
    XCTAssertEqual(MPQuickLookStateForRecord(record, MPBundled(), @"0.22.0"),
                   MPQuickLookExtensionStateOutdated);
}

- (void)testAnotherCopyOfTheApplicationHoldsTheRegistration
{
    NSDictionary *record = MPQuickLookRecordInListing(
        kMPListing, @"com.esempio.macdown.quicklook");
    NSURL *here = [NSURL fileURLWithPath:
        @"/Users/qualcuno/Downloads/MacDown Next.app/Contents/PlugIns/"
        @"MacDownQuickLook.appex"];
    XCTAssertEqual(MPQuickLookStateForRecord(record, here, @"0.21.0"),
                   MPQuickLookExtensionStateElsewhere);
}

- (void)testTheSamePlaceWrittenDifferentlyIsTheSamePlace
{
    NSDictionary *record = MPQuickLookRecordInListing(
        kMPListing, @"com.esempio.macdown.quicklook");
    NSURL *roundabout = [NSURL fileURLWithPath:
        @"/Applications/MacDown Next.app/Contents/Resources/../PlugIns/"
        @"MacDownQuickLook.appex"];
    XCTAssertEqual(MPQuickLookStateForRecord(record, roundabout, @"0.21.0"),
                   MPQuickLookExtensionStateInstalled);
}

- (void)testSwitchedOffByHand
{
    NSString *off = [kMPListing stringByReplacingOccurrencesOfString:@"+   "
        withString:@"-   " options:0 range:NSMakeRange(0, 4)];
    NSDictionary *record = MPQuickLookRecordInListing(
        off, @"com.esempio.macdown.quicklook");
    XCTAssertEqual(MPQuickLookStateForRecord(record, MPBundled(), @"0.21.0"),
                   MPQuickLookExtensionStateDisabled);
}

- (void)testTheSystemKnowsNothingAboutIt
{
    XCTAssertEqual(MPQuickLookStateForRecord(nil, MPBundled(), @"0.21.0"),
                   MPQuickLookExtensionStateNotInstalled);
}

- (void)testABuildWithNoExtensionInItHasNothingToInstall
{
    NSDictionary *record = MPQuickLookRecordInListing(
        kMPListing, @"com.esempio.macdown.quicklook");
    XCTAssertEqual(MPQuickLookStateForRecord(record, nil, nil),
                   MPQuickLookExtensionStateMissing);
    XCTAssertEqual(MPQuickLookStateForRecord(nil, nil, nil),
                   MPQuickLookExtensionStateMissing);
}


#pragma mark - What the panel offers to do

- (void)testTheApplicationKnowsItsOwnExtension
{
    // Not the state — that depends on the machine the tests run on — but
    // that the extension is in the bundle and answers for itself.
    MPQuickLookExtension *extension = [MPQuickLookExtension current];
    XCTAssertNotNil(extension);
    XCTAssertGreaterThan(extension.summary.length, 0u);

    if (extension.state == MPQuickLookExtensionStateMissing)
    {
        XCTAssertFalse(extension.canInstall, @"non c'è niente da installare");
        XCTAssertFalse(extension.canRemove);
        return;
    }

    XCTAssertTrue([extension.identifier hasSuffix:@".quicklook"],
                  @"%@", extension.identifier);
    XCTAssertEqualObjects(extension.bundledURL.lastPathComponent,
                          @"MacDownQuickLook.appex");
    XCTAssertGreaterThan(extension.bundledVersion.length, 0u);
    // Installing and removing are never both pointless.
    XCTAssertTrue(extension.canInstall || extension.canRemove
                  || extension.state == MPQuickLookExtensionStateInstalled);
}

#pragma mark - The panel

/// Builds one, tells it what the system said, and reads the panel back.
- (MPQuickLookPreferencesViewController *)panelShowing:
    (MPQuickLookExtensionState)state version:(NSString *)registered
{
    MPQuickLookExtension *extension = [[MPQuickLookExtension alloc] init];
    [extension setValue:@(state) forKey:@"state"];
    [extension setValue:registered forKey:@"registeredVersion"];
    [extension setValue:@"0.22.0" forKey:@"bundledVersion"];
    [extension setValue:[NSURL fileURLWithPath:@"/Applications/M.app"]
                 forKey:@"registeredURL"];

    MPQuickLookPreferencesViewController *panel =
        [[MPQuickLookPreferencesViewController alloc] init];
    XCTAssertNotNil(panel.view, @"il pannello non si è costruito");
    [panel setValue:extension forKey:@"extension"];
    SEL show = NSSelectorFromString(@"showWhatWeKnow");
    XCTAssertTrue([panel respondsToSelector:show]);
    ((void (*)(id, SEL))objc_msgSend)(panel, show);
    return panel;
}

/// Reads a label or a button title out of the built panel.
- (NSString *)titleOf:(NSString *)key in:(NSViewController *)panel
{
    id control = [panel valueForKey:key];
    if ([control isKindOfClass:[NSButton class]])
        return [control title];
    return [control stringValue];
}

- (void)testAnOlderBuildOffersToUpdate
{
    MPQuickLookPreferencesViewController *panel =
        [self panelShowing:MPQuickLookExtensionStateOutdated version:@"0.21.0"];

    // The titles themselves are translated, so what is checked is that
    // updating and installing do not read the same.
    NSString *update = [self titleOf:@"installButton" in:panel];
    NSString *install = [self titleOf:@"installButton" in:
        [self panelShowing:MPQuickLookExtensionStateNotInstalled version:nil]];
    XCTAssertNotEqualObjects(update, install, @"«%@» per entrambi", update);
    XCTAssertTrue([[panel valueForKey:@"installButton"] isEnabled]);
    XCTAssertTrue([[panel valueForKey:@"removeButton"] isEnabled]);
    // And it says which is which, or the reader cannot tell what changed.
    NSString *summary = [self titleOf:@"summaryLabel" in:panel];
    XCTAssertTrue([summary containsString:@"0.21.0"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"0.22.0"], @"%@", summary);
    XCTAssertTrue([[self titleOf:@"registeredLabel" in:panel]
        containsString:@"/Applications/M.app"]);
}

- (void)testWhenItIsInstalledThereIsNothingToInstall
{
    MPQuickLookPreferencesViewController *panel =
        [self panelShowing:MPQuickLookExtensionStateInstalled version:@"0.22.0"];
    XCTAssertGreaterThan([self titleOf:@"installButton" in:panel].length, 0u);
    XCTAssertFalse([[panel valueForKey:@"installButton"] isEnabled]);
    XCTAssertTrue([[panel valueForKey:@"removeButton"] isEnabled]);
}

- (void)testWhenItIsNotInstalledThereIsNothingToRemove
{
    MPQuickLookPreferencesViewController *panel =
        [self panelShowing:MPQuickLookExtensionStateNotInstalled version:nil];
    XCTAssertTrue([[panel valueForKey:@"installButton"] isEnabled]);
    XCTAssertFalse([[panel valueForKey:@"removeButton"] isEnabled]);
    XCTAssertTrue([[self titleOf:@"registeredLabel" in:panel] length] > 0);
}

- (void)testThePanelHasATabToSitIn
{
    MPQuickLookPreferencesViewController *panel =
        [[MPQuickLookPreferencesViewController alloc] init];
    XCTAssertEqualObjects(panel.viewIdentifier, @"QuickLookPreferences");
    XCTAssertGreaterThan(panel.toolbarItemLabel.length, 0u);
    XCTAssertNotNil(panel.toolbarItemImage);
}


- (void)testWhatTheButtonsDoInEachState
{
    // A table rather than five tests: what matters is that no state leaves
    // the panel with nothing to offer and no explanation.
    NSArray *states = @[
        @[@(MPQuickLookExtensionStateInstalled), @NO, @YES],
        @[@(MPQuickLookExtensionStateOutdated), @YES, @YES],
        @[@(MPQuickLookExtensionStateElsewhere), @YES, @YES],
        @[@(MPQuickLookExtensionStateDisabled), @YES, @NO],
        @[@(MPQuickLookExtensionStateNotInstalled), @YES, @NO],
        @[@(MPQuickLookExtensionStateMissing), @NO, @NO],
    ];
    for (NSArray *row in states)
    {
        MPQuickLookExtension *extension = [[MPQuickLookExtension alloc] init];
        [extension setValue:row[0] forKey:@"state"];
        XCTAssertEqual(extension.canInstall, [row[1] boolValue],
                       @"stato %@", row[0]);
        XCTAssertEqual(extension.canRemove, [row[2] boolValue],
                       @"stato %@", row[0]);
        XCTAssertGreaterThan(extension.summary.length, 0u, @"stato %@", row[0]);
    }
}

@end
