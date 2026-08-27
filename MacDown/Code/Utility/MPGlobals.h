//
//  MPGlobals.h
//  MacDown
//
//  Created by Tzu-ping Chung on 02/12.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "version.h"

// These should match the main bundle's values.
static NSString * const kMPApplicationName = @"MacDown";

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
