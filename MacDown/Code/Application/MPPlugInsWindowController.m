//
//  MPPlugInsWindowController.m
//  MacDown
//

#import "MPPlugInsWindowController.h"
#import "MPPlugIn.h"
#import "MPPreferences.h"
#import "MPUtilities.h"


static NSString * const kMPPlugInEnabledColumn = @"enabled";
static NSString * const kMPPlugInNameColumn = @"name";


@interface MPPlugInsWindowController ()
    <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic) NSTableView *table;
@property (nonatomic) NSButton *removeButton;
@property (nonatomic) NSButton *revealButton;
@property (nonatomic) NSTextField *emptyLabel;
@property (nonatomic, copy) NSArray<MPPlugIn *> *plugIns;
@end


@implementation MPPlugInsWindowController

+ (instancetype)sharedController
{
    static MPPlugInsWindowController *shared = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    NSRect frame = NSMakeRect(0.0, 0.0, 460.0, 320.0);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
        | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = NSLocalizedString(@"Plug-in", @"Plug-in manager window");
    window.minSize = NSMakeSize(380.0, 240.0);
    [window center];

    self = [super initWithWindow:window];
    if (!self)
        return nil;

    [self buildContent];
    return self;
}


#pragma mark - Building

- (void)buildContent
{
    NSView *content = self.window.contentView;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;

    NSTableView *table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    table.dataSource = self;
    table.delegate = self;
    table.usesAlternatingRowBackgroundColors = YES;
    table.rowHeight = 24.0;
    table.allowsMultipleSelection = NO;

    NSTableColumn *enabled =
        [[NSTableColumn alloc] initWithIdentifier:kMPPlugInEnabledColumn];
    enabled.title = @"";
    enabled.width = 24.0;
    enabled.minWidth = 24.0;
    enabled.maxWidth = 24.0;
    [table addTableColumn:enabled];

    NSTableColumn *name =
        [[NSTableColumn alloc] initWithIdentifier:kMPPlugInNameColumn];
    name.title = NSLocalizedString(@"Plug-in", @"Table column");
    name.width = 380.0;
    [table addTableColumn:name];

    scroll.documentView = table;
    [content addSubview:scroll];
    self.table = table;

    // Shown over the empty table, since an empty list otherwise looks like a
    // fault rather than like having no plug-ins.
    NSTextField *empty = [NSTextField wrappingLabelWithString:
        NSLocalizedString(@"Nessun plug-in installato.",
                          @"Shown when the list is empty")];
    empty.alignment = NSTextAlignmentCenter;
    empty.textColor = [NSColor secondaryLabelColor];
    empty.translatesAutoresizingMaskIntoConstraints = NO;
    empty.hidden = YES;
    [content addSubview:empty];
    self.emptyLabel = empty;

    NSButton *add = [NSButton buttonWithTitle:
        NSLocalizedString(@"Aggiungi…", @"Install a plug-in")
                                       target:self
                                       action:@selector(addPlugIn:)];
    NSButton *remove = [NSButton buttonWithTitle:
        NSLocalizedString(@"Rimuovi", @"Uninstall the selected plug-in")
                                          target:self
                                          action:@selector(removePlugIn:)];
    NSButton *reveal = [NSButton buttonWithTitle:
        NSLocalizedString(@"Mostra nel Finder", @"Reveal the plug-ins folder")
                                          target:self
                                          action:@selector(revealFolder:)];
    self.removeButton = remove;
    self.revealButton = reveal;

    NSStackView *buttons =
        [NSStackView stackViewWithViews:@[add, remove, reveal]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 8.0;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:buttons];

    NSTextField *note = [NSTextField wrappingLabelWithString:
        NSLocalizedString(
            @"Le modifiche hanno effetto al prossimo avvio: i plug-in "
            @"vengono caricati una volta sola, all'apertura.",
            @"Explains that plug-in changes need a restart")];
    note.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    note.textColor = [NSColor secondaryLabelColor];
    note.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:note];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:content.topAnchor
                                         constant:16.0],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                             constant:16.0],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                              constant:-16.0],
        [scroll.bottomAnchor constraintEqualToAnchor:buttons.topAnchor
                                            constant:-12.0],

        [empty.centerXAnchor constraintEqualToAnchor:scroll.centerXAnchor],
        [empty.centerYAnchor constraintEqualToAnchor:scroll.centerYAnchor],

        [buttons.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                              constant:16.0],
        [buttons.bottomAnchor constraintEqualToAnchor:note.topAnchor
                                             constant:-10.0],

        [note.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                           constant:16.0],
        [note.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                            constant:-16.0],
        [note.bottomAnchor constraintEqualToAnchor:content.bottomAnchor
                                          constant:-16.0],
    ]];
}


#pragma mark - Showing

