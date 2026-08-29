//
//  MPEditorView.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 30/8.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPEditorView.h"
#import "MPProseChecker.h"
#import "MPMarkerHider.h"


NS_INLINE BOOL MPAreRectsEqual(NSRect r1, NSRect r2)
{
    return (r1.origin.x == r2.origin.x && r1.origin.y == r2.origin.y
            && r1.size.width == r2.size.width
            && r1.size.height == r2.size.height);
}


@interface MPEditorView ()
@property (assign, nonatomic) NSRange lastDrawnActiveRange;

@property NSRect contentRect;
@property CGFloat trailingHeight;

@end


@implementation MPEditorView

#pragma mark - Accessors

@synthesize contentRect = _contentRect;
@synthesize scrollsPastEnd = _scrollsPastEnd;

- (BOOL)scrollsPastEnd
{
    @synchronized(self) {
        return _scrollsPastEnd;
    }
}

#pragma mark - Prose highlights

- (void)setProseHighlightsEnabled:(BOOL)enabled
{
    if (_proseHighlightsEnabled == enabled)
        return;
    _proseHighlightsEnabled = enabled;
    [self updateProseHighlights];
}

/** Underlines flagged words.
 *
 * Temporary attributes rather than the text storage: they are display-only,
 * so they leave the document unmodified, stay out of the undo stack, and
 * cannot end up in a saved file or on the pasteboard.
 */
- (void)updateProseHighlights
{
    NSLayoutManager *manager = self.layoutManager;
    if (!manager)
        return;

    NSRange whole = NSMakeRange(0, self.string.length);
    [manager removeTemporaryAttribute:NSUnderlineStyleAttributeName
                    forCharacterRange:whole];
    [manager removeTemporaryAttribute:NSUnderlineColorAttributeName
                    forCharacterRange:whole];

    if (!self.proseHighlightsEnabled)
        return;

    MPProseChecker *checker = [MPProseChecker sharedChecker];
    NSArray<MPProseIssue *> *issues = [checker issuesInString:self.string];
    for (MPProseIssue *issue in issues)
    {
        if (NSMaxRange(issue.range) > whole.length)
            continue;
        // A dotted underline, to stay clear of the solid red the spell
        // checker already draws.
        [manager addTemporaryAttributes:@{
            NSUnderlineStyleAttributeName:
                @(NSUnderlineStyleThick | NSUnderlinePatternDot),
            NSUnderlineColorAttributeName: issue.color,
        } forCharacterRange:issue.range];
    }
}


- (void)awakeFromNib {
    _activeSourceRange = NSMakeRange(NSNotFound, 0);
    [self registerForDraggedTypes:[NSArray arrayWithObjects: NSDragPboard, nil]];
    [super awakeFromNib];
}

- (void)setActiveSourceRange:(NSRange)range
{
    if (NSEqualRanges(range, _activeSourceRange))
        return;
    _activeSourceRange = range;
    [self setNeedsDisplay:YES];
}

/** Draws the bar marking the block the preview is looking at.
 *
 * In the inset to the left of the text rather than beside it, so turning it
 * on does not reflow a line.
 */
