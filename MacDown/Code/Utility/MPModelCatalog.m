//
//  MPModelCatalog.m
//  MacDown
//

#import "MPModelCatalog.h"

@implementation MPModelListing

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
    self = [super init];
    if (!self)
        return nil;

    NSString *address = dictionary[@"url"];
    _name = [dictionary[@"name"] copy];
    _fileName = [dictionary[@"file"] copy];
    _url = address.length ? [NSURL URLWithString:address] : nil;
    _byteSize = [dictionary[@"bytes"] unsignedLongLongValue];
    _parameters = [dictionary[@"parameters"] copy];
    _quantisation = [dictionary[@"quantisation"] copy];
    _recommended = [dictionary[@"recommended"] boolValue];
    _note = [dictionary[@"note"] copy];

    // Anything without these cannot be offered: a listing with no address
    // is a button that does nothing, and one with no size is a download
    // with no end in sight.
    if (!_name.length || !_fileName.length || !_url || !_byteSize)
        return nil;
    return self;
}

- (NSString *)readableSize
{
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    return [formatter stringFromByteCount:(long long)self.byteSize];
}

@end


@implementation MPModelCatalog

+ (instancetype)sharedCatalog
{
    static MPModelCatalog *catalog = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        catalog = [[MPModelCatalog alloc] init];
    });
    return catalog;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    NSURL *url = [[NSBundle mainBundle] URLForResource:@"models"
                                         withExtension:@"json"
                                          subdirectory:@"Data"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    NSDictionary *parsed = data
        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]
        : nil;

    NSMutableArray<MPModelListing *> *listings = [NSMutableArray array];
    for (NSDictionary *entry in parsed[@"models"])
    {
        if (![entry isKindOfClass:[NSDictionary class]])
            continue;
        MPModelListing *listing =
            [[MPModelListing alloc] initWithDictionary:entry];
        if (listing)
            [listings addObject:listing];
    }
    _listings = listings;
    return self;
}

- (MPModelListing *)recommendedListing
{
    for (MPModelListing *listing in self.listings)
    {
        if (listing.recommended)
            return listing;
    }
    return self.listings.firstObject;
}

@end
