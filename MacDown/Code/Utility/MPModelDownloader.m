//
//  MPModelDownloader.m
//  MacDown
//

#import "MPModelDownloader.h"
#import "MPModelStore.h"

NSString * const MPModelDownloaderErrorDomain =
    @"MPModelDownloaderErrorDomain";
NSString * const MPModelDownloaderProgressNotification =
    @"MPModelDownloaderProgressNotification";
NSString * const MPModelDownloaderFinishedNotification =
    @"MPModelDownloaderFinishedNotification";
NSString * const MPModelDownloaderErrorKey = @"error";

/// Room asked for beyond the file itself, so the disk is not left at zero.
static const unsigned long long kMPModelDownloadHeadroom = 512ULL * 1024 * 1024;


NS_INLINE NSError *MPDownloaderError(MPModelDownloaderError code,
                                     NSString *description)
{
    return [NSError errorWithDomain:MPModelDownloaderErrorDomain code:code
        userInfo:@{NSLocalizedDescriptionKey: description}];
}


@interface MPModelDownloader () <NSURLSessionDownloadDelegate>
@property (strong, nonatomic) NSURLSession *session;
@property (strong, nonatomic) NSURLSessionDownloadTask *task;
@property (strong, nonatomic) MPModelListing *current;
@property (assign, nonatomic) double fractionCompleted;
@property (assign, nonatomic) unsigned long long bytesReceived;
/// Where a cancelled download's bytes wait, by file name.
@property (strong, nonatomic) NSMutableDictionary<NSString *, NSData *> *resumeData;
@end


@implementation MPModelDownloader

+ (instancetype)sharedDownloader
{
    static MPModelDownloader *downloader = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        downloader = [[MPModelDownloader alloc] init];
    });
    return downloader;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    // No cache: the file goes to disk once, and a copy of two gigabytes in
    // the URL cache would be two gigabytes nobody asked for.
    configuration.URLCache = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    _session = [NSURLSession sessionWithConfiguration:configuration
                                             delegate:self
                                        delegateQueue:nil];
    _resumeData = [NSMutableDictionary dictionary];
    return self;
}


#pragma mark - Starting and stopping

- (BOOL)hasResumableDownloadForListing:(MPModelListing *)listing
{
    return self.resumeData[listing.fileName] != nil;
}

/// Whether the volume holding the models folder has room for `bytes`.
- (BOOL)hasRoomFor:(unsigned long long)bytes
{
    NSURL *folder = [MPModelStore sharedStore].directory;
    NSNumber *available = nil;
    [folder getResourceValue:&available
                      forKey:NSURLVolumeAvailableCapacityForImportantUsageKey
                       error:NULL];
    if (!available)
        return YES;     // Cannot tell: better to try than to refuse blindly.
    return available.unsignedLongLongValue > bytes + kMPModelDownloadHeadroom;
}

- (BOOL)startDownloadOfListing:(MPModelListing *)listing
                         error:(NSError **)error
{
    if (!listing)
        return NO;

    if (self.task)
    {
        if (error)
        {
            *error = MPDownloaderError(MPModelDownloaderErrorBusy,
                NSLocalizedString(@"Another model is being downloaded. One "
                                  @"at a time is faster than two.",
                                  @"Model download failure"));
        }
        return NO;
    }

    if (![self hasRoomFor:listing.byteSize])
    {
        if (error)
        {
            *error = MPDownloaderError(MPModelDownloaderErrorNoRoom,
                [NSString stringWithFormat:NSLocalizedString(
                    @"There is not enough room on the disk for %@ plus the "
                    @"space the system needs to keep working.",
                    @"Model download failure"), listing.readableSize]);
        }
        return NO;
    }

    self.current = listing;
    self.fractionCompleted = 0.0;
    self.bytesReceived = 0;

    // Where it left off, if it was stopped part way.
    NSData *resume = self.resumeData[listing.fileName];
    if (resume)
    {
        [self.resumeData removeObjectForKey:listing.fileName];
        self.task = [self.session downloadTaskWithResumeData:resume];
    }
    else
    {
        self.task = [self.session downloadTaskWithURL:listing.url];
    }
    [self.task resume];
    return YES;
}

- (void)cancel
{
    NSURLSessionDownloadTask *task = self.task;
    if (!task)
        return;

    NSString *name = self.current.fileName;
    __weak MPModelDownloader *weakSelf = self;
    [task cancelByProducingResumeData:^(NSData *resume) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MPModelDownloader *downloader = weakSelf;
            if (resume && name)
                downloader.resumeData[name] = resume;
            [downloader finishWithError:nil];
        });
    }];
    self.task = nil;
}