- (void)drawViewBackgroundInRect:(NSRect)rect
{
    [super drawViewBackgroundInRect:rect];

    NSRange range = self.activeSourceRange;
    if (range.location == NSNotFound || range.length == 0)
        return;
    if (NSMaxRange(range) > self.textStorage.length)
        return;

    NSLayoutManager *manager = self.layoutManager;
    NSTextContainer *container = self.textContainer;
    if (!manager || !container)
        return;

    NSRange glyphs = [manager glyphRangeForCharacterRange:range
                                     actualCharacterRange:NULL];
    NSRect bounds = [manager boundingRectForGlyphRange:glyphs
                                       inTextContainer:container];
    if (NSIsEmptyRect(bounds))
        return;

    CGFloat inset = self.textContainerInset.width;
    // Centred in the inset, and never off the left edge on a narrow one.
    CGFloat width = 3.0;
    CGFloat x = MAX(2.0, inset / 2.0 - width / 2.0);

    NSRect bar = NSMakeRect(x,
                            bounds.origin.y + self.textContainerInset.height,
                            width, bounds.size.height);
    if (!NSIntersectsRect(bar, rect))
        return;

    NSColor *ink = self.insertionPointColor ?: [NSColor textColor];
    [[ink colorWithAlphaComponent:0.45] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:1.5 yRadius:1.5] fill];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
    
    sourceDragMask = [sender draggingSourceOperationMask];
    pboard = [sender draggingPasteboard];
    
    if ([pboard canReadItemWithDataConformingToTypes:[NSArray arrayWithObjects:@"public.jpeg", nil]]) {
        if (sourceDragMask & NSDragOperationLink) {
            return NSDragOperationLink;
        } else if (sourceDragMask & NSDragOperationCopy) {
            return NSDragOperationCopy;
        }
    }
    
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
    
    sourceDragMask = [sender draggingSourceOperationMask];
    pboard = [sender draggingPasteboard];
    
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
        
        /* Load data of file. */
        NSError *error;
        NSData *fileData = [NSData dataWithContentsOfFile: files[0]
                                                  options: NSMappedRead
                                                    error: &error];
        if (!error) {
            // convert to base64 representation
            NSString *dataString = [fileData base64Encoding];
            
            // insert into text.
            NSInteger insertionPoint = [[[self selectedRanges] objectAtIndex:0] rangeValue].location;
            [self setString:[NSString stringWithFormat:@"%@![](data:image/jpeg;base64,%@)%@", [[self string] substringToIndex:insertionPoint], dataString, [[self string] substringFromIndex:insertionPoint]]];
            [self didChangeText];
        } else {
            return NO;
        }
    }
    return YES;
}


- (void)setScrollsPastEnd:(BOOL)scrollsPastEnd
{
    @synchronized(self) {
        _scrollsPastEnd = scrollsPastEnd;
        if (scrollsPastEnd)
        {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self updateContentGeometry];
            }];
        }
        else
        {
            // Clears contentRect to fallback to self.frame.
            self.contentRect = NSZeroRect;
        }
    }
}

- (NSRect)contentRect
{
    @synchronized(self) {
        if (MPAreRectsEqual(_contentRect, NSZeroRect))
            return self.frame;
        return _contentRect;
    }
}

- (void)setContentRect:(NSRect)rect
{
    @synchronized(self) {
        _contentRect = rect;
    }
}

- (void)setFrameSize:(NSSize)newSize
{
    if (self.scrollsPastEnd)
    {
        CGFloat ch = self.contentRect.size.height;
        CGFloat eh = self.enclosingScrollView.contentSize.height;
        CGFloat offset = ch < eh ? ch : eh;
        offset -= self.trailingHeight + 2 * self.textContainerInset.height;
        if (offset > 0)
            newSize.height += offset;
    }
    [super setFrameSize:newSize];
}

/** Overriden to perform extra operation on initial text setup.
 *
 * When we first launch the editor, -didChangeText will *not* be called, so we
 * override this to perform required resizing. The -updateContentRect is wrapped
 * inside an NSOperation to be invoked later since the layout manager will not
 * be invoked when the text is first set.
 *
 * @see didChangeText
 * @see updateContentRect
 */
- (void)setString:(NSString *)string
{
    [super setString:string];
    if (self.scrollsPastEnd)
    {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self updateContentGeometry];
        }];
    }
}


#pragma mark - Moving across a marker

/** Steps over markers the reader cannot see.
 *
 * The characters are still there when they are hidden, so the caret used to
 * stall on them: two presses of the right arrow to cross `**`, both of them
 * moving nothing that anyone could see. It now crosses the whole run at
 * once, in either direction.
 *
 * Every marker, not only the ones currently out of sight: arriving next to
 * a construct reveals it, so a marker is never both adjacent and hidden.
 * With hiding on, delimiters are simply not places the caret stops.
 */
- (NSUInteger)positionSkippingHiddenMarkersFrom:(NSUInteger)position
                                        forward:(BOOL)forward
{
    NSUInteger length = self.string.length;
    NSUInteger result = position;

    if (forward)
    {
        while (result < length
               && [self.markerHider isSkippableMarkerAtIndex:result])
            result++;
    }
    else
    {
        while (result > 0
               && [self.markerHider isSkippableMarkerAtIndex:result - 1])
            result--;
    }
    return result;
}

