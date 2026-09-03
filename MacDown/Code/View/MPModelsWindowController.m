//
//  MPModelsWindowController.m
//  MacDown
//

#import "MPModelsWindowController.h"
#import "MPModelCatalog.h"
#import "MPModelDownloader.h"
#import "MPModelStore.h"
#import <objc/runtime.h>

static const CGFloat kMPPanelWidth = 560.0;
static const CGFloat kMPPanelPadding = 20.0;
/// Room for the title bar the content now runs underneath.
static const CGFloat kMPPanelTitleBar = 44.0;
/** The rhythm of a pane, in one place.
 *
 * Generous on purpose. The first attempt used twelve and sixteen and the
 * verdict was that it looked like it had been made in Paint, which was
 * fair: glass wants air around what floats on it, or the pane reads as a
 * box drawn around some text rather than as a surface holding it.
 *
 * The curvature goes with the padding — a wide margin inside a tight
 * corner looks like a mistake — and the buttons keep the system's own
 * radius, which is smaller, so the two sit concentric.
 */
static const CGFloat kMPPaneRadius = 18.0;
static const CGFloat kMPPaneInsetVertical = 20.0;
static const CGFloat kMPPaneInsetHorizontal = 24.0;
/// Between the words and the button that acts on them.
static const CGFloat kMPPaneGap = 24.0;
/// Between the lines of one pane: the name, then what is true about it.
static const CGFloat kMPLineGap = 5.0;
/// Between panes, and the distance at which the glass starts to merge.
static const CGFloat kMPPaneSpacing = 12.0;
static const CGFloat kMPMergeSpacing = 16.0;


@interface MPModelsWindowController ()
@property (strong, nonatomic) NSStackView *rows;
@property (strong, nonatomic) NSTextField *status;
@property (strong, nonatomic) NSProgressIndicator *progress;
@property (strong, nonatomic) NSButton *stopButton;
@property (strong, nonatomic) NSTextField *addressField;
@end


@implementation MPModelsWindowController

+ (instancetype)sharedController
{
    static MPModelsWindowController *controller = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        controller = [[MPModelsWindowController alloc] init];
    });
    return controller;
}

- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0.0, 0.0, kMPPanelWidth, 560.0)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskResizable
                            | NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered defer:NO];
    window.title = NSLocalizedString(@"Models", @"Models panel title");
    window.minSize = NSMakeSize(kMPPanelWidth, 360.0);
    // The material runs the whole height, title bar included: glass needs
    // to be seen against something, and a solid strip across the top is a
    // seam where the design asks for one surface.
    window.titlebarAppearsTransparent = YES;
    window.movableByWindowBackground = YES;
    [window center];

    self = [super initWithWindow:window];
    if (!self)
        return nil;

    [self buildContent];

    NSNotificationCenter *centre = [NSNotificationCenter defaultCenter];
    [centre addObserver:self selector:@selector(downloadProgressed:)
                   name:MPModelDownloaderProgressNotification object:nil];
    [centre addObserver:self selector:@selector(downloadFinished:)
                   name:MPModelDownloaderFinishedNotification object:nil];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildContent
{
    NSView *content = self.window.contentView;

    // The ground. Glass refracts what is behind it, so there has to be a
    // material behind it — over a plain window it looks like a grey box.
    NSVisualEffectView *ground =
        [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    ground.material = NSVisualEffectMaterialUnderWindowBackground;
    ground.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    ground.state = NSVisualEffectStateActive;
    ground.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:ground];

    _rows = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _rows.orientation = NSUserInterfaceLayoutOrientationVertical;
    _rows.alignment = NSLayoutAttributeLeading;
    _rows.spacing = kMPPaneSpacing;
    _rows.translatesAutoresizingMaskIntoConstraints = NO;

    // Merges the panes that are close to one another, which is what makes a
    // list of them read as one surface rather than as a stack of cards. The
    // spacing is the distance at which they start to run together, and it
    // has to be a little more than the gap between rows or nothing merges.
    NSGlassEffectContainerView *container =
        [[NSGlassEffectContainerView alloc] initWithFrame:NSZeroRect];
    container.spacing = kMPMergeSpacing;
    container.contentView = _rows;
    container.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = container;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [ground.topAnchor constraintEqualToAnchor:content.topAnchor],
        [ground.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [ground.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [ground.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [_rows.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_rows.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [_rows.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_rows.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];

    NSStackView *footer = [[NSStackView alloc] initWithFrame:NSZeroRect];
    footer.orientation = NSUserInterfaceLayoutOrientationVertical;
    footer.alignment = NSLayoutAttributeLeading;
    footer.spacing = 10.0;
    footer.translatesAutoresizingMaskIntoConstraints = NO;

    _progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _progress.style = NSProgressIndicatorStyleBar;
    _progress.indeterminate = NO;
    _progress.minValue = 0.0;
    _progress.maxValue = 1.0;
    _progress.hidden = YES;

    _status = [NSTextField wrappingLabelWithString:@""];
    _status.font = [NSFont systemFontOfSize:11.0];
    _status.textColor = [NSColor secondaryLabelColor];
    _status.selectable = NO;

    _stopButton = [NSButton buttonWithTitle:
        NSLocalizedString(@"Stop", @"Models panel") target:self
                                     action:@selector(stopDownload:)];
    _stopButton.hidden = YES;

    NSButton *reveal = [NSButton buttonWithTitle:
        NSLocalizedString(@"Reveal Models Folder", @"Models panel")
                                          target:self
                                          action:@selector(revealFolder:)];

    // Progress and its Stop on one line, the words under them.
    NSStackView *bar = [[NSStackView alloc] initWithFrame:NSZeroRect];
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bar.alignment = NSLayoutAttributeCenterY;
    bar.spacing = 12.0;
    [bar addView:_progress inGravity:NSStackViewGravityLeading];
    [bar addView:_stopButton inGravity:NSStackViewGravityTrailing];
    // Its own height and a width that gives: a progress bar with neither
    // is a nought-by-nought view that appears as nothing appearing.
    [_progress.heightAnchor constraintEqualToConstant:6.0].active = YES;
    [_progress.widthAnchor constraintGreaterThanOrEqualToConstant:200.0]
        .active = YES;
    [_progress setContentHuggingPriority:NSLayoutPriorityDefaultLow
                          forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *words = [[NSStackView alloc] initWithFrame:NSZeroRect];
    words.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    words.alignment = NSLayoutAttributeCenterY;
    words.spacing = 12.0;
    [words addView:_status inGravity:NSStackViewGravityLeading];
    [words addView:reveal inGravity:NSStackViewGravityTrailing];
    [reveal setContentCompressionResistancePriority:NSLayoutPriorityRequired
                          forOrientation:NSLayoutConstraintOrientationHorizontal];

    [footer addView:bar inGravity:NSStackViewGravityTop];
    [footer addView:words inGravity:NSStackViewGravityTop];

    NSView *paddedFooter = [[NSView alloc] initWithFrame:NSZeroRect];
    paddedFooter.translatesAutoresizingMaskIntoConstraints = NO;
    [paddedFooter addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [footer.topAnchor constraintEqualToAnchor:paddedFooter.topAnchor
                                         constant:kMPPaneInsetVertical],
        [footer.bottomAnchor constraintEqualToAnchor:paddedFooter.bottomAnchor
                                            constant:-kMPPaneInsetVertical],
        [footer.leadingAnchor constraintEqualToAnchor:
            paddedFooter.leadingAnchor constant:kMPPaneInsetHorizontal],
        [footer.trailingAnchor constraintEqualToAnchor:
            paddedFooter.trailingAnchor constant:-kMPPaneInsetHorizontal],
    ]];

    NSGlassEffectView *footerPane =
        [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
    footerPane.cornerRadius = kMPPaneRadius;
    footerPane.style = NSGlassEffectViewStyleRegular;
    footerPane.contentView = paddedFooter;
    footerPane.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:footerPane];

    CGFloat pad = kMPPanelPadding;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:content.topAnchor
                                         constant:kMPPanelTitleBar],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                             constant:pad],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                              constant:-pad],
        [scroll.bottomAnchor constraintEqualToAnchor:footerPane.topAnchor
                                            constant:-12.0],

        [container.widthAnchor constraintEqualToAnchor:scroll.widthAnchor
                                              constant:-4.0],

        [footerPane.leadingAnchor constraintEqualToAnchor:
            content.leadingAnchor constant:pad],
        [footerPane.trailingAnchor constraintEqualToAnchor:
            content.trailingAnchor constant:-pad],
        [footerPane.bottomAnchor constraintEqualToAnchor:
            content.bottomAnchor constant:-pad],
        [bar.widthAnchor constraintEqualToAnchor:words.widthAnchor],
    ]];
}


