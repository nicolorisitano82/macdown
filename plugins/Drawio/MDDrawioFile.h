//
//  MDDrawioFile.h
//  MacDown Next — draw.io plug-in
//

#import <Foundation/Foundation.h>

extern NSString * const MDDrawioErrorDomain;

typedef NS_ENUM(NSInteger, MDDrawioError) {
    MDDrawioErrorNotADiagram = 1,
    MDDrawioErrorNoPages,
    MDDrawioErrorPageUnreadable,
    MDDrawioErrorRenderFailed,
    MDDrawioErrorServiceRefused,
};


/// One page of a diagram: what it is called, and the model behind it.
@interface MDDrawioPage : NSObject
/// The name on the tab in draw.io; empty when the file names none.
@property (readonly, copy, nonatomic) NSString *name;
/// The `mxGraphModel` for this page, ready to hand to the viewer.
@property (readonly, copy, nonatomic) NSString *xml;

- (instancetype)initWithName:(NSString *)name xml:(NSString *)xml;
@end


/** A `.drawio` file, read into its pages.
 *
 * The pages are what a person sees as tabs, and each has to become its own
 * picture: a document that links one image and gets four pages of diagram
 * in it is not what anybody meant.
 *
 * Four shapes of file arrive here. An `mxfile` whose pages are plain XML;
 * an `mxfile` whose pages are deflated, base64'd and URI-escaped, which is
 * what draw.io writes by default; a PNG that carries the whole file in a
 * text chunk; and an SVG that carries it in an attribute — the last two
 * being what "editable PNG" and "editable SVG" mean.
 */
@interface MDDrawioFile : NSObject

@property (readonly, copy, nonatomic) NSArray<MDDrawioPage *> *pages;

+ (instancetype)fileWithData:(NSData *)data error:(NSError **)error;
+ (instancetype)fileWithURL:(NSURL *)url error:(NSError **)error;

@end


/** The XML behind a page written the compact way.
 *
 * base64, then raw deflate, then URI-escaped UTF-8 — in that order coming
 * out. Returns nil if any step does not hold, since a wrong guess further
 * up produces text that is not XML rather than an error.
 */
extern NSString *MDDrawioXMLFromCompactPayload(NSString *payload);

/// The `mxfile` a draw.io PNG carries in its text chunks, or nil.
extern NSString *MDDrawioXMLFromPNG(NSData *png);

/** Inflates `data`, or nil if it does not inflate.
 *
 * `raw` for a stream with no header, which is what a page of a diagram is;
 * without it a gzip or zlib header is expected and read, which is what the
 * shape libraries in this bundle are stored with.
 */
extern NSData *MDDrawioInflate(NSData *data, BOOL raw);
