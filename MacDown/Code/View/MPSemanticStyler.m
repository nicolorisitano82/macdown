//
//  MPSemanticStyler.m
//  MacDown
//

#import "MPSemanticStyler.h"


/// Heading sizes as multiples of the editor's base size. The steps narrow as
/// they go down, which is what keeps six levels from running out of room.
static const CGFloat kMPHeadingScales[] = {
    1.60,   // H1
    1.42,   // H2
    1.28,   // H3
    1.16,   // H4
    1.08,   // H5
    1.04,   // H6
};


@interface MPSemanticStyler ()
@property (weak, nonatomic) NSTextView *textView;
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


#pragma mark - Fonts

- (NSFont *)baseFontOrDefault
{
    if (self.baseFont)
        return self.baseFont;
    return self.textView.font ?: [NSFont userFixedPitchFontOfSize:0.0];
}

- (NSFont *)fontWithTraits:(NSFontTraitMask)traits scale:(CGFloat)scale
{
    NSFont *base = [self baseFontOrDefault];
    NSFontManager *manager = [NSFontManager sharedFontManager];

    NSFont *font = base;
    if (scale != 1.0)
    {
        font = [manager convertFont:font toSize:round(base.pointSize * scale)];
    }
    if (traits)
    {
        NSFont *converted = [manager convertFont:font toHaveTrait:traits];
        // A monospaced editor font often has no italic cut. Obliquing it by
        // hand beats silently showing emphasis as plain text.
        if (converted == font && (traits & NSItalicFontMask))
        {
            NSFontDescriptor *oblique = [font.fontDescriptor
                fontDescriptorByAddingAttributes:@{
                    NSFontTraitsAttribute: @{NSFontSlantTrait: @(0.22)},
                }];
            converted = [NSFont fontWithDescriptor:oblique
                                              size:0.0] ?: font;
        }
        font = converted;
    }
    return font;
}

- (NSFont *)monospacedFont
{
    NSFont *base = [self baseFontOrDefault];
    // Already fixed pitch — most editor fonts are — so leave it be rather
    // than swapping in a second monospaced face for no gain.
    if (base.isFixedPitch)
        return base;
    return [NSFont monospacedSystemFontOfSize:base.pointSize
                                       weight:NSFontWeightRegular];
}


#pragma mark - Applying

- (NSLayoutManager *)layoutManager
{
    return self.textView.layoutManager;
}

- (void)removeStyling
{
    NSLayoutManager *manager = [self layoutManager];
    NSUInteger length = self.textView.textStorage.length;
    NSRange all = NSMakeRange(0, length);
    if (!manager || !length)
        return;

    // Only the two attributes this class sets. A blanket removal would take
    // the prose checker's underlines with it.
    [manager removeTemporaryAttribute:NSFontAttributeName
                    forCharacterRange:all];
    [manager removeTemporaryAttribute:NSBackgroundColorAttributeName
                    forCharacterRange:all];
}

- (void)applyToElements:(pmh_element **)elements
{
    NSLayoutManager *manager = [self layoutManager];
    NSTextStorage *storage = self.textView.textStorage;
    if (!manager || !storage.length)
        return;

    [self removeStyling];
    if (!self.enabled || elements == NULL)
        return;

    NSUInteger length = storage.length;

    // Blocks first, spans second: emphasis inside a heading should keep the
    // heading's size and gain the weight, not be overwritten by it.
    pmh_element_type blockOrder[] = {
        pmh_VERBATIM, pmh_H6, pmh_H5, pmh_H4, pmh_H3, pmh_H2, pmh_H1,
    };
    for (size_t i = 0; i < sizeof(blockOrder) / sizeof(blockOrder[0]); i++)
        [self applyType:blockOrder[i] from:elements limit:length];

    pmh_element_type spanOrder[] = {
        pmh_EMPH, pmh_STRONG, pmh_CODE,
    };
    for (size_t i = 0; i < sizeof(spanOrder) / sizeof(spanOrder[0]); i++)
        [self applyType:spanOrder[i] from:elements limit:length];
}

- (void)applyType:(pmh_element_type)type
             from:(pmh_element **)elements
            limit:(NSUInteger)length
{
    NSLayoutManager *manager = [self layoutManager];

    for (pmh_element *cursor = elements[type]; cursor != NULL;
         cursor = cursor->next)
    {
        if (cursor->end <= cursor->pos)
            continue;
        NSRange range = NSMakeRange(cursor->pos, cursor->end - cursor->pos);
        // The parser works on its own copy; a stale element list outliving an
        // edit would otherwise be a crash rather than a wrong colour.
        if (NSMaxRange(range) > length)
            continue;

        NSDictionary *attributes = [self attributesForType:type];
        if (attributes)
            [manager addTemporaryAttributes:attributes forCharacterRange:range];
    }
}

- (NSDictionary *)attributesForType:(pmh_element_type)type
{
    switch (type)
    {
        case pmh_H1: case pmh_H2: case pmh_H3:
        case pmh_H4: case pmh_H5: case pmh_H6:
        {
            NSUInteger level = (NSUInteger)(type - pmh_H1);
            CGFloat scale = kMPHeadingScales[MIN(level, (NSUInteger)5)];
            return @{NSFontAttributeName:
                [self fontWithTraits:NSBoldFontMask scale:scale]};
        }
        case pmh_STRONG:
            return @{NSFontAttributeName:
                [self fontWithTraits:NSBoldFontMask scale:1.0]};
        case pmh_EMPH:
            return @{NSFontAttributeName:
                [self fontWithTraits:NSItalicFontMask scale:1.0]};
        case pmh_CODE:
        case pmh_VERBATIM:
        {
            // A tint of the text colour rather than a fixed grey, so it sits
            // on a dark editor theme as well as a light one.
            NSColor *text = self.textView.textColor ?: [NSColor textColor];
            NSColor *plate = [text colorWithAlphaComponent:0.08];
            return @{
                NSFontAttributeName: [self monospacedFont],
                NSBackgroundColorAttributeName: plate,
            };
        }
        default:
            return nil;
    }
}

@end
