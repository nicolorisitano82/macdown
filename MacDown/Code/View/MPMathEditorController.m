//
//  MPMathEditorController.m
//  MacDown
//

#import "MPMathEditorController.h"
#import <WebKit/WKWebView.h>
#import <WebKit/WKNavigationDelegate.h>


/// How long to wait after a keystroke before typesetting again. Long enough
/// that a burst of typing costs one pass, short enough to feel live.
static const NSTimeInterval kMPMathPreviewDelay = 0.2;


/// Quotes a string for embedding in JavaScript source. JSON is the shortest
/// correct way to do it, and covers the backslashes TeX is made of.
NS_INLINE NSString *MPJavaScriptStringLiteral(NSString *string)
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[string ?: @""]
                                                   options:0 error:NULL];
    NSString *array = [[NSString alloc] initWithData:data
                                            encoding:NSUTF8StringEncoding];
    // Unwrap the one-element array the serialiser insists on.
    if (array.length > 2)
        return [array substringWithRange:NSMakeRange(1, array.length - 2)];
    return @"\"\"";
}


@interface MPMathEditorController () <NSTextViewDelegate, WKNavigationDelegate>

@property (strong, nonatomic) NSTextView *sourceView;
@property (strong, nonatomic) WKWebView *previewView;
@property (strong, nonatomic) NSSegmentedControl *modeControl;
@property (strong, nonatomic) NSButton *insertButton;
@property (assign, nonatomic) BOOL previewReady;
@property (copy, nonatomic) void (^completion)(NSString *, BOOL);

@end


@implementation MPMathEditorController

+ (void)presentForWindow:(NSWindow *)window
              initialTeX:(NSString *)tex
              completion:(void (^)(NSString *, BOOL))completion
{
    MPMathEditorController *controller =
        [[MPMathEditorController alloc] initWithWindow:[self makePanel]];
    controller.completion = completion;
    [controller buildInterface];
    controller.sourceView.string = tex ?: @"";
    [controller updateInsertEnabled];

    // The controller has to outlive this scope; the sheet's completion
    // handler is what lets go of it.
    NSWindow *sheet = controller.window;
    [window beginSheet:sheet completionHandler:^(NSModalResponse response) {
        (void)controller;
    }];
    [sheet makeFirstResponder:controller.sourceView];
}

+ (NSPanel *)makePanel
{
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0.0, 0.0, 520.0, 400.0)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskDocModalWindow
                    backing:NSBackingStoreBuffered defer:YES];
    panel.title = NSLocalizedString(@"Maths", @"maths editor sheet title");
    return panel;
}

#pragma mark - Interface