- (void)finishWithError:(NSError *)error
{
    self.task = nil;
    self.current = nil;
    self.fractionCompleted = 0.0;
    self.bytesReceived = 0;

    NSDictionary *info = error ? @{MPModelDownloaderErrorKey: error} : @{};
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MPModelDownloaderFinishedNotification
                      object:self userInfo:info];
}


#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)written
 totalBytesWritten:(int64_t)total
totalBytesExpectedToWrite:(int64_t)expected
{
    // The listing's size, not the server's: a redirect can answer without a
    // length, and a bar that jumps to full and stays there is worse than a
    // bar that moves slowly.
    unsigned long long size = self.current.byteSize;
    if (expected > 0)
        size = (unsigned long long)expected;

    dispatch_async(dispatch_get_main_queue(), ^{
        self.bytesReceived = (unsigned long long)total;
        self.fractionCompleted = size ? (double)total / (double)size : 0.0;
        [[NSNotificationCenter defaultCenter]
            postNotificationName:MPModelDownloaderProgressNotification
                          object:self];
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
didFinishDownloadingToURL:(NSURL *)location
{
    MPModelListing *listing = self.current;
    NSInteger status = 200;
    if ([task.response isKindOfClass:[NSHTTPURLResponse class]])
        status = [(NSHTTPURLResponse *)task.response statusCode];

    // The temporary file is deleted the moment this returns, so everything
    // that has to look at it happens here and not on another queue.
    NSError *failure = nil;
    if (status < 200 || status >= 300)
    {
        failure = MPDownloaderError(MPModelDownloaderErrorTruncated,
            [NSString stringWithFormat:NSLocalizedString(
                @"The server answered %ld instead of sending the file.",
                @"Model download failure"), (long)status]);
    }
    else
    {
        failure = [self installFileAt:location forListing:listing];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self finishWithError:failure];
    });
}

/** Checks what arrived and puts it in place. Returns nil when it worked.
 *
 * Two checks, both for the same reason: what is wrong should be said here,
 * while there is something useful to say, rather than at load time when all
 * anybody knows is that a model will not open.
 */
- (NSError *)installFileAt:(NSURL *)location
                forListing:(MPModelListing *)listing
{
    NSFileManager *files = [NSFileManager defaultManager];

    NSNumber *size = nil;
    [location getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    unsigned long long arrived = size.unsignedLongLongValue;

    // Short of what the list says: the download stopped part way, or the
    // file on the server is not the file the list was written against.
    if (listing.byteSize && arrived < listing.byteSize)
    {
        NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
        return MPDownloaderError(MPModelDownloaderErrorTruncated,
            [NSString stringWithFormat:NSLocalizedString(
                @"Only %@ of %@ arrived. Try again: what came down is kept "
                @"and the download carries on from there.",
                @"Model download failure"),
                [formatter stringFromByteCount:(long long)arrived],
                listing.readableSize]);
    }

    // GGUF, and not a page of HTML a server sent in its place.
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:location
                                                              error:NULL];
    NSData *magic = [handle readDataUpToLength:4 error:NULL];
    [handle closeAndReturnError:NULL];
    if (magic.length != 4 || memcmp(magic.bytes, "GGUF", 4) != 0)
    {
        return MPDownloaderError(MPModelDownloaderErrorNotAModel,
            NSLocalizedString(@"What arrived is not a model file. The address "
                              @"may have moved.",
                              @"Model download failure"));
    }

    NSURL *destination = [[MPModelStore sharedStore].directory
        URLByAppendingPathComponent:listing.fileName];
    [files removeItemAtURL:destination error:NULL];

    NSError *error = nil;
    if (![files moveItemAtURL:location toURL:destination error:&error])
    {
        return MPDownloaderError(MPModelDownloaderErrorInstallFailed,
            error.localizedDescription
                ?: NSLocalizedString(@"The file could not be moved into the "
                                     @"Models folder.",
                                     @"Model download failure"));
    }
    return nil;
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    // Cancelling comes through here too, and has already been dealt with.
    if (!error || error.code == NSURLErrorCancelled)
        return;

    // The bytes so far, kept for a second attempt.
    NSData *resume = error.userInfo[NSURLSessionDownloadTaskResumeData];
    NSString *name = self.current.fileName;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (resume && name)
            self.resumeData[name] = resume;
        [self finishWithError:error];
    });
}

@end
