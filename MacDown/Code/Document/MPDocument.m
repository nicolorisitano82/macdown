//
//  MPDocument.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPDocument.h"
#import <WebKit/WebKit.h>
#import <JJPluralForm/JJPluralForm.h>
#import <hoedown/html.h>
#import "hoedown_html_patch.h"
#import "HGMarkdownHighlighter.h"
#import "MPUtilities.h"
#import "MPAutosaving.h"
#import "NSColor+HTML.h"
#import "NSDocumentController+Document.h"
#import "NSPasteboard+Types.h"
#import "NSString+Lookup.h"
#import "NSTextView+Autocomplete.h"
#import "MPPreferences.h"
#import "MPDocumentSplitView.h"
#import "MPEditorView.h"
#import "MPRenderer.h"
#import "MPPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPExportPanelAccessoryViewController.h"
#import "MPMathJaxListener.h"
#import "MPToolbarController.h"
#import "MPPreviewSchemeHandler.h"
#import "MPProseChecker.h"
#import "MPMathEditorController.h"
#import "MPSidebarController.h"
#import "MPEpubExport.h"
#import "MPDocxPostProcessing.h"
#import <JavaScriptCore/JavaScriptCore.h>

static NSString * const kMPDefaultAutosaveName = @"Untitled";


NS_INLINE NSString *MPEditorPreferenceKeyWithValueKey(NSString *key)
{
    if (!key.length)
        return @"editor";
    NSString *first = [[key substringToIndex:1] uppercaseString];
    NSString *rest = [key substringFromIndex:1];
    return [NSString stringWithFormat:@"editor%@%@", first, rest];
}

NS_INLINE NSDictionary *MPEditorKeysToObserve()
{
    static NSDictionary *keys = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        keys = @{@"automaticDashSubstitutionEnabled": @NO,
                 @"automaticDataDetectionEnabled": @NO,
                 @"automaticQuoteSubstitutionEnabled": @NO,
                 @"automaticSpellingCorrectionEnabled": @NO,
                 @"automaticTextReplacementEnabled": @NO,
                 @"continuousSpellCheckingEnabled": @NO,
                 @"enabledTextCheckingTypes": @(NSTextCheckingAllTypes),
                 @"grammarCheckingEnabled": @NO};
    });
    return keys;
}

NS_INLINE NSSet *MPEditorPreferencesToObserve()
{
    static NSSet *keys = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        keys = [NSSet setWithObjects:
            @"editorBaseFontInfo", @"extensionFootnotes",
            @"editorHorizontalInset", @"editorVerticalInset",
            @"editorWidthLimited", @"editorMaximumWidth", @"editorLineSpacing",
            @"editorOnRight", @"editorStyleName", @"editorShowWordCount",
            @"editorScrollsPastEnd", @"editorProseHighlights", nil
        ];
    });
    return keys;
}

NS_INLINE NSString *MPRectStringForAutosaveName(NSString *name)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *key = [NSString stringWithFormat:@"NSWindow Frame %@", name];
    NSString *rectString = [defaults objectForKey:key];
    return rectString;
}


@implementation NSURL (Convert)

- (NSString *)absoluteBaseURLString
{
    // Remove fragment (#anchor) and query string.
    NSString *base = self.absoluteString;
    base = [base componentsSeparatedByString:@"?"].firstObject;
    base = [base componentsSeparatedByString:@"#"].firstObject;
    return base;
}

@end


@implementation MPPreferences (Hoedown)
- (int)extensionFlags
{
    int flags = 0;
    if (self.extensionAutolink)
        flags |= HOEDOWN_EXT_AUTOLINK;
    if (self.extensionFencedCode)
        flags |= HOEDOWN_EXT_FENCED_CODE;
    if (self.extensionFootnotes)
        flags |= HOEDOWN_EXT_FOOTNOTES;
    if (self.extensionHighlight)
        flags |= HOEDOWN_EXT_HIGHLIGHT;
    if (!self.extensionIntraEmphasis)
        flags |= HOEDOWN_EXT_NO_INTRA_EMPHASIS;
    if (self.extensionQuote)
        flags |= HOEDOWN_EXT_QUOTE;
    if (self.extensionStrikethough)
        flags |= HOEDOWN_EXT_STRIKETHROUGH;
    if (self.extensionSuperscript)
        flags |= HOEDOWN_EXT_SUPERSCRIPT;
    if (self.extensionTables)
        flags |= HOEDOWN_EXT_TABLES;
    if (self.extensionUnderline)
        flags |= HOEDOWN_EXT_UNDERLINE;
    if (self.htmlMathJax)
        flags |= HOEDOWN_EXT_MATH;
    if (self.htmlMathJaxInlineDollar)
        flags |= HOEDOWN_EXT_MATH_EXPLICIT;
    return flags;
}

- (int)rendererFlags
{
    int flags = 0;
    if (self.htmlTaskList)
        flags |= HOEDOWN_HTML_USE_TASK_LIST;
    if (self.htmlLineNumbers)
        flags |= HOEDOWN_HTML_BLOCKCODE_LINE_NUMBERS;
    if (self.htmlHardWrap)
        flags |= HOEDOWN_HTML_HARD_WRAP;
    if (self.htmlCodeBlockAccessory == MPCodeBlockAccessoryCustom)
        flags |= HOEDOWN_HTML_BLOCKCODE_INFORMATION;
    return flags;
}
@end


@interface MPDocument ()
    <NSSplitViewDelegate, NSTextViewDelegate, NSWindowDelegate,
     MPSidebarControllerDelegate,
     WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
     MPAutosaving, MPRendererDataSource, MPRendererDelegate>

typedef NS_ENUM(NSUInteger, MPWordCountType) {
    MPWordCountTypeWord,
    MPWordCountTypeCharacter,
    MPWordCountTypeCharacterNoSpaces,
};

@property (weak) IBOutlet NSToolbar *toolbar;
@property (weak) IBOutlet MPDocumentSplitView *splitView;
@property (weak) IBOutlet NSView *editorContainer;
@property (unsafe_unretained) IBOutlet MPEditorView *editor;
@property (weak) IBOutlet NSLayoutConstraint *editorPaddingBottom;
@property (weak) IBOutlet NSView *previewContainer;

/** The preview.
 *
 * Built in code rather than in the nib: WKWebView needs a configuration
 * assembled before it exists — the user scripts below have to be in place
 * before the first page loads, and a view unarchived from a nib has already
 * missed that.
 */
@property (strong, nonatomic) WKWebView *preview;

/// Last scroll position the page reported, in CSS pixels.
@property (assign, nonatomic) CGFloat previewScrollTop;
@property (assign, nonatomic) CGFloat previewContentHeight;
@property (assign, nonatomic) CGFloat previewViewportHeight;
/// Body background as the page computes it, for the split view divider.
@property (strong, nonatomic) NSColor *previewBackgroundColor;
/// The drawn diagrams, posted by the page after each render.
@property (copy, nonatomic) NSArray<NSString *> *harvestedDiagrams;
/// The typeset formulas, likewise: {svg, display}.
@property (copy, nonatomic) NSArray<NSDictionary *> *harvestedFormulas;
@property (strong, nonatomic) NSURL *previewScratchDirectory;
@property (strong, nonatomic) MPPreviewSchemeHandler *previewSchemeHandler;
@property (weak) IBOutlet NSPopUpButton *wordCountWidget;
@property (strong) IBOutlet MPToolbarController *toolbarController;
@property (copy, nonatomic) NSString *autosaveName;
@property (copy, nonatomic) NSString *currentHeadHTML;
@property (strong, nonatomic) MPSidebarController *sidebar;
@property (strong, nonatomic) NSSplitView *outerSplitView;
@property (strong) HGMarkdownHighlighter *highlighter;
@property (strong) MPRenderer *renderer;
@property CGFloat previousSplitRatio;
@property BOOL manualRender;
@property BOOL copying;
@property BOOL printing;
@property BOOL shouldHandleBoundsChange;
@property BOOL isPreviewReady;
@property (strong) NSURL *currentBaseUrl;
@property CGFloat lastPreviewScrollTop;
@property (nonatomic, readonly) BOOL needsHtml;
@property (nonatomic) NSUInteger totalWords;
@property (nonatomic) NSUInteger totalCharacters;
@property (nonatomic) NSUInteger totalCharactersNoSpaces;
@property (strong) NSMenuItem *wordsMenuItem;
@property (strong) NSMenuItem *charMenuItem;
@property (strong) NSMenuItem *charNoSpacesMenuItem;
@property (nonatomic) BOOL needsToUnregister;
@property (nonatomic) BOOL alreadyRenderingInWeb;
@property (nonatomic) BOOL renderToWebPending;
@property (strong) NSArray<NSNumber *> *webViewHeaderLocations;
@property (strong) NSArray<NSNumber *> *editorHeaderLocations;
@property (nonatomic) BOOL inLiveScroll;

// Store file content in initializer until nib is loaded.
@property (copy) NSString *loadedString;

- (void)adjustPreviewContentInsets;
- (void)setPreviewScrollTopTo:(CGFloat)top;
- (void)refreshPreviewBackgroundColor;
- (void)harvestDiagramsFromPreview;
- (void)scaleWebview;
- (void)syncScrollers;
-(void) updateHeaderLocations;

@end

static void (^MPGetPreviewLoadingCompletionHandler(MPDocument *doc))()
{
    __weak MPDocument *weakObj = doc;
    return ^{
        [weakObj scaleWebview];
        [weakObj adjustPreviewContentInsets];
        [weakObj refreshPreviewBackgroundColor];
        [weakObj harvestDiagramsFromPreview];
        if (weakObj.preferences.editorSyncScrolling)
        {
            [weakObj updateHeaderLocations];
            [weakObj syncScrollers];
        }
        else
        {
            [weakObj setPreviewScrollTopTo:weakObj.lastPreviewScrollTop];
        }
    };
}


@implementation MPDocument

#pragma mark - Talking to the page

/** Scrolls the preview to a position in CSS pixels.
 *
 * The counterpart of reading it, which arrives on its own through the
 * scroll reporter rather than being asked for: there is no scroll view here
 * to set a bounds origin on.
 */
- (void)setPreviewScrollTopTo:(CGFloat)top
{
    if (!self.preview)
        return;
    NSString *js = [NSString stringWithFormat:
        @"window.scrollTo(0, %.2f);", top];
    [self.preview evaluateJavaScript:js completionHandler:nil];
    self.previewScrollTop = top;
}

/** Loads rendered markup into the preview.
 *
 * Not -loadHTMLString:baseURL:, which would be the obvious call: a page
 * loaded that way has an opaque origin, and WebKit2 then refuses every
 * local subresource it asks for. The stylesheet lives in Application
 * Support, the scripts in the bundle and the images beside the document,
 * so that leaves nothing but unstyled text.
 *
 * Writing the markup to a file and loading it as a file grants read access
 * explicitly. A <base> keeps relative paths in the document — an image next
 * to it — resolving against the document rather than against the temporary
 * file.
 */
- (void)loadPreviewHTML:(NSString *)html baseURL:(NSURL *)baseUrl
{
    NSURL *directory = self.previewScratchDirectory;
    if (!directory)
    {
        // Nowhere to write: better an unstyled preview than none.
        [self.preview loadHTMLString:html baseURL:baseUrl];
        return;
    }

    // Assets are emitted as file:// links by the renderer; they have to
    // arrive through the handler like everything else.
    html = [html stringByReplacingOccurrencesOfString:@"file://"
                                           withString:
        [MPPreviewURLScheme stringByAppendingString:@"://"]];

    // A <base> so that a relative path in the document — an image beside it
    // — resolves against the document rather than against the file this is
    // written to.
    NSString *directoryPath = baseUrl.isFileURL
        ? baseUrl.path.stringByDeletingLastPathComponent : nil;
    if (directoryPath.length)
    {
        NSURL *base = MPPreviewURLForPath(
            [directoryPath stringByAppendingString:@"/"]);
        NSString *tag = [NSString stringWithFormat:@"<base href=\"%@\">",
                         base.absoluteString];
        NSRange head = [html rangeOfString:@"<head>"];
        if (head.location != NSNotFound)
        {
            html = [html stringByReplacingCharactersInRange:head
                withString:[@"<head>" stringByAppendingString:tag]];
        }
    }

    NSURL *file = [directory URLByAppendingPathComponent:@"preview.html"];
    if (![html writeToURL:file atomically:YES
                 encoding:NSUTF8StringEncoding error:NULL])
    {
        [self.preview loadHTMLString:html baseURL:baseUrl];
        return;
    }

    NSURL *served = MPPreviewURLForPath(file.path);
    [self.preview loadRequest:[NSURLRequest requestWithURL:served]];
}

/** A per-document directory for the file the preview is loaded from. */
- (NSURL *)previewScratchDirectory
{
    if (_previewScratchDirectory)
        return _previewScratchDirectory;

    NSString *name = [NSString stringWithFormat:@"MacDownPreview-%@",
                      [[NSUUID UUID] UUIDString]];
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                  URLByAppendingPathComponent:name isDirectory:YES];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:url
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&error])
        return nil;

    _previewScratchDirectory = url;
    return url;
}

/** Asks the page for the diagrams it has drawn.
 *
 * Kept here so that exporting stays synchronous: a save panel hands back a
 * URL and the file is written on the spot, with no opportunity to wait for
 * another process to answer.
 */
- (void)harvestDiagramsFromPreview
{
    static NSString * const script =
        @"(function(){var out=[];"
        @"var nodes=document.querySelectorAll('.macdown-diagram svg');"
        @"for(var i=0;i<nodes.length;i++){"
        @"var c=nodes[i].cloneNode(true);"
        @"c.removeAttribute('width');c.removeAttribute('height');"
        @"c.style.width='';c.style.height='';c.style.maxWidth='100%';"
        @"out.push(c.outerHTML);}"
        // MathJax draws with currentColor, which is inherited. Detached from
        // the page for rasterising there is nothing to inherit from, and the
        // formula would come out invisible.
        @"var maths=[];"
        @"var m=document.querySelectorAll('mjx-container');"
        @"for(var j=0;j<m.length;j++){"
        @"var svg=m[j].querySelector('svg');"
        @"if(!svg)continue;"
        @"var k=svg.cloneNode(true);"
        @"k.setAttribute('color','#000000');"
        @"k.style.color='#000000';"
        // MathJax sizes its output in ex, which rasterises to a formula a
        // few pixels wide. The page knows what it actually drew.
        @"var r=svg.getBoundingClientRect();"
        @"if(r.width>0&&r.height>0){"
        @"k.setAttribute('width',Math.ceil(r.width));"
        @"k.setAttribute('height',Math.ceil(r.height));"
        @"k.style.width='';k.style.height='';}"
        @"maths.push({svg:k.outerHTML,"
        @"display:m[j].getAttribute('display')==='true'});}"
        @"try{window.webkit.messageHandlers.macdownDiagrams"
        @".postMessage({diagrams:out,formulas:maths});}catch(e){}"
        @"return out.length;})";

    // Installed as a function rather than run once, because it has to run
    // again later: MathJax typesets after the page has finished loading, so
    // a single pass here finds the diagrams and no formulas at all.
    NSString *install = [NSString stringWithFormat:
        @"window.MacDownHarvest = %@; MacDownHarvest();"
        @"if (window.MathJax && MathJax.startup && MathJax.startup.promise)"
        @" MathJax.startup.promise.then(function(){MacDownHarvest();});",
        script];
    [self.preview evaluateJavaScript:install completionHandler:nil];
}

