//
//  MPQuickLookExtension.h
//  MacDown
//

#import <Cocoa/Cocoa.h>


/// Where the Finder preview stands, from the reader's point of view.
typedef NS_ENUM(NSUInteger, MPQuickLookExtensionState) {
    /// Registered, switched on, and this copy of the application's own.
    MPQuickLookExtensionStateInstalled,
    /// Registered from here, but an older build than the one running.
    MPQuickLookExtensionStateOutdated,
    /// Registered from a different copy of the application.
    MPQuickLookExtensionStateElsewhere,
    /// Registered and switched off, which only the reader can have done.
    MPQuickLookExtensionStateDisabled,
    /// The system does not know about it.
    MPQuickLookExtensionStateNotInstalled,
    /// This build carries no extension to install.
    MPQuickLookExtensionStateMissing,
};


/** The Finder preview for Markdown files, as the system sees it.
 *
 * The extension lives inside the application — an extension cannot live
 * anywhere else — so "installing" it means getting macOS to notice it, and
 * "removing" it means getting macOS to forget it. Both are asked of the
 * same tools the system uses itself, because there is no API for it.
 *
 * Worth having a panel for because the registration goes wrong in ways
 * nothing tells you about: a copy of the application in the Downloads
 * folder can hold the registration, an update can leave the old build
 * registered, and a preview that does not appear says nothing at all.
 */
@interface MPQuickLookExtension : NSObject

/// What the system currently thinks.
@property (readonly, nonatomic) MPQuickLookExtensionState state;

/// The extension's bundle identifier, which is what the system knows it by.
@property (readonly, copy, nonatomic) NSString *identifier;

/// The extension inside the running application, or nil if there is none.
@property (readonly, copy, nonatomic) NSURL *bundledURL;
/// Its version, as the extension itself reports it.
@property (readonly, copy, nonatomic) NSString *bundledVersion;

/// The copy the system has registered, when there is one.
@property (readonly, copy, nonatomic) NSURL *registeredURL;
/// And the version of that copy, as the system reports it.
@property (readonly, copy, nonatomic) NSString *registeredVersion;

/// A sentence saying where things stand, for the panel to show.
@property (readonly, copy, nonatomic) NSString *summary;
/// Whether installing would change anything.
@property (readonly, nonatomic) BOOL canInstall;
/// Whether there is a registration to take away.
@property (readonly, nonatomic) BOOL canRemove;

/// Asks the system. Takes a moment: it runs the tools that know.
+ (instancetype)current;

/** Makes macOS notice the extension inside this application.
 *
 * Also what an update goes through: the registration is replaced rather
 * than added to, because a stale record is not replaced by asking twice.
 */
- (BOOL)install:(NSError **)error;

/// Makes macOS forget it. The application itself stays registered.
- (BOOL)remove:(NSError **)error;

@end


#pragma mark - The parts worth checking on their own

/// One record out of `pluginkit -m -vvv` output, or nil when it is not there.
///
/// Keys: `path`, `parent`, `version`, and `enabled` — which is false only
/// when the reader has switched the extension off by hand.
extern NSDictionary *MPQuickLookRecordInListing(NSString *listing,
                                                NSString *identifier);

/// Where things stand, given what the system says and what is in the app.
extern MPQuickLookExtensionState MPQuickLookStateForRecord(
    NSDictionary *record, NSURL *bundledURL, NSString *bundledVersion);
