//
//  MPLinkPreviewViewController.h
//  MacDown
//

#import <Cocoa/Cocoa.h>

@class MPLinkPreview;


/// The little card that appears when a link in the preview is hovered.
@interface MPLinkPreviewViewController : NSViewController

- (instancetype)initWithPreview:(MPLinkPreview *)preview;

@end