/** Reads the body background out of the page, for the divider.
 *
 * Asked for once per load and kept, because the answer only changes when the
 * stylesheet does and the question now costs a round trip to another
 * process.
 */
- (void)refreshPreviewBackgroundColor
{
    if (!self.preview)
        return;
    NSString *js = @"getComputedStyle(document.body).backgroundColor";
    __weak MPDocument *weakSelf = self;
    [self.preview evaluateJavaScript:js completionHandler:
        ^(id result, NSError *error) {
        NSString *value = [result isKindOfClass:[NSString class]]
            ? result : nil;
        weakSelf.previewBackgroundColor = value.length
            ? [NSColor colorWithHTMLName:value] : nil;
        [weakSelf redrawDivider];
    }];
}

#pragma mark - Accessor

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

- (NSString *)markdown
{
    return self.editor.string;
}

- (void)setMarkdown:(NSString *)markdown
{
    self.editor.string = markdown;
}

- (NSString *)html
{
    return self.renderer.currentHtml;
}

- (BOOL)toolbarVisible
{
    return self.windowForSheet.toolbar.visible;
}

- (BOOL)previewVisible
{
    return (self.preview.frame.size.width != 0.0);
}

- (BOOL)editorVisible
{
    return (self.editorContainer.frame.size.width != 0.0);
}

- (BOOL)needsHtml
{
    if (self.preferences.markdownManualRender)
        return NO;
    return (self.previewVisible || self.preferences.editorShowWordCount);
}

- (void)setTotalWords:(NSUInteger)value
{
    _totalWords = value;
    NSString *key = NSLocalizedString(@"WORDS_PLURAL_STRING", @"");
    NSInteger rule = kJJPluralFormRule.integerValue;
    self.wordsMenuItem.title =
        [JJPluralForm pluralStringForNumber:value withPluralForms:key
                            usingPluralRule:rule localizeNumeral:NO];
}

- (void)setTotalCharacters:(NSUInteger)value
{
    _totalCharacters = value;
    NSString *key = NSLocalizedString(@"CHARACTERS_PLURAL_STRING", @"");
    NSInteger rule = kJJPluralFormRule.integerValue;
    self.charMenuItem.title =
        [JJPluralForm pluralStringForNumber:value withPluralForms:key
                            usingPluralRule:rule localizeNumeral:NO];
}

- (void)setTotalCharactersNoSpaces:(NSUInteger)value
{
    _totalCharactersNoSpaces = value;
    NSString *key = NSLocalizedString(@"CHARACTERS_NO_SPACES_PLURAL_STRING",
                                      @"");
    NSInteger rule = kJJPluralFormRule.integerValue;
    self.charNoSpacesMenuItem.title =
        [JJPluralForm pluralStringForNumber:value withPluralForms:key
                            usingPluralRule:rule localizeNumeral:NO];
}

- (void)setAutosaveName:(NSString *)autosaveName
{
    _autosaveName = autosaveName;
    self.splitView.autosaveName = autosaveName;
}


#pragma mark - Override

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    self.isPreviewReady = NO;
    self.shouldHandleBoundsChange = YES;
    self.previousSplitRatio = -1.0;
    
    return self;
}

- (NSString *)windowNibName
{
    return @"MPDocument";
}

/** Names the page uses to talk back to us. */
static NSString * const kMPScrollMessage = @"macdownScroll";
static NSString * const kMPMathJaxMessage = @"macdownMathJax";
static NSString * const kMPDiagramsMessage = @"macdownDiagrams";

/** Reports scrolling and the page's dimensions back to the document.
 *
 * WKWebView exposes no scroll view on macOS — the one on iOS has no
 * counterpart here — so the numbers the editor needs to stay in step have to
 * come from the page itself. Coalesced onto an animation frame: a scroll
 * fires far more often than there is any point answering, and every one of
 * these crosses out of the web process.
 */
static NSString * const kMPScrollReporterSource =
    @"(function(){"
    @"var pending=false;"
    @"function report(){"
    @"pending=false;"
    @"try{window.webkit.messageHandlers.macdownScroll.postMessage({"
    @"top:window.scrollY,"
    @"height:document.documentElement.scrollHeight,"
    @"viewport:window.innerHeight});}catch(e){}}"
    @"function schedule(){if(!pending){pending=true;"
    @"requestAnimationFrame(report);}}"
    @"window.addEventListener('scroll',schedule,{passive:true});"
    @"window.addEventListener('resize',schedule,{passive:true});"
    @"window.MacDownReportScroll=report;"
    @"schedule();"
    @"})();";

- (WKWebView *)buildPreviewWebView
{
    WKWebViewConfiguration *configuration =
        [[WKWebViewConfiguration alloc] init];

    WKUserContentController *content = configuration.userContentController;
    [content addScriptMessageHandler:self name:kMPScrollMessage];
    [content addScriptMessageHandler:self name:kMPMathJaxMessage];
    [content addScriptMessageHandler:self name:kMPDiagramsMessage];

    // At the end of the document, so the page it decorates exists, and in
    // every frame the preview will ever load rather than being re-injected
    // by hand after each render.
    WKUserScript *reporter = [[WKUserScript alloc]
        initWithSource:kMPScrollReporterSource
         injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
      forMainFrameOnly:YES];
    [content addUserScript:reporter];

    // Everything the preview loads comes through here. See
    // MPPreviewSchemeHandler for why it cannot simply be file://.
    self.previewSchemeHandler = [[MPPreviewSchemeHandler alloc] init];
    [configuration setURLSchemeHandler:self.previewSchemeHandler
                          forURLScheme:MPPreviewURLScheme];
    if (@available(macOS 10.15, *))
        configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSZeroRect
                                            configuration:configuration];
    webView.navigationDelegate = self;
    webView.UIDelegate = self;

    // The page paints its own background, dark or light. Left opaque, the
    // web view flashes white behind every load.
    if (@available(macOS 12.0, *))
        webView.underPageBackgroundColor = [NSColor clearColor];
    webView.allowsMagnification = NO;

    return webView;
}

/** Puts the preview inside the container the nib provides. */
- (void)installPreviewWebView
{
    NSView *container = self.previewContainer;
    if (!container)
        return;

    WKWebView *webView = [self buildPreviewWebView];
    webView.frame = container.bounds;
    webView.autoresizingMask =
        NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:webView];
    self.preview = webView;
}


- (void)windowControllerDidLoadNib:(NSWindowController *)controller
{
    [super windowControllerDidLoadNib:controller];

    [self installPreviewWebView];

    // Unified toolbar, but the content deliberately does NOT run underneath
    // it: no NSWindowStyleMaskFullSizeContentView here.
    //
    // This window shows two backdrops at once whose brightness is unrelated,
    // because the editor theme is picked independently of the system
    // appearance and is routinely dark while the preview is light. With the
    // content extending under the toolbar, items drawn without a background
    // of their own took a single glyph colour from the appearance and
    // disappeared over whichever half happened to match it. Keeping the
    // toolbar in its own titlebar area gives every item a predictable ground.
    NSWindow *window = controller.window;
    window.toolbarStyle = NSWindowToolbarStyleUnified;

    [self installSidebarInWindow:window];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // All files use their absolute path to keep their window states.
    NSString *autosaveName = kMPDefaultAutosaveName;
    if (self.fileURL)
        autosaveName = self.fileURL.absoluteString;
    controller.window.frameAutosaveName = autosaveName;
    self.autosaveName = autosaveName;

    // Perform initial resizing manually because for some reason untitled
    // documents do not pick up the autosaved frame automatically in 10.10.
    NSString *rectString = MPRectStringForAutosaveName(autosaveName);
    if (!rectString)
        rectString = MPRectStringForAutosaveName(kMPDefaultAutosaveName);
    if (rectString)
        [controller.window setFrameFromString:rectString];

    self.highlighter =
        [[HGMarkdownHighlighter alloc] initWithTextView:self.editor
                                           waitInterval:0.0];
    self.renderer = [[MPRenderer alloc] init];
    self.renderer.dataSource = self;
    self.renderer.delegate = self;

    for (NSString *key in MPEditorPreferencesToObserve())
    {
        [defaults addObserver:self forKeyPath:key
                      options:NSKeyValueObservingOptionNew context:NULL];
    }
    for (NSString *key in MPEditorKeysToObserve())
    {
        [self.editor addObserver:self forKeyPath:key
                         options:NSKeyValueObservingOptionNew context:NULL];
    }

    self.editor.postsFrameChangedNotifications = YES;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(editorTextDidChange:)
                   name:NSTextDidChangeNotification object:self.editor];
    [center addObserver:self selector:@selector(userDefaultsDidChange:)
                   name:NSUserDefaultsDidChangeNotification
                 object:[NSUserDefaults standardUserDefaults]];
    [center addObserver:self selector:@selector(editorBoundsDidChange:)
                   name:NSViewBoundsDidChangeNotification
                 object:self.editor.enclosingScrollView.contentView];
    [center addObserver:self selector:@selector(editorFrameDidChange:)
                   name:NSViewFrameDidChangeNotification object:self.editor];
    [center addObserver:self selector:@selector(didRequestEditorReload:)
                   name:MPDidRequestEditorSetupNotification object:nil];
    [center addObserver:self selector:@selector(didRequestPreviewReload:)
                   name:MPDidRequestPreviewRenderNotification object:nil];
    [center addObserver:self selector:@selector(willStartLiveScroll:)
                   name:NSScrollViewWillStartLiveScrollNotification
                 object:self.editor.enclosingScrollView];
    [center addObserver:self selector:@selector(didEndLiveScroll:)
                   name:NSScrollViewDidEndLiveScrollNotification
                 object:self.editor.enclosingScrollView];

    self.needsToUnregister = YES;

    self.wordsMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL
                                             keyEquivalent:@""];
    self.charMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL
                                            keyEquivalent:@""];
    self.charNoSpacesMenuItem = [[NSMenuItem alloc] initWithTitle:@""
                                                           action:NULL
                                                    keyEquivalent:@""];

    NSPopUpButton *wordCountWidget = self.wordCountWidget;
    [wordCountWidget removeAllItems];
    [wordCountWidget.menu addItem:self.wordsMenuItem];
    [wordCountWidget.menu addItem:self.charMenuItem];
    [wordCountWidget.menu addItem:self.charNoSpacesMenuItem];
    [wordCountWidget selectItemAtIndex:self.preferences.editorWordCountType];
    wordCountWidget.alphaValue = 0.9;
    wordCountWidget.hidden = !self.preferences.editorShowWordCount;
    wordCountWidget.enabled = NO;

    // These needs to be queued until after the window is shown, so that editor
    // can have the correct dimention for size-limiting and stuff. See
    // https://github.com/uranusjr/macdown/issues/236
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self setupEditor:nil];
        [self redrawDivider];
        [self reloadFromLoadedString];
    }];
}

- (void)reloadFromLoadedString
{
    if (self.loadedString && self.editor && self.renderer && self.highlighter)
    {
        self.editor.string = self.loadedString;
        self.loadedString = nil;
        [self.renderer parseAndRenderNow];
        [self.highlighter parseAndHighlightNow];
    }
}

- (void)close
{
    if (self.needsToUnregister) 
    {
        // Close can be called multiple times, but this can only be done once.
        // http://www.cocoabuilder.com/archive/cocoa/240166-nsdocument-close-method-calls-itself.html
        self.needsToUnregister = NO;

        // Need to cleanup these so that callbacks won't crash the app.
        [self.highlighter deactivate];
        self.highlighter.targetTextView = nil;
        self.highlighter = nil;
        self.renderer = nil;
        if (_previewScratchDirectory)
        {
            [[NSFileManager defaultManager]
                removeItemAtURL:_previewScratchDirectory error:NULL];
            _previewScratchDirectory = nil;
        }
        self.preview.navigationDelegate = nil;
        self.preview.UIDelegate = nil;
        [self.preview.configuration.userContentController
            removeAllScriptMessageHandlers];

        [[NSNotificationCenter defaultCenter] removeObserver:self];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

        for (NSString *key in MPEditorPreferencesToObserve())
            [defaults removeObserver:self forKeyPath:key];
        for (NSString *key in MPEditorKeysToObserve())
            [self.editor removeObserver:self forKeyPath:key];
    }

    [super close];
}

+ (BOOL)autosavesInPlace
{
    return YES;
}

+ (NSArray *)writableTypes
{
    return @[@"net.daringfireball.markdown"];
}

- (BOOL)isDocumentEdited
{
    // Prevent save dialog on an unnamed, empty document. The file will still
    // show as modified (because it is), but no save dialog will be presented
    // when the user closes it.
    if (!self.presentedItemURL && !self.editor.string.length)
        return NO;
    return [super isDocumentEdited];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName
             error:(NSError *__autoreleasing *)outError
{
    if (self.preferences.editorEnsuresNewlineAtEndOfFile)
    {
        NSCharacterSet *newline = [NSCharacterSet newlineCharacterSet];
        NSString *text = self.editor.string;
        NSUInteger end = text.length;
        if (end && ![newline characterIsMember:[text characterAtIndex:end - 1]])
        {
            NSRange selection = self.editor.selectedRange;
            [self.editor insertText:@"\n" replacementRange:NSMakeRange(end, 0)];
            self.editor.selectedRange = selection;
        }
    }
    return [super writeToURL:url ofType:typeName error:outError];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    return [self.editor.string dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName
               error:(NSError **)outError
{
    NSString *content = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
    if (!content)
        return NO;

    self.loadedString = content;
    [self reloadFromLoadedString];
    return YES;
}

- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel
{
    savePanel.extensionHidden = NO;
    if (self.fileURL && self.fileURL.isFileURL)
    {
        NSString *path = self.fileURL.path;

        // Use path of parent directory if this is a file. Otherwise this is it.
        BOOL isDir = NO;
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path
                                                           isDirectory:&isDir];
        if (!exists || !isDir)
            path = [path stringByDeletingLastPathComponent];

        savePanel.directoryURL = [NSURL fileURLWithPath:path];
    }
    else
    {
        // Suggest a file name for new documents.
        NSString *fileName = self.presumedFileName;
        if (fileName && ![fileName hasExtension:@"md"])
        {
            fileName = [fileName stringByAppendingPathExtension:@"md"];
            savePanel.nameFieldStringValue = fileName;
        }
    }
    
    // Get supported extensions from plist
    static NSMutableArray *supportedExtensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        supportedExtensions = [NSMutableArray array];
        NSDictionary *infoDict = [NSBundle mainBundle].infoDictionary;
        for (NSDictionary *docType in infoDict[@"CFBundleDocumentTypes"])
        {
            NSArray *exts = docType[@"CFBundleTypeExtensions"];
            if (exts.count)
            {
                [supportedExtensions addObjectsFromArray:exts];
            }
        }
    });
    
    savePanel.allowedFileTypes = supportedExtensions;
    savePanel.allowsOtherFileTypes = YES; // Allow all extensions.
    
    return [super prepareSavePanel:savePanel];
}

