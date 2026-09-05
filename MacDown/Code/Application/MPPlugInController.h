//
//  MPPlugInController.h
//  MacDown
//
//  Created by Tzu-ping Chung on 02/3.
//  Copyright © 2016 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>

@class MPPlugIn;


@interface MPPlugInController : NSObject<NSMenuDelegate>

@property (weak) IBOutlet NSDocumentController *documentController;

/** The exporters that are installed and switched on.
 *
 * They are deliberately absent from the plug-ins menu — an exporter is a
 * format, not a command — so this is how File ▸ Export finds them.
 */
+ (NSArray<MPPlugIn *> *)enabledExporters;

@end
