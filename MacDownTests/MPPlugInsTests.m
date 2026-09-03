//
//  MPPlugInsTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPPlugIn.h"
#import "MPPlugInsWindowController.h"
#import "MPUtilities.h"


/// Private, and the whole of what "Rimuovi" does once the alert is answered.
@interface MPPlugInsWindowController (Testing)
- (BOOL)trashPlugIn:(MPPlugIn *)plugin error:(NSError **)error;
@end


@interface MPPlugInsTests : XCTestCase
@property (strong) NSURL *scratch;
@end


@implementation MPPlugInsTests

- (void)setUp
{
    [super setUp];
    self.scratch = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.scratch
        withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.scratch error:NULL];
    [super tearDown];
}

- (NSURL *)folderNamed:(NSString *)name holding:(NSArray *)entries
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *folder = [self.scratch URLByAppendingPathComponent:name];
    [manager createDirectoryAtURL:folder withIntermediateDirectories:YES
                       attributes:nil error:NULL];
    for (NSString *entry in entries)
    {
        NSURL *url = [folder URLByAppendingPathComponent:entry];
        if ([entry.pathExtension isEqualToString:@"plugin"])
        {
            [manager createDirectoryAtURL:url withIntermediateDirectories:YES
                               attributes:nil error:NULL];
        }
        else
        {
            [@"x" writeToURL:url atomically:YES
                    encoding:NSUTF8StringEncoding error:NULL];
        }
    }
    return folder;
}

/// The names in the order the application would load them.
/// The folder a listed plug-in came out of, as the file system spells it.
- (NSString *)folderOf:(NSArray<NSURL *> *)urls
{
    return ((NSURL *)urls.firstObject).URLByDeletingLastPathComponent
        .URLByResolvingSymlinksInPath.path;
}

- (NSArray *)namesIn:(NSArray<NSURL *> *)urls
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSURL *url in urls)
        [names addObject:url.lastPathComponent];
    return names;
}

/// Sets when a copy was last written, which is what decides between two.
- (void)date:(NSURL *)url to:(NSTimeInterval)secondsFromNow
{
    [[NSFileManager defaultManager] setAttributes:@{
        NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:
            secondsFromNow]}
        ofItemAtPath:url.path error:NULL];
}

/** Of two copies of the same plug-in, the newer one is loaded.
 *
 * "Installed wins" was the first rule, and it pins an old copy in silence:
 * install one, rebuild the application with a fixed version inside it, and
 * the fixed one never runs. Which is exactly what happened — an hour of a
 * correct build being tested through an old copy in Application Support.
 */
- (void)testOnlyPlugInsAreLoadedAndTheNewerCopyWins
{
    NSURL *installed = [self folderNamed:@"installati"
                                 holding:@[@"Alfa.plugin", @"note.txt"]];
    NSURL *shipped = [self folderNamed:@"in-dotazione"
        holding:@[@"Alfa.plugin", @"Beta.plugin", @"Prove.xctest"]];

    // Only plug-ins, and one row per name.
    NSArray *urls = MPPlugInBundleURLsInFolders(@[installed, shipped]);
    XCTAssertEqualObjects([self namesIn:urls],
                          (@[@"Alfa.plugin", @"Beta.plugin"]));

    // A copy dropped in to be tried is newer than the application it is
    // being tried against, and it wins.
    [self date:[installed URLByAppendingPathComponent:@"Alfa.plugin"] to:0.0];
    [self date:[shipped URLByAppendingPathComponent:@"Alfa.plugin"] to:-3600.0];
    urls = MPPlugInBundleURLsInFolders(@[installed, shipped]);
    XCTAssertEqualObjects([self folderOf:urls],
                          installed.URLByResolvingSymlinksInPath.path);

    // A new build of the application is newer than the copy left behind,
    // and that wins instead — the case the first rule got wrong.
    [self date:[shipped URLByAppendingPathComponent:@"Alfa.plugin"] to:0.0];
    [self date:[installed URLByAppendingPathComponent:@"Alfa.plugin"]
            to:-3600.0];
    urls = MPPlugInBundleURLsInFolders(@[installed, shipped]);
    XCTAssertEqualObjects([self folderOf:urls],
                          shipped.URLByResolvingSymlinksInPath.path);

    // And with the installed one gone there is one copy to choose from.
    [[NSFileManager defaultManager]
        removeItemAtURL:[installed URLByAppendingPathComponent:@"Alfa.plugin"]
                  error:NULL];
    urls = MPPlugInBundleURLsInFolders(@[installed, shipped]);
    XCTAssertEqualObjects([self namesIn:urls],
                          (@[@"Alfa.plugin", @"Beta.plugin"]));
    XCTAssertEqualObjects([self folderOf:urls],
                          shipped.URLByResolvingSymlinksInPath.path);
}

- (void)testAFolderThatIsNotThereIsNotAnError
{
    NSURL *missing = [self.scratch URLByAppendingPathComponent:@"assente"];
    XCTAssertEqualObjects(MPPlugInBundleURLsInFolders(@[missing]), @[]);
    XCTAssertEqualObjects(MPPlugInBundleURLsInFolders(@[]), @[]);
}

/** Removing a plug-in has to take the file with it.
 *
 * Done on a copy of the real one, loaded first, because that is the state
 * the manager is in when Rimuovi is pressed: every plug-in it lists it has
 * also loaded.
 */
- (void)testRemovingAPlugInTakesTheFileWithIt
{
    NSURL *products = [NSBundle mainBundle].bundleURL
        .URLByDeletingLastPathComponent;
    NSURL *source = [products URLByAppendingPathComponent:@"Drawio.plugin"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:source.path])
    {
        XCTSkip("Drawio.plugin non è stato costruito");
        return;
    }

    NSURL *copy = [self.scratch URLByAppendingPathComponent:@"Drawio.plugin"];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtURL:source
                                                          toURL:copy
                                                          error:&error],
                  @"%@", error);

    MPPlugIn *plugin = [[MPPlugIn alloc]
        initWithBundle:[NSBundle bundleWithURL:copy]];
    XCTAssertNotNil(plugin);
    XCTAssertFalse(plugin.isBuiltIn, @"una copia in una cartella temporanea "
                   @"non è in dotazione");

    MPPlugInsWindowController *manager =
        [MPPlugInsWindowController sharedController];
    XCTAssertTrue([manager trashPlugIn:plugin error:&error], @"%@", error);
    XCTAssertFalse([[NSFileManager defaultManager]
        fileExistsAtPath:copy.path], @"il file è rimasto dov'era");

    // And it is no longer among what would be loaded.
    XCTAssertEqualObjects(MPPlugInBundleURLsInFolders(@[self.scratch]), @[]);

    // What it says when there is nothing to remove, rather than saying
    // nothing and leaving the row where it was.
    MPPlugIn *nowhere = [[MPPlugIn alloc]
        initWithBundle:[NSBundle bundleWithURL:copy]];
    error = nil;
    XCTAssertFalse([manager trashPlugIn:nowhere error:&error]);
    XCTAssertGreaterThan(error.localizedDescription.length, 0u);
}

@end