- (NSPrintInfo *)printInfo
{
    NSPrintInfo *info = [super printInfo];
    if (!info)
        info = [[NSPrintInfo sharedPrintInfo] copy];
    info.horizontalPagination = NSAutoPagination;
    info.verticalPagination = NSAutoPagination;
    info.verticallyCentered = NO;
    info.topMargin = 50.0;
    info.leftMargin = 0.0;
    info.rightMargin = 0.0;
    info.bottomMargin = 50.0;
    return info;
}

- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)printSettings
                                           error:(NSError *__autoreleasing *)e
{
    NSPrintInfo *info = [self.printInfo copy];
    [info.dictionary addEntriesFromDictionary:printSettings];

    // WKWebView prints itself; the frame view this used to reach for has no
    // counterpart, and does not need one.
    return [self.preview printOperationWithPrintInfo:info];
}

- (void)printDocumentWithSettings:(NSDictionary *)printSettings
                   showPrintPanel:(BOOL)showPrintPanel delegate:(id)delegate
                 didPrintSelector:(SEL)selector contextInfo:(void *)contextInfo
{
    self.printing = YES;
    NSInvocation *invocation = nil;
    if (delegate && selector)
    {
        NSMethodSignature *signature =
            [NSMethodSignature methodSignatureForSelector:selector];
        invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = delegate;
        if (contextInfo)
            [invocation setArgument:&contextInfo atIndex:2];
    }
    [super printDocumentWithSettings:printSettings
                      showPrintPanel:showPrintPanel delegate:self
                    didPrintSelector:@selector(document:didPrint:context:)
                         contextInfo:(void *)invocation];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    BOOL result = [super validateUserInterfaceItem:item];
    SEL action = item.action;
    if (action == @selector(toggleToolbar:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.title = self.toolbarVisible ?
            NSLocalizedString(@"Hide Toolbar",
                              @"Toggle reveal toolbar") :
            NSLocalizedString(@"Show Toolbar",
                              @"Toggle reveal toolbar");
    }
    else if (action == @selector(togglePreviewPane:))
    {
        NSMenuItem *it = ((NSMenuItem *)item);
        it.hidden = (!self.previewVisible && self.previousSplitRatio < 0.0);
        it.title = self.previewVisible ?
            NSLocalizedString(@"Hide Preview Pane",
                              @"Toggle preview pane menu item") :
            NSLocalizedString(@"Restore Preview Pane",
                              @"Toggle preview pane menu item");

    }
    else if (action == @selector(toggleEditorPane:))
    {
        NSMenuItem *it = (NSMenuItem*)item;
        it.title = self.editorVisible ?
        NSLocalizedString(@"Hide Editor Pane",
                          @"Toggle editor pane menu item") :
        NSLocalizedString(@"Restore Editor Pane",
                          @"Toggle editor pane menu item");
    }
    return result;
}


#pragma mark - NSSplitViewDelegate

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    [self redrawDivider];
    self.editor.editable = self.editorVisible;
}


#pragma mark - NSTextViewDelegate

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (commandSelector == @selector(insertTab:))
        return ![self textViewShouldInsertTab:textView];
    else if (commandSelector == @selector(insertBacktab:))
        return ![self textViewShouldInsertBacktab:textView];
    else if (commandSelector == @selector(insertNewline:))
        return ![self textViewShouldInsertNewline:textView];
    else if (commandSelector == @selector(deleteBackward:))
        return ![self textViewShouldDeleteBackward:textView];
    else if (commandSelector == @selector(moveToLeftEndOfLine:))
        return ![self textViewShouldMoveToLeftEndOfLine:textView];
    return NO;
}

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range
                                              replacementString:(NSString *)str
{
    // Ignore if this originates from an IM marked text commit event.
    if (NSIntersectionRange(textView.markedRange, range).length)
        return YES;

    if (self.preferences.editorCompleteMatchingCharacters)
    {
        BOOL strikethrough = self.preferences.extensionStrikethough;
        if ([textView completeMatchingCharactersForTextInRange:range
                                                    withString:str
                                          strikethroughEnabled:strikethrough])
            return NO;
    }
    
	// For every change, set the typing attributes
	if (range.location > 0) {
		NSRange prevRange = range;
		prevRange.location -= 1;
		prevRange.length = 1;

		NSDictionary *attr = [[textView attributedString] fontAttributesInRange:prevRange];
		[textView setTypingAttributes:attr];
	}

    return YES;
}

#pragma mark - Fake NSTextViewDelegate

- (BOOL)textViewShouldInsertTab:(NSTextView *)textView
{
    if (textView.selectedRange.length != 0)
    {
        [self indent:nil];
        return NO;
    }
    else if (self.preferences.editorConvertTabs)
    {
        [textView insertSpacesForTab];
        return NO;
    }
    return YES;
}

- (BOOL)textViewShouldInsertBacktab:(NSTextView *)textView
{
    [self unindent:nil];
    return NO;
}

- (BOOL)textViewShouldInsertNewline:(NSTextView *)textView
{
    if ([textView insertMappedContent])
        return NO;

    BOOL inserts = self.preferences.editorInsertPrefixInBlock;
    if (inserts && [textView completeNextListItem:
            self.preferences.editorAutoIncrementNumberedLists])
        return NO;
    if (inserts && [textView completeNextBlockquoteLine])
        return NO;
    if ([textView completeNextIndentedLine])
        return NO;
    return YES;
}

- (BOOL)textViewShouldDeleteBackward:(NSTextView *)textView
{
    NSRange selectedRange = textView.selectedRange;
    if (self.preferences.editorCompleteMatchingCharacters)
    {
        NSUInteger location = selectedRange.location;
        if ([textView deleteMatchingCharactersAround:location])
            return NO;
    }
    if (self.preferences.editorConvertTabs && !selectedRange.length)
    {
        NSUInteger location = selectedRange.location;
        if ([textView unindentForSpacesBefore:location])
            return NO;
    }
    return YES;
}

- (BOOL)textViewShouldMoveToLeftEndOfLine:(NSTextView *)textView
{
    if (!self.preferences.editorSmartHome)
        return YES;
    NSUInteger cur = textView.selectedRange.location;
    NSUInteger location =
        [textView.string locationOfFirstNonWhitespaceCharacterInLineBefore:cur];
    if (location == cur || cur == 0)
        return YES;
    else if (cur >= textView.string.length)
        cur = textView.string.length - 1;

    // We don't want to jump rows when the line is wrapped. (#103)
    // If the line is wrapped, the target will be higher than the current glyph.
    NSLayoutManager *manager = textView.layoutManager;
    NSTextContainer *container = textView.textContainer;
    NSRect targetRect =
        [manager boundingRectForGlyphRange:NSMakeRange(location, 1)
                           inTextContainer:container];
    NSRect currentRect =
        [manager boundingRectForGlyphRange:NSMakeRange(cur, 1)
                           inTextContainer:container];
    if (targetRect.origin.y != currentRect.origin.y)
        return YES;

    textView.selectedRange = NSMakeRange(location, 0);
    return NO;
}


#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView
    didCommitNavigation:(WKNavigation *)navigation
{
    // The flush-window dance that used to live here is gone: the methods it
    // called have been no-ops since the window server stopped working that
    // way, and WKWebView draws in another process regardless.
}

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation
{
    // Always, MathJax or not. This used to be left to a callback from
    // MathJax's own startup when maths was enabled, which meant the scroll
    // position stayed unsynced if that callback never arrived. MathJax still
    // calls in when it has finished, as a second pass once the equations have
    // changed the layout.
    id callback = MPGetPreviewLoadingCompletionHandler(self);
    [[NSOperationQueue mainQueue] addOperationWithBlock:callback];

    self.isPreviewReady = YES;

    if (self.preferences.editorShowWordCount)
        [self updateWordCount];

    self.alreadyRenderingInWeb = NO;

    if (self.renderToWebPending)
        [self.renderer parseAndRenderNow];

    self.renderToWebPending = NO;
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self webView:webView didFinishNavigation:navigation];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error
{
    [self webView:webView didFinishNavigation:navigation];
}

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:
        (void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURL *url = navigationAction.request.URL;

    if (navigationAction.navigationType == WKNavigationTypeLinkActivated)
    {
        // The same page: a fragment jump, which the page can do itself.
        if ([self.currentBaseUrl isEqual:url])
        {
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }
        // Somewhere else: ours to open, not the preview's to navigate to.
        if (![self isCurrentBaseUrl:url])
        {
            decisionHandler(WKNavigationActionPolicyCancel);
            [self openOrCreateFileForUrl:url];
            return;
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}


#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)controller
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    if ([message.name isEqualToString:kMPScrollMessage])
    {
        NSDictionary *body = message.body;
        if (![body isKindOfClass:[NSDictionary class]])
            return;

        self.previewScrollTop = [body[@"top"] doubleValue];
        self.lastPreviewScrollTop = self.previewScrollTop;
        self.previewContentHeight = [body[@"height"] doubleValue];
        self.previewViewportHeight = [body[@"viewport"] doubleValue];
        return;
    }

    if ([message.name isEqualToString:kMPDiagramsMessage])
    {
        NSDictionary *body = message.body;
        if ([body isKindOfClass:[NSDictionary class]])
        {
            self.harvestedDiagrams = body[@"diagrams"];
            self.harvestedFormulas = body[@"formulas"];
        }
        return;
    }

    if ([message.name isEqualToString:kMPMathJaxMessage])
    {
        // MathJax has finished typesetting, and the layout has moved under
        // whatever was measured before it ran.
        MPGetPreviewLoadingCompletionHandler(self)();
        return;
    }
}


#pragma mark - MPRendererDataSource

- (BOOL)rendererLoading {
	return self.preview.loading;
}
    
- (NSString *)rendererMarkdown:(MPRenderer *)renderer
{
    return self.editor.string;
}

- (NSString *)rendererHTMLTitle:(MPRenderer *)renderer
{
    NSString *n = self.fileURL.lastPathComponent.stringByDeletingPathExtension;
    return n ? n : @"";
}


#pragma mark - MPRendererDelegate

- (int)rendererExtensions:(MPRenderer *)renderer
{
    return self.preferences.extensionFlags;
}

- (BOOL)rendererHasSmartyPants:(MPRenderer *)renderer
{
    return self.preferences.extensionSmartyPants;
}

- (BOOL)rendererRendersTOC:(MPRenderer *)renderer
{
    return self.preferences.htmlRendersTOC;
}

- (NSString *)rendererStyleName:(MPRenderer *)renderer
{
    return self.preferences.htmlStyleName;
}

- (BOOL)rendererDetectsFrontMatter:(MPRenderer *)renderer
{
    return self.preferences.htmlDetectFrontMatter;
}

- (BOOL)rendererHasSyntaxHighlighting:(MPRenderer *)renderer
{
    return self.preferences.htmlSyntaxHighlighting;
}

- (BOOL)rendererHasMermaid:(MPRenderer *)renderer
{
    return self.preferences.htmlMermaid;
}

- (BOOL)rendererHasGraphviz:(MPRenderer *)renderer
{
    return self.preferences.htmlGraphviz;
}

- (MPCodeBlockAccessoryType)rendererCodeBlockAccesory:(MPRenderer *)renderer
{
    return self.preferences.htmlCodeBlockAccessory;
}

- (BOOL)rendererHasMathJax:(MPRenderer *)renderer
{
    return self.preferences.htmlMathJax;
}

- (NSString *)rendererHighlightingThemeName:(MPRenderer *)renderer
{
    return self.preferences.htmlHighlightingThemeName;
}

/// The contents of <head>, or nil if the document is not shaped as expected.
NS_INLINE NSString *MPHeadOfHTML(NSString *html)
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [[NSRegularExpression alloc] initWithPattern:
            @"<head[^>]*>([\\s\\S]*)</head>"
                    options:NSRegularExpressionCaseInsensitive error:NULL];
    });
    NSTextCheckingResult *match =
        [regex firstMatchInString:html options:0
                            range:NSMakeRange(0, html.length)];
    if (!match)
        return nil;
    return [html substringWithRange:[match rangeAtIndex:1]];
}

/// The contents of <body>, or nil if the document is not shaped as expected.
NS_INLINE NSString *MPBodyOfHTML(NSString *html)
{
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [[NSRegularExpression alloc] initWithPattern:
            @"<body[^>]*>([\\s\\S]*)</body>"
                    options:NSRegularExpressionCaseInsensitive error:NULL];
    });
    NSTextCheckingResult *match =
        [regex firstMatchInString:html options:0
                            range:NSMakeRange(0, html.length)];
    if (!match)
        return nil;
    return [html substringWithRange:[match rangeAtIndex:1]];
}


/** Whether a WikiLink target resolves to a file next to the document.
 *
 * Tries the name as written first, then the extensions a Markdown document is
 * likely to carry, which is the same order MacDown itself uses when it
 * follows a link.
 */
NS_INLINE BOOL MPWikiTargetExists(NSURL *directory, NSString *target)
{
    if (!directory.isFileURL || !target.length)
        return NO;

    NSFileManager *manager = [NSFileManager defaultManager];
    NSURL *base = [directory URLByAppendingPathComponent:target];
    if ([manager fileExistsAtPath:base.path])
        return YES;

    for (NSString *extension in @[@"md", @"markdown", @"txt"])
    {
        NSURL *candidate = [base URLByAppendingPathExtension:extension];
        if ([manager fileExistsAtPath:candidate.path])
            return YES;
    }
    return NO;
}

/** Turns [[Target]] and [[Target|label]] into links.
 *
 * The href deliberately carries no extension: MacDown's own link handling
 * already tries .md and offers to create what is missing, so a WikiLink to a
 * page that does not exist yet behaves the way it does in a wiki.
 *
 * Runs on the rendered HTML rather than the Markdown so that fenced code and
 * inline code can be skipped — [[this]] inside a code block is code, not a
 * link, and a pass over the Markdown could not tell the difference.
 */
