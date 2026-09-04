//
//  MPUpdateTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import <objc/message.h>
#import "MPUpdate.h"
#import "MPUpdateController.h"
#import "MPPreferences.h"


/// Cut down from what api.github.com actually answers for this repository.
static NSString * const kMPFeed = @"{"
    @"\"tag_name\": \"v0.22.0\","
    @"\"name\": \"v0.22.0 — due anteprime\","
    @"\"draft\": false,"
    @"\"prerelease\": false,"
    @"\"body\": \"Quello che cambia.\","
    @"\"html_url\": \"https://github.com/tizio/macdown-next/releases/tag/v0.22.0\","
    @"\"assets\": ["
    @"  {\"name\": \"note.txt\","
    @"   \"size\": 12,"
    @"   \"browser_download_url\": \"https://github.com/tizio/x/note.txt\"},"
    @"  {\"name\": \"MacDownNext-0.22.0.dmg\","
    @"   \"size\": 17301504,"
    @"   \"browser_download_url\": "
    @"     \"https://github.com/tizio/macdown-next/releases/download/v0.22.0/"
    @"MacDownNext-0.22.0.dmg\"}"
    @"]}";

static NSData *MPFeed(NSString *json)
{
    return [json dataUsingEncoding:NSUTF8StringEncoding];
}


@interface MPUpdateTests : XCTestCase
@property (strong) NSURL *folder;
@end


@implementation MPUpdateTests

- (void)setUp
{
    [super setUp];
    self.folder = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.folder
        withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.folder error:NULL];
    [super tearDown];
}


#pragma mark - Which version is later

- (void)testTheOrdinaryComparisons
{
    XCTAssertEqual(MPCompareVersions(@"0.22.0", @"0.21.0"), NSOrderedDescending);
    XCTAssertEqual(MPCompareVersions(@"0.21.0", @"0.22.0"), NSOrderedAscending);
    XCTAssertEqual(MPCompareVersions(@"1.0.0", @"0.99.99"), NSOrderedDescending);
    XCTAssertEqual(MPCompareVersions(@"0.22.1", @"0.22.0"), NSOrderedDescending);
    XCTAssertEqual(MPCompareVersions(@"0.22.0", @"0.22.0"), NSOrderedSame);
}

- (void)testTheTagAndTheVersionAreTheSameThing
{
    XCTAssertEqual(MPCompareVersions(@"v0.22.0", @"0.22.0"), NSOrderedSame);
}

- (void)testAMissingPartIsAZero
{
    XCTAssertEqual(MPCompareVersions(@"0.22", @"0.22.0"), NSOrderedSame);
    XCTAssertEqual(MPCompareVersions(@"0.22", @"0.22.1"), NSOrderedAscending);
}

- (void)testABuildOnTheWayToAReleaseIsBehindIt
{
    // 0.22.0d7 is seven commits into what will become 0.22.0.
    XCTAssertEqual(MPCompareVersions(@"0.22.0d7", @"0.22.0"),
                   NSOrderedAscending);
    XCTAssertEqual(MPCompareVersions(@"0.22.0d7", @"0.21.0"),
                   NSOrderedDescending);
    XCTAssertEqual(MPCompareVersions(@"0.22.0d7", @"0.22.0d3"),
                   NSOrderedDescending);
    XCTAssertEqual(MPCompareVersions(@"0.22.0d7", @"0.22.0d7"), NSOrderedSame);
}

- (void)testNothingToCompare
{
    XCTAssertEqual(MPCompareVersions(@"", @""), NSOrderedSame);
    XCTAssertEqual(MPCompareVersions(@"0.1", @""), NSOrderedDescending);
}


#pragma mark - Reading the answer

- (void)testTheReleaseIsReadOutOfTheFeed
{
    MPRelease *release = MPReleaseFromFeed(MPFeed(kMPFeed));

    XCTAssertEqualObjects(release.version, @"0.22.0");
    XCTAssertTrue([release.title containsString:@"anteprime"]);
    XCTAssertEqualObjects(release.notes, @"Quello che cambia.");
    XCTAssertEqualObjects(release.pageURL.absoluteString,
        @"https://github.com/tizio/macdown-next/releases/tag/v0.22.0");
    // The disk image, not the first attachment it happens to find.
    XCTAssertEqualObjects(release.diskImageURL.lastPathComponent,
                          @"MacDownNext-0.22.0.dmg");
    XCTAssertEqual(release.size, 17301504LL);
}

- (void)testADraftIsNotOutYet
{
    NSString *draft = [kMPFeed stringByReplacingOccurrencesOfString:
        @"\"draft\": false" withString:@"\"draft\": true"];
    XCTAssertNil(MPReleaseFromFeed(MPFeed(draft)));
}

- (void)testAReleaseWithNothingToDownloadIsNoUse
{
    NSString *empty = @"{\"tag_name\": \"v0.23.0\", \"assets\": []}";
    XCTAssertNil(MPReleaseFromFeed(MPFeed(empty)));
}

