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
#import "MPTableSource.h"
#import "MPSectionFolder.h"
#import "MPCodeLanguages.h"
#import "MPCodeIndenter.h"


NS_INLINE BOOL MPAreRectsEqual(NSRect r1, NSRect r2)
{
    return (r1.origin.x == r2.origin.x && r1.origin.y == r2.origin.y
            && r1.size.width == r2.size.width
            && r1.size.height == r2.size.height);
}


@interface MPEditorView ()
@property (assign, nonatomic) NSUInteger tableActionIndex;
@property (assign, nonatomic) NSUInteger codeActionIndex;
/// Where the "N righe" marks were drawn, so a click on one can be caught.
@property (strong, nonatomic) NSMutableArray *foldMarks;
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
 * The document asks for these to be off when it sets the editor up, and
 * that is where the real fix is: it used to hand over a text-checking mask
 * that turned them back on. This is the belt to that pair of braces —
 * whatever else touches the view, the last word is taken as it gains focus.
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
    _tableMenuEnabled = YES;
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

        // With the caret on it the dashes are drawn again, and a line
        // through them would be the rule and its own source at once.
        if (![self.markerHider isHiddenMarkerAtIndex:range.location])
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
/** What a folded heading says about itself.
 *
 * Text that is not drawn is text nobody can tell is there, so a folded
 * section puts a count at the end of its heading. Also the place to click
 * to get it back — the rectangles are kept as they are drawn, since that is
 * the only pass that knows where the heading ended.
 */
- (void)drawFoldMarks
{
    self.foldMarks = [NSMutableArray array];
    NSArray<MPSection *> *folded = self.sectionFolder.foldedSections;
    if (!folded.count)
        return;

    NSLayoutManager *manager = self.layoutManager;
    NSTextContainer *container = self.textContainer;
    if (!manager || !container)
        return;

    NSSize inset = self.textContainerInset;
    NSFont *font = [NSFont systemFontOfSize:
        [NSFont smallSystemFontSize]];

    for (MPSection *section in folded)
    {
        NSRange heading = section.headingRange;
        if (!heading.length || NSMaxRange(heading) > self.textStorage.length)
            continue;

        NSRange glyphs = [manager glyphRangeForCharacterRange:heading
                                        actualCharacterRange:NULL];
        if (!glyphs.length)
            continue;
        NSRect used = [manager boundingRectForGlyphRange:glyphs
                                         inTextContainer:container];
        if (NSIsEmptyRect(used))
            continue;

        NSString *label = [NSString stringWithFormat:
            NSLocalizedString(@"▸ %lu righe", @"A folded section's line count"),
            (unsigned long)section.bodyLines];
        if (section.bodyLines == 1)
        {
            label = NSLocalizedString(@"▸ 1 riga",
                                      @"A folded section of one line");
        }

        NSDictionary *style = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
        };
        NSSize size = [label sizeWithAttributes:style];
        NSRect pill = NSMakeRect(inset.width + NSMaxX(used) + 8.0,
                                 inset.height + NSMinY(used)
                                     + (NSHeight(used) - size.height) / 2.0,
                                 size.width + 12.0, size.height + 2.0);

        [[NSColor quaternaryLabelColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:pill xRadius:4.0 yRadius:4.0]
            fill];
        [label drawAtPoint:NSMakePoint(NSMinX(pill) + 6.0, NSMinY(pill))
            withAttributes:style];

        [self.foldMarks addObject:@{
            @"rect": [NSValue valueWithRect:pill],
            @"index": @(heading.location),
        }];
    }
}

/// A click on a fold's mark opens it; everything else is a click in text.
- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    for (NSDictionary *mark in self.foldMarks)
    {
        if (!NSPointInRect(point, [mark[@"rect"] rectValue]))
            continue;
        [self unfoldSectionAtIndex:[mark[@"index"] unsignedIntegerValue]];
        return;
    }
    [super mouseDown:event];
}


#pragma mark - Folding