- (NSString *)htmlByResolvingWikiLinksIn:(NSString *)html
{
    static NSRegularExpression *wikiRegex = nil;
    static NSRegularExpression *codeRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        wikiRegex = [[NSRegularExpression alloc] initWithPattern:
            @"\\[\\[([^\\[\\]|]+)(?:\\|([^\\[\\]]+))?\\]\\]"
                                                        options:0 error:NULL];
        codeRegex = [[NSRegularExpression alloc] initWithPattern:
            @"<pre[\\s\\S]*?</pre>|<code[\\s\\S]*?</code>"
                    options:NSRegularExpressionCaseInsensitive error:NULL];
    });

    NSRange whole = NSMakeRange(0, html.length);
    NSArray<NSTextCheckingResult *> *links =
        [wikiRegex matchesInString:html options:0 range:whole];
    if (!links.count)
        return html;

    NSArray<NSTextCheckingResult *> *codeSpans =
        [codeRegex matchesInString:html options:0 range:whole];

    // An unsaved document has nowhere to resolve against, so every target
    // reads as missing until the file has been saved somewhere.
    NSURL *directory = self.fileURL.URLByDeletingLastPathComponent;

    NSMutableString *result = [html mutableCopy];

    // Back to front, so each replacement leaves the earlier ranges valid.
    for (NSInteger i = (NSInteger)links.count - 1; i >= 0; i--)
    {
        NSTextCheckingResult *link = links[(NSUInteger)i];

        BOOL insideCode = NO;
        for (NSTextCheckingResult *span in codeSpans)
        {
            if (NSIntersectionRange(span.range, link.range).length)
            {
                insideCode = YES;
                break;
            }
        }
        if (insideCode)
            continue;

        NSCharacterSet *spaces = [NSCharacterSet whitespaceCharacterSet];
        NSString *target = [[html substringWithRange:[link rangeAtIndex:1]]
            stringByTrimmingCharactersInSet:spaces];
        if (!target.length)
            continue;

        NSRange labelRange = [link rangeAtIndex:2];
        NSString *label = target;
        if (labelRange.location != NSNotFound)
        {
            label = [[html substringWithRange:labelRange]
                stringByTrimmingCharactersInSet:spaces];
        }

        NSString *href = [target stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet URLPathAllowedCharacterSet]] ?: target;

        NSString *replacement;
        if (MPWikiTargetExists(directory, target))
        {
            replacement = [NSString stringWithFormat:
                @"<a href=\"%@\" class=\"wikilink\">%@</a>", href, label];
        }
        else
        {
            NSString *tip = NSLocalizedString(
                @"This page does not exist yet",
                @"tooltip on a WikiLink whose target is missing");
            replacement = [NSString stringWithFormat:
                @"<a href=\"%@\" class=\"wikilink wikilink-missing\" "
                @"title=\"%@\">%@</a>", href, tip, label];
        }

        [result replaceCharactersInRange:link.range withString:replacement];
    }
    return result;
}


- (void)renderer:(MPRenderer *)renderer didProduceHTMLOutput:(NSString *)html
{
    if (self.alreadyRenderingInWeb)
    {
        self.renderToWebPending = YES;
        return;
    }
    
    if (self.printing)
        return;
    
    self.alreadyRenderingInWeb = YES;

    // Delayed copying for -copyHtml.
    if (self.copying)
    {
        self.copying = NO;
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard writeObjects:@[self.renderer.currentHtml]];
    }

    if (self.preferences.htmlWikiLinks)
        html = [self htmlByResolvingWikiLinksIn:html];

    NSURL *baseUrl = self.fileURL;
    if (!baseUrl)   // Unsaved doument; just use the default URL.
        baseUrl = self.preferences.htmlDefaultDirectoryUrl;

    self.manualRender = self.preferences.markdownManualRender;

    // Typing reloads the whole page unless the head is unchanged.
    //
    // A full load tears the document down and builds it again, and that is
    // what makes the preview blink on every keystroke: the window flush
    // guards around it are no-ops on current AppKit. Replacing the body
    // instead leaves the head — the stylesheets, and the scripts that have
    // already run — exactly where it is, so there is nothing to flash and
    // the reader keeps their scroll position.
    //
    // The head is compared rather than assumed: it changes when a preference
    // adds or removes a stylesheet, and those renders still need a real load.
    NSString *head = MPHeadOfHTML(html);
    NSString *body = MPBodyOfHTML(html);

    if (self.isPreviewReady && body && head
            && [self.currentBaseUrl isEqualTo:baseUrl]
            && [head isEqualToString:self.currentHeadHTML]
            && [self replacePreviewBodyWith:body])
    {
        return;
    }

    [self loadPreviewHTML:html baseURL:baseUrl];
    self.currentBaseUrl = baseUrl;
    self.currentHeadHTML = head;
}


/** Swaps the preview's body, leaving the rest of the document alone.
 *
 * Returns NO if the document is not in a state to be updated this way, in
 * which case the caller falls back to a full load.
 */
- (BOOL)replacePreviewBodyWith:(NSString *)body
{
    if (!self.isPreviewReady || !self.preview)
        return NO;

    // The markup travels as a JSON string rather than being pasted into the
    // script: a document contains quotes, newlines and backslashes, and
    // escaping them by hand is a bug waiting for the first apostrophe.
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:@[body]
                                                      options:0 error:NULL];
    NSString *literal = [[NSString alloc] initWithData:encoded
                                              encoding:NSUTF8StringEncoding];
    if (!literal)
        return NO;

    // Assigning innerHTML does not re-run the page's scripts, so everything
    // that decorates the document has to be invited back for this revision.
    // window keeps its properties across the swap, so they are all still
    // there. Mermaid goes first: it replaces whole code blocks, and there is
    // no point highlighting the ones that are about to disappear.
    NSString *js = [NSString stringWithFormat:
        @"(function(){"
        @"if (!document.body) return false;"
        @"document.body.innerHTML = %@[0];"
        @"if (window.MacDownRenderMermaid) MacDownRenderMermaid();"
        @"if (window.MacDownRenderGraphviz) MacDownRenderGraphviz();"
        @"if (window.Prism && Prism.highlightAll) Prism.highlightAll();"
        @"if (window.MathJax && MathJax.typesetPromise)"
        @" MathJax.typesetPromise();"
        @"if (window.MacDownReportScroll) MacDownReportScroll();"
        @"return true;})()", literal];
    [self.preview evaluateJavaScript:js completionHandler:nil];

    // No load means no load-finished delegate call, so the bookkeeping it
    // does has to happen here: the same completion handler for scaling,
    // insets and scroll syncing, and the flags that let the next render run.
    id callback = MPGetPreviewLoadingCompletionHandler(self);
    [[NSOperationQueue mainQueue] addOperationWithBlock:callback];

    if (self.preferences.editorShowWordCount)
        [self updateWordCount];

    self.alreadyRenderingInWeb = NO;
    if (self.renderToWebPending)
        [self.renderer parseAndRenderNow];
    self.renderToWebPending = NO;

    return YES;
}


#pragma mark - Notification handler

- (void)editorTextDidChange:(NSNotification *)notification
{
    if (self.editor.proseHighlightsEnabled)
        [self updateProseSummary];

    [self.sidebar updateOutlineWithMarkdown:self.editor.string ?: @""];

    if (self.needsHtml)
        [self.renderer parseAndRenderLater];
}

- (void)userDefaultsDidChange:(NSNotification *)notification
{
    MPRenderer *renderer = self.renderer;

    // Force update if we're switching from manual to auto, or renderer settings
    // changed.
    int rendererFlags = self.preferences.rendererFlags;
    if ((!self.preferences.markdownManualRender && self.manualRender)
            || renderer.rendererFlags != rendererFlags)
    {
        renderer.rendererFlags = rendererFlags;
        [renderer parseAndRenderLater];
    }
    else
    {
        [renderer parseIfPreferencesChanged];
        [renderer renderIfPreferencesChanged];
    }
}

- (void)editorFrameDidChange:(NSNotification *)notification
{
    if (self.preferences.editorWidthLimited)
        [self adjustEditorInsets];
}

- (void)willStartLiveScroll:(NSNotification *)notification
{
    [self updateHeaderLocations];
    _inLiveScroll = YES;
}

-(void)didEndLiveScroll:(NSNotification *)notification
{
    _inLiveScroll = NO;
}

- (void)editorBoundsDidChange:(NSNotification *)notification
{
    if (!self.shouldHandleBoundsChange)
        return;

    if (self.preferences.editorSyncScrolling)
    {
        @synchronized(self) {
            self.shouldHandleBoundsChange = NO;
            if(!_inLiveScroll){
                [self updateHeaderLocations];
            }
            
            [self syncScrollers];
            self.shouldHandleBoundsChange = YES;
        }
    }
}

- (void)didRequestEditorReload:(NSNotification *)notification
{
    NSString *key =
        notification.userInfo[MPDidRequestEditorSetupNotificationKeyName];
    [self setupEditor:key];
}

- (void)didRequestPreviewReload:(NSNotification *)notification
{
    [self render:nil];
}



#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context
{
    if (object == self.editor)
    {
        if (!self.highlighter.isActive)
            return;
        id value = change[NSKeyValueChangeNewKey];
        NSString *preferenceKey = MPEditorPreferenceKeyWithValueKey(keyPath);
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:value forKey:preferenceKey];
    }
    else if (object == [NSUserDefaults standardUserDefaults])
    {
        if (self.highlighter.isActive)
            [self setupEditor:keyPath];
        [self redrawDivider];
    }
}


#pragma mark - IBAction

- (IBAction)copyHtml:(id)sender
{
    // Dis-select things in WebView so that it's more obvious we're NOT
    // respecting the selection range.
    [self.preview evaluateJavaScript:
        @"if (window.getSelection) getSelection().removeAllRanges();"
                   completionHandler:nil];

    // If the preview is hidden, the HTML are not updating on text change.
    // Perform one extra rendering so that the HTML is up to date, and do the
    // copy in the rendering callback.
    if (!self.needsHtml)
    {
        self.copying = YES;
        [self.renderer parseAndRenderNow];
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[self.renderer.currentHtml]];
}

/** A PNG <img> tag for SVG markup, for consumers that cannot read SVG.
 *
 * Rasterised above 1:1 and then declared at its point size, so the picture
 * carries enough detail to survive being printed rather than looking soft.
 */
NS_INLINE NSString *MPImageTagForSVG(NSString *svg, CGFloat scale)
{
    NSData *svgData = [svg dataUsingEncoding:NSUTF8StringEncoding];
    NSImage *image = svgData ? [[NSImage alloc] initWithData:svgData] : nil;
    NSSize points = image ? image.size : NSZeroSize;
    if (points.width <= 0.0 || points.height <= 0.0)
        return nil;

    NSInteger wide = (NSInteger)ceil(points.width * scale);
    NSInteger high = (NSInteger)ceil(points.height * scale);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:wide pixelsHigh:high
                   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:0 bitsPerPixel:0];
    rep.size = points;

    NSGraphicsContext *context =
        [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    if (!context)
        return nil;

    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    [image drawInRect:NSMakeRect(0.0, 0.0, points.width, points.height)];
    [NSGraphicsContext restoreGraphicsState];

    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                    properties:@{}];
    if (!png.length)
        return nil;

    return [NSString stringWithFormat:
            @"<p><img alt=\"diagram\" width=\"%ld\" src=\"data:image/png;"
            @"base64,%@\"></p>",
            (long)lround(points.width),
            [png base64EncodedStringWithOptions:0]];
}


/** The diagrams as the preview drew them, in document order.
 *
 * Both kinds: mermaid and Graphviz share one container class, and both are
 * wanted in an export for the same reason.
 */
- (NSArray<NSString *> *)renderedDiagrams
{
    // Normalised for a document that is not MacDown's preview: the fixed
    // pixel size the zoom viewport needs gives way to a responsive one. The
    // element ids stay, because the <style> mermaid inlines is scoped to them.
    static NSString * const script =
        @"(function(){var out=[];"
        @"var nodes=document.querySelectorAll('.macdown-diagram svg');"
        @"for(var i=0;i<nodes.length;i++){"
        @"var c=nodes[i].cloneNode(true);"
        @"c.removeAttribute('width');c.removeAttribute('height');"
        @"c.style.width='';c.style.height='';c.style.maxWidth='100%';"
        @"out.push(c.outerHTML);}"
        @"return JSON.stringify(out);})()";

    // Collected after each render and kept, rather than asked for here.
    // Exporting is synchronous — a save panel returns a URL and the file is
    // written — and there is no longer any way to ask the page a question
    // and have the answer in the same breath.
    (void)script;
    return self.harvestedDiagrams ?: @[];
}

/** Puts the drawn diagrams into exported markup, in place of their sources.
 *
 * The alternative would be shipping the mermaid library with every export and
 * re-rendering on open, which is 1.1 MB per file and needs JavaScript enabled
 * wherever it lands.
 *
 * Diagrams are matched to fences by position, so a mismatch in the counts
 * means something did not draw. Rather than risk pairing a diagram with the
 * wrong fence, that leaves every fence alone as a code block.
 */
/** Puts the typeset formulas into exported markup, in place of their TeX.
 *
 * An EPUB carries no scripts, and neither does a Word file, so TeX left in
 * the text stays TeX: the reader sees \(E = mc^2\) where the formula should
 * be. MathJax has already drawn it in the preview, so what is exported is
 * that drawing.
 *
 * MathJax normalises the delimiters while it works, so by the time this runs
 * every formula is \( \) or \[ \] whatever the document used.
 */
- (NSString *)htmlByInliningFormulasIn:(NSString *)html asImages:(BOOL)asImages
{
    NSArray<NSDictionary *> *formulas = self.harvestedFormulas;
    if (!formulas.count)
        return html;

    // Non-greedy, and the two forms in one alternation so that the matches
    // come back in document order — the order MathJax typeset them in.
    static NSString * const pattern =
        @"\\\\\\[[\\s\\S]*?\\\\\\]|\\\\\\([\\s\\S]*?\\\\\\)";
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:pattern options:0
                                                    error:NULL];
    NSArray<NSTextCheckingResult *> *found =
        [regex matchesInString:html options:0
                         range:NSMakeRange(0, html.length)];

    // An export embeds its scripts, and MathJax's own source is full of the
    // sequences this is looking for — twenty of them in a document with two
    // formulas in it. Only what lies outside a script is TeX.
    static NSRegularExpression *scriptRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        scriptRegex = [NSRegularExpression regularExpressionWithPattern:
            @"<script[\\s\\S]*?</script>"
            options:NSRegularExpressionCaseInsensitive error:NULL];
    });
    NSArray<NSTextCheckingResult *> *scripts =
        [scriptRegex matchesInString:html options:0
                               range:NSMakeRange(0, html.length)];

    NSMutableArray<NSTextCheckingResult *> *matches = [NSMutableArray array];
    for (NSTextCheckingResult *candidate in found)
    {
        BOOL inScript = NO;
        for (NSTextCheckingResult *script in scripts)
        {
            if (NSLocationInRange(candidate.range.location, script.range))
            {
                inScript = YES;
                break;
            }
        }
        if (!inScript)
            [matches addObject:candidate];
    }

    if (matches.count != formulas.count)
        return html;

    NSMutableString *result = [html mutableCopy];
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--)
    {
        NSDictionary *formula = formulas[(NSUInteger)i];
        NSString *svg = formula[@"svg"];
        if (![svg isKindOfClass:[NSString class]])
            continue;

        // EPUB carries SVG natively, and it is the better answer: the
        // formula stays sharp at any zoom, and NSImage cannot rasterise
        // what MathJax emits anyway — its <defs> and <use> come back a
        // solid black rectangle. Word has no SVG, so there it is a picture
        // and the black rectangle is a known limit.
        NSString *tag = asImages ? MPImageTagForSVG(svg, 3.0) : svg;
        if (!tag)
            continue;

        // A display formula sits on its own line; an inline one has to sit
        // on the text's baseline, or it rides above it.
        if ([formula[@"display"] boolValue])
        {
            tag = [NSString stringWithFormat:
                @"<span style=\"display:block;text-align:center\">%@</span>",
                tag];
        }
        else
        {
            // Only the picture needs help sitting on the baseline. The SVG
            // arrives with MathJax's own vertical-align on it, which is the
            // exact offset for that formula — and a second style attribute
            // would not be valid XML anyway.
            if (asImages)
            {
                tag = [tag stringByReplacingOccurrencesOfString:@"<img "
                    withString:@"<img style=\"vertical-align:middle\" "];
            }
        }

        [result replaceCharactersInRange:matches[(NSUInteger)i].range
                              withString:tag];
    }
    return result;
}

