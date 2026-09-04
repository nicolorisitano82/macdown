//
//  MPUpdate.h
//  MacDown
//

#import <Cocoa/Cocoa.h>


/// A release of MacDown Next, as its own repository describes it.
@interface MPRelease : NSObject

/// The version, without the "v" the tag carries: "0.22.0".
@property (readonly, copy, nonatomic) NSString *version;
/// What the release is called, which is a sentence rather than a number.
@property (readonly, copy, nonatomic) NSString *title;
/// The release notes, as Markdown.
@property (readonly, copy, nonatomic) NSString *notes;
/// The page to read them on.
@property (readonly, copy, nonatomic) NSURL *pageURL;
/// The disk image to download.
@property (readonly, copy, nonatomic) NSURL *diskImageURL;
/// How big it is, so the question can say so before the answer costs.
@property (readonly, nonatomic) long long size;

@end


/// Asks the repository what the latest release is.
@interface MPUpdateCheck : NSObject

/// The answer, or an error. The completion runs on the main queue.
+ (void)latestReleaseWithCompletion:(void (^)(MPRelease *release,
                                              NSError *error))completion;
@end


#pragma mark - The parts worth checking on their own

/// Which of two versions is the later one.
///
/// Understands the shapes this project produces: a tag (`v0.22.0`), a
/// release (`0.22.0`), and a build between two releases (`0.22.0d7`, seven
/// commits into what will become 0.22.0 — so *older* than 0.22.0 itself).
extern NSComparisonResult MPCompareVersions(NSString *one, NSString *other);

/// The release GitHub's answer describes, or nil when it describes none.
extern MPRelease *MPReleaseFromFeed(NSData *json);

/// Whether a release is worth telling somebody who is running `running`.
extern BOOL MPUpdateIsNewer(MPRelease *release, NSString *running);

/// Whether enough time has passed to look again. A day.
extern BOOL MPUpdateIsDue(NSDate *lastCheck, NSDate *now);

/// Where a download goes, and under what name when that one is taken.
extern NSURL *MPDownloadsFolder(void);
extern NSURL *MPFreeFileInFolder(NSURL *folder, NSString *name);

/// How far along a download is: -1 while the size is unknown.
extern double MPProgressFraction(long long received, long long total);

/// Whether an address is one of ours to download from.
///
/// The list of releases comes from GitHub over HTTPS, and so must the file
/// it points at: a feed that has been tampered with should not be able to
/// send the application off to fetch something from somewhere else.
extern BOOL MPIsTrustedDownload(NSURL *url);


#pragma mark - Fetching it

/// A download in progress, which can be watched and called off.
@interface MPUpdateDownload : NSObject

/// Where the file ended up, once it has.
@property (readonly, copy, nonatomic) NSURL *fileURL;
/// Whether it is still going.
@property (readonly, nonatomic, getter=isRunning) BOOL running;

- (instancetype)initWithRelease:(MPRelease *)release;

/// Both blocks run on the main queue; `progress` reports a fraction of one,
/// or -1 while the size is unknown.
- (void)startWithProgress:(void (^)(double fraction, long long received,
                                    long long total))progress
               completion:(void (^)(NSURL *file, NSError *error))completion;

/// Stops it. The completion is called with an error saying who stopped it.
- (void)cancel;

@end
