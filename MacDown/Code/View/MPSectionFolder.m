//
//  MPSectionFolder.m
//  MacDown
//

#import "MPSectionFolder.h"
#import "MPUtilities.h"


@interface MPSection ()
@property (nonatomic) NSUInteger level;
@property (copy, nonatomic) NSString *title;
@property (nonatomic) NSRange headingRange;
@property (nonatomic) NSRange bodyRange;
@property (nonatomic) NSUInteger bodyLines;
@end


@implementation MPSection

- (NSString *)description
{
    return [NSString stringWithFormat:@"<h%lu %@ (%lu righe)>",
            (unsigned long)self.level, self.title,
            (unsigned long)self.bodyLines];
}

@end


@interface MPSectionFolder ()
@property (copy, nonatomic) NSArray<MPSection *> *sections;
/// What is folded, by heading rather than by place. See the header.
@property (strong, nonatomic) NSMutableSet<NSString *> *foldedKeys;
@property (strong, nonatomic) NSIndexSet *hiddenIndexes;
@end


@implementation MPSectionFolder

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;
    _enabled = YES;
    _sections = @[];
    _foldedKeys = [NSMutableSet set];
    _hiddenIndexes = [NSIndexSet indexSet];
    return self;
}

/// What a fold is remembered by.
static NSString *MPKeyOfSection(MPSection *section)
{
    return [NSString stringWithFormat:@"%lu\t%@",
            (unsigned long)section.level, section.title];
}


#pragma mark - Reading the headings

- (void)updateWithText:(NSString *)text
{
    NSString *whole = text ?: @"";
    NSArray<NSValue *> *code = MPMarkdownCodeRanges(whole);

    static NSRegularExpression *heading = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        // A hash with no space after it is a hashtag, not a heading, which
        // is what this editor's parser was taught as well.
        heading = [[NSRegularExpression alloc] initWithPattern:
            @"^[ \\t]{0,3}(#{1,6})[ \\t]+(\\S.*?)[ \\t]*#*[ \\t]*$"
                    options:NSRegularExpressionAnchorsMatchLines error:NULL];
    });

    NSMutableArray<MPSection *> *found = [NSMutableArray array];
    for (NSTextCheckingResult *match in [heading matchesInString:whole
            options:0 range:NSMakeRange(0, whole.length)])
    {
        BOOL inCode = NO;
        for (NSValue *value in code)
        {
            if (NSIntersectionRange(value.rangeValue, match.range).length)
            {
                inCode = YES;
                break;
            }
        }
        if (inCode)
            continue;

        MPSection *section = [[MPSection alloc] init];
        section.level = [match rangeAtIndex:1].length;
        section.title = [whole substringWithRange:[match rangeAtIndex:2]];
        section.headingRange = match.range;
        [found addObject:section];
    }

    // The body of a section runs to the next heading that is not under it.
    for (NSUInteger i = 0; i < found.count; i++)
    {
        MPSection *section = found[i];
        NSUInteger start = NSMaxRange(section.headingRange);
        // Past the line break that ends the heading, so the heading's own
        // line stays whole and visible.
        if (start < whole.length)
            start += 1;
        start = MIN(start, whole.length);

        NSUInteger end = whole.length;
        for (NSUInteger j = i + 1; j < found.count; j++)
        {
            if (found[j].level <= section.level)
            {
                end = found[j].headingRange.location;
                break;
            }
        }
        section.bodyRange = NSMakeRange(start,
                                        end > start ? end - start : 0);

        // Counted here, where the text is: what a folded heading says about
        // itself is how many lines went away.
        NSUInteger lines = 0;
        if (section.bodyRange.length)
        {
            NSUInteger at = section.bodyRange.location;
            NSUInteger limit = NSMaxRange(section.bodyRange);
            while (at < limit)
            {
                NSUInteger lineStart = 0, lineEnd = 0, contentsEnd = 0;
                [whole getLineStart:&lineStart end:&lineEnd
                        contentsEnd:&contentsEnd
                           forRange:NSMakeRange(at, 0)];
                if (lineEnd <= at)
                    break;
                // A line with nothing on it is not a line somebody misses.
                if (contentsEnd > lineStart)
                    lines++;
                at = lineEnd;
            }
        }
        section.bodyLines = lines;
    }

    self.sections = found;
    [self recomputeHidden];
}

