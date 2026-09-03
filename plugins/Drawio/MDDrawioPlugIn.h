//
//  MDDrawioPlugIn.h
//  MacDown Next — draw.io plug-in
//

#import <Cocoa/Cocoa.h>


/** Brings a draw.io diagram into the document as a picture.
 *
 * A `.drawio` file is XML that only draw.io can draw, so a Markdown
 * document cannot link one and show anything. This picks the file, draws
 * every page it holds, writes the PNGs beside the document and links them —
 * which is the whole of what one wants from "import this diagram".
 */
@interface MDDrawioPlugIn : NSObject

- (NSString *)name;
- (BOOL)run:(id)sender;

@end


/** What the pictures are called, and how they are linked.
 *
 * Apart from the command because the command needs a window, a document
 * and a person at the keyboard, and these two answers need none of that
 * and are the ones with an off-by-one in them.
 */
@interface MDDrawioNaming : NSObject

/// A page name turned into something that can be a file name.
+ (NSString *)fileNameSlugOf:(NSString *)name;

/** What goes in the parentheses of the link.
 *
 * Relative when the picture sits under the document's folder, so the two
 * keep working when they are moved together; escaped either way, since a
 * space in a path is not a space in a link.
 */
+ (NSString *)linkTargetForFile:(NSURL *)file
                 besideDocument:(NSURL *)document;

@end
