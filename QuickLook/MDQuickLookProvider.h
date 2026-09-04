//
//  MDQuickLookProvider.h
//  MacDown QuickLook
//

#import <QuickLookUI/QuickLookUI.h>


/// Draws Markdown files for Finder: pressing space on a `.md` file shows the
/// document as it reads, not as it is typed.
@interface MDQuickLookProvider : QLPreviewProvider <QLPreviewingController>
@end
