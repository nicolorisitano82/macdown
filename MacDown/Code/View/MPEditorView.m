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
#import "MPMarkdownFromRichText.h"


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


/** Turns off the corrections that rewrite Markdown as you type.
 *
 * `---` is a horizontal rule, the underline of a setext heading, and the
 * separator row of a table; turned into an em dash it is none of them, and
 * the table stops being a table. Straight quotes belong in a link title and
 * in any HTML the document carries. Capitalising the first word of a line
 * rewrites `git` and `npm` in a document about them.
 *
 * The document already asks for these to be off when it sets the editor
 * up. Something puts them back — typing `---` in a released build produced
 * an em dash — and the mechanism is not yet pinned down; setting them from
 * the view, last of all as it takes focus, is the position nothing later
 * can undo.
 */
- (void)disableTextSubstitutions
{
    self.automaticDashSubstitutionEnabled = NO;
    self.automaticQuoteSubstitutionEnabled = NO;
    self.automaticTextReplacementEnabled = NO;
    self.automaticSpellingCorrectionEnabled = NO;
    self.automaticDataDetectionEnabled = NO;
    if (@available(macOS 10.12.2, *))
        self.automaticTextCompletionEnabled = NO;
}

- (BOOL)becomeFirstResponder
{
    BOOL became = [super becomeFirstResponder];
    if (became)
        [self disableTextSubstitutions];
    return became;
}

- (void)awakeFromNib {
    _activeSourceRange = NSMakeRange(NSNotFound, 0);
    [self registerForDraggedTypes:[NSArray arrayWithObjects: NSDragPboard, nil]];
    [super awakeFromNib];
    [self disableTextSubstitutions];
}

- (void)setActiveSourceRange:(NSRange)range
{
    if (NSEqualRanges(range, _activeSourceRange))
        return;
    _activeSourceRange = range;
    [self setNeedsDisplay:YES];
}

/// A rule down the margin of a quotation, where the preview draws one too.
- (void)drawQuoteBars
{
    if (!self.quoteRanges.count)
        return;

    NSLayoutManager *manager = self.layoutManager;
    NSTextContainer *container = self.textContainer;
    NSColor *ink = self.textColor ?: [NSColor textColor];
    if (!manager || !container)
        return;

    [[ink colorWithAlphaComponent:0.25] setFill];
    CGFloat unit = self.textContainerInset.width;

    for (NSValue *value in self.quoteRanges)
    {
        NSRange range = value.rangeValue;
        if (NSMaxRange(range) > self.textStorage.length)
            continue;

        NSRange glyphs = [manager glyphRangeForCharacterRange:range
                                         actualCharacterRange:NULL];

        // Per line fragment, not once for the whole range. A quotation whose
        // line wraps has one bounding rectangle covering both lines, and its
        // continuation carries no > of its own; drawing from the fragments
        // gives an unbroken rule beside every line the quotation occupies.
        [manager enumerateLineFragmentsForGlyphRange:glyphs
            usingBlock:^(NSRect fragment, NSRect used, NSTextContainer *c,
                         NSRange glyphRange, BOOL *stop) {
            // A fixed distance from the margin rather than following the
            // text: the indent is the same on every line, and a bar that
            // moved with the words would not read as one rule.
            NSRect bar = NSMakeRect(unit + 6.0,
                                    fragment.origin.y
                                        + self.textContainerInset.height,
                                    2.0, fragment.size.height);
            NSRectFillUsingOperation(bar, NSCompositingOperationSourceOver);
        }];
    }
}

/** A line across the text where the source has three dashes.
 *
 * The dashes are hidden by then, so the line stands in for them rather than
 * decorating them; that is why this and the hiding are switched on together.
 */
