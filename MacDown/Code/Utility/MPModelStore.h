//
//  MPModelStore.h
//  MacDown
//

#import <Foundation/Foundation.h>

/// One model file on disk, and what can be said about it without opening it.
@interface MPModelFile : NSObject
@property (readonly, copy, nonatomic) NSURL *url;
/// The file name without its extension, which is what a reader chose it by.
@property (readonly, copy, nonatomic) NSString *name;
@property (readonly, assign, nonatomic) unsigned long long byteSize;
@end


/** The models installed on this Mac, and where they go.
 *
 * The reading half. Downloading is the panel's business and comes after,
 * but where the files live is decided here so that both halves agree — and
 * so the writing commands can find a model that was put there by hand,
 * which is how anybody trying this out will do it first.
 */
@interface MPModelStore : NSObject

+ (instancetype)sharedStore;

/// `~/Library/Application Support/MacDown/Models`, made if it is not there.
@property (readonly, copy, nonatomic) NSURL *directory;

/// Every `.gguf` in the folder, by name. Empty when there are none.
@property (readonly, copy, nonatomic) NSArray<MPModelFile *> *installedModels;

/** The one the writing commands should use.
 *
 * Whichever was chosen, if it is still there; otherwise the first
 * installed, so that dropping a single file into the folder is enough to
 * get going and nothing has to be chosen at all.
 */
@property (strong, nonatomic) MPModelFile *selectedModel;

/// Removes a model from disk. NO, with `error` set, if it will not go.
- (BOOL)removeModel:(MPModelFile *)model error:(NSError **)error;

@end