#pragma mark - Showing

- (void)showPanel
{
    [self reload];
    [self.window makeKeyAndOrderFront:nil];
}

/// The accent, weak enough to tint glass rather than paint it.
- (NSColor *)accentTint
{
    return [[NSColor controlAccentColor] colorWithAlphaComponent:0.28];
}

/** A heading between the two halves of the list.
 *
 * Not on glass. Everything cannot float, or nothing reads as floating:
 * the headings belong to the ground and the panes sit above them.
 */
- (NSView *)headingWithText:(NSString *)text
{
    NSTextField *label = [NSTextField labelWithString:
        text.localizedUppercaseString];
    label.font = [NSFont systemFontOfSize:11.0
                                   weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSTextField *)noteWithText:(NSString *)text
{
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:11.0];
    label.textColor = [NSColor secondaryLabelColor];
    label.selectable = NO;
    // Shortened rather than clipped: a line that wants four points more
    // than the column has was losing its last letters without saying so.
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

/** One row: what it is on the left, what can be done with it on the right,
 *  the pair floating on a pane of glass.
 *
 * `tint` colours the glass rather than anything drawn on it, which is how
 * the one in use and the one recommended are told apart without a badge,
 * a border or a second typeface.
 */
- (NSView *)rowWithTitle:(NSString *)title
                  detail:(NSString *)detail
                    note:(NSString *)note
             buttonTitle:(NSString *)buttonTitle
                  action:(SEL)action
          representedBy:(id)object
                 enabled:(BOOL)enabled
                    tint:(NSColor *)tint
{
    NSStackView *row = [[NSStackView alloc] initWithFrame:NSZeroRect];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = kMPPaneGap;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *text = [[NSStackView alloc] initWithFrame:NSZeroRect];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = kMPLineGap;

    NSTextField *name = [NSTextField labelWithString:title];
    name.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    [text addView:name inGravity:NSStackViewGravityTop];

    if (detail.length)
        [text addView:[self noteWithText:detail]
            inGravity:NSStackViewGravityTop];
    if (note.length)
        [text addView:[self noteWithText:note]
            inGravity:NSStackViewGravityTop];

    [row addView:text inGravity:NSStackViewGravityLeading];

    if (buttonTitle.length)
    {
        NSButton *button = [NSButton buttonWithTitle:buttonTitle target:self
                                              action:action];
        button.enabled = enabled;
        // Carried on the button, so an action knows which row it came from
        // without the controller holding a parallel list of anything.
        button.identifier = nil;
        objc_setAssociatedObject(button, @selector(rowObject), object,
                                 OBJC_ASSOCIATION_RETAIN);
        [row addView:button inGravity:NSStackViewGravityTrailing];
    }

    // The row inside a plain view, pinned with constraints, and that view
    // is what the glass holds. A stack view's own edgeInsets did not
    // survive being a glass content view — measured: the pane came out
    // exactly as tall as its text, with no margin at all — and explicit
    // constraints are not open to interpretation.
    NSView *padded = [[NSView alloc] initWithFrame:NSZeroRect];
    padded.translatesAutoresizingMaskIntoConstraints = NO;
    [padded addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:padded.topAnchor
                                      constant:kMPPaneInsetVertical],
        [row.bottomAnchor constraintEqualToAnchor:padded.bottomAnchor
                                         constant:-kMPPaneInsetVertical],
        [row.leadingAnchor constraintEqualToAnchor:padded.leadingAnchor
                                          constant:kMPPaneInsetHorizontal],
        [row.trailingAnchor constraintEqualToAnchor:padded.trailingAnchor
                                           constant:-kMPPaneInsetHorizontal],
    ]];

    NSGlassEffectView *pane =
        [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
    pane.cornerRadius = kMPPaneRadius;
    pane.style = NSGlassEffectViewStyleRegular;
    pane.tintColor = tint;
    // Only the content view is promised a place inside the glass; a
    // subview added the ordinary way is not.
    pane.contentView = padded;
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    return pane;
}

