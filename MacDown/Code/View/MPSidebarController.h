//
//  MPSidebarController.h
//  MacDown
//
//  A sidebar with two views of where you are: the headings in this document,
//  and the files sitting next to it.
//

#import <Cocoa/Cocoa.h>


@protocol MPSidebarControllerDelegate <NSObject>

/// A heading was chosen. The range is into the Markdown source.
- (void)sidebarDidSelectHeadingRange:(NSRange)range;

/// A file was chosen.
- (void)sidebarDidSelectFileURL:(NSURL *)url;

@end


@interface MPSidebarController : NSObject

@property (weak, nonatomic) id<MPSidebarControllerDelegate> delegate;

/// The view to put in a window. Built on first access.
@property (readonly, nonatomic) NSView *view;

/// Rebuilds the outline. Cheap enough for every edit.
- (void)updateOutlineWithMarkdown:(NSString *)markdown;

/// The folder the file list shows. Nil for an unsaved document, which leaves
/// the list empty rather than guessing at somewhere to point it.
- (void)setRootURL:(NSURL *)url;

/// Highlights the heading containing `location`, following the caret.
- (void)selectHeadingContainingLocation:(NSUInteger)location;

@end
