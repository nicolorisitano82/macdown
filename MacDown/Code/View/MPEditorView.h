//
//  MPEditorView.h
//  MacDown
//
//  Created by Tzu-ping Chung  on 30/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MPEditorView : NSTextView

@property BOOL scrollsPastEnd;

/// Underlines words the prose checker flags. Off by default.
@property BOOL proseHighlightsEnabled;

- (NSRect)contentRect;

/// Recomputes the prose underlines. Cheap enough to call on every edit: it
/// only touches the layout manager's temporary attributes, never the text.
- (void)updateProseHighlights;

@end