- (id)rowObject:(NSButton *)button
{
    return objc_getAssociatedObject(button, @selector(rowObject));
}

/** Adds a pane, full width.
 *
 * A stack view sizes its children to what they contain, so the panes came
 * out five different widths — measured, and wrong: they are rows of one
 * list and a list has one edge.
 */
- (void)addPane:(NSView *)pane
{
    [self.rows addView:pane inGravity:NSStackViewGravityTop];
    [pane.widthAnchor constraintEqualToAnchor:self.rows.widthAnchor].active =
        YES;
}

- (void)reload
{
    for (NSView *view in [self.rows.views copy])
        [self.rows removeView:view];

    MPModelStore *store = [MPModelStore sharedStore];
    NSArray<MPModelFile *> *installed = store.installedModels;
    MPModelFile *chosen = store.selectedModel;

    [self.rows addView:[self headingWithText:
        NSLocalizedString(@"Installed", @"Models panel")]
             inGravity:NSStackViewGravityTop];

    if (!installed.count)
    {
        [self.rows addView:[self noteWithText:NSLocalizedString(
            @"None yet. Download one below, or put a .gguf file in the "
            @"Models folder yourself — either way works.",
            @"Models panel")] inGravity:NSStackViewGravityTop];
    }

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;

    for (MPModelFile *model in installed)
    {
        BOOL inUse = [model.url isEqual:chosen.url];
        NSString *detail = [formatter
            stringFromByteCount:(long long)model.byteSize];
        if (inUse)
        {
            detail = [detail stringByAppendingString:NSLocalizedString(
                @" — the one the writing commands use",
                @"Models panel")];
        }
        [self addPane:
            [self rowWithTitle:model.name detail:detail note:nil
                   buttonTitle:inUse
                        ? NSLocalizedString(@"Remove", @"Models panel")
                        : NSLocalizedString(@"Use This One", @"Models panel")
                        action:inUse ? @selector(removeModel:)
                                     : @selector(useModel:)
                 representedBy:model enabled:YES
                          tint:inUse ? [self accentTint] : nil]];
    }

    NSView *lastInstalled = self.rows.views.lastObject;
    NSView *availableHeading = [self headingWithText:
        NSLocalizedString(@"Available to download", @"Models panel")];
    [self.rows addView:availableHeading inGravity:NSStackViewGravityTop];
    // Air above the second heading: without it the panes of one half merge
    // with the panes of the other and the list reads as one long thing.
    if (lastInstalled)
        [self.rows setCustomSpacing:26.0 afterView:lastInstalled];

    MPModelDownloader *downloader = [MPModelDownloader sharedDownloader];
    NSMutableSet<NSString *> *have = [NSMutableSet set];
    for (MPModelFile *model in installed)
        [have addObject:model.url.lastPathComponent];

    for (MPModelListing *listing in [MPModelCatalog sharedCatalog].listings)
    {
        BOOL already = [have containsObject:listing.fileName];
        NSString *detail = [NSString stringWithFormat:@"%@ · %@ · %@",
            listing.readableSize, listing.parameters, listing.quantisation];

        NSString *title = NSLocalizedString(@"Download", @"Models panel");
        if (already)
            title = NSLocalizedString(@"Installed", @"Models panel");
        else if ([downloader hasResumableDownloadForListing:listing])
            title = NSLocalizedString(@"Resume", @"Models panel");

        [self addPane:
            [self rowWithTitle:listing.name detail:detail note:listing.note
                   buttonTitle:title action:@selector(downloadModel:)
                 representedBy:listing
                       enabled:!already && !downloader.current
                          tint:listing.recommended && !already
                                ? [self accentTint] : nil]];
    }

    [self addPane:[self pastePane]];
    [self updateProgress];
}

