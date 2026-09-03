//
//  MPModelCatalogTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPModelCatalog.h"
#import "MPModelDownloader.h"
#import "MPModelStore.h"

@interface MPModelCatalogTests : XCTestCase
@end

@implementation MPModelCatalogTests

- (void)testTheCatalogueLoads
{
    NSArray<MPModelListing *> *listings =
        [MPModelCatalog sharedCatalog].listings;
    XCTAssertTrue(listings.count >= 4, @"%lu voci",
                  (unsigned long)listings.count);
}

/** Every listing has to be usable, and the sizes have to be real.
 *
 * A listing with no address is a button that does nothing; one with no
 * size is a progress bar that lies and a disk-space check that passes
 * when it should not have. Both are dropped on being read, so what comes
 * back is what can be offered.
 */
- (void)testEveryListingIsComplete
{
    for (MPModelListing *listing in [MPModelCatalog sharedCatalog].listings)
    {
        XCTAssertTrue(listing.name.length > 0);
        XCTAssertTrue([listing.fileName.pathExtension.lowercaseString
            isEqualToString:@"gguf"], @"%@", listing.name);
        XCTAssertEqualObjects(listing.url.scheme, @"https", @"%@",
                              listing.name);
        XCTAssertTrue(listing.byteSize > 100 * 1024 * 1024,
                      @"%@ dichiara %llu byte", listing.name,
                      listing.byteSize);
        XCTAssertTrue(listing.note.length > 20,
                      @"%@ non dice niente di sé", listing.name);
        XCTAssertTrue(listing.readableSize.length > 0);
    }
}

/// Exactly one is put forward, or a reader has to choose blind.
- (void)testExactlyOneIsRecommended
{
    NSUInteger recommended = 0;
    for (MPModelListing *listing in [MPModelCatalog sharedCatalog].listings)
        if (listing.recommended)
            recommended++;
    XCTAssertEqual(recommended, (NSUInteger)1);
    XCTAssertNotNil([MPModelCatalog sharedCatalog].recommendedListing);
}

/// The names are what a menu and a folder are keyed by: no two the same.
- (void)testNoTwoListingsCollide
{
    NSMutableSet *names = [NSMutableSet set];
    NSMutableSet *files = [NSMutableSet set];
    for (MPModelListing *listing in [MPModelCatalog sharedCatalog].listings)
    {
        XCTAssertFalse([names containsObject:listing.name], @"%@",
                       listing.name);
        XCTAssertFalse([files containsObject:listing.fileName], @"%@",
                       listing.fileName);
        [names addObject:listing.name];
        [files addObject:listing.fileName];
    }
}

/// A listing missing what it needs is refused rather than half-offered.
- (void)testTheModelsFolderIsThere
{
    NSURL *folder = [MPModelStore sharedStore].directory;
    BOOL directory = NO;
    XCTAssertTrue([[NSFileManager defaultManager]
        fileExistsAtPath:folder.path isDirectory:&directory]);
    XCTAssertTrue(directory);
    XCTAssertEqualObjects(folder.lastPathComponent, @"Models");
}

/// Nothing is downloading, so nothing is claimed to be.
- (void)testTheDownloaderStartsIdle
{
    MPModelDownloader *downloader = [MPModelDownloader sharedDownloader];
    XCTAssertNil(downloader.current);
    XCTAssertEqual(downloader.fractionCompleted, 0.0);
    XCTAssertFalse([downloader hasResumableDownloadForListing:
        [MPModelCatalog sharedCatalog].recommendedListing]);
}