- (void)moveRight:(id)sender
{
    NSRange selection = self.selectedRange;
    if (selection.length == 0)
    {
        NSUInteger skipped =
            [self positionSkippingHiddenMarkersFrom:selection.location
                                            forward:YES];
        if (skipped != selection.location)
        {
            self.selectedRange = NSMakeRange(skipped, 0);
            // The markers are behind the caret now; carry on with the step
            // the reader actually asked for.
        }
    }
    [super moveRight:sender];
}

- (void)moveLeft:(id)sender
{
    [super moveLeft:sender];

    NSRange selection = self.selectedRange;
    if (selection.length != 0)
        return;
    NSUInteger skipped =
        [self positionSkippingHiddenMarkersFrom:selection.location
                                        forward:NO];
    if (skipped != selection.location)
        self.selectedRange = NSMakeRange(skipped, 0);
}


#pragma mark - Deleting a marker

/** Removes the emphasis rather than half of its punctuation.
 *
 * Backspace over the last asterisk of `**bold**` used to leave `**bold*`,
 * which is broken Markdown made out of characters that were invisible a
 * moment earlier. What someone means by that keystroke is "stop this being
 * bold", so the whole construct is replaced by what it contains — one edit,
 * and one step to undo.
 *
 * Only when the markers are being hidden. With them visible, deleting one
 * asterisk of a pair is ordinary text editing and none of this business.
 */
- (BOOL)removeConstructForDeletionAt:(NSUInteger)index
{
    NSRange construct = NSMakeRange(NSNotFound, 0);
    NSUInteger marker = 0;
    if (![self.markerHider construct:&construct markerLength:&marker
               coveringMarkerAtIndex:index])
        return NO;

    NSRange inner = NSMakeRange(construct.location + marker,
                                construct.length - 2 * marker);
    if (inner.length == 0 || NSMaxRange(construct) > self.string.length)
        return NO;

    NSString *content = [self.string substringWithRange:inner];
    if (![self shouldChangeTextInRange:construct replacementString:content])
        return NO;

    [self.textStorage replaceCharactersInRange:construct withString:content];
    [self didChangeText];
    self.selectedRange = NSMakeRange(construct.location + inner.length, 0);
    return YES;
}

- (void)deleteBackward:(id)sender
{
    NSRange selection = self.selectedRange;
    if (selection.length == 0 && selection.location > 0
            && [self removeConstructForDeletionAt:selection.location - 1])
        return;
    [super deleteBackward:sender];
}

- (void)deleteForward:(id)sender
{
    NSRange selection = self.selectedRange;
    if (selection.length == 0 && selection.location < self.string.length
            && [self removeConstructForDeletionAt:selection.location])
        return;
    [super deleteForward:sender];
}


#pragma mark - Overrides

/** Overriden to perform extra operation on text change.
 *
 * Updates content height, and invoke the resizing method to apply it.
 *
 * @see updateContentRect
 */
- (void)didChangeText
{
    [super didChangeText];
    if (self.scrollsPastEnd)
        [self updateContentGeometry];
    if (self.proseHighlightsEnabled)
        [self updateProseHighlights];
}


#pragma mark - Private

- (void)updateContentGeometry
{
    static NSCharacterSet *visibleCharacterSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        visibleCharacterSet = ws.invertedSet;
    });

    NSString *content = self.string;
    NSLayoutManager *manager = self.layoutManager;
    NSTextContainer *container = self.textContainer;
    NSRect r = [manager usedRectForTextContainer:container];

    NSRange lastRange = [content rangeOfCharacterFromSet:visibleCharacterSet
                                                 options:NSBackwardsSearch];
    NSRect junkRect = r;
    if (lastRange.location != NSNotFound)
    {
        NSUInteger contentLength = content.length;
        NSUInteger firstJunkLocation = lastRange.location + lastRange.length;
        NSRange junkRange = NSMakeRange(firstJunkLocation,
                                        contentLength - firstJunkLocation);
        junkRect = [manager boundingRectForGlyphRange:junkRange
                                      inTextContainer:container];
    }
    self.trailingHeight = junkRect.size.height;

    NSSize inset = self.textContainerInset;
    r.size.width += 2 * inset.width;
    r.size.height += 2 * inset.height;
    self.contentRect = r;

    [self setFrameSize:self.frame.size];    // Force size update.
}

@end
