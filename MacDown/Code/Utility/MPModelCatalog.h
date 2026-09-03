//
//  MPModelCatalog.h
//  MacDown
//

#import <Foundation/Foundation.h>

/// One model that can be fetched, as the bundled list describes it.
@interface MPModelListing : NSObject
@property (readonly, copy, nonatomic) NSString *name;
/// The file name it is saved under, which is also how it is recognised later.
@property (readonly, copy, nonatomic) NSString *fileName;
@property (readonly, copy, nonatomic) NSURL *url;
@property (readonly, assign, nonatomic) unsigned long long byteSize;
@property (readonly, copy, nonatomic) NSString *parameters;
@property (readonly, copy, nonatomic) NSString *quantisation;
@property (readonly, assign, nonatomic) BOOL recommended;
/// What is true about it that a reader could not guess from its size.
@property (readonly, copy, nonatomic) NSString *note;

/// "2,1 GB", in the reader's own idiom.
@property (readonly, copy, nonatomic) NSString *readableSize;

/** One entry of the list. Nil if it lacks what it needs to be offered.
 *
 * Declared here rather than kept private because it is how a listing is
 * made, and because the refusing is worth a test of its own: a listing
 * with no address is a button that does nothing.
 */
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end


/** The models the panel offers to fetch.
 *
 * A list that ships with the application rather than one fetched from
 * anywhere: it is four addresses, and an application that phones a server
 * of mine to find out what it may download is an application with a
 * dependency it does not need and a way to break that nobody can fix.
 *
 * The sizes in it were checked against the servers. A wrong one is a
 * progress bar that lies and a disk-space check that passes when it should
 * not have.
 */
@interface MPModelCatalog : NSObject

+ (instancetype)sharedCatalog;

@property (readonly, copy, nonatomic) NSArray<MPModelListing *> *listings;

/// The one to offer first, or nil if the list is somehow empty.
@property (readonly, nonatomic) MPModelListing *recommendedListing;

@end
