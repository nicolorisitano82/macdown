//
//  MPPlugIn.h
//  MacDown
//
//  Created by Tzu-ping Chung on 02/3.
//  Copyright © 2016 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MPDOcument.h"

@interface MPPlugIn : NSObject

@property (nonatomic, readonly) NSString *name;
/// The bundle identifier, or the file name when the bundle declares none.
/// Used to remember which plug-ins have been switched off.
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *version;
@property (nonatomic, readonly) NSURL *bundleURL;

- (instancetype)initWithBundle:(NSBundle *)bundle;
- (BOOL)run:(id)sender;

- (void)plugInDidInitialize;

@end