/// Puts the layout right after the set of hidden characters has changed.
- (void)foldingChanged
{
    self.markerHider.foldedIndexes = self.sectionFolder.hiddenIndexes;

    NSRange whole = NSMakeRange(0, self.textStorage.length);
    [self.layoutManager invalidateGlyphsForCharacterRange:whole
                                           changeInLength:0
                                     actualCharacterRange:NULL];
    [self.layoutManager invalidateLayoutForCharacterRange:whole
                                     actualCharacterRange:NULL];
    [self setNeedsDisplay:YES];
}

- (BOOL)foldSectionAtIndex:(NSUInteger)index
{
    MPSection *section = [self.sectionFolder sectionCoveringIndex:index];
    if (![self.sectionFolder fold:section])
        return NO;

    // The caret cannot stay in what has just gone dark: it goes to the
    // heading, which is where somebody who folded a section is looking.
    if (NSLocationInRange(self.selectedRange.location, section.bodyRange))
        self.selectedRange = NSMakeRange(section.headingRange.location, 0);
    [self foldingChanged];
    return YES;
}

- (BOOL)unfoldSectionAtIndex:(NSUInteger)index
{
    MPSection *section = [self.sectionFolder sectionCoveringIndex:index];
    if (![self.sectionFolder unfold:section])
        return NO;
    [self foldingChanged];
    return YES;
}

- (BOOL)foldEverySection
{
    if (![self.sectionFolder foldAll])
        return NO;
    if ([self.sectionFolder isHiddenIndex:self.selectedRange.location])
        self.selectedRange = NSMakeRange(0, 0);
    [self foldingChanged];
    return YES;
}

- (BOOL)unfoldEverySection
{
    if (![self.sectionFolder unfoldAll])
        return NO;
    [self foldingChanged];
    return YES;
}

- (BOOL)revealFoldedSelection
{
    if (![self.sectionFolder revealRange:self.selectedRange])
        return NO;
    [self foldingChanged];
    return YES;
}


