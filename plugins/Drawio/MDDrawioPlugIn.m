//
//  MDDrawioPlugIn.m
//  MacDown Next — draw.io plug-in
//

#import "MDDrawioPlugIn.h"
#import "MDDrawioFile.h"
#import "MDDrawioRenderer.h"

/// What was asked for last time, remembered in the application's defaults.
static NSString * const kMDScaleKey = @"MDDrawioScale";
static NSString * const kMDUseServiceKey = @"MDDrawioUsesExportServer";
static NSString * const kMDServiceKey = @"MDDrawioExportServer";


#pragma mark - Reaching the document

/// The first text view inside a view, which in this window is the editor.
static NSTextView *MDTextViewIn(NSView *view)
{
    if ([view isKindOfClass:[NSTextView class]])
        return (NSTextView *)view;
    for (NSView *child in view.subviews)
    {
        NSTextView *found = MDTextViewIn(child);
        if (found)
            return found;
    }
    return nil;
}

/** The editor of a document, found through the window rather than the class.
 *
 * A plug-in is loaded into the application and could call straight into
 * MPDocument, which would tie it to the version of MacDown Next it was
 * built against. A text view in a window is a text view in any version.
 */
static NSTextView *MDEditorOfDocument(NSDocument *document)
{
    for (NSWindowController *controller in document.windowControllers)
    {
        NSWindow *window = controller.window;
        if ([window.firstResponder isKindOfClass:[NSTextView class]])
            return (NSTextView *)window.firstResponder;
        NSTextView *found = MDTextViewIn(window.contentView);
        if (found)
            return found;
    }
    return nil;
}

@implementation MDDrawioNaming

/// A name that can be a file name: no separators, no surprises.
+ (NSString *)fileNameSlugOf:(NSString *)name
{
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet
        alphanumericCharacterSet];
    [allowed addCharactersInString:@"-_ àèéìòùáíóúäöüçñ"];
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < name.length; i++)
    {
        unichar c = [name characterAtIndex:i];
        [out appendString:[allowed characterIsMember:c]
            ? [NSString stringWithCharacters:&c length:1] : @"-"];
    }
    NSString *slug = [out stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];
    return slug.length ? slug : @"pagina";
}