- (void)testADiskImageFromSomewhereElseIsRefused
{
    NSString *elsewhere = [kMPFeed stringByReplacingOccurrencesOfString:
        @"https://github.com/tizio/macdown-next/releases/download"
        withString:@"https://esempio.invalid/releases/download"];
    XCTAssertNil(MPReleaseFromFeed(MPFeed(elsewhere)),
                 @"un feed manomesso non deve poter dirottare lo scaricamento");
}

- (void)testWhatCountsAsOurOwnDownload
{
    XCTAssertTrue(MPIsTrustedDownload([NSURL URLWithString:
        @"https://github.com/tizio/macdown-next/releases/download/v1/a.dmg"]));
    XCTAssertTrue(MPIsTrustedDownload([NSURL URLWithString:
        @"https://objects.githubusercontent.com/qualcosa"]));
    // Not the scheme, not the host, and not a host that merely ends in one.
    XCTAssertFalse(MPIsTrustedDownload([NSURL URLWithString:
        @"http://github.com/tizio/a.dmg"]));
    XCTAssertFalse(MPIsTrustedDownload([NSURL URLWithString:
        @"https://esempio.invalid/a.dmg"]));
    XCTAssertFalse(MPIsTrustedDownload([NSURL URLWithString:
        @"https://github.com.esempio.invalid/a.dmg"]));
    XCTAssertFalse(MPIsTrustedDownload(nil));
}

- (void)testNonsenseInsteadOfAnAnswer
{
    XCTAssertNil(MPReleaseFromFeed(nil));
    XCTAssertNil(MPReleaseFromFeed(MPFeed(@"")));
    XCTAssertNil(MPReleaseFromFeed(MPFeed(@"non è JSON")));
    XCTAssertNil(MPReleaseFromFeed(MPFeed(@"[1, 2, 3]")));
}


#pragma mark - Whether to say anything

- (void)testWorthTellingSomebodyAbout
{
    MPRelease *release = MPReleaseFromFeed(MPFeed(kMPFeed));
    XCTAssertTrue(MPUpdateIsNewer(release, @"0.21.0"));
    XCTAssertTrue(MPUpdateIsNewer(release, @"0.22.0d3"),
                  @"una build in corsa verso la 0.22.0 non è la 0.22.0");
    XCTAssertFalse(MPUpdateIsNewer(release, @"0.22.0"));
    XCTAssertFalse(MPUpdateIsNewer(release, @"0.23.0"));
    XCTAssertFalse(MPUpdateIsNewer(nil, @"0.21.0"));
}

- (void)testHowOftenItLooks
{
    NSDate *now = [NSDate date];
    XCTAssertTrue(MPUpdateIsDue(nil, now), @"non ha mai guardato");
    XCTAssertFalse(MPUpdateIsDue([now dateByAddingTimeInterval:-3600.0], now));
    XCTAssertTrue(MPUpdateIsDue([now dateByAddingTimeInterval:-90000.0], now));
    // A clock that has gone backwards must not stop it for ever.
    XCTAssertTrue(MPUpdateIsDue([now dateByAddingTimeInterval:8000000.0], now));
}


#pragma mark - Where the file goes

- (void)testTheNameIsTakenWhenItIsFree
{
    NSURL *file = MPFreeFileInFolder(self.folder, @"MacDownNext-0.22.0.dmg");
    XCTAssertEqualObjects(file.lastPathComponent, @"MacDownNext-0.22.0.dmg");
}