- (NSString *)htmlByInliningDiagramsIn:(NSString *)html asImages:(BOOL)asImages
{
    NSArray<NSString *> *diagrams = self.renderedDiagrams;
    if (!diagrams.count)
        return html;

    // Matches what hoedown_patch_render_blockcode emits for a fence, for
    // every language that becomes a drawing: mermaid, and the six Graphviz
    // layout engines. Both lists are in document order, so the nth fence is
    // the nth diagram.
    static NSString * const pattern =
        @"<div><pre[^>]*><code class=\"language-"
        @"(?:mermaid|dot|neato|fdp|circo|twopi|osage)\">[\\s\\S]*?"
        @"</code></pre></div>";
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:pattern options:0
                                                    error:NULL];
    NSArray<NSTextCheckingResult *> *matches =
        [regex matchesInString:html options:0
                         range:NSMakeRange(0, html.length)];
    if (matches.count != diagrams.count)
        return html;

    // Back to front, so each replacement leaves the earlier ranges valid.
    NSMutableString *result = [html mutableCopy];
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--)
    {
        NSString *svg = diagrams[(NSUInteger)i];
        NSString *replacement = asImages
            ? MPImageTagForSVG(svg, 2.0)
            : [NSString stringWithFormat:@"<p>%@</p>", svg];
        if (!replacement)
            continue;
        [result replaceCharactersInRange:matches[(NSUInteger)i].range
                              withString:replacement];
    }
    return result;
}


- (IBAction)exportHtml:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"html"];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;

    MPExportPanelAccessoryViewController *controller =
        [[MPExportPanelAccessoryViewController alloc] init];
    controller.stylesIncluded = (BOOL)self.preferences.htmlStyleName;
    controller.highlightingIncluded = self.preferences.htmlSyntaxHighlighting;
    panel.accessoryView = controller.view;

    NSWindow *w = self.windowForSheet;
    [panel beginSheetModalForWindow:w completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton)
            return;
        BOOL styles = controller.stylesIncluded;
        BOOL highlighting = controller.highlightingIncluded;
        NSString *html = [self.renderer HTMLForExportWithStyles:styles
                                                   highlighting:highlighting];
        if (self.preferences.htmlWikiLinks)
        html = [self htmlByResolvingWikiLinksIn:html];
        html = [self htmlByInliningDiagramsIn:html asImages:NO];
        [html writeToURL:panel.URL atomically:NO encoding:NSUTF8StringEncoding
                   error:NULL];
    }];
}

- (IBAction)exportEpub:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"epub"];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;

    NSWindow *window = self.windowForSheet;
    [panel beginSheetModalForWindow:window completionHandler:^(NSInteger res) {
        if (res != NSFileHandlingPanelOKButton)
            return;
        [self writeEpubToURL:panel.URL];
    }];
}

- (void)writeEpubToURL:(NSURL *)url
{
    // Styles are not linked in: an EPUB carries its own, and a reader is
    // entitled to override them. Diagrams are rasterised for the same reason
    // the Word export does it — nothing here runs scripts.
    NSString *html = [self.renderer HTMLForExportWithStyles:NO
                                               highlighting:NO];
    if (self.preferences.htmlWikiLinks)
        html = [self htmlByResolvingWikiLinksIn:html];
    html = [self htmlByInliningDiagramsIn:html asImages:YES];
    html = [self htmlByInliningFormulasIn:html asImages:NO];

    NSURL *cssURL = [[NSBundle mainBundle] URLForResource:@"epub-export"
                                            withExtension:@"css"
                                             subdirectory:@"Extensions"];
    NSString *css = cssURL
        ? [NSString stringWithContentsOfURL:cssURL encoding:NSUTF8StringEncoding
                                      error:NULL]
        : @"";

    MPEpubMetadata *metadata = [[MPEpubMetadata alloc] init];
    metadata.title = self.presumedFileName.stringByDeletingPathExtension;
    metadata.author = NSFullUserName();

    NSData *epub = MPEpubDataFromHTML(html, css, self.fileURL, metadata);
    if (!epub)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(
            @"The EPUB could not be built.",
            @"EPUB export failure title");
        alert.informativeText = NSLocalizedString(
            @"The rendered document could not be turned into the XHTML an "
            @"EPUB requires.",
            @"EPUB export failure detail");
        [alert beginSheetModalForWindow:self.windowForSheet
                      completionHandler:nil];
        return;
    }

    NSError *error = nil;
    if (![epub writeToURL:url options:NSDataWritingAtomic error:&error])
        [self presentError:error];
}

- (IBAction)exportDocx:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"docx"];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;

    NSWindow *window = self.windowForSheet;
    [panel beginSheetModalForWindow:window completionHandler:^(NSInteger res) {
        if (res != NSFileHandlingPanelOKButton)
            return;
        [self writeDocxToURL:panel.URL];
    }];
}

/** PNG bytes and page size for one image reachable from exported markup.
 *
 * Everything is re-encoded to PNG so the archive only has to declare one
 * image content type, and rendered at the source's own pixel size so nothing
 * is upscaled or thrown away.
 */
NS_INLINE MPDocxImage *MPDocxImageFromData(NSData *data, NSString *placeholder)
{
    NSImage *image = data.length ? [[NSImage alloc] initWithData:data] : nil;
    NSSize points = image ? image.size : NSZeroSize;
    if (points.width <= 0.0 || points.height <= 0.0)
        return nil;

    NSInteger wide = 0;
    NSInteger high = 0;
    for (NSImageRep *rep in image.representations)
    {
        wide = MAX(wide, rep.pixelsWide);
        high = MAX(high, rep.pixelsHigh);
    }
    // Vector sources report no pixels; twice the point size prints cleanly.
    if (wide <= 0 || high <= 0)
    {
        wide = (NSInteger)ceil(points.width * 2.0);
        high = (NSInteger)ceil(points.height * 2.0);
    }

    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:wide pixelsHigh:high
                   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:0 bitsPerPixel:0];
    bitmap.size = points;

    NSGraphicsContext *context =
        [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    if (!context)
        return nil;
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    [image drawInRect:NSMakeRect(0.0, 0.0, points.width, points.height)];
    [NSGraphicsContext restoreGraphicsState];

    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG
                                       properties:@{}];
    if (!png.length)
        return nil;

    MPDocxImage *result = [[MPDocxImage alloc] init];
    result.placeholder = placeholder;
    result.pngData = png;
    result.pointSize = points;
    return result;
}

/** Loads what an <img src> points at, for the Word export.
 *
 * Only data: URIs and local files. A remote image is left alone rather than
 * quietly turning an export into a network fetch.
 */
- (NSData *)imageDataForExportSource:(NSString *)source
{
    if ([source hasPrefix:@"data:"])
    {
        NSRange marker = [source rangeOfString:@";base64,"];
        if (marker.location == NSNotFound)
            return nil;
        NSString *encoded = [source substringFromIndex:NSMaxRange(marker)];
        return [[NSData alloc] initWithBase64EncodedString:encoded
            options:NSDataBase64DecodingIgnoreUnknownCharacters];
    }

    NSURL *url = [NSURL URLWithString:source];
    if (!url.scheme)
    {
        NSURL *base = self.fileURL.URLByDeletingLastPathComponent;
        url = base ? [NSURL URLWithString:source relativeToURL:base] : nil;
    }
    if (!url.isFileURL)
        return nil;
    return [NSData dataWithContentsOfURL:url];
}

/** Swaps every <img> for a plain-text marker, collecting the pictures.
 *
 * The markers survive AppKit's Word writer as ordinary runs, which is what
 * gives MPDocxPostProcessing somewhere to put the pictures back.
 */
- (NSString *)html:(NSString *)html
    withImagesReplacedByPlaceholders:(NSMutableArray<MPDocxImage *> *)images
                             skipped:(NSUInteger *)skipped
{
    NSRegularExpression *imgRegex = [NSRegularExpression
        regularExpressionWithPattern:@"<img[^>]*>"
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];
    NSRegularExpression *srcRegex = [NSRegularExpression
        regularExpressionWithPattern:@"src\\s*=\\s*\"([^\"]*)\""
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];

    NSArray<NSTextCheckingResult *> *matches =
        [imgRegex matchesInString:html options:0
                            range:NSMakeRange(0, html.length)];

    NSMutableString *result = [html mutableCopy];
    NSUInteger lost = 0;

    // Back to front, so each replacement leaves the earlier ranges valid.
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--)
    {
        NSRange tagRange = matches[(NSUInteger)i].range;
        NSString *tag = [html substringWithRange:tagRange];

        NSTextCheckingResult *src =
            [srcRegex firstMatchInString:tag options:0
                                   range:NSMakeRange(0, tag.length)];
        MPDocxImage *image = nil;
        if (src)
        {
            NSString *source = [tag substringWithRange:[src rangeAtIndex:1]];
            NSString *placeholder = [NSString stringWithFormat:
                @"MPIMGPLACEHOLDER%ld", (long)i];
            image = MPDocxImageFromData(
                [self imageDataForExportSource:source], placeholder);
        }

        if (image)
        {
            [images addObject:image];
            [result replaceCharactersInRange:tagRange
                                 withString:image.placeholder];
        }
        else
        {
            lost++;
        }
    }

    if (skipped)
        *skipped = lost;
    return result;
}

/** The markup handed to the Word converter, on its own stylesheet.
 *
 * Not the preview style: that one is written for a screen, and the reader
 * that builds the Word document honours only a narrow subset of it. The
 * bundled word-export.css says the same things in the terms that reader
 * understands. Syntax highlighting is left out too, since it only ever
 * colours anything once Prism has run, and nothing runs in a .docx.
 */
- (NSString *)htmlForWordExport
{
    NSString *html = [self.renderer HTMLForExportWithStyles:NO
                                               highlighting:NO];
    if (self.preferences.htmlWikiLinks)
        html = [self htmlByResolvingWikiLinksIn:html];

    NSURL *url = [[NSBundle mainBundle] URLForResource:@"word-export"
                                        withExtension:@"css"
                                         subdirectory:@"Extensions"];
    NSString *css = url
        ? [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding
                                      error:NULL]
        : nil;
    if (!css.length)
        return html;

    NSString *tag = [NSString stringWithFormat:@"<style>\n%@\n</style>", css];
    NSRange head = [html rangeOfString:@"</head>"];
    if (head.location == NSNotFound)
        return html;

    return [html stringByReplacingCharactersInRange:head
                                         withString:
            [tag stringByAppendingString:@"</head>"]];
}

/** Collects the runs in a table cell, keeping the inline formatting.
 *
 * Walks the element rather than stripping tags, so a bold word or a snippet
 * of code inside a cell still reads as one in the Word file.
 */
static void MPCollectCellRuns(NSXMLNode *node,
                              NSMutableArray<MPDocxTextRun *> *runs,
                              BOOL bold, BOOL italic, BOOL monospaced)
{
    for (NSXMLNode *child in node.children)
    {
        if (child.kind == NSXMLTextKind)
        {
            NSString *text = child.stringValue;
            if (!text.length)
                continue;
            MPDocxTextRun *run = [[MPDocxTextRun alloc] init];
            run.text = text;
            run.bold = bold;
            run.italic = italic;
            run.monospaced = monospaced;
            [runs addObject:run];
            continue;
        }

        if (child.kind != NSXMLElementKind)
            continue;

        NSString *name = child.name.lowercaseString;
        if ([name isEqualToString:@"br"])
        {
            MPDocxTextRun *run = [[MPDocxTextRun alloc] init];
            run.text = @" ";
            [runs addObject:run];
            continue;
        }

        BOOL nowBold = bold
            || [name isEqualToString:@"strong"] || [name isEqualToString:@"b"];
        BOOL nowItalic = italic
            || [name isEqualToString:@"em"] || [name isEqualToString:@"i"];
        BOOL nowMono = monospaced
            || [name isEqualToString:@"code"] || [name isEqualToString:@"tt"];
        MPCollectCellRuns(child, runs, nowBold, nowItalic, nowMono);
    }
}

/** Reads one hoedown-emitted <table> into the model the builder wants.
 *
 * Parsed as XML, which hoedown's output is: it closes every cell and escapes
 * its text. Returns nil on anything it cannot parse, so the table is left to
 * AppKit rather than half-converted.
 */
NS_INLINE MPDocxTable *MPDocxTableFromHTML(NSString *html,
                                           NSString *placeholder)
{
    // Void elements hoedown writes unclosed, which XML will not accept.
    NSMutableString *xml = [html mutableCopy];
    [xml replaceOccurrencesOfString:@"<br>" withString:@"<br/>"
                            options:NSCaseInsensitiveSearch
                              range:NSMakeRange(0, xml.length)];

    NSError *error = nil;
    NSXMLDocument *parsed = [[NSXMLDocument alloc] initWithXMLString:xml
                                                            options:0
                                                              error:&error];
    NSXMLElement *root = parsed.rootElement;
    if (!root)
        return nil;

    NSArray<NSXMLNode *> *rowNodes = [root nodesForXPath:@".//tr" error:NULL];
    if (!rowNodes.count)
        return nil;

    NSMutableArray *rows = [NSMutableArray array];
    for (NSXMLNode *rowNode in rowNodes)
    {
        NSArray<NSXMLNode *> *cellNodes =
            [rowNode nodesForXPath:@"./th|./td" error:NULL];
        if (!cellNodes.count)
            continue;

        NSMutableArray<MPDocxTableCell *> *cells = [NSMutableArray array];
        for (NSXMLNode *cellNode in cellNodes)
        {
            MPDocxTableCell *cell = [[MPDocxTableCell alloc] init];
            cell.header = [cellNode.name.lowercaseString isEqualToString:@"th"];

            NSMutableArray<MPDocxTextRun *> *runs = [NSMutableArray array];
            MPCollectCellRuns(cellNode, runs, cell.header, NO, NO);
            cell.runs = runs;

            // hoedown puts the column alignment in a style attribute.
            NSXMLNode *style = [(NSXMLElement *)cellNode attributeForName:@"style"];
            NSString *value = style.stringValue;
            if ([value containsString:@"center"])
                cell.alignment = @"center";
            else if ([value containsString:@"right"])
                cell.alignment = @"right";

            [cells addObject:cell];
        }
        [rows addObject:cells];
    }

    if (!rows.count)
        return nil;

    MPDocxTable *table = [[MPDocxTable alloc] init];
    table.placeholder = placeholder;
    table.rows = rows;
    return table;
}

