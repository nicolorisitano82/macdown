//
//  MPGlobals.h
//  MacDown
//
//  Created by Tzu-ping Chung on 02/12.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "version.h"

// These should match the main bundle's values.
static NSString * const kMPApplicationName = @"MacDown Next";

/** The folder in Application Support, which is not the application's name.
 *
 * It used to be read out of CFBundleName, so renaming the application
 * would have sent it looking in a folder that does not exist — and the
 * themes, styles and plug-ins someone had put in the old one would have
 * gone quiet without a word. A display name is a label; this is an
 * address, and addresses do not change because a label did.
 */
static NSString * const kMPDataDirectoryName = @"MacDown";

#ifdef DEBUG
static NSString * const kMPApplicationBundleIdentifier = @"com.nicolorisitano82.macdown-debug";
#else
static NSString * const kMPApplicationBundleIdentifier = @"com.nicolorisitano82.macdown";
#endif

static NSString * const kMPApplicationSuiteName = @"com.nicolorisitano82.macdown";

/** The shell utility's name, and the one place it is written.
 *
 * `macdownext`, not `macdown`. It was kept as `macdown` through the rename
 * of the application so that what people had typed for years kept working;
 * that call has been overruled, and the two do not clash now — someone
 * with the original MacDown installed keeps its `macdown` and gets this
 * one beside it.
 *
 * A symlink already made under the old name is not removed by installing
 * this one: it goes on pointing at whatever app put it there.
 */
static NSString * const kMPCommandName = @"macdownext";
static NSString * const MPCommandInstallationPath =
    @"/usr/local/bin/macdownext";

static NSString * const kMPHelpKey = @"help";
static NSString * const kMPVersionKey = @"version";

static NSString * const kMPFilesToOpenKey = @"filesToOpenOnNextLaunch";
static NSString * const kMPPipedContentFileToOpen = @"pipedContentFileToOpenOnNextLaunch";
