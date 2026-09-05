//
//  MPExporterPlugIn.h
//  MacDown
//
//  What a plug-in adopts to add a format to File ▸ Export.
//

#import <Foundation/Foundation.h>


/** A plug-in that turns a document into a file of some other kind.
 *
 * The plug-ins menu lists commands — things a reader picks to make something
 * happen now. An exporter is not one of those: it is a format, and it
 * belongs where the other formats are. So a plug-in that adopts this
 * protocol **does not appear in the plug-ins menu at all**; it appears in
 * **File ▸ Export**, under the name it gives itself, beside HTML and PDF.
 *
 * It is still a plug-in in every other way: it is listed in the plug-ins
 * window, it can be switched off there, and switching it off takes its
 * format out of the Export menu.
 *
 * What arrives is the document already rendered and made self-contained —
 * the diagrams and the formulas drawn as pictures, the pictures kept on the
 * web fetched if the preferences allow it — so an exporter has one job:
 * turning that HTML into the bytes of its own format.
 *
 * The principal class of the bundle adopts this, the same class that would
 * adopt `run:` for an ordinary plug-in.
 */
@protocol MPExporterPlugIn <NSObject>

@required

/// What the format is called in the menu: "OpenDocument", "LaTeX", "Typst".
/// The ellipsis is added by the application, since every export asks where
/// the file should go.
- (NSString *)exportFormatName;

/// The extension the file gets, without the dot: `odt`, `tex`, `typ`.
- (NSString *)exportFileExtension;

/** The bytes to write, or nil with `error` set.
 *
 * @param html     the rendered document, self-contained.
 * @param markdown the source, for a format that would rather start there.
 * @param fileURL  where the document lives, or nil if it has never been
 *                 saved — for resolving anything the markup points at.
 *
 * Returning nil with no error means the same as returning nil with one: the
 * reader is told the export did not happen. Say why in the error if you can;
 * "the exporter gave no reason" is what they see otherwise.
 */
- (NSData *)exportDataFromHTML:(NSString *)html
                      markdown:(NSString *)markdown
                       fileURL:(NSURL *)fileURL
                         error:(NSError **)error;

@optional

/// A word or two under the save panel's file name, saying what the format
/// is good for. Nothing is shown when this is not implemented.
- (NSString *)exportFormatDescription;

@end
