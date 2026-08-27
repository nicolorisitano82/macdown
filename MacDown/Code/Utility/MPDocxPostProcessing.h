//
//  MPDocxPostProcessing.h
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


/** A stretch of cell text sharing one set of run properties. */
@interface MPDocxTextRun : NSObject
@property (copy, nonatomic) NSString *text;
@property (assign, nonatomic) BOOL bold;
@property (assign, nonatomic) BOOL italic;
@property (assign, nonatomic) BOOL monospaced;
@end


@interface MPDocxTableCell : NSObject
@property (copy, nonatomic) NSArray<MPDocxTextRun *> *runs;
/// "left", "center" or "right"; nil to leave it to the paragraph default.
@property (copy, nonatomic) NSString *alignment;
@property (assign, nonatomic) BOOL header;
@end


@interface MPDocxTable : NSObject
@property (copy, nonatomic) NSString *placeholder;
@property (copy, nonatomic) NSArray<NSArray<MPDocxTableCell *> *> *rows;
@end


/** Builds real tables in a .docx, in place of text markers.
 *
 * AppKit's Word writer emits no w:tbl at all: a table reaches the file as a
 * run of paragraphs separated by tab stops, which is why the columns come out
 * scattered down the page. Nothing can be recovered from that after the fact,
 * so the structure is parsed from the HTML beforehand and the table is built
 * here from scratch, borders and header row included.
 *
 * Returns the input unchanged when there is nothing to build, and nil if the
 * archive cannot be read.
 */
NSData *MPDocxDataByBuildingTables(NSData *docxData,
                                   NSArray<MPDocxTable *> *tables,
                                   NSString *bodyFamily,
                                   NSString *monospaceFamily,
                                   CGFloat pointSize);


/** Declares the document's fonts in word/fontTable.xml.
 *
 * AppKit writes no font table, so the file names Menlo and nothing else: no
 * pitch, no family, no alternative. On a machine without Menlo — every
 * Windows one — Word has nothing to substitute from and falls back to a
 * proportional face, which is how a code block stops looking like code.
 *
 * Declaring the fonts as fixed pitch, with an alternative that does ship on
 * Windows, keeps a code block monospaced away from a Mac.
 *
 * Returns the input unchanged if the archive already has a font table, and
 * nil if it cannot be read.
 */
NSData *MPDocxDataByDeclaringFonts(NSData *docxData,
                                   NSString *monospaceFamily,
                                   NSString *monospaceAlternative,
                                   NSString *bodyFamily,
                                   NSString *bodyAlternative);