- (void)drawViewBackgroundInRect:(NSRect)rect
{
    [super drawViewBackgroundInRect:rect];
    [self drawQuoteBars];
    [self drawRules];
    [self drawFoldMarks];

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
 * Only the ones actually out of sight. Arriving beside a construct reveals
 * it, so in the ordinary case there is nothing here to skip and the caret
 * walks the delimiters one at a time — which is right, because by then it
 * can see them. What is left for this to do is the caret that is beside a
 * hidden marker anyway: a second caret of a multiple selection, or the
 * moment between an edit and the parse that follows it.
 */
- (NSUInteger)positionSkippingHiddenMarkersFrom:(NSUInteger)position
                                        forward:(BOOL)forward
{
    NSUInteger length = self.string.length;
    NSUInteger result = position;

    if (forward)
    {
        while (result < length
               && [self.markerHider isHiddenMarkerAtIndex:result])
            result++;
    }
    else
    {
        while (result > 0
               && [self.markerHider isHiddenMarkerAtIndex:result - 1])
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
 * Only while the markers are hidden. Once the caret is on the construct
 * they are drawn, and deleting one asterisk of a pair is ordinary text
 * editing and none of this business — which is how a delimiter gets
 * changed rather than only removed wholesale.
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

#pragma mark - Table commands

/** The table commands, on the menu the right button opens.
 *
 * Seven separate insert commands is what a table looks like from the
 * outside: above, below, at the end, at the start, here. From the inside
 * they are four, because the menu already knows which cell was clicked —
 * "at the end" is "below" pressed on the last row. What the shorter list
 * leaves room for is what was missing: taking a row or a column out again,
 * and setting a column's alignment, which is the one piece of table syntax
 * nobody remembers.
 *
 * Two more appear only when they apply: giving a table its separator row,
 * and repairing one whose dashes are not hyphens.
 */
- (NSMenu *)menuForEvent:(NSEvent *)event
{
    NSMenu *menu = [super menuForEvent:event];
    if (!menu)
        return menu;

    /* The note that leads somewhere before there is anything there.
     *
     * At the top, and only with something selected, because the selection
     * is both the name of the file and the words of the link — with nothing
     * selected there is nothing to call it. Target nil so it walks the
     * responder chain to the document, which is what knows where its own
     * folder is.
     */
    if (self.selectedRange.length > 0)
    {
        NSMenuItem *link = [[NSMenuItem alloc] initWithTitle:
            NSLocalizedString(@"Link to a New Markdown File",
                              @"Editor context menu")
            action:@selector(linkToNewMarkdownFile:) keyEquivalent:@""];
        link.target = nil;
        [menu insertItem:link atIndex:0];
        [menu insertItem:[NSMenuItem separatorItem] atIndex:1];
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSUInteger index = [self characterIndexForInsertionAtPoint:point];
    if (index == NSNotFound || index > self.string.length)
        return menu;

    [self addCodeBlockItemsToMenu:menu forIndex:index];
    [self addFoldingItemsToMenu:menu forIndex:index];

    if (!self.tableMenuEnabled)
        return menu;

    MPTableSource *table = [MPTableSource tableCoveringIndex:index
                                                      inText:self.string];
    if (!table)
        return menu;

    self.tableActionIndex = index;

    NSMutableArray<NSMenuItem *> *items = [NSMutableArray array];
    NSUInteger row = [table rowContainingIndex:index];
    BOOL onSeparator = (row != NSNotFound && row == table.separatorRow);

    void (^add)(NSString *, SEL) = ^(NSString *title, SEL action) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:action
                                               keyEquivalent:@""];
        item.target = self;
        [items addObject:item];
    };

    if (table.separatorIsBroken)
    {
        add(NSLocalizedString(@"Repair the Separator Row",
                              @"Table menu: rewrite a mangled |---| row"),
            @selector(repairTableSeparator:));
        [items addObject:[NSMenuItem separatorItem]];
    }
    else if (table.separatorRow == NSNotFound)
    {
        add(NSLocalizedString(@"Make This a Table",
                              @"Table menu: add the missing |---| row"),
            @selector(addTableHeaderRow:));
        [items addObject:[NSMenuItem separatorItem]];
    }

    add(NSLocalizedString(@"Insert Row Above", @"Table menu"),
        @selector(insertTableRowAbove:));
    add(NSLocalizedString(@"Insert Row Below", @"Table menu"),
        @selector(insertTableRowBelow:));
    add(NSLocalizedString(@"Insert Column to the Left", @"Table menu"),
        @selector(insertTableColumnLeft:));
    add(NSLocalizedString(@"Insert Column to the Right", @"Table menu"),
        @selector(insertTableColumnRight:));

    [items addObject:[NSMenuItem separatorItem]];
    if (!onSeparator && table.rowCount > 2)
        add(NSLocalizedString(@"Delete Row", @"Table menu"),
            @selector(deleteTableRow:));
    if (table.columnCount > 1)
        add(NSLocalizedString(@"Delete Column", @"Table menu"),
            @selector(deleteTableColumn:));

    NSMenuItem *align = [[NSMenuItem alloc]
        initWithTitle:NSLocalizedString(@"Align Column", @"Table menu")
               action:NULL keyEquivalent:@""];
    NSMenu *alignments = [[NSMenu alloc] init];
    NSArray *titles = @[NSLocalizedString(@"Default", @"Table column alignment"),
                        NSLocalizedString(@"Left", @"Table column alignment"),
                        NSLocalizedString(@"Center", @"Table column alignment"),
                        NSLocalizedString(@"Right", @"Table column alignment")];
    NSUInteger column = [table columnContainingIndex:index];
    MPTableAlignment current = column == NSNotFound
        ? MPTableAlignmentNone : [table alignmentOfColumn:column];
    for (NSUInteger i = 0; i < titles.count; i++)
    {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[i]
            action:@selector(alignTableColumn:) keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)i;
        item.state = (current == (MPTableAlignment)i)
            ? NSControlStateValueOn : NSControlStateValueOff;
        [alignments addItem:item];
    }
    align.submenu = alignments;
    [items addObject:[NSMenuItem separatorItem]];
    [items addObject:align];
    [items addObject:[NSMenuItem separatorItem]];

    for (NSUInteger i = 0; i < items.count; i++)
        [menu insertItem:items[i] atIndex:(NSInteger)i];
    return menu;
}

/// Folding, on the section that was clicked rather than the one with the caret.
- (void)addFoldingItemsToMenu:(NSMenu *)menu forIndex:(NSUInteger)index
{
    MPSection *section = [self.sectionFolder sectionCoveringIndex:index];
    if (!section || !section.bodyRange.length)
        return;

    BOOL folded = [self.sectionFolder isFolded:section];
    NSString *title = [NSString stringWithFormat:folded
        ? NSLocalizedString(@"Apri «%@»", @"Unfold the clicked section")
        : NSLocalizedString(@"Piega «%@»", @"Fold the clicked section"),
        section.title];

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
        action:folded ? @selector(unfoldClickedSection:)
                      : @selector(foldClickedSection:)
        keyEquivalent:@""];
    item.target = self;
    item.tag = (NSInteger)section.headingRange.location;
    [menu insertItem:item atIndex:0];
    [menu insertItem:[NSMenuItem separatorItem] atIndex:1];
}

