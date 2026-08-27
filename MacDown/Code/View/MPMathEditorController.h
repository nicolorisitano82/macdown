//
//  MPMathEditorController.h
//  MacDown
//
//  A sheet for writing a TeX expression with a live preview of it, and
//  inserting the result into the document.
//

#import <Cocoa/Cocoa.h>


@interface MPMathEditorController : NSWindowController

/** Runs the sheet on `window`.
 *
 * `completion` is called with the TeX the user settled on and whether they
 * asked for display maths, or with nil if they cancelled. `tex` carries no
 * delimiters: the caller decides how to wrap it, because which delimiters a
 * document wants depends on its own preferences.
 */
+ (void)presentForWindow:(NSWindow *)window
              initialTeX:(NSString *)tex
              completion:(void (^)(NSString *tex, BOOL display))completion;

@end
