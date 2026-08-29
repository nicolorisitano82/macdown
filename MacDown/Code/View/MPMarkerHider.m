//
//  MPMarkerHider.m
//  MacDown
//

#import "MPMarkerHider.h"


@interface MPMarkerHider ()
@property (weak, nonatomic) NSTextView *textView;
/// Every marker character in the document.
@property (strong, nonatomic) NSMutableIndexSet *markers;
/// The constructs themselves, so the caret can be placed inside one.
@property (strong, nonatomic) NSMutableArray<NSValue *> *constructs;
/// The markers currently shown because the caret is in their construct.
@property (strong, nonatomic) NSIndexSet *revealed;
@end


@implementation MPMarkerHider

- (instancetype)initWithTextView:(NSTextView *)textView
{
    self = [super init];
    if (!self)
        return nil;
    _textView = textView;
    _markers = [NSMutableIndexSet indexSet];
    _constructs = [NSMutableArray array];
    _revealed = [NSIndexSet indexSet];
    textView.layoutManager.delegate = self;
    return self;
}

- (void)setEnabled:(BOOL)enabled
{
    if (_enabled == enabled)
        return;
    _enabled = enabled;
    [self invalidateRange:NSMakeRange(0, self.textView.textStorage.length)];
}


#pragma mark - Finding the markers

/** The delimiters of one construct, measured rather than assumed.
 *
 * The parser reports the whole of `**bold**` as one element and says nothing
 * about the asterisks, and the length is not fixed by the type: emphasis and
 * strong are the same type of thing with one or two markers, and inline code
 * takes as many backticks as the writer felt like. So both ends are measured
 * — the run of the same character inwards from each — and they have to
 * agree, or this is not a construct worth touching.
 */
- (BOOL)markerLength:(NSUInteger *)outLength
             inRange:(NSRange)range
                text:(NSString *)text
{
    if (range.length < 2 || NSMaxRange(range) > text.length)
        return NO;

    unichar first = [text characterAtIndex:range.location];
    if (first != '*' && first != '_' && first != '`')
        return NO;

    NSUInteger opening = 0;
    while (opening < range.length
           && [text characterAtIndex:range.location + opening] == first)
        opening++;

    NSUInteger closing = 0;
    while (closing < range.length
           && [text characterAtIndex:NSMaxRange(range) - 1 - closing] == first)
        closing++;

    // Unbalanced, or nothing left between them: leave it alone. A construct
    // whose markers are longer than its content is more likely a row of
    // asterisks than something to hide.
    if (opening != closing || opening == 0 || opening * 2 >= range.length)
        return NO;

    *outLength = opening;
    return YES;
}

- (void)updateWithElements:(pmh_element **)elements
{
    NSString *text = self.textView.string;
    NSUInteger length = text.length;

    NSRange previous = NSMakeRange(0, length);
    [self.markers removeAllIndexes];
    [self.constructs removeAllObjects];

    if (elements != NULL && length)
    {
        pmh_element_type types[] = {pmh_EMPH, pmh_STRONG, pmh_CODE};
        for (size_t t = 0; t < sizeof(types) / sizeof(types[0]); t++)
        {
            for (pmh_element *cursor = elements[types[t]]; cursor != NULL;
                 cursor = cursor->next)
            {
                if (cursor->end <= cursor->pos)
                    continue;
                NSRange range = NSMakeRange(cursor->pos,
                                            cursor->end - cursor->pos);
                // A stale list outliving an edit would be a crash rather
                // than a misplaced marker.
                if (NSMaxRange(range) > length)
                    continue;

                NSUInteger marker = 0;
                if (![self markerLength:&marker inRange:range text:text])
                    continue;

                [self.markers addIndexesInRange:
                    NSMakeRange(range.location, marker)];
                [self.markers addIndexesInRange:
                    NSMakeRange(NSMaxRange(range) - marker, marker)];
                [self.constructs addObject:[NSValue valueWithRange:range]];
            }
        }
    }

    [self recomputeRevealed];
    [self invalidateRange:previous];
}