/** A field for an address of one's own, at the end of the offered ones.
 *
 * Four models is a list, not a policy. Somebody who wants a family this
 * does not know about should not have to wait for the list to grow, and
 * everything that guards the offered ones — the room on the disk, the size
 * against what arrives, the four bytes that say GGUF — guards this equally.
 */
- (NSView *)pastePane
{
    NSStackView *row = [[NSStackView alloc] initWithFrame:NSZeroRect];
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    row.spacing = kMPLineGap;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = [NSTextField labelWithString:
        NSLocalizedString(@"From an address", @"Models panel")];
    [row addView:title inGravity:NSStackViewGravityTop];
    [row addView:[self noteWithText:NSLocalizedString(
        @"A link to a .gguf file. A Hugging Face page address works too — "
        @"the link to the file itself is what gets used.",
        @"Models panel")] inGravity:NSStackViewGravityTop];

    if (!_addressField)
    {
        _addressField = [NSTextField textFieldWithString:@""];
        _addressField.placeholderString =
            @"https://huggingface.co/…/model-Q4_K_M.gguf";
        _addressField.font = [NSFont systemFontOfSize:11.0];
    }
    NSButton *go = [NSButton buttonWithTitle:
        NSLocalizedString(@"Download", @"Models panel") target:self
                                      action:@selector(downloadFromAddress:)];
    go.enabled = ([MPModelDownloader sharedDownloader].current == nil);

    NSStackView *line = [[NSStackView alloc] initWithFrame:NSZeroRect];
    line.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    line.alignment = NSLayoutAttributeCenterY;
    line.spacing = 10.0;
    [line addView:_addressField inGravity:NSStackViewGravityLeading];
    [line addView:go inGravity:NSStackViewGravityTrailing];
    [go setContentCompressionResistancePriority:NSLayoutPriorityRequired
                  forOrientation:NSLayoutConstraintOrientationHorizontal];
    [row addView:line inGravity:NSStackViewGravityTop];

    NSView *padded = [[NSView alloc] initWithFrame:NSZeroRect];
    padded.translatesAutoresizingMaskIntoConstraints = NO;
    [padded addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:padded.topAnchor
                                      constant:kMPPaneInsetVertical],
        [row.bottomAnchor constraintEqualToAnchor:padded.bottomAnchor
                                         constant:-kMPPaneInsetVertical],
        [row.leadingAnchor constraintEqualToAnchor:padded.leadingAnchor
                                          constant:kMPPaneInsetHorizontal],
        [row.trailingAnchor constraintEqualToAnchor:padded.trailingAnchor
                                           constant:-kMPPaneInsetHorizontal],
        [line.widthAnchor constraintEqualToAnchor:row.widthAnchor],
    ]];

    NSGlassEffectView *pane =
        [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
    pane.cornerRadius = kMPPaneRadius;
    pane.style = NSGlassEffectViewStyleRegular;
    pane.contentView = padded;
    pane.translatesAutoresizingMaskIntoConstraints = NO;
    return pane;
}

