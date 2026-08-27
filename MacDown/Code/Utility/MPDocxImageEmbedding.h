//
//  MPDocxImageEmbedding.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

/** One picture to be planted in a .docx, in place of a text marker.
 *
 * `pointSize` is the size the picture should occupy on the page, which is
 * independent of the pixel dimensions of `pngData`: rasterising above 1:1 and
 * declaring the smaller point size is what keeps a diagram sharp in print.
 */
@interface MPDocxImage : NSObject

@property (copy, nonatomic) NSString *placeholder;
@property (copy, nonatomic) NSData *pngData;
@property (assign, nonatomic) NSSize pointSize;

@end


/** Plants PNGs into a .docx that AppKit produced.
 *
 * AppKit reads images fine — they arrive as text attachments — but every one
 * of its writers except rtfd discards them, so a .docx it produces has no
 * word/media part, no image relationship and no png content type. This adds
 * all three, and swaps each placeholder run for a DrawingML picture.
 *
 * Returns the input unchanged when there is nothing to plant, and nil if the
 * archive cannot be read.
 */
NSData *MPDocxDataByEmbeddingImages(NSData *docxData,
                                    NSArray<MPDocxImage *> *images);


/** Repairs what AppKit's Word writer leaves out of the layout.
 *
 * Two things it drops, measured on its output: background-color never
 * becomes a `w:shd` shading element, so code blocks lose the plate that
 * separates them from prose; and list items come out with a 720 twip hanging
 * indent, which puts half an inch of air between the bullet and its text.
 *
 * Shading is applied to paragraphs set in the monospace family the Word
 * stylesheet reserves for code, which is what identifies them once the
 * markup is gone.
 *
 * Returns the input unchanged if there is nothing to repair, nil if the
 * archive cannot be read.
 */
NSData *MPDocxDataByRepairingLayout(NSData *docxData,
                                    NSString *monospaceFamily,
                                    NSString *codeShadingHex);