- (void)testAFileAlreadyThereIsNotOverwritten
{
    [@"vecchio" writeToURL:
        [self.folder URLByAppendingPathComponent:@"MacDownNext-0.22.0.dmg"]
        atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    NSURL *file = MPFreeFileInFolder(self.folder, @"MacDownNext-0.22.0.dmg");
    XCTAssertEqualObjects(file.lastPathComponent, @"MacDownNext-0.22.0 2.dmg");

    // And again, for a second copy.
    [@"anche questo" writeToURL:file atomically:YES
                       encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertEqualObjects(
        MPFreeFileInFolder(self.folder, @"MacDownNext-0.22.0.dmg")
            .lastPathComponent,
        @"MacDownNext-0.22.0 3.dmg");
}

- (void)testDownloadsIsWhereDownloadsGo
{
    NSURL *folder = MPDownloadsFolder();
    XCTAssertNotNil(folder);
    XCTAssertTrue([folder.path hasPrefix:NSHomeDirectory()], @"%@", folder);
}


#pragma mark - How far along it is

- (void)testTheProgressOfADownload
{
    XCTAssertEqualWithAccuracy(MPProgressFraction(0, 100), 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(MPProgressFraction(50, 100), 0.5, 0.0001);
    XCTAssertEqualWithAccuracy(MPProgressFraction(100, 100), 1.0, 0.0001);
    // More than expected still means finished, not more than finished.
    XCTAssertEqualWithAccuracy(MPProgressFraction(120, 100), 1.0, 0.0001);
    // A server that does not say how big it is leaves the bar indefinite.
    XCTAssertLessThan(MPProgressFraction(1000, 0), 0.0);
    XCTAssertLessThan(MPProgressFraction(1000, -1), 0.0);
}


#pragma mark - Fetching it

- (void)testAnUpdateFromSomewhereElseIsNotFetched
{
    // The check is made again at the moment of downloading, not only when
    // the feed is read: the two are far apart in time and in code.
    NSString *elsewhere = [kMPFeed stringByReplacingOccurrencesOfString:
        @"MacDownNext-0.22.0.dmg\"}" withString:@"MacDownNext-0.22.0.dmg\"}"];
    MPRelease *release = MPReleaseFromFeed(MPFeed(elsewhere));
    [release setValue:[NSURL URLWithString:@"https://esempio.invalid/a.dmg"]
               forKey:@"diskImageURL"];

    MPUpdateDownload *download =
        [[MPUpdateDownload alloc] initWithRelease:release];
    XCTestExpectation *refused =
        [self expectationWithDescription:@"non lo scarica"];
    [download startWithProgress:nil completion:^(NSURL *file, NSError *error) {
        XCTAssertNil(file);
        XCTAssertNotNil(error);
        [refused fulfill];
    }];
    [self waitForExpectations:@[refused] timeout:5.0];
    XCTAssertFalse(download.isRunning);
}


#pragma mark - When it looks by itself

/// The preference is the reader's, so the tests put it back as they found it.
- (void)withPreferences:(void (^)(MPPreferences *preferences))block
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    BOOL automatically = preferences.updatesCheckAutomatically;
    NSDate *last = preferences.updatesLastCheck;
    block(preferences);
    preferences.updatesCheckAutomatically = automatically;
    preferences.updatesLastCheck = last;
}

- (void)testTheSwitchIsObeyed
{
    [self withPreferences:^(MPPreferences *preferences) {
        preferences.updatesCheckAutomatically = NO;
        preferences.updatesLastCheck = nil;

        [[MPUpdateController sharedInstance] checkQuietlyIfDue];
        // Nothing was asked of anybody, so nothing was written down.
        XCTAssertNil(preferences.updatesLastCheck);
        XCTAssertFalse([MPUpdateController sharedInstance].isBusy);
    }];
}

- (void)testItDoesNotLookTwiceInADay
{
    [self withPreferences:^(MPPreferences *preferences) {
        preferences.updatesCheckAutomatically = YES;
        NSDate *anHourAgo = [NSDate dateWithTimeIntervalSinceNow:-3600.0];
        preferences.updatesLastCheck = anHourAgo;

        [[MPUpdateController sharedInstance] checkQuietlyIfDue];
        XCTAssertEqualWithAccuracy(
            [preferences.updatesLastCheck timeIntervalSinceDate:anHourAgo],
            0.0, 1.0, @"ha guardato di nuovo dopo un'ora");
        XCTAssertFalse([MPUpdateController sharedInstance].isBusy);
    }];
}


#pragma mark - The panel that shows how far along it is

- (MPRelease *)aRelease
{
    return MPReleaseFromFeed(MPFeed(kMPFeed));
}

- (void)testTheProgressPanelIsBuiltAndTakenAway
{
    MPUpdateController *controller = [MPUpdateController sharedInstance];
    SEL show = NSSelectorFromString(@"showProgressFor:");
    SEL hide = NSSelectorFromString(@"hideProgress");
    XCTAssertTrue([controller respondsToSelector:show]);

    ((void (*)(id, SEL, id))objc_msgSend)(controller, show, [self aRelease]);
    NSWindow *panel = [controller valueForKey:@"progressWindow"];
    XCTAssertNotNil(panel, @"il pannello non si è costruito");
    XCTAssertTrue([panel.title length] > 0);

    NSProgressIndicator *bar = [controller valueForKey:@"bar"];
    XCTAssertNotNil(bar);
    XCTAssertTrue(bar.isIndeterminate, @"finché non si sa quanto è grande");

    // Told how far along it is, the bar becomes definite and says so.
    SEL showFraction = NSSelectorFromString(@"showFraction:received:total:");
    ((void (*)(id, SEL, double, long long, long long))objc_msgSend)(
        controller, showFraction, 0.25, 4LL * 1024 * 1024, 16LL * 1024 * 1024);
    XCTAssertFalse(bar.isIndeterminate);
    XCTAssertEqualWithAccuracy(bar.doubleValue, 0.25, 0.001);
    NSTextField *label = [controller valueForKey:@"progressLabel"];
    XCTAssertTrue([label.stringValue containsString:@"MB"], @"%@",
                  label.stringValue);

    ((void (*)(id, SEL))objc_msgSend)(controller, hide);
    XCTAssertNil([controller valueForKey:@"progressWindow"]);
}

- (void)testStoppingWithNothingRunningIsHarmless
{
    MPUpdateController *controller = [MPUpdateController sharedInstance];
    SEL stop = NSSelectorFromString(@"stopDownload:");
    XCTAssertNoThrow(((void (*)(id, SEL, id))objc_msgSend)(controller, stop,
                                                           nil));
    XCTAssertFalse(controller.isBusy);
}

@end
