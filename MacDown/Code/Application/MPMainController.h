//
//  MPMainController.h
//  MacDown
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>
@class MPPreferences;

/// The tag on Format › Insert Template, so a test can find the same menu.
extern const NSInteger kMPTemplateMenuTag;

@interface MPMainController : NSObject <NSApplicationDelegate>

@property (nonatomic, readonly) MPPreferences *preferences;

@end
