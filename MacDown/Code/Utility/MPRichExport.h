//
//  MPRichExport.h
//  MacDown
//
//  What AppKit's OpenDocument and RTF writers leave out.
//

#import <Cocoa/Cocoa.h>

#import "MPDocxPostProcessing.h"


/// The two formats that share the export path but not the last step.
typedef NS_ENUM(NSUInteger, MPRichExportKind) {
    MPRichExportOpenDocument,
    MPRichExportRTF,
};


/** Plants PNGs into an .odt that AppKit produced.
 *
 * Measured on its output: tables and character styling survive, and every
 * picture is dropped — the same hole its Word writer has, and for the same
 * reason. Each placeholder run is swapped for a `draw:frame`, the pictures
 * are added to the archive under `Pictures/`, and the manifest is told about
 * them, because a file the manifest does not list is a file the reader
 * refuses to show.
 *
 * Pictures whose marker is not in the document have their `source` added to
 * `unplaced`, if one is given: a picture that could not be placed is a
 * picture missing from somebody's document, and the name says which.
 *
 * Returns the input unchanged when there is nothing to plant, and nil when
 * the archive cannot be read.
 */
NSData *MPOdtDataByEmbeddingImages(NSData *odtData,
                                   NSArray<MPDocxImage *> *images,
                                   NSMutableArray<NSString *> *unplaced);


/** Plants PNGs into RTF that AppKit produced.
 *
 * RTF carries pictures perfectly well — `\pict` with `\pngblip` and the
 * bytes in hexadecimal — but Cocoa only writes them into RTFD, where they
 * become files beside the text. Here each placeholder becomes the picture
 * itself, so a single .rtf travels whole.
 *
 * Returns the input unchanged when there is nothing to plant.
 */
NSData *MPRtfDataByEmbeddingImages(NSData *rtfData,
                                   NSArray<MPDocxImage *> *images,
                                   NSMutableArray<NSString *> *unplaced);