/** Swaps every <table> for a text marker, collecting its structure.
 *
 * The structure has to be read here: by the time AppKit has written the
 * .docx, a table is a run of tab-separated paragraphs and there is nothing
 * left to rebuild from.
 */
- (NSString *)html:(NSString *)html
    withTablesReplacedByPlaceholders:(NSMutableArray<MPDocxTable *> *)tables
{
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<table[^>]*>[\\s\\S]*?</table>"
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];
    NSArray<NSTextCheckingResult *> *matches =
        [regex matchesInString:html options:0
                         range:NSMakeRange(0, html.length)];

    NSMutableString *result = [html mutableCopy];

    // Back to front, so each replacement leaves the earlier ranges valid.
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--)
    {
        NSRange range = matches[(NSUInteger)i].range;
        NSString *placeholder =
            [NSString stringWithFormat:@"MPTBLPLACEHOLDER%ld", (long)i];
        MPDocxTable *table = MPDocxTableFromHTML(
            [html substringWithRange:range], placeholder);
        if (!table)
            continue;

        [tables addObject:table];
        [result replaceCharactersInRange:range withString:placeholder];
    }
    return result;
}


- (void)writeDocxToURL:(NSURL *)url
{
    NSString *html = [self htmlForWordExport];

    // Rasterised rather than left as SVG, because AppKit's HTML reader has no
    // SVG support at all and would drop the diagrams without a word. They
    // then travel the same road as any other image below.
    html = [self htmlByInliningDiagramsIn:html asImages:YES];
    html = [self htmlByInliningFormulasIn:html asImages:YES];

    NSMutableArray<MPDocxImage *> *images = [NSMutableArray array];
    NSUInteger skipped = 0;
    html = [self html:html withImagesReplacedByPlaceholders:images
              skipped:&skipped];

    NSMutableArray<MPDocxTable *> *tables = [NSMutableArray array];
    html = [self html:html withTablesReplacedByPlaceholders:tables];

    NSData *htmlData = [html dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *readOptions = @{
        NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
        NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding),
    };

    NSError *error = nil;
    NSAttributedString *rich =
        [[NSAttributedString alloc] initWithData:htmlData options:readOptions
                              documentAttributes:NULL error:&error];
    if (!rich)
    {
        [self presentError:error];
        return;
    }

    NSDictionary *writeOptions = @{
        NSDocumentTypeDocumentAttribute: NSOfficeOpenXMLTextDocumentType,
    };
    NSData *docx = [rich dataFromRange:NSMakeRange(0, rich.length)
                   documentAttributes:writeOptions error:&error];
    if (!docx)
    {
        [self presentError:error];
        return;
    }

    // Puts the pictures in, which AppKit's writer would otherwise have left
    // out of the file entirely.
    NSData *embedded = MPDocxDataByEmbeddingImages(docx, images);
    if (embedded)
        docx = embedded;

    // Shading and list indents, which the writer does not carry over either.
    // The family and colour have to match word-export.css, since the font is
    // what identifies a code paragraph once the markup is gone.
    NSData *repaired = MPDocxDataByRepairingLayout(docx, @"Menlo", @"F4F4F4");
    if (repaired)
        docx = repaired;

    // Tables, which the writer flattens into tab-separated paragraphs. The
    // fonts and size match word-export.css so a table sits with the prose.
    NSData *tabled = MPDocxDataByBuildingTables(docx, tables,
                                                @"Helvetica Neue", @"Menlo",
                                                10.0);
    if (tabled)
        docx = tabled;

    // Menlo ships with macOS and nowhere else, so on its own it leaves code
    // blocks proportional in Word on Windows. The font table gives Word a
    // fixed-pitch alternative to reach for.
    NSData *withFonts = MPDocxDataByDeclaringFonts(docx, @"Menlo", @"Consolas",
                                                   @"Helvetica Neue",
                                                   @"Arial");
    if (withFonts)
        docx = withFonts;

    if (![docx writeToURL:url options:NSDataWritingAtomic error:&error])
    {
        [self presentError:error];
        return;
    }

    if (skipped)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(
            @"Some images were not included",
            @"Word export partial images");
        alert.informativeText = [NSString stringWithFormat:NSLocalizedString(
            @"Could not read %lu of the images in this document, so they are "
            @"missing from the Word file. Images loaded over the network are "
            @"not fetched during an export.",
            @"Word export partial images"), (unsigned long)skipped];
        [alert runModal];
    }
}

- (IBAction)exportPdf:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"pdf"];
    if (self.presumedFileName)
        panel.nameFieldStringValue = self.presumedFileName;
    
    NSWindow *w = nil;
    NSArray *windowControllers = self.windowControllers;
    if (windowControllers.count > 0)
        w = [windowControllers[0] window];

    [panel beginSheetModalForWindow:w completionHandler:^(NSInteger result) {
        if (result != NSFileHandlingPanelOKButton)
            return;

        NSDictionary *settings = @{
            NSPrintJobDisposition: NSPrintSaveJob,
            NSPrintJobSavingURL: panel.URL,
        };
        [self printDocumentWithSettings:settings showPrintPanel:NO delegate:nil
                       didPrintSelector:NULL contextInfo:NULL];
    }];
}

- (IBAction)convertToH1:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:1];
}

- (IBAction)convertToH2:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:2];
}

- (IBAction)convertToH3:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:3];
}

- (IBAction)convertToH4:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:4];
}

- (IBAction)convertToH5:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:5];
}

- (IBAction)convertToH6:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:6];
}

- (IBAction)convertToParagraph:(id)sender
{
    [self.editor makeHeaderForSelectedLinesWithLevel:0];
}

- (IBAction)toggleStrong:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"**" suffix:@"**"];
}

- (IBAction)toggleEmphasis:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"*" suffix:@"*"];
}

- (IBAction)toggleInlineCode:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"`" suffix:@"`"];
}

- (IBAction)toggleStrikethrough:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"~~" suffix:@"~~"];
}

- (IBAction)toggleUnderline:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"_" suffix:@"_"];
}

- (IBAction)toggleHighlight:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"==" suffix:@"=="];
}

- (IBAction)toggleComment:(id)sender
{
    [self.editor toggleForMarkupPrefix:@"<!--" suffix:@"-->"];
}

- (IBAction)toggleLink:(id)sender
{
    BOOL inserted = [self.editor toggleForMarkupPrefix:@"[" suffix:@"]()"];
    if (!inserted)
        return;

    NSRange selectedRange = self.editor.selectedRange;
    NSUInteger location = selectedRange.location + selectedRange.length + 2;
    selectedRange = NSMakeRange(location, 0);

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *url = [pb URLForType:NSPasteboardTypeString].absoluteString;
    if (url)
    {
        [self.editor insertText:url replacementRange:selectedRange];
        selectedRange.length = url.length;
    }
    self.editor.selectedRange = selectedRange;
}

/** Markdown link for an image being inserted into this document.
 *
 * Relative to the document's own folder when the image sits inside it, so
 * that moving the pair together keeps the link alive; absolute otherwise.
 * Percent-encoded either way, because an unescaped space ends the link
 * target and the rest of the path leaks into the page as text.
 */
/** MIME type for a data: URI built from an image file.
 *
 * Derived from the extension rather than from UTType, which would pull the
 * UniformTypeIdentifiers framework onto the target for one lookup.
 */
NS_INLINE NSString *MPMIMETypeForImageURL(NSURL *url)
{
    static NSDictionary *types = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        types = @{
            @"png": @"image/png",
            @"jpg": @"image/jpeg",
            @"jpeg": @"image/jpeg",
            @"gif": @"image/gif",
            @"svg": @"image/svg+xml",
            @"webp": @"image/webp",
            @"heic": @"image/heic",
            @"heif": @"image/heif",
            @"avif": @"image/avif",
            @"tif": @"image/tiff",
            @"tiff": @"image/tiff",
            @"bmp": @"image/bmp",
            @"ico": @"image/x-icon",
        };
    });
    NSString *type = types[url.pathExtension.lowercaseString];
    return type ? type : @"application/octet-stream";
}


NS_INLINE NSString *MPImageLinkForURL(NSURL *imageURL, NSURL *documentURL)
{
    NSString *path = imageURL.path;
    NSString *directory = documentURL.URLByDeletingLastPathComponent.path;

    if (directory.length)
    {
        NSString *prefix = [directory hasSuffix:@"/"]
            ? directory : [directory stringByAppendingString:@"/"];
        if ([path hasPrefix:prefix])
            path = [path substringFromIndex:prefix.length];
        else
            path = nil;
    }
    else
    {
        path = nil;
    }

    if (!path)
        return imageURL.absoluteString;

    NSCharacterSet *allowed = [NSCharacterSet URLPathAllowedCharacterSet];
    return [path stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}


- (NSString *)dataURIForImageURL:(NSURL *)imageURL
{
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:imageURL
                                        options:NSDataReadingMappedIfSafe
                                          error:&error];
    if (!data)
    {
        [self presentError:error];
        return nil;
    }
    return [NSString stringWithFormat:@"data:%@;base64,%@",
            MPMIMETypeForImageURL(imageURL),
            [data base64EncodedStringWithOptions:0]];
}

- (void)insertImageMarkupForURL:(NSURL *)imageURL embedded:(BOOL)embedded
{
    NSString *target = embedded
        ? [self dataURIForImageURL:imageURL]
        : MPImageLinkForURL(imageURL, self.fileURL);
    if (!target)
        return;

    NSRange selected = self.editor.selectedRange;

    // A selection is taken as the caption; otherwise the file name stands in,
    // which is at least a real alt text rather than an empty bracket.
    NSString *alt = selected.length
        ? [self.editor.string substringWithRange:selected]
        : imageURL.lastPathComponent.stringByDeletingPathExtension;

    NSString *markup =
        [NSString stringWithFormat:@"![%@](%@)", alt, target];

    [self.editor insertText:markup replacementRange:selected];
    self.editor.selectedRange =
        NSMakeRange(selected.location + markup.length, 0);
}

/** Base64 turns a binary file into document text, so a large image lands in
 * the editor as megabytes of one unbreakable line. Worth a question first.
 */
- (BOOL)confirmEmbeddingImageURL:(NSURL *)imageURL
{
    static const unsigned long long kWarnAboveBytes = 1024 * 1024;

    NSNumber *size = nil;
    [imageURL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
    if (!size || size.unsignedLongLongValue <= kWarnAboveBytes)
        return YES;

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    NSString *readable =
        [formatter stringFromByteCount:(long long)size.unsignedLongLongValue];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedString(
        @"Embed this image in the document?",
        @"Large inline image confirmation");
    alert.informativeText = [NSString stringWithFormat:NSLocalizedString(
        @"%@ of image data will be written into the text as Base64, which is "
        @"roughly a third larger again. Linking the file instead keeps the "
        @"document small.",
        @"Large inline image confirmation"), readable];
    [alert addButtonWithTitle:NSLocalizedString(
        @"Embed", @"Large inline image confirmation")];
    [alert addButtonWithTitle:NSLocalizedString(
        @"Cancel", @"Large inline image confirmation")];

    return [alert runModal] == NSAlertFirstButtonReturn;
}

- (IBAction)toggleImage:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.message = NSLocalizedString(
        @"Choose an image to link in the document",
        @"Image chooser prompt");

    // Deprecated in favour of -allowedContentTypes, which needs UTType from
    // UniformTypeIdentifiers and so a new framework on the target. Left as is
    // rather than growing the project file for a filter.
    panel.allowedFileTypes = [NSImage imageTypes];

    NSButton *embedToggle = [NSButton checkboxWithTitle:NSLocalizedString(
        @"Embed the image in the document (Base64)",
        @"Image chooser option") target:nil action:NULL];
    embedToggle.toolTip = NSLocalizedString(
        @"Writes the image data inline instead of linking the file, so the "
        @"document no longer depends on it. Note that some sites, GitHub "
        @"among them, strip inline image data.",
        @"Image chooser option help");
    embedToggle.frame = NSMakeRect(18.0, 10.0, 384.0, 20.0);

    NSView *accessory =
        [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 40.0)];
    [accessory addSubview:embedToggle];
    panel.accessoryView = accessory;
    panel.accessoryViewDisclosed = YES;

    NSWindow *window = self.windowForSheet;
    void (^handler)(NSModalResponse) = ^(NSModalResponse result) {
        if (result != NSModalResponseOK)
            return;
        NSURL *url = panel.URLs.firstObject;
        if (!url)
            return;

        BOOL embedded = (embedToggle.state == NSControlStateValueOn);
        if (embedded && ![self confirmEmbeddingImageURL:url])
            return;

        [self insertImageMarkupForURL:url embedded:embedded];
    };

    if (window)
        [panel beginSheetModalForWindow:window completionHandler:handler];
    else
        handler([panel runModal]);
}

- (IBAction)toggleOrderedList:(id)sender
{
    [self.editor toggleBlockWithPattern:@"^[0-9]+ \\S" prefix:@"1. "];
}

- (IBAction)toggleUnorderedList:(id)sender
{
    NSString *marker = self.preferences.editorUnorderedListMarker;
    [self.editor toggleBlockWithPattern:@"^[\\*\\+-] \\S" prefix:marker];
}

- (IBAction)toggleBlockquote:(id)sender
{
    [self.editor toggleBlockWithPattern:@"^> \\S" prefix:@"> "];
}

- (IBAction)indent:(id)sender
{
    NSString *padding = @"\t";
    if (self.preferences.editorConvertTabs)
        padding = @"    ";
    [self.editor indentSelectedLinesWithPadding:padding];
}

- (IBAction)unindent:(id)sender
{
    [self.editor unindentSelectedLines];
}

- (IBAction)insertNewParagraph:(id)sender
{
    NSRange range = self.editor.selectedRange;
    NSUInteger location = range.location;
    NSUInteger length = range.length;
    NSString *content = self.editor.string;
    NSInteger newlineBefore = [content locationOfFirstNewlineBefore:location];
    NSUInteger newlineAfter =
        [content locationOfFirstNewlineAfter:location + length - 1];

    // If we are on an empty line, treat as normal return key; otherwise insert
    // two newlines.
    if (location == newlineBefore + 1 && location == newlineAfter)
        [self.editor insertNewline:self];
    else
        [self.editor insertText:@"\n\n"];
}

- (IBAction)setEditorOneQuarter:(id)sender
{
    [self setSplitViewDividerLocation:0.25];
}

- (IBAction)setEditorThreeQuarters:(id)sender
{
    [self setSplitViewDividerLocation:0.75];
}

- (IBAction)setEqualSplit:(id)sender
{
    [self setSplitViewDividerLocation:0.5];
}

