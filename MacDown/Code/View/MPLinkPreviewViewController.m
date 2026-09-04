//
//  MPLinkPreviewViewController.m
//  MacDown
//

#import "MPLinkPreviewViewController.h"
#import "MPLinkPreview.h"

static const CGFloat kMPCardWidth = 320.0;
static const CGFloat kMPCardPadding = 12.0;
static const CGFloat kMPThumbnailHeight = 160.0;


@interface MPLinkPreviewViewController ()
@property (strong, nonatomic) MPLinkPreview *preview;
@end


@implementation MPLinkPreviewViewController

- (instancetype)initWithPreview:(MPLinkPreview *)preview
{
    self = [super initWithNibName:nil bundle:nil];
    if (!self)
        return nil;
    _preview = preview;
    return self;
}

- (void)loadView
{
    NSMutableArray<NSView *> *rows = [NSMutableArray array];

    NSTextField *title = [NSTextField
        wrappingLabelWithString:self.preview.title ?: @""];
    title.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
    title.maximumNumberOfLines = 2;
    [rows addObject:title];

    // A picture shows itself; there is nothing to say about it that the
    // picture does not say better.
    if (self.preview.kind == MPLinkPreviewKindImage && self.preview.fileURL)
    {
        NSImage *image = [[NSImage alloc]
            initWithContentsOfURL:self.preview.fileURL];
        if (image)
        {
            NSImageView *view = [NSImageView imageViewWithImage:image];
            view.imageScaling = NSImageScaleProportionallyUpOrDown;
            CGFloat height = MIN(kMPThumbnailHeight, image.size.height);
            view.frame = NSMakeRect(0.0, 0.0,
                                    kMPCardWidth - 2 * kMPCardPadding,
                                    height);
            [rows addObject:view];
        }
    }
    else if (self.preview.body.length)
    {
        NSTextField *body = [NSTextField
            wrappingLabelWithString:self.preview.body];
        body.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        body.textColor = [NSColor secondaryLabelColor];
        body.maximumNumberOfLines = 5;
        [rows addObject:body];
    }

    if (self.preview.footnote.length)
    {
        NSTextField *note = [NSTextField
            labelWithString:self.preview.footnote];
        note.font = [NSFont systemFontOfSize:
            [NSFont smallSystemFontSize] - 1.0];
        note.textColor = [NSColor tertiaryLabelColor];
        note.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [rows addObject:note];
    }

    NSStackView *stack = [NSStackView stackViewWithViews:rows];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6.0;
    stack.edgeInsets = NSEdgeInsetsMake(kMPCardPadding, kMPCardPadding,
                                        kMPCardPadding, kMPCardPadding);
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *card = [[NSView alloc] initWithFrame:
        NSMakeRect(0.0, 0.0, kMPCardWidth, 100.0)];
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [card.widthAnchor constraintEqualToConstant:kMPCardWidth],
    ]];

    self.view = card;
    // Laid out now, so the popover can be told how big it is.
    [card layoutSubtreeIfNeeded];
}

@end