+ (NSString *)linkTargetForFile:(NSURL *)file besideDocument:(NSURL *)document
{
    NSString *path = file.URLByStandardizingPath.path;
    NSString *folder = document.URLByDeletingLastPathComponent
        .URLByStandardizingPath.path;
    if (folder.length && [path hasPrefix:[folder stringByAppendingString:@"/"]])
        path = [path substringFromIndex:folder.length + 1];

    NSCharacterSet *safe = [NSCharacterSet
        characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyz"
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/"];
    return [path stringByAddingPercentEncodingWithAllowedCharacters:safe];
}

@end


#pragma mark - The sheet

/// Scale, and which of the two ways the drawing is done.
@interface MDDrawioOptions : NSView
@property (strong, nonatomic) NSPopUpButton *scaleButton;
@property (strong, nonatomic) NSButton *hereRadio;
@property (strong, nonatomic) NSButton *serviceRadio;
@property (strong, nonatomic) NSTextField *serviceField;
@end


@implementation MDDrawioOptions

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
{
    self = [super initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 116.0)];
    if (!self)
        return nil;

    NSTextField *sizeLabel = [NSTextField labelWithString:@"Dimensione:"];
    sizeLabel.alignment = NSTextAlignmentRight;
    sizeLabel.frame = NSMakeRect(0.0, 94.0, 92.0, 18.0);
    [self addSubview:sizeLabel];

    _scaleButton = [[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(96.0, 90.0, 150.0, 25.0) pullsDown:NO];
    [_scaleButton addItemsWithTitles:@[@"1×", @"2× (retina)", @"3×"]];
    double scale = [defaults doubleForKey:kMDScaleKey];
    [_scaleButton selectItemAtIndex:(scale >= 3.0 ? 2 : (scale <= 1.0 ? 0 : 1))];
    [self addSubview:_scaleButton];

    NSTextField *whereLabel = [NSTextField labelWithString:@"Disegna:"];
    whereLabel.alignment = NSTextAlignmentRight;
    whereLabel.frame = NSMakeRect(0.0, 64.0, 92.0, 18.0);
    [self addSubview:whereLabel];

    _hereRadio = [NSButton radioButtonWithTitle:
        @"Su questo Mac, senza connessione"
                                         target:self
                                         action:@selector(whereChanged:)];
    _hereRadio.frame = NSMakeRect(96.0, 62.0, 300.0, 20.0);
    [self addSubview:_hereRadio];

    _serviceRadio = [NSButton radioButtonWithTitle:
        @"Su un export server, a questo indirizzo:"
                                            target:self
                                            action:@selector(whereChanged:)];
    _serviceRadio.frame = NSMakeRect(96.0, 40.0, 300.0, 20.0);
    [self addSubview:_serviceRadio];

    BOOL service = [defaults boolForKey:kMDUseServiceKey];
    _hereRadio.state = service ? NSControlStateValueOff
                               : NSControlStateValueOn;
    _serviceRadio.state = service ? NSControlStateValueOn
                                  : NSControlStateValueOff;

    _serviceField = [NSTextField textFieldWithString:
        [defaults stringForKey:kMDServiceKey] ?: @"http://localhost:8000/"];
    _serviceField.frame = NSMakeRect(114.0, 12.0, 282.0, 22.0);
    _serviceField.placeholderString = @"http://localhost:8000/";
    [self addSubview:_serviceField];

    [self whereChanged:nil];
    return self;
}

- (void)whereChanged:(id)sender
{
    self.serviceField.enabled = self.usesService;
}

- (BOOL)usesService
{
    return self.serviceRadio.state == NSControlStateValueOn;
}

- (CGFloat)scale
{
    switch (self.scaleButton.indexOfSelectedItem)
    {
        case 0: return 1.0;
        case 2: return 3.0;
        default: return 2.0;
    }
}

- (NSURL *)service
{
    NSString *text = [self.serviceField.stringValue
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return text.length ? [NSURL URLWithString:text] : nil;
}

@end


#pragma mark - The plug-in

@interface MDDrawioPlugIn ()
@property (strong, nonatomic) MDDrawioRenderer *renderer;
@end


@implementation MDDrawioPlugIn

- (NSString *)name
{
    return @"Importa un diagramma draw.io…";
}

- (BOOL)run:(id)sender
{
    NSDocument *document =
        [NSDocumentController sharedDocumentController].currentDocument;
    NSTextView *editor = document ? MDEditorOfDocument(document) : nil;
    if (!document || !editor)
    {
        [self say:@"Apri un documento" text:
            @"Il diagramma viene messo in un documento, quindi ce ne vuole "
            @"uno davanti."];
        return NO;
    }
    // The picture goes beside the document, and a link to it is relative to
    // the document's folder. Without a folder there is neither.
    if (!document.fileURL)
    {
        [self say:@"Salva prima il documento" text:
            @"Le immagini vengono scritte accanto al documento, e un "
            @"documento non salvato non ha una cartella accanto a cui "
            @"stare."];
        return NO;
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"drawio", @"xml", @"png", @"svg"];
    panel.allowsMultipleSelection = NO;
    panel.message = @"Scegli il diagramma draw.io da importare";
    if ([panel runModal] != NSModalResponseOK || !panel.URL)
        return YES;   // asked and answered: nothing went wrong

    NSError *error = nil;
    MDDrawioFile *file = [MDDrawioFile fileWithURL:panel.URL error:&error];
    if (!file)
    {
        [self say:@"Il diagramma non si è potuto leggere"
             text:error.localizedDescription];
        return NO;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    MDDrawioOptions *options =
        [[MDDrawioOptions alloc] initWithDefaults:defaults];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = file.pages.count == 1
        ? @"Importa il diagramma"
        : [NSString stringWithFormat:@"Importa %lu pagine",
           (unsigned long)file.pages.count];
    alert.informativeText =
        @"Ogni pagina diventa un PNG accanto al documento, e viene "
        @"collegata nel punto dove sta il cursore. Disegnato su questo Mac "
        @"il diagramma non esce dalla macchina; su un export server viene "
        @"mandato all'indirizzo che indichi.";
    [alert addButtonWithTitle:@"Importa"];
    [alert addButtonWithTitle:@"Annulla"];
    alert.accessoryView = options;

    if ([alert runModal] != NSAlertFirstButtonReturn)
        return YES;

    [defaults setDouble:options.scale forKey:kMDScaleKey];
    [defaults setBool:options.usesService forKey:kMDUseServiceKey];
    if (options.usesService && options.service)
        [defaults setObject:options.service.absoluteString forKey:kMDServiceKey];

    if (options.usesService && !options.service)
    {
        [self say:@"Indirizzo mancante"
             text:@"Per disegnare su un export server serve il suo indirizzo."];
        return NO;
    }

    self.renderer = [[MDDrawioRenderer alloc]
        initWithBundle:[NSBundle bundleForClass:[self class]]];

    [self renderPagesOf:file from:panel.URL into:document editor:editor
                  scale:options.scale
                service:options.usesService ? options.service : nil];
    return YES;
}

/** One page at a time, because the local renderer holds one web view.
 *
 * Written and linked as they arrive rather than all at the end: a diagram
 * of twenty pages that fails on the nineteenth should still have brought
 * in eighteen.
 */
- (void)renderPagesOf:(MDDrawioFile *)file
                 from:(NSURL *)source
                 into:(NSDocument *)document
               editor:(NSTextView *)editor
                scale:(CGFloat)scale
              service:(NSURL *)service
{
    NSMutableArray<MDDrawioPage *> *queue = [file.pages mutableCopy];
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    NSString *stem = source.lastPathComponent.stringByDeletingPathExtension;

    __block NSUInteger index = 0;
    __block void (^next)(void) = nil;
    void (^step)(void) = ^{
        if (!queue.count)
        {
            if (problems.count)
            {
                [self say:@"Non tutte le pagine sono arrivate"
                     text:[problems componentsJoinedByString:@"\n"]];
            }
            next = nil;
            return;
        }

        MDDrawioPage *page = queue.firstObject;
        [queue removeObjectAtIndex:0];
        index++;

        NSString *label = page.name.length ? page.name
            : (file.pages.count > 1
               ? [NSString stringWithFormat:@"pagina %lu", (unsigned long)index]
               : stem);

        MDDrawioRenderHandler done = ^(NSData *png, NSError *error) {
            if (!png)
            {
                [problems addObject:[NSString stringWithFormat:@"%@: %@",
                    label, error.localizedDescription ?: @"non si è disegnata"]];
            }
            else
            {
                NSString *problem = [self write:png forLabel:label
                                           stem:stem document:document
                                         editor:editor
                                     manyPages:file.pages.count > 1];
                if (problem)
                    [problems addObject:problem];
            }
            if (next)
                next();
        };

        if (service)
            [self.renderer renderPage:page scale:scale onService:service
                           completion:done];
        else
            [self.renderer renderPage:page scale:scale completion:done];
    };
    next = step;
    step();
}

/// Writes the picture beside the document and links it, once.
- (NSString *)write:(NSData *)png
           forLabel:(NSString *)label
               stem:(NSString *)stem
           document:(NSDocument *)document
             editor:(NSTextView *)editor
          manyPages:(BOOL)manyPages
{
    NSString *name = manyPages
        ? [NSString stringWithFormat:@"%@-%@.png", [MDDrawioNaming fileNameSlugOf:stem],
           [MDDrawioNaming fileNameSlugOf:label]]
        : [NSString stringWithFormat:@"%@.png",
           [MDDrawioNaming fileNameSlugOf:stem]];
    NSURL *folder = document.fileURL.URLByDeletingLastPathComponent;
    NSURL *file = [folder URLByAppendingPathComponent:name];

    NSError *error = nil;
    // Written over, deliberately: importing the same diagram again is how a
    // picture gets brought up to date, and the link must keep working.
    if (![png writeToURL:file options:NSDataWritingAtomic error:&error])
    {
        return [NSString stringWithFormat:@"%@: %@", label,
                error.localizedDescription];
    }

    NSString *target = [MDDrawioNaming linkTargetForFile:file
                                      besideDocument:document.fileURL];
    NSString *markup = [NSString stringWithFormat:@"![%@](%@)\n",
                        label, target];

    // The document may already carry this link, from the last import of the
    // same diagram. The file has just been rewritten, so there is nothing
    // to add: adding it would show the same picture twice.
    if ([editor.string containsString:target])
        return nil;

    NSRange at = editor.selectedRange;
    if (NSMaxRange(at) > editor.string.length)
        at = NSMakeRange(editor.string.length, 0);
    if ([editor shouldChangeTextInRange:at replacementString:markup])
    {
        [editor insertText:markup replacementRange:at];
        editor.selectedRange = NSMakeRange(at.location + markup.length, 0);
    }
    return nil;
}

- (void)say:(NSString *)title text:(NSString *)text
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = text ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end
