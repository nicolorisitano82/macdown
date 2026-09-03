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


@interface MPModelsWindowController ()
@property (strong, nonatomic) NSStackView *rows;
@property (strong, nonatomic) NSTextField *status;
@property (strong, nonatomic) NSProgressIndicator *progress;
@property (strong, nonatomic) NSButton *stopButton;
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
        initWithContentRect:NSMakeRect(0.0, 0.0, kMPPanelWidth, 520.0)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered defer:NO];
    window.title = NSLocalizedString(@"Models", @"Models panel title");
    window.minSize = NSMakeSize(kMPPanelWidth, 300.0);
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

    _rows = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _rows.orientation = NSUserInterfaceLayoutOrientationVertical;
    _rows.alignment = NSLayoutAttributeLeading;
    _rows.spacing = 14.0;
    _rows.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = _rows;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:scroll];

    _progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _progress.style = NSProgressIndicatorStyleBar;
    _progress.indeterminate = NO;
    _progress.minValue = 0.0;
    _progress.maxValue = 1.0;
    _progress.hidden = YES;
    _progress.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_progress];

    _status = [NSTextField labelWithString:@""];
    _status.font = [NSFont systemFontOfSize:11.0];
    _status.textColor = [NSColor secondaryLabelColor];
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_status];

    _stopButton = [NSButton buttonWithTitle:
        NSLocalizedString(@"Stop", @"Models panel") target:self
                                     action:@selector(stopDownload:)];
    _stopButton.hidden = YES;
    _stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_stopButton];

    NSButton *reveal = [NSButton buttonWithTitle:
        NSLocalizedString(@"Reveal Models Folder", @"Models panel")
                                          target:self
                                          action:@selector(revealFolder:)];
    reveal.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:reveal];

    CGFloat pad = kMPPanelPadding;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:content.topAnchor
                                         constant:pad],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                             constant:pad],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                              constant:-pad],
        [scroll.bottomAnchor constraintEqualToAnchor:_progress.topAnchor
                                            constant:-14.0],

        [_rows.widthAnchor constraintEqualToAnchor:scroll.widthAnchor
                                          constant:-4.0],

        [_progress.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                               constant:pad],
        [_progress.trailingAnchor constraintEqualToAnchor:
            _stopButton.leadingAnchor constant:-10.0],
        [_stopButton.trailingAnchor constraintEqualToAnchor:
            content.trailingAnchor constant:-pad],
        [_stopButton.centerYAnchor constraintEqualToAnchor:
            _progress.centerYAnchor],

        [_status.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                             constant:pad],
        [_status.topAnchor constraintEqualToAnchor:_progress.bottomAnchor
                                         constant:8.0],
        [_status.trailingAnchor constraintLessThanOrEqualToAnchor:
            reveal.leadingAnchor constant:-10.0],

        [reveal.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                             constant:-pad],
        [reveal.topAnchor constraintEqualToAnchor:_progress.bottomAnchor
                                        constant:4.0],
        [reveal.bottomAnchor constraintEqualToAnchor:content.bottomAnchor
                                            constant:-pad],
    ]];
}


#pragma mark - Showing

- (void)showPanel
{
    [self reload];
    [self.window makeKeyAndOrderFront:nil];
}

/// A heading between the two halves of the list.
- (NSView *)headingWithText:(NSString *)text
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont boldSystemFontOfSize:
        [NSFont systemFontSize]];
    return label;
}

- (NSTextField *)noteWithText:(NSString *)text
{
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:11.0];
    label.textColor = [NSColor secondaryLabelColor];
    label.selectable = NO;
    return label;
}

/** One row: what it is on the left, what can be done with it on the right.
 */
- (NSView *)rowWithTitle:(NSString *)title
                  detail:(NSString *)detail
                    note:(NSString *)note
             buttonTitle:(NSString *)buttonTitle
                  action:(SEL)action
          representedBy:(id)object
                 enabled:(BOOL)enabled
{
    NSStackView *row = [[NSStackView alloc] initWithFrame:NSZeroRect];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12.0;

    NSStackView *text = [[NSStackView alloc] initWithFrame:NSZeroRect];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 2.0;

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
    return row;
}

- (id)rowObject:(NSButton *)button
{
    return objc_getAssociatedObject(button, @selector(rowObject));
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
        [self.rows addView:
            [self rowWithTitle:model.name detail:detail note:nil
                   buttonTitle:inUse
                        ? NSLocalizedString(@"Remove", @"Models panel")
                        : NSLocalizedString(@"Use This One", @"Models panel")
                        action:inUse ? @selector(removeModel:)
                                     : @selector(useModel:)
                 representedBy:model enabled:YES]
                 inGravity:NSStackViewGravityTop];
    }

    [self.rows addView:[self headingWithText:
        NSLocalizedString(@"Available to download", @"Models panel")]
             inGravity:NSStackViewGravityTop];

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

        [self.rows addView:
            [self rowWithTitle:listing.name detail:detail note:listing.note
                   buttonTitle:title action:@selector(downloadModel:)
                 representedBy:listing
                       enabled:!already && !downloader.current]
                 inGravity:NSStackViewGravityTop];
    }

    [self updateProgress];
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