- (void)buildInterface
{
    NSView *content = self.window.contentView;

    NSTextField *label = [NSTextField labelWithString:NSLocalizedString(
        @"TeX", @"label above the maths editor's source field")];
    label.textColor = [NSColor secondaryLabelColor];
    label.font = [NSFont systemFontOfSize:
        [NSFont smallSystemFontSize]];

    NSScrollView *sourceScroll = [[NSScrollView alloc] init];
    sourceScroll.hasVerticalScroller = YES;
    sourceScroll.borderType = NSBezelBorder;
    sourceScroll.drawsBackground = YES;

    NSTextView *source = [[NSTextView alloc] init];
    source.delegate = self;
    source.font = [NSFont monospacedSystemFontOfSize:12.0
                                              weight:NSFontWeightRegular];
    source.automaticQuoteSubstitutionEnabled = NO;
    source.automaticDashSubstitutionEnabled = NO;
    source.automaticTextReplacementEnabled = NO;
    source.automaticSpellingCorrectionEnabled = NO;
    // TeX is not prose; red underlines all over a formula are noise.
    source.continuousSpellCheckingEnabled = NO;
    source.minSize = NSMakeSize(0.0, 0.0);
    source.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    source.verticallyResizable = YES;
    source.horizontallyResizable = NO;
    source.autoresizingMask = NSViewWidthSizable;
    source.textContainer.widthTracksTextView = YES;
    sourceScroll.documentView = source;
    self.sourceView = source;

    NSSegmentedControl *mode = [NSSegmentedControl
        segmentedControlWithLabels:@[NSLocalizedString(@"Inline", @"inline maths"),
                                     NSLocalizedString(@"Display", @"display maths")]
                      trackingMode:NSSegmentSwitchTrackingSelectOne
                            target:self action:@selector(modeChanged:)];
    mode.selectedSegment = 0;
    self.modeControl = mode;

    WKWebView *preview = [[WKWebView alloc] initWithFrame:NSZeroRect];
    preview.navigationDelegate = self;
    preview.wantsLayer = YES;
    // The sheet's own background shows through, so the preview belongs to the
    // sheet rather than looking like a web page dropped into it.
    [preview setValue:@NO forKey:@"drawsBackground"];
    self.previewView = preview;

    NSBox *previewBox = [[NSBox alloc] init];
    previewBox.boxType = NSBoxCustom;
    previewBox.cornerRadius = 6.0;
    previewBox.borderColor = [NSColor separatorColor];
    previewBox.fillColor = [NSColor textBackgroundColor];
    previewBox.contentView = preview;

    NSButton *cancel = [NSButton buttonWithTitle:NSLocalizedString(
        @"Cancel", @"maths editor cancel button") target:self
                                          action:@selector(cancel:)];
    cancel.keyEquivalent = @"\033";

    NSButton *insert = [NSButton buttonWithTitle:NSLocalizedString(
        @"Insert", @"maths editor insert button") target:self
                                          action:@selector(insert:)];
    // Command-Return, not Return: TeX is legitimately multi-line — an
    // aligned environment spans several — so the field keeps Return for a
    // new line, which is the usual arrangement for a multi-line sheet.
    insert.keyEquivalent = @"\r";
    insert.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    self.insertButton = insert;

    NSTextField *hint = [NSTextField labelWithString:NSLocalizedString(
        @"⌘↩ to insert", @"hint about the maths editor's insert shortcut")];
    hint.textColor = [NSColor tertiaryLabelColor];
    hint.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];

    for (NSView *view in @[label, sourceScroll, mode, previewBox, cancel,
                           insert, hint])
    {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:view];
    }

    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:content.topAnchor
                                        constant:16.0],
        [label.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                            constant:20.0],

        [sourceScroll.topAnchor constraintEqualToAnchor:label.bottomAnchor
                                               constant:6.0],
        [sourceScroll.leadingAnchor
            constraintEqualToAnchor:content.leadingAnchor constant:20.0],
        [sourceScroll.trailingAnchor
            constraintEqualToAnchor:content.trailingAnchor constant:-20.0],
        [sourceScroll.heightAnchor constraintEqualToConstant:110.0],

        [mode.topAnchor constraintEqualToAnchor:sourceScroll.bottomAnchor
                                       constant:12.0],
        [mode.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                           constant:20.0],

        [previewBox.topAnchor constraintEqualToAnchor:mode.bottomAnchor
                                             constant:12.0],
        [previewBox.leadingAnchor
            constraintEqualToAnchor:content.leadingAnchor constant:20.0],
        [previewBox.trailingAnchor
            constraintEqualToAnchor:content.trailingAnchor constant:-20.0],
        [previewBox.bottomAnchor constraintEqualToAnchor:insert.topAnchor
                                                constant:-16.0],

        [insert.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                             constant:-20.0],
        [insert.bottomAnchor constraintEqualToAnchor:content.bottomAnchor
                                            constant:-16.0],
        [insert.widthAnchor constraintGreaterThanOrEqualToConstant:90.0],

        [cancel.trailingAnchor constraintEqualToAnchor:insert.leadingAnchor
                                              constant:-10.0],
        [cancel.centerYAnchor constraintEqualToAnchor:insert.centerYAnchor],
        [cancel.widthAnchor constraintGreaterThanOrEqualToConstant:90.0],

        [hint.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                           constant:20.0],
        [hint.centerYAnchor constraintEqualToAnchor:insert.centerYAnchor],
        [hint.trailingAnchor
            constraintLessThanOrEqualToAnchor:cancel.leadingAnchor
                                     constant:-12.0],
    ]];

    NSURL *page = [[NSBundle mainBundle] URLForResource:@"editor"
                                          withExtension:@"html"
                                           subdirectory:@"MathJax"];
    if (page)
    {
        // Read access to the folder, not just the file, so the page can pull
        // tex-svg.js in beside it.
        [preview loadFileURL:page
     allowingReadAccessToURL:page.URLByDeletingLastPathComponent];
    }
}

#pragma mark - Preview

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation
{
    self.previewReady = YES;

    NSString *placeholder = NSLocalizedString(
        @"The preview appears here",
        @"placeholder in the maths editor's preview");
    [webView evaluateJavaScript:
        [NSString stringWithFormat:@"setPlaceholder(%@)",
            MPJavaScriptStringLiteral(placeholder)]
          completionHandler:nil];

    [self refreshPreview];
}

- (void)refreshPreview
{
    if (!self.previewReady)
        return;

    NSString *tex = self.sourceView.string ?: @"";
    BOOL display = (self.modeControl.selectedSegment == 1);
    NSString *script = [NSString stringWithFormat:@"render(%@, %@)",
        MPJavaScriptStringLiteral(tex), display ? @"true" : @"false"];
    [self.previewView evaluateJavaScript:script completionHandler:nil];
}

- (void)schedulePreviewRefresh
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(refreshPreview)
                                               object:nil];
    [self performSelector:@selector(refreshPreview) withObject:nil
               afterDelay:kMPMathPreviewDelay];
}

- (void)updateInsertEnabled
{
    NSCharacterSet *blank = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *trimmed =
        [self.sourceView.string stringByTrimmingCharactersInSet:blank];
    self.insertButton.enabled = trimmed.length > 0;
}

#pragma mark - Actions

- (void)textDidChange:(NSNotification *)notification
{
    [self schedulePreviewRefresh];
    [self updateInsertEnabled];
}

- (void)modeChanged:(id)sender
{
    [self refreshPreview];
}

- (void)finishWithTeX:(NSString *)tex display:(BOOL)display
{
    // The sheet's completion handler holds the only strong reference to this
    // controller, and -endSheet: runs it. Without the local below, self is
    // deallocated part way through this method and the completion never
    // reaches the document. ARC retains the local for the scope, which is
    // what keeps it alive; the block is taken out first for the same reason.
    MPMathEditorController *keepAlive = self;
    void (^completion)(NSString *, BOOL) = self.completion;
    self.completion = nil;

    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    NSWindow *sheet = self.window;
    [sheet.sheetParent endSheet:sheet];

    if (completion)
        completion(tex, display);

    (void)keepAlive;
}

- (void)insert:(id)sender
{
    NSCharacterSet *blank = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *tex =
        [self.sourceView.string stringByTrimmingCharactersInSet:blank];
    if (!tex.length)
        return;
    [self finishWithTeX:tex display:(self.modeControl.selectedSegment == 1)];
}

- (void)cancel:(id)sender
{
    [self finishWithTeX:nil display:NO];
}

@end