- (void)drawRules
{
    if (!self.ruleRanges.count)
        return;

    NSLayoutManager *manager = self.layoutManager;
    NSTextContainer *container = self.textContainer;
    NSColor *ink = self.textColor ?: [NSColor textColor];
    if (!manager || !container)
        return;

    [[ink colorWithAlphaComponent:0.3] setFill];
    NSSize inset = self.textContainerInset;

    for (NSValue *value in self.ruleRanges)
    {
        NSRange range = value.rangeValue;
        if (NSMaxRange(range) > self.textStorage.length)
            continue;

        // Measured from the line break that closes the rule, not from the
        // dashes. Their glyphs are suppressed, and a run of suppressed
        // glyphs at the head of a line is folded into the fragment above it
        // — asking where the dashes are puts the answer one row too high.
        NSUInteger anchor = NSMaxRange(range);
        if (anchor >= self.textStorage.length)
            anchor = range.location;
        NSRange glyphs = [manager glyphRangeForCharacterRange:NSMakeRange(anchor, 1)
                                         actualCharacterRange:NULL];
        if (!glyphs.length)
            continue;
        NSRect fragment = [manager lineFragmentRectForGlyphAtIndex:glyphs.location
                                                    effectiveRange:NULL];
        if (NSIsEmptyRect(fragment))
            continue;

        // Down the middle of the line the dashes would have occupied: the
        // line keeps its height even with nothing drawn in it, so the rule
        // sits in the gap rather than pushing the text apart.
        NSRect rule = NSMakeRect(inset.width + 4.0,
                                 inset.height + NSMidY(fragment) - 0.5,
                                 container.size.width - 8.0, 1.0);
        NSRectFillUsingOperation(rule, NSCompositingOperationSourceOver);
    }
}

/** Draws the bar marking the block the preview is looking at.
 *
 * In the inset to the left of the text rather than beside it, so turning it
 * on does not reflow a line.
 */
