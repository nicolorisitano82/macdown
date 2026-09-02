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

static NSString * const MPCommandInstallationPath = @"/usr/local/bin/macdown";
static NSString * const kMPCommandName = @"macdown";

static NSString * const kMPHelpKey = @"help";
static NSString * const kMPVersionKey = @"version";

static NSString * const kMPFilesToOpenKey = @"filesToOpenOnNextLaunch";
static NSString * const kMPPipedContentFileToOpen = @"pipedContentFileToOpenOnNextLaunch";