- (void)downloadFromAddress:(id)sender
{
    NSString *text = self.addressField.stringValue;
    self.status.stringValue = NSLocalizedString(@"Asking how big it is…",
                                                @"Models panel");

    __weak MPModelsWindowController *weakSelf = self;
    [[MPModelDownloader sharedDownloader] listingForPastedText:text
                                                    completion:
        ^(MPModelListing *listing, NSError *error) {
        MPModelsWindowController *controller = weakSelf;
        if (!listing)
        {
            [controller updateProgress];
            [controller presentError:error];
            return;
        }
        NSError *failure = nil;
        if (![[MPModelDownloader sharedDownloader]
                startDownloadOfListing:listing error:&failure])
        {
            [controller updateProgress];
            [controller presentError:failure];
            return;
        }
        controller.addressField.stringValue = @"";
        [controller reload];
    }];
}

- (void)updateProgress
{
    MPModelDownloader *downloader = [MPModelDownloader sharedDownloader];
    MPModelListing *current = downloader.current;

    self.progress.hidden = (current == nil);
    self.stopButton.hidden = (current == nil);
    if (!current)
    {
        self.status.stringValue = NSLocalizedString(
            @"A model is a few gigabytes and stays on your Mac. Nothing is "
            @"sent anywhere: the writing commands run on this machine.",
            @"Models panel");
        return;
    }

    self.progress.doubleValue = downloader.fractionCompleted;

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    self.status.stringValue = [NSString stringWithFormat:
        NSLocalizedString(@"%@ — %@ of %@", @"Models panel"),
        current.name,
        [formatter stringFromByteCount:(long long)downloader.bytesReceived],
        current.readableSize];
}


#pragma mark - Actions

- (void)downloadModel:(NSButton *)sender
{
    MPModelListing *listing = [self rowObject:sender];
    NSError *error = nil;
    if (![[MPModelDownloader sharedDownloader] startDownloadOfListing:listing
                                                                error:&error]
            && error)
    {
        [self presentError:error];
        return;
    }
    [self reload];
}

- (void)stopDownload:(id)sender
{
    [[MPModelDownloader sharedDownloader] cancel];
}

- (void)useModel:(NSButton *)sender
{
    [MPModelStore sharedStore].selectedModel = [self rowObject:sender];
    // The one in memory is no longer the one chosen.
    [[MPModelStore sharedStore] unloadGenerator];
    [self reload];
}

- (void)removeModel:(NSButton *)sender
{
    MPModelFile *model = [self rowObject:sender];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:NSLocalizedString(
        @"Remove “%@”?", @"Models panel"), model.name];
    alert.informativeText = NSLocalizedString(
        @"The file is deleted from your Mac. It can be downloaded again.",
        @"Models panel");
    [alert addButtonWithTitle:NSLocalizedString(@"Remove", @"Models panel")];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Models panel")];

    __weak MPModelsWindowController *weakSelf = self;
    [alert beginSheetModalForWindow:self.window completionHandler:
        ^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn)
            return;
        NSError *error = nil;
        if (![[MPModelStore sharedStore] removeModel:model error:&error])
            [weakSelf presentError:error];
        [weakSelf reload];
    }];
}

- (void)revealFolder:(id)sender
{
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:
        @[[MPModelStore sharedStore].directory]];
}

- (void)presentError:(NSError *)error
{
    if (!error)
        return;
    NSAlert *alert = [NSAlert alertWithError:error];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}


#pragma mark - Notifications

- (void)downloadProgressed:(NSNotification *)notification
{
    [self updateProgress];
}

- (void)downloadFinished:(NSNotification *)notification
{
    NSError *error = notification.userInfo[MPModelDownloaderErrorKey];
    [self reload];
    if (error)
        [self presentError:error];
}

@end