- (void)drawViewBackgroundInRect:(NSRect)rect
{
    [super drawViewBackgroundInRect:rect];
    [self drawQuoteBars];
    [self drawRules];

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
    // The step first, then over whatever markers it landed on — the same
    // order as -moveLeft:. Skipping first and stepping afterwards counted
    // the markers as a move of their own, so a caret standing on one (put
    // there by a click, by Home, or by arriving at the start of a line)
    // came out one character past where it should.
    [super moveRight:sender];

    NSRange selection = self.selectedRange;
    if (selection.length != 0)
        return;
    NSUInteger skipped =
        [self positionSkippingHiddenMarkersFrom:selection.location
                                        forward:YES];
    if (skipped != selection.location)
        self.selectedRange = NSMakeRange(skipped, 0);
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
 * and one step to undo. Over a link's tail it leaves the link's text, which
 * is the same idea.
 *
 * Only when the markers are being hidden. With them visible, deleting one
 * asterisk of a pair is ordinary text editing and none of this business.
 */
- (BOOL)removeConstructForDeletionAt:(NSUInteger)index
{
    NSRange construct = NSMakeRange(NSNotFound, 0);
    NSRange inner = NSMakeRange(NSNotFound, 0);
    if (![self.markerHider construct:&construct content:&inner
               coveringMarkerAtIndex:index])
        return NO;

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

/** Deletes past a run of markers that are not being drawn.
 *
 * With `**bold**` shown as `bold`, the caret after the last `d` is really
 * after the closing asterisks, and backspace there has to remove the `d` —
 * that is the character the reader sees in front of the caret. So the run
 * of undrawn markers is stepped over and the deletion lands on the text.
 *
 * Two cases end differently. A construct with nothing left inside it is
 * removed whole, because `****` is not something anyone meant to type; and
 * one that has no content at all — a horizontal rule, which is delimiter
 * from end to end — goes the same way in a single press.
 */
- (BOOL)deleteThroughHiddenMarkersFrom:(NSUInteger)caret backward:(BOOL)back
{
    MPMarkerHider *hider = self.markerHider;
    if (!hider)
        return NO;

    NSUInteger edge = caret;
    if (back)
    {
        while (edge > 0 && [hider isHiddenMarkerAtIndex:edge - 1])
            edge--;
    }
    else
    {
        while (edge < self.string.length
               && [hider isHiddenMarkerAtIndex:edge])
            edge++;
    }
    if (edge == caret)
        return NO;

    // The construct that owns the run, taken from one of its own markers.
    NSRange construct = NSMakeRange(NSNotFound, 0);
    NSRange inner = NSMakeRange(NSNotFound, 0);
    NSUInteger marker = back ? edge : caret;
    if (![hider construct:&construct content:&inner
        coveringMarkerAtIndex:marker])
        return NO;
    if (NSMaxRange(construct) > self.string.length)
        return NO;

    NSRange doomed;
    if (inner.length <= 1)
        doomed = construct;
    else if (back)
        doomed = NSMakeRange(edge - 1, 1);
    else
        doomed = NSMakeRange(edge, 1);

    if (back && inner.length > 1 && doomed.location < inner.location)
        return NO;
    if (!back && inner.length > 1 && doomed.location >= NSMaxRange(inner))
        return NO;

    if (![self shouldChangeTextInRange:doomed replacementString:@""])
        return NO;
    [self.textStorage replaceCharactersInRange:doomed withString:@""];
    [self didChangeText];

    // Back where it looked like it was, which is on the far side of the
    // markers. Leaving it at the deletion point would put it inside the
    // construct, which reveals the markers — and the next press of the same
    // key would then be deleting something else.
    NSUInteger rest;
    if (inner.length <= 1)
        rest = construct.location;
    else
        rest = back ? caret - doomed.length : caret;
    self.selectedRange = NSMakeRange(rest, 0);
    return YES;
}

#pragma mark - Pasting

/** The Markdown for what is on the pasteboard, if it is worth having.
 *
 * Nil when the pasteboard holds nothing but plain text, and also when the
 * conversion comes back the same as the plain text — in both cases the
 * ordinary paste does the same thing, and going through here would only
 * risk doing it differently.
 */
- (NSString *)markdownFromPasteboard:(NSPasteboard *)board
{
    NSString *plain = [board stringForType:NSPasteboardTypeString];
    NSString *markdown = nil;

    NSString *html = [board stringForType:NSPasteboardTypeHTML];
    if (html.length)
    {
        markdown = [MPMarkdownFromRichText markdownFromHTML:html];
    }
    else
    {
        // Word processors and note-takers that offer styled text and no
        // HTML. Less to go on, but better than dropping the formatting.
        NSData *data = [board dataForType:NSPasteboardTypeRTFD]
            ?: [board dataForType:NSPasteboardTypeRTF];
        if (data.length)
        {
            NSAttributedString *styled = [[NSAttributedString alloc]
                initWithData:data options:@{} documentAttributes:NULL
                       error:NULL];
            if (styled.length)
                markdown = [MPMarkdownFromRichText
                    markdownFromAttributedString:styled];
        }
    }

    if (!markdown.length)
        return nil;
    if (plain && [markdown isEqualToString:plain])
        return nil;
    return markdown;
}

- (void)paste:(id)sender
{
    NSString *markdown = self.pastesAsMarkdown
        ? [self markdownFromPasteboard:[NSPasteboard generalPasteboard]] : nil;
    if (!markdown)
    {
        [super paste:sender];
        return;
    }
    // Through insertText: so that it is one undo step and the delegate sees
    // it, exactly as a plain paste would be.
    [self insertText:markdown replacementRange:self.selectedRange];
}


#pragma mark - Deleting

- (void)deleteBackward:(id)sender
{
    NSRange selection = self.selectedRange;
    if (selection.length == 0 && selection.location > 0)
    {
        if ([self deleteThroughHiddenMarkersFrom:selection.location
                                        backward:YES])
            return;
        if ([self removeConstructForDeletionAt:selection.location - 1])
            return;
    }
    [super deleteBackward:sender];
}

- (void)deleteForward:(id)sender
{
    NSRange selection = self.selectedRange;
    if (selection.length == 0 && selection.location < self.string.length)
    {
        if ([self deleteThroughHiddenMarkersFrom:selection.location
                                        backward:NO])
            return;
        if ([self removeConstructForDeletionAt:selection.location])
            return;
    }
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
