//
//  MPSemanticStyler.m
//  MacDown
//

#import "MPSemanticStyler.h"
#import "HGMarkdownHighlightingStyle.h"


/** The body size a theme's numbers were chosen against.
 *
 * An assumption, and worth naming as one: no theme records this. It is
 * MacDown's default editor size, which is what a theme author would have
 * been looking at while picking the numbers. Being wrong about it costs
 * proportion, not correctness — and at this size the styler is a no-op, so
 * anyone on the default sees exactly what the theme intended.
 */
static const CGFloat kMPAssumedThemeBodySize = 14.0;


@interface MPSemanticStyler ()
@property (weak, nonatomic) NSTextView *textView;
/// Element type to the ratio the theme wanted, against the body size.
@property (strong, nonatomic) NSDictionary<NSNumber *, NSNumber *> *ratios;
@end


@implementation MPSemanticStyler

- (instancetype)initWithTextView:(NSTextView *)textView
{
    self = [super init];
    if (!self)
        return nil;
    _textView = textView;
    return self;
}


#pragma mark - Reading the theme

- (void)setThemeStyles:(NSArray<HGMarkdownHighlightingStyle *> *)styles
{
    _themeStyles = [styles copy];

    NSMutableDictionary *ratios = [NSMutableDictionary dictionary];
    for (HGMarkdownHighlightingStyle *style in styles)
    {
        NSDictionary *info = style.attributesToAdd[HGFontInformation];
        CGFloat size = [info[HGFontInformationSizeKey] doubleValue];
        // Only sizes. A theme that says nothing about an element's size is
        // saying it should look like the body, which needs no help.
        if (size <= 0.0)
            continue;
        ratios[@(style.elementType)] = @(size / kMPAssumedThemeBodySize);
    }
    _ratios = ratios;
}


#pragma mark - Applying

- (NSLayoutManager *)layoutManager
{
    return self.textView.layoutManager;
}

/** Nothing to undo.
 *
 * The highlighter rewrites the theme's own fonts over the whole document on
 * every pass, so switching this off and asking for a parse is enough to put
 * them back. Removing anything here would strip the base font instead.
 */
- (void)removeStyling
{
}

- (void)applyToElements:(pmh_element **)elements
{
    NSTextStorage *storage = self.textView.textStorage;
    NSUInteger length = storage.length;
    if (!length)
        return;

    if (!self.enabled || elements == NULL || !self.ratios.count)
        return;

    NSFont *base = self.baseFont ?: self.textView.font;
    if (!base)
        return;

    // Nothing to correct when the reader is on the size the theme was
    // written for, and saying so plainly beats re-applying identical fonts.
    if (fabs(base.pointSize - kMPAssumedThemeBodySize) < 0.01)
        return;

    // Into the text storage, not as temporary attributes. Those are display
    // only and documented not to affect layout: the font went in and the
    // reader saw no change, because nothing was re-laid out. It never
    // reaches the file — the document is saved as the string.
    NSFontManager *fonts = [NSFontManager sharedFontManager];
    [storage beginEditing];

    for (NSNumber *key in self.ratios)
    {
        pmh_element_type type = (pmh_element_type)key.integerValue;
        CGFloat ratio = [self.ratios[key] doubleValue];
        CGFloat size = round(base.pointSize * ratio);
        if (size <= 0.0)
            continue;

        for (pmh_element *cursor = elements[type]; cursor != NULL;
             cursor = cursor->next)
        {
            if (cursor->end <= cursor->pos)
                continue;
            NSRange range = NSMakeRange(cursor->pos,
                                        cursor->end - cursor->pos);
            // A stale element list outliving an edit would otherwise be a
            // crash rather than a wrong size.
            if (NSMaxRange(range) > length)
                continue;

            // Resized from whatever the highlighter left in place, so the
            // weight and face the theme asked for come along.
            NSFont *current = [storage attribute:NSFontAttributeName
                                         atIndex:range.location
                                  effectiveRange:NULL] ?: base;
            NSFont *sized = [fonts convertFont:current toSize:size];
            if (!sized)
                continue;
            [storage addAttribute:NSFontAttributeName value:sized
                            range:range];
        }
    }

    [storage endEditing];
}

@end