/** Turns the prose underlines on and off.
 *
 * Per window rather than a stored preference: it is a thing you switch on to
 * go over a draft, not a way you leave the editor set up.
 */
/** Wraps the editor/preview split in a second one, with the sidebar first.
 *
 * Done here rather than in the nib because the nib pins the existing split
 * view to the window, and moving it means taking those constraints with it.
 */
- (void)installSidebarInWindow:(NSWindow *)window
{
    NSView *content = window.contentView;
    NSView *panes = self.splitView;
    if (!content || !panes || self.outerSplitView)
        return;

    self.sidebar = [[MPSidebarController alloc] init];
    self.sidebar.delegate = self;

    NSMutableArray<NSLayoutConstraint *> *stale = [NSMutableArray array];
    for (NSLayoutConstraint *constraint in content.constraints)
    {
        if (constraint.firstItem == panes || constraint.secondItem == panes)
            [stale addObject:constraint];
    }
    [content removeConstraints:stale];
    [panes removeFromSuperview];

    NSSplitView *outer = [[NSSplitView alloc] initWithFrame:content.bounds];
    outer.vertical = YES;
    outer.dividerStyle = NSSplitViewDividerStyleThin;
    // The sidebar is delegate of its own split view: it owns the width
    // rules, and this document is already delegate of the inner one.
    outer.delegate = (id<NSSplitViewDelegate>)self.sidebar;
    // No autosave name. NSSplitView restores a saved position after the
    // subviews are in place, which lands on top of the position set below
    // and leaves the sidebar as an unusable sliver.
    outer.translatesAutoresizingMaskIntoConstraints = NO;

    [outer addSubview:self.sidebar.view];
    [outer addSubview:panes];
    [content addSubview:outer];

    [NSLayoutConstraint activateConstraints:@[
        [outer.topAnchor constraintEqualToAnchor:content.topAnchor],
        [outer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [outer.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [outer.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
    ]];

    // The panes take the space; the sidebar keeps the width it was given.
    [outer setHoldingPriority:NSLayoutPriorityDefaultHigh
           forSubviewAtIndex:0];
    self.outerSplitView = outer;

    // Closed to begin with: a sidebar nobody asked for is in the way.
    [outer setPosition:0.0 ofDividerAtIndex:0];

    [self.sidebar setRootURL:self.fileURL.URLByDeletingLastPathComponent];
    [self.sidebar updateOutlineWithMarkdown:self.editor.string ?: @""];
}

- (IBAction)toggleSidebar:(id)sender
{
    NSSplitView *outer = self.outerSplitView;
    if (!outer)
        return;

    NSView *sidebar = outer.subviews.firstObject;
    BOOL visible = ![outer isSubviewCollapsed:sidebar]
        && sidebar.frame.size.width > 1.0;
    [outer setPosition:(visible ? 0.0 : 240.0) ofDividerAtIndex:0];
    [outer adjustSubviews];

    if (!visible)
    {
        [self.sidebar setRootURL:self.fileURL.URLByDeletingLastPathComponent];
        [self.sidebar updateOutlineWithMarkdown:self.editor.string ?: @""];
    }
}

#pragma mark - MPSidebarControllerDelegate

- (void)sidebarDidSelectHeadingRange:(NSRange)range
{
    if (NSMaxRange(range) > self.editor.string.length)
        return;

    // Selecting the heading line, rather than only scrolling to it, makes it
    // obvious where you have landed.
    [self.editor setSelectedRange:range];
    [self.editor scrollRangeToVisible:range];
    [self.windowForSheet makeFirstResponder:self.editor];
}

- (void)sidebarDidSelectFileURL:(NSURL *)url
{
    [[NSDocumentController sharedDocumentController]
        openDocumentWithContentsOfURL:url display:YES
                    completionHandler:^(NSDocument *document,
                                        BOOL alreadyOpen, NSError *error) {
        (void)document; (void)alreadyOpen; (void)error;
    }];
}


/** Opens the maths sheet and inserts what comes back.
 *
 * The delimiters are chosen here rather than in the sheet, because which
 * ones a document wants is a preference: inline maths is written with
 * dollars only when the user has asked for that, and with \( \) otherwise.
 */
- (IBAction)showMathEditor:(id)sender
{
    NSWindow *window = self.windowForSheet;
    if (!window)
        return;

    // A selection is treated as a formula to edit rather than replaced
    // blindly, so the sheet can be used to fix an expression as well as
    // write one.
    NSRange selected = self.editor.selectedRange;
    NSString *initial = selected.length
        ? [self.editor.string substringWithRange:selected] : nil;

    __weak MPDocument *weakSelf = self;
    [MPMathEditorController presentForWindow:window initialTeX:initial
                                  completion:^(NSString *tex, BOOL display) {
        MPDocument *self = weakSelf;
        if (!self || !tex.length)
            return;

        NSString *markup;
        if (display)
        {
            markup = [NSString stringWithFormat:@"$$%@$$", tex];
        }
        else if (self.preferences.htmlMathJaxInlineDollar)
        {
            markup = [NSString stringWithFormat:@"$%@$", tex];
        }
        else
        {
            markup = [NSString stringWithFormat:@"\\(%@\\)", tex];
        }

        // Through the text view, so it lands in the undo stack like any
        // other edit.
        [self.editor insertText:markup
               replacementRange:self.editor.selectedRange];
    }];
}

- (IBAction)toggleProseHighlights:(id)sender
{
    BOOL on = !self.editor.proseHighlightsEnabled;
    self.editor.proseHighlightsEnabled = on;

    // Remembered, so the choice outlives the window it was made in. It used
    // to live only on the editor, which meant switching it on and reopening
    // the document switched it off again.
    self.preferences.editorProseHighlights = on;
    [self updateProseSummary];
}

/// Puts the tally in the window subtitle, which is otherwise unused, so the
/// count needs no widget of its own.
- (void)updateProseSummary
{
    NSWindow *window = self.windowForSheet;
    if (!window)
        return;

    if (!self.editor.proseHighlightsEnabled)
    {
        window.subtitle = @"";
        return;
    }

    MPProseChecker *checker = [MPProseChecker sharedChecker];
    NSArray<MPProseIssue *> *issues =
        [checker issuesInString:self.editor.string ?: @""];
    NSString *summary = [checker summaryForIssues:issues];
    window.subtitle = summary ?: NSLocalizedString(
        @"nothing flagged", @"prose checker found no issues");
}

- (IBAction)toggleToolbar:(id)sender
{
    [self.windowForSheet toggleToolbarShown:sender];
    [self adjustPreviewContentInsets];
}

- (IBAction)togglePreviewPane:(id)sender
{
    [self toggleSplitterCollapsingEditorPane:NO];
}

- (IBAction)toggleEditorPane:(id)sender
{
    [self toggleSplitterCollapsingEditorPane:YES];
}

- (IBAction)render:(id)sender
{
    [self.renderer parseAndRenderLater];
}


#pragma mark - Private

- (void)toggleSplitterCollapsingEditorPane:(BOOL)forEditorPane
{
    BOOL isVisible = forEditorPane ? self.editorVisible : self.previewVisible;
    BOOL editorOnRight = self.preferences.editorOnRight;

    float targetRatio = ((forEditorPane == editorOnRight) ? 1.0 : 0.0);

    if (isVisible)
    {
        CGFloat oldRatio = self.splitView.dividerLocation;
        if (oldRatio != 0.0 && oldRatio != 1.0)
        {
            // We don't want to save these values, since they are meaningless.
            // The user should be able to switch between 100% editor and 100%
            // preview without losing the old ratio.
            self.previousSplitRatio = oldRatio;
        }
        [self setSplitViewDividerLocation:targetRatio];
    }
    else
    {
        // We have an inconsistency here, let's just go back to 0.5,
        // otherwise nothing will happen
        if (self.previousSplitRatio < 0.0)
            self.previousSplitRatio = 0.5;

        [self setSplitViewDividerLocation:self.previousSplitRatio];
    }
}

- (void)setupEditor:(NSString *)changedKey
{
    [self.highlighter deactivate];

    if (!changedKey || [changedKey isEqualToString:@"extensionFootnotes"])
    {
        int extensions = pmh_EXT_NOTES;
        if (self.preferences.extensionFootnotes)
            extensions = pmh_EXT_NONE;
        self.highlighter.extensions = extensions;
    }

    if (!changedKey || [changedKey isEqualToString:@"editorHorizontalInset"]
            || [changedKey isEqualToString:@"editorVerticalInset"]
            || [changedKey isEqualToString:@"editorWidthLimited"]
            || [changedKey isEqualToString:@"editorMaximumWidth"])
    {
        [self adjustEditorInsets];
    }

    if (!changedKey || [changedKey isEqualToString:@"editorBaseFontInfo"]
            || [changedKey isEqualToString:@"editorStyleName"]
            || [changedKey isEqualToString:@"editorLineSpacing"])
    {
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineSpacing = self.preferences.editorLineSpacing;
        self.editor.defaultParagraphStyle = [style copy];
        NSFont *font = [self.preferences.editorBaseFont copy];
        if (font)
            self.editor.font = font;
        self.editor.textColor = nil;
        self.editor.backgroundColor = [NSColor clearColor];
        self.highlighter.styles = nil;
        [self.highlighter readClearTextStylesFromTextView];

        NSString *themeName = [self.preferences.editorStyleName copy];
        if (themeName.length)
        {
            NSString *path = MPThemePathForName(themeName);
            NSString *themeString = MPReadFileOfPath(path);
            [self.highlighter applyStylesFromStylesheet:themeString
                                       withErrorHandler:
                ^(NSArray *errorMessages) {
                    self.preferences.editorStyleName = nil;
                }];
        }

        // Configure the view's own backing layer instead of swapping in a
        // bare CALayer: a replacement layer is not managed by AppKit, so it
        // loses its contentsScale and renders at 1x on Retina displays.
        NSView *container = self.editorContainer;
        container.wantsLayer = YES;
        CGColorRef backgroundCGColor = self.editor.backgroundColor.CGColor;
        if (backgroundCGColor)
            container.layer.backgroundColor = backgroundCGColor;
    }
    
    if ([changedKey isEqualToString:@"editorBaseFontInfo"])
    {
        [self scaleWebview];
    }

    if (!changedKey || [changedKey isEqualToString:@"editorShowWordCount"])
    {
        if (self.preferences.editorShowWordCount)
        {
            self.wordCountWidget.hidden = NO;
            self.editorPaddingBottom.constant = 35.0;
            [self updateWordCount];
        }
        else
        {
            self.wordCountWidget.hidden = YES;
            self.editorPaddingBottom.constant = 0.0;
        }
    }

    if (!changedKey || [changedKey isEqualToString:@"editorProseHighlights"])
    {
        self.editor.proseHighlightsEnabled =
            self.preferences.editorProseHighlights;
        [self updateProseSummary];
    }

    if (!changedKey || [changedKey isEqualToString:@"editorScrollsPastEnd"])
    {
        self.editor.scrollsPastEnd = self.preferences.editorScrollsPastEnd;
        NSRect contentRect = self.editor.contentRect;
        NSSize minSize = self.editor.enclosingScrollView.contentSize;
        if (contentRect.size.height < minSize.height)
            contentRect.size.height = minSize.height;
        if (contentRect.size.width < minSize.width)
            contentRect.size.width = minSize.width;
        self.editor.frame = contentRect;
    }

    if (!changedKey)
    {
        NSClipView *contentView = self.editor.enclosingScrollView.contentView;
        contentView.postsBoundsChangedNotifications = YES;

        NSDictionary *keysAndDefaults = MPEditorKeysToObserve();
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for (NSString *key in keysAndDefaults)
        {
            NSString *preferenceKey = MPEditorPreferenceKeyWithValueKey(key);
            id value = [defaults objectForKey:preferenceKey];
            value = value ? value : keysAndDefaults[key];
            [self.editor setValue:value forKey:key];
        }
    }

    if (!changedKey || [changedKey isEqualToString:@"editorOnRight"])
    {
        BOOL editorOnRight = self.preferences.editorOnRight;
        NSArray *subviews = self.splitView.subviews;
        if ((!editorOnRight && subviews[0] == self.preview)
            || (editorOnRight && subviews[1] == self.preview))
        {
            [self.splitView swapViews];
            if (!self.previewVisible && self.previousSplitRatio >= 0.0)
                self.previousSplitRatio = 1.0 - self.previousSplitRatio;

            // Need to queue this or the views won't be initialised correctly.
            // Don't really know why, but this works.
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                self.splitView.needsLayout = YES;
            }];
        }
    }

    [self.highlighter activate];
    self.editor.automaticLinkDetectionEnabled = NO;
}

- (void)adjustEditorInsets
{
    CGFloat x = self.preferences.editorHorizontalInset;
    CGFloat y = self.preferences.editorVerticalInset;
    if (self.preferences.editorWidthLimited)
    {
        CGFloat editorWidth = self.editor.frame.size.width;
        CGFloat maxWidth = self.preferences.editorMaximumWidth;
        if (editorWidth > 2 * x + maxWidth)
            x = (editorWidth - maxWidth) * 0.45;
        // We tend to expect things in an editor to shift to left a bit.
        // Hence the 0.45 instead of 0.5 (which whould feel a bit too much).
    }
    self.editor.textContainerInset = NSMakeSize(x, y);
}

- (void)adjustPreviewContentInsets
{
    // Pads the page by however much the titlebar and toolbar overlap the
    // content view, which is zero as the window is currently configured, so
    // this is a no-op that costs one JS call per load and starts working
    // again on its own if the full-size content view is ever restored.
    //
    // It pads the document element rather than setting contentInsets on
    // WebKit's scroll view: that leaves the exposed strip painted white, no
    // matter what the scroll view's own background is set to. The body
    // background propagates to the canvas, so the page's own colour fills
    // the padded area.
    NSWindow *window = self.windowForSheet;
    NSView *contentView = window.contentView;
    if (!contentView)
        return;

    CGFloat overlap = NSHeight(contentView.bounds)
                      - NSHeight(window.contentLayoutRect);
    NSString *js = [NSString stringWithFormat:
        @"document.documentElement.style.paddingTop = '%.0fpx';", overlap];
    [self.preview evaluateJavaScript:js completionHandler:nil];

}


#pragma mark - NSWindowDelegate

- (void)windowDidResize:(NSNotification *)notification
{
    // Entering or leaving full screen changes the overlap, not just the size.
    [self adjustPreviewContentInsets];
}


- (void)redrawDivider
{
    if (!self.editorVisible)
    {
        // If the editor is not visible, detect preview's background color via
        // DOM query and use it instead. This is more expensive; we should try
        // to avoid it.
        // TODO: Is it possible to cache this until the user switches the style?
        // Will need to take account of the user MODIFIES the style without
        // switching. Complicated. This will do for now.
        self.splitView.dividerColor = self.previewBackgroundColor;
    }
    else if (!self.previewVisible)
    {
        // If the editor is visible, match its background color.
        self.splitView.dividerColor = self.editor.backgroundColor;
    }
    else
    {
        // If both sides are visible, draw a default "transparent" divider.
        // This works around the possibile problem of divider's color being too
        // similar to both the editor and preview and being obscured.
        self.splitView.dividerColor = nil;
    }
}

- (void)scaleWebview
{
    if (!self.preferences.previewZoomRelativeToBaseFontSize)
        return;

    CGFloat fontSize = self.preferences.editorBaseFontSize;
    if (fontSize <= 0.0)
        return;

    static const CGFloat defaultSize = 14.0;
    CGFloat scale = fontSize / defaultSize;
    
#if 0
    // Sadly, this doesn’t work correctly.
    // It looks fine, but selections are offset relative to the mouse cursor.
    NSScrollView *previewScrollView =

    NSClipView *previewContentView = previewScrollView.contentView;
    [previewContentView scaleUnitSquareToSize:NSMakeSize(scale, scale)];
    [previewContentView setNeedsDisplay:YES];
#else
    // Warning: this is private webkit API and NOT App Store-safe!
    // pageZoom is the public counterpart of -setPageSizeMultiplier:, the
    // private call this used to make.
    self.preview.pageZoom = scale;
#endif
}

/** Where each heading sits in the preview, in document coordinates.
 *
 * The page is asked for these rather than measured from here, and answers
 * when it answers: the editor half of the calculation below runs straight
 * away, and the preview half lands on a later turn of the run loop. Nothing
 * downstream needs them in the same breath — they are read by -syncScrollers
 * on the next scroll.
 */
-(void) updateHeaderLocations
{
    // Offsets are added in the page, where the scroll position is known
    // without asking, so the answer arrives already in document coordinates.
    static NSString * const script =
        @"(function(){var top=window.scrollY;"
        @"var nodes=document.querySelectorAll("
        @"'h1, h2, h3, h4, h5, h6, img:only-child');"
        @"var out=[];"
        @"for(var i=0;i<nodes.length;i++){"
        @"out.push(nodes[i].getBoundingClientRect().top+top);}"
        @"return out;})()";

    __weak MPDocument *weakSelf = self;
    [self.preview evaluateJavaScript:script completionHandler:
        ^(id result, NSError *error) {
        if ([result isKindOfClass:[NSArray class]])
            weakSelf.webViewHeaderLocations = result;
    }];


    // Next, cache the locations of all of the reference nodes in the editor
    // view. This half is measured here and needs nothing from the page.
    NSMutableArray<NSNumber *> *locations = [NSMutableArray array];
    NSInteger characterCount = 0;
    NSLayoutManager *layoutManager = [self.editor layoutManager];
    NSArray<NSString *> *documentLines = [self.editor.string componentsSeparatedByString:@"\n"];
    [locations removeAllObjects];

    // These are the patterns for markdown headers and images respectively. we're only going to
    // handle images that are not inline with other text/images
    NSRegularExpression *dashRegex = [NSRegularExpression regularExpressionWithPattern:@"^([-]+)$" options:0 error:nil];
    NSRegularExpression *headerRegex = [NSRegularExpression regularExpressionWithPattern:@"^(#+)\\s" options:0 error:nil];
    NSRegularExpression *imgRegex = [NSRegularExpression regularExpressionWithPattern:@"^!\\[[^\\]]*\\]\\([^)]*\\)$" options:0 error:nil];
    BOOL previousLineHadContent = NO;
    
    CGFloat editorContentHeight = ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight = ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));

    // We start by splitting our document into lines, and then searching
    // line by line for headers or images.
    for (NSInteger lineNumber = 0; lineNumber < [documentLines count]; lineNumber++)
    {
        NSString *line = documentLines[lineNumber];
        
        if ((previousLineHadContent && [dashRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, [line length])]) ||
            [imgRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, [line length])] ||
            [headerRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, [line length])])
        {
            // Calculate where this header/image appears vertically in the editor
            NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:NSMakeRange(characterCount, [line length]) actualCharacterRange:nil];
            NSRect topRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:[self.editor textContainer]];
            CGFloat headerY = NSMidY(topRect);

            if(headerY <= editorContentHeight - editorVisibleHeight){
                [locations addObject:@(headerY)];
            }
        }
        
        previousLineHadContent = [line length] && ![dashRegex numberOfMatchesInString:line options:0 range:NSMakeRange(0, [line length])];
        
        characterCount += [line length] + 1;
    }

    _editorHeaderLocations = [locations copy];
}

