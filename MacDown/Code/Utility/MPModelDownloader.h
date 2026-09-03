//
//  MPModelDownloader.h
//  MacDown
//

#import <Foundation/Foundation.h>
#import "MPModelCatalog.h"

extern NSString * const MPModelDownloaderErrorDomain;

typedef NS_ENUM(NSInteger, MPModelDownloaderError) {
    MPModelDownloaderErrorBusy = 1,
    MPModelDownloaderErrorNoRoom,
    MPModelDownloaderErrorTruncated,
    MPModelDownloaderErrorNotAModel,
    MPModelDownloaderErrorInstallFailed,
};

/// Posted as the bytes arrive, and when one finishes or fails.
extern NSString * const MPModelDownloaderProgressNotification;
extern NSString * const MPModelDownloaderFinishedNotification;
/// The error, in the finished notification's userInfo. Absent on success.
extern NSString * const MPModelDownloaderErrorKey;


/** Fetches a model into the folder the application reads models from.
 *
 * One at a time. Two gigabytes and two gigabytes at once is slower than
 * one after the other, and a panel showing two bars is a panel explaining
 * something nobody asked for.
 *
 * What arrives is checked before it is installed: a file that stops short,
 * or a page of HTML that a server sent instead of the model, would
 * otherwise be installed as a model and fail later — at load time, in a
 * place with nothing useful to say about it.
 */
@interface MPModelDownloader : NSObject

+ (instancetype)sharedDownloader;

/// What is being fetched, or nil.
@property (readonly, strong, nonatomic) MPModelListing *current;

/// 0 to 1, or 0 when nothing is being fetched.
@property (readonly, assign, nonatomic) double fractionCompleted;
@property (readonly, assign, nonatomic) unsigned long long bytesReceived;

/** Starts fetching `listing`. NO, with `error`, if it will not start.
 *
 * Refuses when another is in flight, and when the disk has not the room —
 * checked before rather than discovered at ninety per cent.
 */
- (BOOL)startDownloadOfListing:(MPModelListing *)listing
                         error:(NSError **)error;

/// Stops the one in flight. What has arrived is kept, to resume from.
- (void)cancel;

/// Whether a half-finished download of this model is waiting to resume.
- (BOOL)hasResumableDownloadForListing:(MPModelListing *)listing;

@end
