//
//  MPTableAligner.m
//  MacDown
//

#import "MPTableAligner.h"
#import "MPMarkerHider.h"


/// One line of a table, and where its bars fall in the document.
@interface MPTableRow : NSObject
@property (assign, nonatomic) NSRange line;
@property (strong, nonatomic) NSMutableArray<NSNumber *> *separators;
@end

@implementation MPTableRow
@end


@interface MPTableAligner ()
@property (weak, nonatomic) NSTextView *textView;
@end


@implementation MPTableAligner

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
    [self align];
}


#pragma mark - Reading the source

/** The bars in one line that actually separate cells.
 *
 * A bar written `\|` is a bar in a cell, not the end of one. Nothing else
 * is exempt: a bar inside a code span ends the cell too, which is what the
 * renderer does with it and therefore what the writer has to see.
 */
- (NSMutableArray<NSNumber *> *)separatorsInLine:(NSRange)line
                                            text:(NSString *)text
{
    NSMutableArray<NSNumber *> *found = [NSMutableArray array];
    BOOL escaped = NO;
    for (NSUInteger i = line.location; i < NSMaxRange(line); i++)
    {
        unichar c = [text characterAtIndex:i];
        if (escaped)
        {
            escaped = NO;
            continue;
        }
        if (c == '\\')
            escaped = YES;
        else if (c == '|')
            [found addObject:@(i)];
    }
    return found;
}

/// Whether a line is the `|---|:--:|` that turns the line above into a table.
- (BOOL)isDelimiterLine:(NSRange)line text:(NSString *)text
{
    BOOL sawDash = NO;
    for (NSUInteger i = line.location; i < NSMaxRange(line); i++)
    {
        unichar c = [text characterAtIndex:i];
        if (c == '-')
            sawDash = YES;
        else if (c != '|' && c != ':' && c != ' ' && c != '\t')
            return NO;
    }
    return sawDash;
}

/// Whether a line opens or closes a fenced block, whose contents are code.
- (BOOL)isFenceLine:(NSRange)line text:(NSString *)text
{
    NSString *body = [[text substringWithRange:line]
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
    return [body hasPrefix:@"```"] || [body hasPrefix:@"~~~"];
}


#pragma mark - Measuring

/** How wide `range` is drawn, which is not how wide it is written.
 *
 * The hidden markers come out before measuring: a column padded to the width
 * of a cell's asterisks would be padded to a width nothing occupies. The
 * attributes come from the storage, so a cell set in the code face is
 * measured in the code face.
 */
- (CGFloat)drawnWidthOfRange:(NSRange)range
{
    if (!range.length)
        return 0.0;

    NSTextStorage *storage = self.textView.textStorage;
    if (NSMaxRange(range) > storage.length)
        return 0.0;

    NSMutableAttributedString *piece =
        [[storage attributedSubstringFromRange:range] mutableCopy];

    MPMarkerHider *hider = self.markerHider;
    if (hider)
    {
        // Backwards, so each deletion leaves the earlier offsets valid.
        for (NSUInteger i = range.length; i > 0; i--)
        {
            if ([hider isSkippableMarkerAtIndex:range.location + i - 1])
                [piece deleteCharactersInRange:NSMakeRange(i - 1, 1)];
        }
    }
    return piece.size.width;
}


#pragma mark - Applying

/** Takes the padding back off, wherever it was put.
 *
 * Only where it actually is: removing an attribute from a range marks that
 * range as changed whether or not it was there, and a blanket removal on
 * every parse would relayout the whole document every time the typing
 * paused, for the sake of a table that might not exist.
 */
- (void)clear
{
    NSTextStorage *storage = self.textView.textStorage;
    if (!storage.length)
        return;

    NSMutableArray<NSValue *> *kerned = [NSMutableArray array];
    [storage enumerateAttribute:NSKernAttributeName
                        inRange:NSMakeRange(0, storage.length)
                        options:0
                     usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value)
            [kerned addObject:[NSValue valueWithRange:range]];
    }];
    if (!kerned.count)
        return;

    [storage beginEditing];
    for (NSValue *range in kerned)
        [storage removeAttribute:NSKernAttributeName range:range.rangeValue];
    [storage endEditing];
}

/** Pads one table's cells out to its columns.
 *
 * The padding goes on the character in front of the bar, because kerning
 * widens the character it is set on. An empty cell has the bar before it to
 * hang the padding from; a cell at the very start of the line has nothing,
 * and is left alone — it is empty in every row or it would not be first.
 */