- (void)recomputeHidden
{
    NSMutableIndexSet *hidden = [NSMutableIndexSet indexSet];
    if (self.enabled)
    {
        for (MPSection *section in self.sections)
        {
            if (section.bodyRange.length && [self isFolded:section])
                [hidden addIndexesInRange:section.bodyRange];
        }
    }
    self.hiddenIndexes = hidden;
}

- (void)setEnabled:(BOOL)enabled
{
    if (_enabled == enabled)
        return;
    _enabled = enabled;
    [self recomputeHidden];
}


#pragma mark - Which section, and whether it is folded

- (MPSection *)sectionCoveringIndex:(NSUInteger)index
{
    /* Three questions, in this order, because the boundaries touch.
     *
     * A section's body ends exactly where the next heading begins, so the
     * first character of "## Seconda sezione" was claimed both by that
     * heading and by the end of the section above it — and at equal level
     * the earlier one won, which folded the section above the one that was
     * pressed. Standing on a heading has to mean that heading, whatever
     * else ends there.
     */
    MPSection *best = nil;
    for (MPSection *section in self.sections)
    {
        if (!NSLocationInRange(index, section.headingRange))
            continue;
        if (!best || section.level > best.level)
            best = section;
    }
    if (best)
        return best;

    for (MPSection *section in self.sections)
    {
        if (!NSLocationInRange(index, section.bodyRange))
            continue;
        // The innermost: a subsection's body is inside its parent's, and
        // the one being asked about is the smaller of the two.
        if (!best || section.level > best.level)
            best = section;
    }
    if (best)
        return best;

    // The very end of the document, where nothing contains the index and
    // the caret still has to belong somewhere.
    for (MPSection *section in self.sections)
    {
        if (index != NSMaxRange(section.bodyRange)
                && index != NSMaxRange(section.headingRange))
            continue;
        if (!best || section.level > best.level)
            best = section;
    }
    return best;
}

- (BOOL)isFolded:(MPSection *)section
{
    return section && [self.foldedKeys containsObject:MPKeyOfSection(section)];
}

- (BOOL)isHiddenIndex:(NSUInteger)index
{
    return [self.hiddenIndexes containsIndex:index];
}

- (NSArray<MPSection *> *)foldedSections
{
    if (!self.enabled)
        return @[];
    NSMutableArray *folded = [NSMutableArray array];
    for (MPSection *section in self.sections)
    {
        if (section.bodyRange.length && [self isFolded:section])
            [folded addObject:section];
    }
    return folded;
}


#pragma mark - Folding

- (BOOL)fold:(MPSection *)section
{
    if (!self.enabled || !section || !section.bodyRange.length)
        return NO;
    if ([self isFolded:section])
        return NO;
    [self.foldedKeys addObject:MPKeyOfSection(section)];
    [self recomputeHidden];
    return YES;
}

- (BOOL)unfold:(MPSection *)section
{
    if (!section || ![self isFolded:section])
        return NO;
    [self.foldedKeys removeObject:MPKeyOfSection(section)];
    [self recomputeHidden];
    return YES;
}

- (BOOL)foldAll
{
    if (!self.enabled)
        return NO;
    BOOL any = NO;
    for (MPSection *section in self.sections)
    {
        if (!section.bodyRange.length || [self isFolded:section])
            continue;
        [self.foldedKeys addObject:MPKeyOfSection(section)];
        any = YES;
    }
    if (any)
        [self recomputeHidden];
    return any;
}

- (BOOL)unfoldAll
{
    if (!self.foldedKeys.count)
        return NO;
    [self.foldedKeys removeAllObjects];
    [self recomputeHidden];
    return YES;
}

- (BOOL)revealRange:(NSRange)range
{
    if (!self.hiddenIndexes.count)
        return NO;

    NSRange asked = range.length ? range : NSMakeRange(range.location, 1);
    if (![self.hiddenIndexes intersectsIndexesInRange:asked])
        return NO;

    // Every section whose body covers any of it, parents included: opening
    // a subsection inside a folded parent would show nothing.
    BOOL any = NO;
    for (MPSection *section in [self.sections copy])
    {
        if (![self isFolded:section])
            continue;
        if (!NSIntersectionRange(section.bodyRange, asked).length)
            continue;
        [self.foldedKeys removeObject:MPKeyOfSection(section)];
        any = YES;
    }
    if (any)
        [self recomputeHidden];
    return any;
}

@end
