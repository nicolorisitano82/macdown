//
//  MPDocumentTemplate.h
//  MacDown
//

#import <Foundation/Foundation.h>

/** A skeleton document, written by hand and inserted as it is.
 *
 * Not generated. Asked for a commissioning report, the model produced a
 * table headed "Causi di prova" and five rows with no columns for what was
 * expected or what was found — measured, not supposed. A structure has one
 * right shape and a model guesses at it every time, so the shapes are
 * written out once and kept as files.
 *
 * Which means they are also instant, deterministic, translatable, and
 * available with no model installed at all. The model's part comes after:
 * filling and adapting what is already the right shape.
 */
@interface MPDocumentTemplate : NSObject

/// The file name without its extension. What the menu says.
@property (readonly, copy, nonatomic) NSString *name;
@property (readonly, copy, nonatomic) NSURL *url;
/// True for one the reader put in their own folder, not one that shipped.
@property (readonly, assign, nonatomic) BOOL isCustom;

/// The Markdown itself, read when it is asked for. Nil if it will not read.
- (NSString *)markdown;

/** Everything installed, by name: those in the bundle, then the reader's.
 *
 * A file in the reader's folder with the same name as one of ours replaces
 * it, which is how the ones that ship can be adjusted without being
 * fought with on every update.
 */
+ (NSArray<MPDocumentTemplate *> *)installedTemplates;

/// `~/Library/Application Support/MacDown/Templates`, made if absent.
+ (NSURL *)customDirectory;

@end