- (void)foldClickedSection:(NSMenuItem *)sender
{
    [self foldSectionAtIndex:(NSUInteger)sender.tag];
}

- (void)unfoldClickedSection:(NSMenuItem *)sender
{
    [self unfoldSectionAtIndex:(NSUInteger)sender.tag];
}

/** The one command a code block has of its own: lay it out.
 *
 * Only for a block whose language has a rule, and only when the rule would
 * actually change something — a command that does nothing when you press it
 * teaches you to stop pressing it.
 */
- (void)addCodeBlockItemsToMenu:(NSMenu *)menu forIndex:(NSUInteger)index
{
    MPFencedCodeBlock *block =
        [MPFencedCodeBlock blockCoveringIndex:index inText:self.string];
    if (!block || !block.language.length)
        return;

    MPCodeIndentRule *rule = MPCodeIndentRuleForLanguage(block.language);
    if (!rule || rule.family == MPCodeIndentFamilyNone)
        return;

    NSString *body = [self.string substringWithRange:block.bodyRange];
    if ([MPReindentedCode(body, block.language) isEqualToString:body])
        return;

    self.codeActionIndex = index;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:
        [NSString stringWithFormat:
            NSLocalizedString(@"Indent as %@", @"Editor context menu"),
            MPTitleOfCodeLanguage(block.language)]
        action:@selector(indentCodeBlock:) keyEquivalent:@""];
    item.target = self;
    [menu insertItem:item atIndex:0];
    [menu insertItem:[NSMenuItem separatorItem] atIndex:1];
}

/// The block is found again from the click, so a stale menu cannot misfire.
- (IBAction)indentCodeBlock:(id)sender
{
    NSUInteger index = self.codeActionIndex;
    if (index > self.string.length)
        return;

    MPFencedCodeBlock *block =
        [MPFencedCodeBlock blockCoveringIndex:index inText:self.string];
    if (!block)
        return;

    NSString *body = [self.string substringWithRange:block.bodyRange];
    NSString *laid = MPReindentedCode(body, block.language);
    if (!laid || [laid isEqualToString:body])
        return;

    if (![self shouldChangeTextInRange:block.bodyRange
                    replacementString:laid])
        return;

    [self.textStorage replaceCharactersInRange:block.bodyRange
                                    withString:laid];
    [self didChangeText];
    [self.undoManager setActionName:
        [NSString stringWithFormat:
            NSLocalizedString(@"Indent as %@", @"Editor context menu"),
            MPTitleOfCodeLanguage(block.language)]];

    // The code that moved, so what the command did can be seen.
    self.selectedRange = NSMakeRange(block.bodyRange.location, laid.length);
}