/// A size no disk could hold is refused before anything is fetched.
- (void)testADownloadTooBigForTheDiskIsRefused
{
    NSDictionary *absurd = @{
        @"name": @"Troppo grande",
        @"file": @"troppo.gguf",
        @"url": @"https://esempio.it/troppo.gguf",
        @"bytes": @(900ULL * 1024 * 1024 * 1024),   // 900 GB
        @"parameters": @"—", @"quantisation": @"—",
        @"note": @"Serve solo a far dire no al controllo dello spazio.",
    };
    MPModelListing *listing =
        [[MPModelListing alloc] initWithDictionary:absurd];
    XCTAssertNotNil(listing);

    NSError *error = nil;
    XCTAssertFalse([[MPModelDownloader sharedDownloader]
        startDownloadOfListing:listing error:&error]);
    XCTAssertEqual(error.code, MPModelDownloaderErrorNoRoom);
    // The code, and that something was said — not the words. This asserted
    // the English "room" and failed the day the message was translated,
    // which is the test being wrong rather than the message.
    XCTAssertTrue(error.localizedDescription.length > 20,
                  @"%@", error.localizedDescription);
    XCTAssertNotEqual([error.localizedDescription
        rangeOfString:@"966" options:0].location, (NSUInteger)NSNotFound,
        @"la dimensione chiesta deve comparire: %@",
        error.localizedDescription);
}

/// What cannot be offered is refused on being read, not half-shown.
- (void)testAnIncompleteListingIsRefused
{
    NSDictionary *complete = @{
        @"name": @"Va bene", @"file": @"ok.gguf",
        @"url": @"https://esempio.it/ok.gguf", @"bytes": @(2000000000),
    };
    XCTAssertNotNil([[MPModelListing alloc] initWithDictionary:complete]);

    for (NSString *missing in @[@"name", @"file", @"url", @"bytes"])
    {
        NSMutableDictionary *broken = [complete mutableCopy];
        [broken removeObjectForKey:missing];
        XCTAssertNil([[MPModelListing alloc] initWithDictionary:broken],
                     @"senza «%@» non si può offrire", missing);
    }
}

#pragma mark - An address somebody pasted

/// The page address and the file address are one word apart.
- (void)testAHuggingFacePageAddressBecomesTheFile
{
    NSURL *url = [MPModelCatalog downloadableURLFromPastedText:
        @"https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/blob/main/"
        @"qwen2.5-3b-instruct-q4_k_m.gguf"];
    XCTAssertEqualObjects(url.absoluteString,
        @"https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/"
        @"qwen2.5-3b-instruct-q4_k_m.gguf",
        @"con /blob/ il server manda una pagina, non il modello");
}

- (void)testAFileAddressIsLeftAsItIs
{
    NSString *good = @"https://esempio.it/modelli/m-Q4_K_M.gguf";
    XCTAssertEqualObjects(
        [MPModelCatalog downloadableURLFromPastedText:good].absoluteString,
        good);
}

/// Spaces around it are what a paste brings, not what a reader meant.
- (void)testItIsTrimmed
{
    XCTAssertNotNil([MPModelCatalog downloadableURLFromPastedText:
        @"  https://esempio.it/m.gguf\n"]);
}

/** What is refused, and refused before two gigabytes move.
 *
 * A wrong address that is only found out at the end costs a download; the
 * magic-number check would catch it, and saying so first is cheaper.
 */
- (void)testWhatIsNotAModelAddressIsRefused
{
    NSArray<NSString *> *bad = @[
        @"",
        @"   ",
        @"https://esempio.it/pagina",          // nessuna estensione
        @"https://esempio.it/modello.bin",     // non gguf
        @"ftp://esempio.it/m.gguf",            // non http
        @"file:///Users/x/m.gguf",             // non è uno scaricamento
        @"m.gguf",                             // nessuno schema
        @"parole qualsiasi",
    ];
    for (NSString *text in bad)
    {
        XCTAssertNil([MPModelCatalog downloadableURLFromPastedText:text],
                     @"«%@» non doveva passare", text);
    }
}

/// The name it will be saved under, unescaped, because a folder is not a URL.
- (void)testTheFileNameComesOffTheAddress
{
    XCTAssertEqualObjects([MPModelCatalog fileNameFromPastedText:
        @"https://esempio.it/a/b/Modello-Q4_K_M.gguf"],
        @"Modello-Q4_K_M.gguf");
    XCTAssertEqualObjects([MPModelCatalog fileNameFromPastedText:
        @"https://esempio.it/a/Modello%20con%20spazi.gguf"],
        @"Modello con spazi.gguf");
    XCTAssertNil([MPModelCatalog fileNameFromPastedText:@"niente"]);
}

@end