- (void)syncScrollers
{
    CGFloat editorContentHeight = ceilf(NSHeight(self.editor.enclosingScrollView.documentView.bounds));
    CGFloat editorVisibleHeight = ceilf(NSHeight(self.editor.enclosingScrollView.contentView.bounds));
    // Last reported by the page. Asking for them here would mean waiting on
    // another process while the editor is mid-scroll.
    CGFloat previewContentHeight = ceilf(self.previewContentHeight);
    CGFloat previewVisibleHeight = ceilf(self.previewViewportHeight);
    NSInteger relativeHeaderIndex = -1; // -1 is start of document, before any other header
    CGFloat currY = NSMinY(self.editor.enclosingScrollView.contentView.bounds);
    CGFloat minY = 0;
    CGFloat maxY = 0;
    
    // align the documents at the middle of the screen, except at top/bottom of document
    CGFloat topTaper = MAX(0, MIN(1.0, currY / editorVisibleHeight));
    CGFloat bottomTaper = 1.0 - MAX(0, MIN(1.0, (currY - editorContentHeight + 2 * editorVisibleHeight) / editorVisibleHeight));
    CGFloat adjustmentForScroll = topTaper * bottomTaper * editorVisibleHeight / 2;

    // We start by splitting our document into lines, and then searching
    // line by line for headers or images.
    for (NSNumber *headerYNum in _editorHeaderLocations) {
        CGFloat headerY = [headerYNum floatValue];
        headerY -= adjustmentForScroll;
        
        if (headerY < currY)
        {
            // The header is before our current scroll position. the closest
            // of these will be our first reference node
            relativeHeaderIndex += 1;
            minY = headerY;
        } else if (maxY == 0 && headerY < editorContentHeight - editorVisibleHeight)
        {
            // Skip any headers that are within the last screen of the editor.
            // we'll interpolate to the end of the document in that case.
            maxY = headerY;
        }
    }
    
    // Usually, we'll be scrolling between two reference nodes, but toward the end
    // of the document we'll ignore nodes and reference the end of the document instead
    BOOL interpolateToEndOfDocument = NO;
    
    if (maxY == 0)
    {
        // We only have a reference node before our current position,
        // but not after, so we'll use the end of the document.
        maxY = editorContentHeight - editorVisibleHeight + adjustmentForScroll;
        interpolateToEndOfDocument = YES;
    }

    // We are currently at currY offset, between minY and maxY, which represent
    // headers indexed by relativeHeaderIndex and relativeHeaderIndex+1.
    currY = MAX(0, currY - minY);
    maxY -= minY;
    minY -= minY;
    CGFloat percentScrolledBetweenHeaders = MAX(0, MIN(1.0, currY / maxY));
    
    // Now that we know where the editor position is relative to two reference nodes,
    // we need to find the positions of those nodes in the HTML preview
    CGFloat topHeaderY = 0;
    CGFloat bottomHeaderY = previewContentHeight - previewVisibleHeight;
    
    // Find the Y positions in the preview window that we're scrolling between
    if ([_webViewHeaderLocations count] > relativeHeaderIndex)
    {
        topHeaderY = floorf([_webViewHeaderLocations[relativeHeaderIndex] doubleValue]) - adjustmentForScroll;
    }
    
    if (!interpolateToEndOfDocument && [_webViewHeaderLocations count] > relativeHeaderIndex + 1)
    {
        bottomHeaderY = ceilf([_webViewHeaderLocations[relativeHeaderIndex + 1] doubleValue]) - adjustmentForScroll;
    }
    
    // Now we scroll percentScrolledBetweenHeaders percent between those two positions in the webview
    CGFloat previewY = topHeaderY + (bottomHeaderY - topHeaderY) * percentScrolledBetweenHeaders;
    [self setPreviewScrollTopTo:previewY];
}

- (void)setSplitViewDividerLocation:(CGFloat)ratio
{
    BOOL wasVisible = self.previewVisible;
    [self.splitView setDividerLocation:ratio];
    if (!wasVisible && self.previewVisible
            && !self.preferences.markdownManualRender)
        [self.renderer parseAndRenderNow];
    [self setupEditor:NSStringFromSelector(@selector(editorHorizontalInset))];
}

- (NSString *)presumedFileName
{
    if (self.fileURL)
        return self.fileURL.lastPathComponent.stringByDeletingPathExtension;

    NSString *title = nil;
    NSString *string = self.editor.string;
    if (self.preferences.htmlDetectFrontMatter)
        title = [[[string frontMatter:NULL] objectForKey:@"title"] description];
    if (title)
        return title;

    title = string.titleString;
    if (!title)
        return NSLocalizedString(@"Untitled", @"default filename if no title can be determined");

    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"[/|:]"
                                                          options:0 error:NULL];
    });

    NSRange range = NSMakeRange(0, title.length);
    title = [regex stringByReplacingMatchesInString:title options:0 range:range
                                       withTemplate:@"-"];
    return title;
}

/** Counts the words in the rendered document.
 *
 * The walk used to be done from here, over the live DOM, through the
 * DOMNode+Text category. There is no live DOM to walk any more, so the same
 * rules run inside the page: skip what is not prose, count a code block as
 * nothing and an inline code span as a single word.
 */
static NSString * const kMPWordCountScript =
    @"(function(){"
    @"var SKIP={SCRIPT:1,STYLE:1,HEAD:1,NOSCRIPT:1};"
    @"var words=0,chars=0,bare=0;"
    @"function words_in(t){var m=t.match(/\\S+/g);return m?m.length:0;}"
    @"function walk(node){"
    @"if(node.nodeType===3||node.nodeType===4){"
    @"var t=node.nodeValue||'';"
    @"words+=words_in(t);"
    @"chars+=t.replace(/[\\r\\n]/g,'').length;"
    @"bare+=t.replace(/\\s/g,'').length;"
    @"return;}"
    @"if(node.nodeType!==1&&node.nodeType!==9&&node.nodeType!==11)return;"
    @"var tag=node.tagName?node.tagName.toUpperCase():'';"
    @"if(SKIP[tag])return;"
    @"if(tag==='CODE'||tag==='TT'){"
    // A code block is not prose; an inline span is one word if it has any
    // content at all. Characters are still counted either way.
    @"var parent=node.parentElement;"
    @"var block=parent&&parent.tagName==='PRE';"
    @"var before=words;"
    @"for(var c=node.firstChild;c;c=c.nextSibling)walk(c);"
    @"words=block?before:before+((words>before)?1:0);"
    @"return;}"
    @"for(var k=node.firstChild;k;k=k.nextSibling)walk(k);}"
    @"walk(document.body||document);"
    @"return {words:words,characters:chars,bare:bare};})()";

- (void)updateWordCount
{
    if (!self.preview)
        return;

    __weak MPDocument *weakSelf = self;
    [self.preview evaluateJavaScript:kMPWordCountScript completionHandler:
        ^(id result, NSError *error) {
        if (![result isKindOfClass:[NSDictionary class]])
            return;

        MPDocument *me = weakSelf;
        me.totalWords = [result[@"words"] unsignedIntegerValue];
        me.totalCharacters = [result[@"characters"] unsignedIntegerValue];
        me.totalCharactersNoSpaces = [result[@"bare"] unsignedIntegerValue];

        if (me.isPreviewReady)
            me.wordCountWidget.enabled = YES;
    }];
}

- (BOOL)isCurrentBaseUrl:(NSURL *)another
{
    NSString *mine = self.currentBaseUrl.absoluteBaseURLString;
    NSString *theirs = another.absoluteBaseURLString;
    return mine == theirs || [mine isEqualToString:theirs];
}


#define OPEN_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
@"Please check the path of your link is correct. Turn on \
“Automatically create link targets” If you want MacDown to \
create nonexistent link targets for you.", \
@"preview navigation error information")

#define AUTO_CREATE_FAIL_ALERT_INFORMATIVE NSLocalizedString( \
@"MacDown can’t create a file for the clicked link because \
the current file is not saved anywhere yet. Save the \
current file somewhere to enable this feature.", \
@"preview navigation error information")


- (void)openOrCreateFileForUrl:(NSURL *)url
{
    // Simply open the file if it is not local, or exists already.
    BOOL file = url.isFileURL;
    BOOL reachable = !file || [url checkResourceIsReachableAndReturnError:NULL];
    
    // If the file is local but doesn't exist, check if a file with
    // the .md extension exists.
    if (file && !reachable && [url.pathExtension isEqualToString:@""])
    {
        NSURL *markdownURL = [url URLByAppendingPathExtension:@"md"];
        if ([markdownURL checkResourceIsReachableAndReturnError:NULL])
        {
            reachable = YES;
            url = markdownURL;
        }
    }
    
    if (reachable)
    {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    // Show an error if the user doesn't want us to create it automatically.
    if (!self.preferences.createFileForLinkTarget)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"File not found at path:\n%@",
            @"preview navigation error message");
        alert.messageText = [NSString stringWithFormat:template, url.path];
        alert.informativeText = OPEN_FAIL_ALERT_INFORMATIVE;
        [alert runModal];
        return;
    }

    // We can only create a file if the current file is saved. (Why?)
    if (!self.fileURL)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"Can’t create file:\n%@", @"preview navigation error message");
        alert.messageText = [NSString stringWithFormat:template,
                             url.lastPathComponent];
        alert.informativeText = AUTO_CREATE_FAIL_ALERT_INFORMATIVE;
        [alert runModal];
    }

    // Try to created the file.
    NSDocumentController *controller =
        [NSDocumentController sharedDocumentController];

    NSError *error = nil;
    id doc = [controller createNewEmptyDocumentForURL:url
                                              display:YES error:&error];
    if (!doc)
    {
        NSAlert *alert = [[NSAlert alloc] init];
        NSString *template = NSLocalizedString(
            @"Can’t create file:\n%@",
            @"preview navigation error message");
        alert.messageText =
            [NSString stringWithFormat:template, url.lastPathComponent];
        template = NSLocalizedString(
            @"An error occurred while creating the file:\n%@",
            @"preview navigation error information");
        alert.informativeText =
            [NSString stringWithFormat:template, error.localizedDescription];
        [alert runModal];
    }
}


- (void)document:(NSDocument *)doc didPrint:(BOOL)ok context:(void *)context
{
    if ([doc respondsToSelector:@selector(setPrinting:)])
        ((MPDocument *)doc).printing = NO;
    if (context)
    {
        NSInvocation *invocation = (__bridge NSInvocation *)context;
        if ([invocation isKindOfClass:[NSInvocation class]])
        {
            [invocation setArgument:&doc atIndex:0];
            [invocation setArgument:&ok atIndex:1];
            [invocation invoke];
        }
    }
}

@end