/// Runs one edit: the table is read again, so a stale menu cannot misfire.
- (void)applyTableEdit:(NSString *(^)(MPTableSource *, NSUInteger row,
                                      NSUInteger column, NSUInteger *caret))edit
{
    NSUInteger index = self.tableActionIndex;
    if (index > self.string.length)
        return;
    MPTableSource *table = [MPTableSource tableCoveringIndex:index
                                                      inText:self.string];
    if (!table)
        return;

    NSUInteger row = [table rowContainingIndex:index];
    NSUInteger column = [table columnContainingIndex:index];
    if (row == NSNotFound)
        row = 0;
    if (column == NSNotFound)
        column = 0;

    NSUInteger caret = table.range.location;
    NSString *replacement = edit(table, row, column, &caret);
    if (!replacement)
        return;
    if (![self shouldChangeTextInRange:table.range
                     replacementString:replacement])
        return;

    [self.textStorage replaceCharactersInRange:table.range
                                    withString:replacement];
    [self didChangeText];
    self.selectedRange = NSMakeRange(MIN(caret, self.string.length), 0);
}

- (IBAction)insertTableRowAbove:(id)sender
{
    [self applyTableEdit:^NSString *(MPTableSource *t, NSUInteger row,
                                     NSUInteger column, NSUInteger *caret) {
        return [t textByInsertingRowAt:row caret:caret];
    }];
}

- (IBAction)insertTableRowBelow:(id)sender
{
    [self applyTableEdit:^NSString *(MPTableSource *t, NSUInteger row,
                                     NSUInteger column, NSUInteger *caret) {
        return [t textByInsertingRowAt:row + 1 caret:caret];
    }];
}

- (IBAction)insertTableColumnLeft:(id)sender
{
    [self applyTableEdit:^NSString *(MPTableSource *t, NSUInteger row,
                                     NSUInteger column, NSUInteger *caret) {
        return [t textByInsertingColumnAt:column caret:caret];
    }];
}

- (IBAction)insertTableColumnRight:(id)sender
{
    [self applyTableEdit:^NSString *(MPTableSource *t, NSUInteger row,
                                     NSUInteger column, NSUInteger *caret) {
        return [t textByInsertingColumnAt:column + 1 caret:caret];
    }];
}

- (IBAction)deleteTableRow:(id)sender
{
    [self applyTableEdit:^NSString *(MPTableSource *t, NSUInteger row,
                                     NSUInteger column, NSUInteger *caret) {
        return [t textByDeletingRow:row caret:caret];
    }];
}

- (IBAction)deleteTableColumn:(id)sender
{
    [self applyTableEdit:^NSString *(MPTableSource *t, NSUInteger row,
                                     NSUInteger column, NSUInteger *caret) {
        return [t textByDeletingColumn:column caret:caret];
    }];
}

- (IBAction)alignTableColumn:(id)sender
{
    MPTableAlignment alignment =
        (MPTableAlignment)[(NSMenuItem *)sender tag];
    [self applyTableEdit:^NSString *(MPTableSource *t, NSUInteger row,
                                     NSUInteger column, NSUInteger *caret) {
        return [t textBySettingAlignment:alignment forColumn:column
                                   caret:caret];
    }];
}

- (IBAction)addTableHeaderRow:(id)sender
{
    [self applyTableEdit:^NSString *(MPTableSource *t, NSUInteger row,
                                     NSUInteger column, NSUInteger *caret) {
        return [t textByAddingSeparatorRowWithCaret:caret];
    }];
}

- (IBAction)repairTableSeparator:(id)sender
{
    [self applyTableEdit:^NSString *(MPTableSource *t, NSUInteger row,
                                     NSUInteger column, NSUInteger *caret) {
        return [t textByRepairingSeparatorRowWithCaret:caret];
    }];
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
