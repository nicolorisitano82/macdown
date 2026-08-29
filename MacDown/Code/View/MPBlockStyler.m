//
//  MPBlockStyler.m
//  MacDown
//

#import "MPBlockStyler.h"
#import "MPEditorView.h"


@interface MPBlockStyler ()
@property (weak, nonatomic) NSTextView *textView;
@end


@implementation MPBlockStyler

- (instancetype)initWithTextView:(NSTextView *)textView
{
    self = [super init];
    if (!self)
        return nil;
    _textView = textView;
    return self;
}

- (void)setEnabled:(BOOL)enabled
{
    if (_enabled == enabled)
        return;
    _enabled = enabled;
    if (!enabled)
        [self clear];
}


#pragma mark - Measurements

/// Indents in character widths, so they hold at any font size.
- (CGFloat)characterWidth
{
    NSFont *font = self.baseFont ?: self.textView.font;
    if (!font)
        return 7.0;
    CGFloat width = [@"m" sizeWithAttributes:@{NSFontAttributeName: font}].width;
    return width > 0.0 ? width : 7.0;
}

/** The paragraph style already in force at `location`, ready to be adjusted.
 *
 * Derived rather than built: the reader's line spacing lives in this same
 * attribute, and a fresh NSParagraphStyle would silently discard it.
 */
- (NSMutableParagraphStyle *)styleAt:(NSUInteger)location
{
    NSTextStorage *storage = self.textView.textStorage;
    NSParagraphStyle *existing = nil;
    if (location < storage.length)
    {
        existing = [storage attribute:NSParagraphStyleAttributeName
                              atIndex:location effectiveRange:NULL];
    }
    if (!existing)
        existing = self.textView.defaultParagraphStyle;
    if (!existing)
        existing = [NSParagraphStyle defaultParagraphStyle];
    return [existing mutableCopy];
}


#pragma mark - Applying

- (void)clear
{
    NSTextStorage *storage = self.textView.textStorage;
    if (!storage.length)
        return;

    NSParagraphStyle *plain = self.textView.defaultParagraphStyle
        ?: [NSParagraphStyle defaultParagraphStyle];
    [storage beginEditing];
    [storage addAttribute:NSParagraphStyleAttributeName value:plain
                    range:NSMakeRange(0, storage.length)];
    [storage endEditing];

    if ([self.textView isKindOfClass:[MPEditorView class]])
        [(MPEditorView *)self.textView setQuoteRanges:@[]];
}

- (void)applyToElements:(pmh_element **)elements
{
    NSTextStorage *storage = self.textView.textStorage;
    NSUInteger length = storage.length;
    if (!length)
        return;

    if (!self.enabled || elements == NULL)
    {
        [self clear];
        return;
    }

    CGFloat unit = [self characterWidth];
    NSMutableArray<NSValue *> *quotes = [NSMutableArray array];

    [storage beginEditing];

    // Back to plain first: a block that stopped being a block on the last
    // keystroke has to lose its indent, and there is no record of which.
    NSParagraphStyle *plain = self.textView.defaultParagraphStyle
        ?: [NSParagraphStyle defaultParagraphStyle];
    [storage addAttribute:NSParagraphStyleAttributeName value:plain
                    range:NSMakeRange(0, length)];

    // Lists first, quotes second: a list inside a quotation should carry
    // both indents, and the quote's is the outer one.
    struct { pmh_element_type type; CGFloat head; CGFloat first; } blocks[] = {
        {pmh_LIST_BULLET,     3.0, 0.0},
        {pmh_LIST_ENUMERATOR, 3.0, 0.0},
        {pmh_BLOCKQUOTE,      2.0, 2.0},
    };

    for (size_t b = 0; b < sizeof(blocks) / sizeof(blocks[0]); b++)
    {
        for (pmh_element *cursor = elements[blocks[b].type]; cursor != NULL;
             cursor = cursor->next)
        {
            if (cursor->end <= cursor->pos)
                continue;
            NSRange range = NSMakeRange(cursor->pos, cursor->end - cursor->pos);
            if (NSMaxRange(range) > length)
                continue;

            NSMutableParagraphStyle *style = [self styleAt:range.location];
            // The hanging indent: a list item's second line lines up with
            // its first word, not with its bullet.
            style.headIndent += blocks[b].head * unit;
            style.firstLineHeadIndent += blocks[b].first * unit;
            [storage addAttribute:NSParagraphStyleAttributeName value:style
                            range:range];

            if (blocks[b].type == pmh_BLOCKQUOTE)
                [quotes addObject:[NSValue valueWithRange:range]];
        }
    }

    // Headings get room above them rather than below: the space belongs to
    // the section that is starting, which is what makes it read as a break.
    for (pmh_element_type type = pmh_H1; type <= pmh_H6; type++)
    {
        for (pmh_element *cursor = elements[type]; cursor != NULL;
             cursor = cursor->next)
        {
            if (cursor->end <= cursor->pos)
                continue;
            NSRange range = NSMakeRange(cursor->pos, cursor->end - cursor->pos);
            if (NSMaxRange(range) > length)
                continue;

            NSMutableParagraphStyle *style = [self styleAt:range.location];
            style.paragraphSpacingBefore = 10.0;
            style.paragraphSpacing = 4.0;
            [storage addAttribute:NSParagraphStyleAttributeName value:style
                            range:range];
        }
    }

    [storage endEditing];

    if ([self.textView isKindOfClass:[MPEditorView class]])
        [(MPEditorView *)self.textView setQuoteRanges:quotes];
}

@end