- (void)showPanel:(id)sender
{
    [self reload];
    [self showWindow:sender];
    [self.window makeKeyAndOrderFront:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)reload
{
    self.plugIns = [self installedPlugIns];
    [self.table reloadData];
    self.emptyLabel.hidden = (self.plugIns.count > 0);
    [self updateButtons];
}

- (void)updateButtons
{
    NSInteger row = self.table.selectedRow;
    BOOL hasSelection = (row >= 0 && row < (NSInteger)self.plugIns.count);
    // One that ships inside the application is not ours to throw away: it
    // would come back with the next build, and taking a piece out of an
    // application is how an application stops working. Switch it off
    // instead — the checkbox does that, and it lasts.
    self.removeButton.enabled = hasSelection
        && !self.plugIns[(NSUInteger)row].isBuiltIn;
}

/// Read straight from the folders rather than from the running application,
/// so a plug-in dropped in while MacDown is open still shows up here.
- (NSArray<MPPlugIn *> *)installedPlugIns
{
    NSMutableArray *found = [NSMutableArray array];
    for (NSURL *url in MPPlugInBundleURLs())
    {
        NSBundle *bundle = [NSBundle bundleWithURL:url];
        MPPlugIn *plugin = [[MPPlugIn alloc] initWithBundle:bundle];
        if (plugin)
            [found addObject:plugin];
    }
    return [found copy];
}


#pragma mark - Enabled state

- (BOOL)isEnabled:(MPPlugIn *)plugin
{
    NSArray *disabled = [MPPreferences sharedInstance].disabledPlugIns;
    return ![disabled containsObject:plugin.identifier];
}

- (void)setEnabled:(BOOL)enabled forPlugIn:(MPPlugIn *)plugin
{
    MPPreferences *preferences = [MPPreferences sharedInstance];
    NSMutableArray *disabled =
        [preferences.disabledPlugIns mutableCopy] ?: [NSMutableArray array];

    [disabled removeObject:plugin.identifier];
    if (!enabled)
        [disabled addObject:plugin.identifier];
    preferences.disabledPlugIns = disabled;
}


#pragma mark - Actions

- (void)toggleEnabled:(NSButton *)sender
{
    NSInteger row = sender.tag;
    if (row < 0 || row >= (NSInteger)self.plugIns.count)
        return;
    [self setEnabled:(sender.state == NSControlStateValueOn)
           forPlugIn:self.plugIns[(NSUInteger)row]];
}

- (void)addPlugIn:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[kMPPlugInFileExtension];
    // A .plugin is a folder that the system usually knows is one file. When
    // it does not — a fresh build that Launch Services has never seen —
    // the panel shows it as a folder to walk into and nothing to choose.
    // This way it can be picked either way round.
    panel.canChooseDirectories = YES;
    panel.treatsFilePackagesAsDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.message = NSLocalizedString(
        @"Scegli uno o più plug-in da installare.",
        @"Open panel prompt");

    if ([panel runModal] != NSModalResponseOK)
        return;

    NSString *destination = MPDataDirectory(kMPPlugInsDirectoryName);
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:destination
       withIntermediateDirectories:YES attributes:nil error:NULL];

    for (NSURL *source in panel.URLs)
    {
        NSURL *target = [[NSURL fileURLWithPath:destination]
            URLByAppendingPathComponent:source.lastPathComponent];

        // Replacing rather than refusing, so installing a newer build of a
        // plug-in you already have does the obvious thing.
        if ([manager fileExistsAtPath:target.path])
            [manager removeItemAtURL:target error:NULL];

        NSError *error = nil;
        if (![manager copyItemAtURL:source toURL:target error:&error])
            [self.window presentError:error];
    }
    [self reload];
}

- (void)removePlugIn:(id)sender
{
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.plugIns.count)
        return;
    MPPlugIn *plugin = self.plugIns[(NSUInteger)row];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:NSLocalizedString(
        @"Rimuovere “%@”?", @"Confirm removing a plug-in"), plugin.name];
    alert.informativeText = NSLocalizedString(
        @"Il plug-in viene spostato nel Cestino.",
        @"Says removal is recoverable");
    [alert addButtonWithTitle:NSLocalizedString(@"Rimuovi", @"Confirm")];
    [alert addButtonWithTitle:NSLocalizedString(@"Annulla", @"Cancel")];

    if ([alert runModal] != NSAlertFirstButtonReturn)
        return;

    // The Trash rather than deletion: this is the user's file, and a wrong
    // click should be recoverable.
    NSError *error = nil;
    if (![[NSFileManager defaultManager] trashItemAtURL:plugin.bundleURL
                                       resultingItemURL:NULL error:&error])
    {
        [self.window presentError:error];
    }
    [self reload];
}

- (void)revealFolder:(id)sender
{
    NSString *path = MPDataDirectory(kMPPlugInsDirectoryName);
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    [[NSWorkspace sharedWorkspace]
        activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
}


#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.plugIns.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    MPPlugIn *plugin = self.plugIns[(NSUInteger)row];

    if ([column.identifier isEqualToString:kMPPlugInEnabledColumn])
    {
        NSButton *box = [NSButton checkboxWithTitle:@"" target:self
                                             action:@selector(toggleEnabled:)];
        box.state = [self isEnabled:plugin] ? NSControlStateValueOn
                                            : NSControlStateValueOff;
        box.tag = row;
        return box;
    }

    NSTextField *label = [NSTextField labelWithString:plugin.name];
    if (plugin.version.length)
    {
        label.stringValue = [NSString stringWithFormat:@"%@  %@",
                             plugin.name, plugin.version];
    }
    label.textColor = [self isEnabled:plugin] ? [NSColor labelColor]
                                              : [NSColor secondaryLabelColor];
    label.toolTip = plugin.identifier;
    return label;
}


#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateButtons];
}

@end