- (void)padRows:(NSArray<MPTableRow *> *)rows
{
    NSUInteger columns = 0;
    for (MPTableRow *row in rows)
        columns = MAX(columns, row.separators.count);
    if (!columns)
        return;

    NSTextStorage *storage = self.textView.textStorage;

    // Cell widths first, then the column each one belongs to. A cell is what
    // lies between the bar before it and the bar that ends it.
    NSMutableArray<NSMutableArray<NSNumber *> *> *widths =
        [NSMutableArray array];
    NSMutableArray<NSNumber *> *columnWidths = [NSMutableArray array];
    for (NSUInteger c = 0; c < columns; c++)
        [columnWidths addObject:@(0.0)];

    for (MPTableRow *row in rows)
    {
        NSMutableArray<NSNumber *> *cells = [NSMutableArray array];
        NSUInteger start = row.line.location;
        for (NSUInteger c = 0; c < row.separators.count; c++)
        {
            NSUInteger bar = row.separators[c].unsignedIntegerValue;
            CGFloat width = [self drawnWidthOfRange:
                NSMakeRange(start, bar - start)];
            [cells addObject:@(width)];
            if (width > columnWidths[c].doubleValue)
                columnWidths[c] = @(width);
            start = bar + 1;
        }
        [widths addObject:cells];
    }

    for (NSUInteger r = 0; r < rows.count; r++)
    {
        MPTableRow *row = rows[r];
        NSArray<NSNumber *> *cells = widths[r];
        for (NSUInteger c = 0; c < cells.count; c++)
        {
            CGFloat padding = columnWidths[c].doubleValue
                - cells[c].doubleValue;
            // Below a point is a rounding difference between two ways of
            // measuring the same glyphs, not a column out of line.
            if (padding < 1.0)
                continue;

            NSUInteger bar = row.separators[c].unsignedIntegerValue;
            if (bar == row.line.location)
                continue;   // Nothing in front of it to widen.

            [storage addAttribute:NSKernAttributeName value:@(padding)
                            range:NSMakeRange(bar - 1, 1)];
        }
    }
}


#pragma mark - Finding the tables

- (void)align
{
    NSTextStorage *storage = self.textView.textStorage;
    if (!storage.length)
        return;

    [self clear];
    if (!self.enabled)
        return;

    NSString *text = self.textView.string;
    NSUInteger length = text.length;

    // Line ranges once, since everything below is line work.
    NSMutableArray<NSValue *> *lines = [NSMutableArray array];
    NSUInteger index = 0;
    while (index < length)
    {
        NSRange line = [text lineRangeForRange:NSMakeRange(index, 0)];
        NSUInteger end = line.location + line.length;
        NSRange body = line;
        while (body.length > 0)
        {
            unichar last = [text characterAtIndex:NSMaxRange(body) - 1];
            if (last != '\n' && last != '\r')
                break;
            body.length--;
        }
        [lines addObject:[NSValue valueWithRange:body]];
        if (end <= index)
            break;
        index = end;
    }

    [storage beginEditing];

    BOOL fenced = NO;
    NSUInteger i = 0;
    while (i < lines.count)
    {
        NSRange line = lines[i].rangeValue;
        if ([self isFenceLine:line text:text])
        {
            fenced = !fenced;
            i++;
            continue;
        }
        if (fenced)
        {
            i++;
            continue;
        }

        NSMutableArray<NSNumber *> *bars = [self separatorsInLine:line
                                                             text:text];
        if (!bars.count || i + 1 >= lines.count)
        {
            i++;
            continue;
        }

        // A line of bars is only a table once the line under it says so.
        NSRange next = lines[i + 1].rangeValue;
        if (![self isDelimiterLine:next text:text]
                || ![self separatorsInLine:next text:text].count)
        {
            i++;
            continue;
        }

        NSMutableArray<MPTableRow *> *rows = [NSMutableArray array];
        NSUInteger r = i;
        while (r < lines.count)
        {
            NSRange body = lines[r].rangeValue;
            if (!body.length || [self isFenceLine:body text:text])
                break;
            NSMutableArray<NSNumber *> *found =
                [self separatorsInLine:body text:text];
            if (!found.count)
                break;

            MPTableRow *row = [[MPTableRow alloc] init];
            row.line = body;
            row.separators = found;
            [rows addObject:row];
            r++;
        }

        [self padRows:rows];
        i = MAX(r, i + 1);
    }

    [storage endEditing];
}

@end
