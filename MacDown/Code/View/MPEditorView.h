//
//  MPEditorView.h
//  MacDown
//
//  Created by Tzu-ping Chung  on 30/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class MPMarkerHider;

@interface MPEditorView : NSTextView

@property BOOL scrollsPastEnd;

/** The block the preview is showing the reader, drawn as a margin bar.
 *
 * A location of NSNotFound clears it. Presentation only: it never touches
 * the text or the selection.
 */
@property (assign, nonatomic) NSRange activeSourceRange;

/// Underlines words the prose checker flags. Off by default.
@property BOOL proseHighlightsEnabled;

/** Consulted when a deletion lands on a hidden marker.
 *
 * Weak: the hider is owned by the document, and holds this view.
 */
@property (weak, nonatomic) MPMarkerHider *markerHider;

/// The blockquotes, drawn as a bar in the margin. Presentation only.
@property (copy, nonatomic) NSArray<NSValue *> *quoteRanges;

/** Whether pasting formatted text writes Markdown rather than plain text.
 *
 * ⌘⇧V is unaffected, and stays the way to paste exactly what was copied.
 */
@property (assign, nonatomic) BOOL pastesAsMarkdown;

/** The horizontal rules, drawn as a line across the text.
 *
 * Set only when their dashes are being hidden as well, so that the drawn
 * line replaces them rather than joining them.
 */
@property (copy, nonatomic) NSArray<NSValue *> *ruleRanges;

- (NSRect)contentRect;

/// Recomputes the prose underlines. Cheap enough to call on every edit: it
/// only touches the layout manager's temporary attributes, never the text.
- (void)updateProseHighlights;

@end