#pragma mark - The caret

/** The markers to show, because the caret is working on their construct.
 *
 * The construct's own range is widened by one at each end: with the caret
 * just past a closing marker you are about to delete it, and it has to be
 * visible for that to make sense.
 */
- (void)recomputeRevealed
{
    NSMutableIndexSet *shown = [NSMutableIndexSet indexSet];
    NSRange selection = self.textView.selectedRange;

    for (NSValue *value in self.constructs)
    {
        NSRange construct = value.rangeValue;
        NSRange touched = NSMakeRange(
            construct.location > 0 ? construct.location - 1 : 0,
            construct.length + (construct.location > 0 ? 2 : 1));

        BOOL inside = NSLocationInRange(selection.location, touched)
            || NSIntersectionRange(selection, touched).length > 0;
        if (inside)
            [shown addIndexesInRange:construct];
    }
    self.revealed = shown;
}

- (void)selectionDidChange
{
    if (!self.enabled)
        return;

    NSIndexSet *before = self.revealed;
    [self recomputeRevealed];
    if ([before isEqualToIndexSet:self.revealed])
        return;

    // Only what changed: the markers that were shown and no longer are, and
    // the other way round. Invalidating the document on every arrow key
    // would relayout it on every arrow key.
    NSMutableIndexSet *changed = [before mutableCopy];
    [changed addIndexes:self.revealed];
    if (!changed.count)
        return;

    NSUInteger first = changed.firstIndex;
    NSUInteger last = changed.lastIndex;
    [self invalidateRange:NSMakeRange(first, last - first + 1)];
}

- (void)invalidateRange:(NSRange)range
{
    NSLayoutManager *manager = self.textView.layoutManager;
    NSUInteger length = self.textView.textStorage.length;
    if (!manager || !length)
        return;

    range = NSIntersectionRange(range, NSMakeRange(0, length));
    if (!range.length)
        return;

    [manager invalidateGlyphsForCharacterRange:range changeInLength:0
                          actualCharacterRange:NULL];
    [manager invalidateLayoutForCharacterRange:range
                            actualCharacterRange:NULL];
}


#pragma mark - NSLayoutManagerDelegate

- (NSUInteger)layoutManager:(NSLayoutManager *)layoutManager
       shouldGenerateGlyphs:(const CGGlyph *)glyphs
                 properties:(const NSGlyphProperty *)properties
           characterIndexes:(const NSUInteger *)characterIndexes
                       font:(NSFont *)font
            forGlyphRange:(NSRange)glyphRange
{
    if (!self.enabled || !self.markers.count)
        return 0;

    // Only worth rewriting the run if it actually contains a hidden marker.
    BOOL any = NO;
    for (NSUInteger i = 0; i < glyphRange.length; i++)
    {
        NSUInteger index = characterIndexes[i];
        if ([self.markers containsIndex:index]
                && ![self.revealed containsIndex:index])
        {
            any = YES;
            break;
        }
    }
    if (!any)
        return 0;

    NSGlyphProperty *rewritten = calloc(glyphRange.length,
                                        sizeof(NSGlyphProperty));
    if (!rewritten)
        return 0;

    for (NSUInteger i = 0; i < glyphRange.length; i++)
    {
        NSUInteger index = characterIndexes[i];
        BOOL hide = [self.markers containsIndex:index]
            && ![self.revealed containsIndex:index];
        // Null rather than ControlCharacter: the character keeps its place
        // in the text and its position in the layout, and simply draws
        // nothing. Deleting it still deletes one character, which is what
        // someone pressing backspace at that spot expects.
        rewritten[i] = hide ? NSGlyphPropertyNull : properties[i];
    }

    [layoutManager setGlyphs:glyphs properties:rewritten
            characterIndexes:characterIndexes font:font
                   forGlyphRange:glyphRange];
    free(rewritten);
    return glyphRange.length;
}

@end
