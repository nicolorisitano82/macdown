//
//  update_feed.m
//  MacDown
//
//  Reads GitHub's answer about the latest release the way the application
//  reads it, and prints what it made of it. So that a check can see whether
//  the live feed still says what the parser expects, without going through
//  the panel that asks about it.
//
//  Used by Tools/verify_features.sh. Build:
//
//      clang -fobjc-arc -framework Cocoa -IMacDown/Code/Utility \
//            -o update_feed Tools/update_feed.m \
//            MacDown/Code/Utility/MPUpdate.m
//
//  Usage: update_feed <feed.json> [running version]
//
//  Prints one line — version, disk image, size — and, when a running
//  version is given, whether that release would be offered.
//

#import <Foundation/Foundation.h>

#import "MPUpdate.h"


int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 2)
        {
            fputs("usage: update_feed <feed.json> [running version]\n", stderr);
            return 2;
        }

        NSData *json = [NSData dataWithContentsOfFile:@(argv[1])];
        if (!json)
        {
            fprintf(stderr, "non si legge: %s\n", argv[1]);
            return 1;
        }

        MPRelease *release = MPReleaseFromFeed(json);
        if (!release)
        {
            fputs("nessun rilascio con un'immagine disco\n", stderr);
            return 1;
        }

        printf("%s\t%s\t%lld\n", release.version.UTF8String,
               release.diskImageURL.absoluteString.UTF8String, release.size);
        if (argc > 2)
        {
            printf("%s\n", MPUpdateIsNewer(release, @(argv[2]))
                   ? "offerto" : "niente da offrire");
        }
    }
    return 0;
}
