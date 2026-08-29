//
//  MPMarkdownFromRichText.m
//  MacDown
//

#import "MPMarkdownFromRichText.h"
#import <AppKit/AppKit.h>


/// One open inline construct, so an empty one can be taken back out again.
@interface MPInlineMark : NSObject
@property (copy, nonatomic) NSString *closing;
@property (assign, nonatomic) NSUInteger openingLength;
@property (assign, nonatomic) NSUInteger contentStart;
@end

@implementation MPInlineMark
@end


/// One level of list, ordered or not, counting its own items.
@interface MPListLevel : NSObject
@property (assign, nonatomic) BOOL ordered;
@property (assign, nonatomic) NSUInteger index;
@end

@implementation MPListLevel
@end


@interface MPMarkdownFromRichText ()

@property (strong, nonatomic) NSMutableString *out;
@property (strong, nonatomic) NSMutableArray<MPInlineMark *> *inlines;
@property (strong, nonatomic) NSMutableArray<MPListLevel *> *lists;
@property (assign, nonatomic) NSUInteger quoteDepth;
@property (assign, nonatomic) NSUInteger skipDepth;

/** How many line breaks are owed before the next thing written.
 *
 * Kept as a number rather than written straight out: a document ends up
 * with runs of empty tags around nothing, and asking for a break that never
 * gets used costs nothing, while a blank line already written has to be
 * taken back.
 */
@property (assign, nonatomic) NSUInteger pendingBreaks;

/// True from `<li>` until the item has some text, so the block tags a page
/// puts inside its items do not push the text off the bullet.
@property (assign, nonatomic) BOOL atItemStart;

/// Set while inside <pre>, which keeps its own whitespace and its own text.
@property (strong, nonatomic) NSMutableString *preformatted;
@property (copy, nonatomic) NSString *preLanguage;

/// Table cells are collected rather than written, then laid out at </table>.
@property (strong, nonatomic) NSMutableArray<NSMutableArray<NSString *> *> *rows;
@property (strong, nonatomic) NSMutableString *cell;

@end


@implementation MPMarkdownFromRichText

#pragma mark - Entry points

+ (NSString *)markdownFromHTML:(NSString *)html
{
    if (!html.length)
        return @"";
    MPMarkdownFromRichText *converter = [[self alloc] init];
    return [converter convert:html];
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;
    _out = [NSMutableString string];
    _inlines = [NSMutableArray array];
    _lists = [NSMutableArray array];
    return self;
}


#pragma mark - Writing

/// Everything written goes through here, so a cell or a fence can catch it.
- (NSMutableString *)sink
{
    if (self.cell)
        return self.cell;
    if (self.preformatted)
        return self.preformatted;
    return self.out;
}

/// The `> ` and the indent that every line inside a quote or a list carries.
- (NSString *)linePrefix
{
    NSMutableString *prefix = [NSMutableString string];
    for (NSUInteger i = 0; i < self.quoteDepth; i++)
        [prefix appendString:@"> "];
    for (NSUInteger i = 1; i < self.lists.count; i++)
        [prefix appendString:@"  "];
    return prefix;
}

/// Asks for a break; two of them is a blank line, and so a new block.
- (void)requestBreaks:(NSUInteger)count
{
    if (self.cell || self.preformatted)
        return;
    self.pendingBreaks = MAX(self.pendingBreaks, count);
}

- (void)flushBreaks
{
    if (!self.pendingBreaks)
        return;
    NSUInteger count = self.pendingBreaks;
    self.pendingBreaks = 0;

    NSString *prefix = [self linePrefix];
    // Nothing written yet: no line to end, and a document should not open
    // with the blank line its first block asked for. The prefix is still
    // owed — a fragment that begins inside a quotation begins with `> `.
    if (self.out.length)
    {
        NSString *empty = [prefix stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
        [self.out appendString:@"\n"];
        for (NSUInteger i = 1; i < count; i++)
            [self.out appendFormat:@"%@\n", empty];
    }
    [self.out appendString:prefix];
}

- (void)write:(NSString *)text
{
    if (self.skipDepth || !text.length)
        return;
    if (!self.cell && !self.preformatted)
        [self flushBreaks];
    [[self sink] appendString:text];
}

/** A break between two blocks, which a list is allowed to overrule.
 *
 * Pages wrap the contents of a list item in `<p>` and `<div>`, and taken at
 * face value each one would end the item and start a paragraph of its own.
 * Inside a list the gap shrinks to a single line — which Markdown reads as
 * a continuation of the item — and right after the bullet it disappears.
 */
- (void)requestBlockBreak
{
    if (self.atItemStart)
        return;
    [self requestBreaks:self.lists.count ? 1 : 2];
}


#pragma mark - Inline constructs

- (void)openInline:(NSString *)opening closing:(NSString *)closing
{
    if (self.skipDepth)
        return;
    [self write:opening];
    MPInlineMark *mark = [[MPInlineMark alloc] init];
    mark.closing = closing;
    mark.openingLength = opening.length;
    mark.contentStart = [self sink].length;
    [self.inlines addObject:mark];
}

/** Closes the innermost inline construct, or takes it back if it is empty.
 *
 * `<strong></strong>` around nothing is common in pasted markup, and a bare
 * `****` in the document is markup the reader has to clean up by hand.
 */
- (void)closeInline
{
    if (self.skipDepth || !self.inlines.count)
        return;
    MPInlineMark *mark = self.inlines.lastObject;
    [self.inlines removeLastObject];

    NSMutableString *sink = [self sink];
    NSString *content = sink.length > mark.contentStart
        ? [sink substringFromIndex:mark.contentStart] : @"";

    // Empty, or spanning a line break. Inline markup cannot cross a block
    // boundary in Markdown, and a page that wraps a heading in a link would
    // otherwise leave a stray bracket at each end of it.
    BOOL usable = content.length
        && [content rangeOfString:@"\n"].location == NSNotFound;
    if (!usable)
    {
        if (mark.openingLength && mark.contentStart >= mark.openingLength)
            [sink deleteCharactersInRange:
                NSMakeRange(mark.contentStart - mark.openingLength,
                            mark.openingLength)];
        return;
    }
    [self write:mark.closing];
}


#pragma mark - Text

/// Markdown's own punctuation, so pasted prose does not become markup.
- (NSString *)escaped:(NSString *)text
{
    static NSCharacterSet *special = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        special = [NSCharacterSet characterSetWithCharactersInString:
                   @"\\*_`[]"];
    });

    NSMutableString *escaped = [NSMutableString stringWithCapacity:text.length];
    for (NSUInteger i = 0; i < text.length; i++)
    {
        unichar c = [text characterAtIndex:i];
        if ([special characterIsMember:c])
            [escaped appendString:@"\\"];
        [escaped appendFormat:@"%C", c];
    }
    return escaped;
}

- (void)writeText:(NSString *)text
{
    if (self.skipDepth || !text.length)
        return;

    if (self.preformatted)
    {
        [self.preformatted appendString:text];
        return;
    }

    // HTML collapses whitespace, and a pasted fragment carries all the
    // indentation of the page it was laid out in.
    NSMutableString *flat = [NSMutableString stringWithCapacity:text.length];
    BOOL space = NO;
    for (NSUInteger i = 0; i < text.length; i++)
    {
        unichar c = [text characterAtIndex:i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == 0x00A0)
        {
            space = YES;
            continue;
        }
        if (space)
            [flat appendString:@" "];
        space = NO;
        [flat appendFormat:@"%C", c];
    }
    if (space)
        [flat appendString:@" "];

    // A run of pure whitespace at the head of a block is the page's layout,
    // not the writer's.
    NSString *result = flat;
    if (self.pendingBreaks || !self.out.length)
    {
        while ([result hasPrefix:@" "])
            result = [result substringFromIndex:1];
    }
    if (!result.length)
        return;

    self.atItemStart = NO;
    [self write:[self escaped:result]];
}


#pragma mark - Blocks

- (void)openList:(BOOL)ordered
{
    // A list nested in another belongs to the item above it, so it starts
    // on the next line rather than after a gap.
    [self requestBreaks:self.lists.count ? 1 : 2];
    MPListLevel *level = [[MPListLevel alloc] init];
    level.ordered = ordered;
    [self.lists addObject:level];
}

- (void)closeList
{
    if (self.lists.count)
        [self.lists removeLastObject];
    [self requestBreaks:self.lists.count ? 1 : 2];
}

- (void)openItem
{
    if (!self.lists.count)
        [self openList:NO];
    // One break, not two: the items of a list belong together.
    [self requestBreaks:1];
    MPListLevel *level = self.lists.lastObject;
    level.index++;
    [self write:level.ordered
        ? [NSString stringWithFormat:@"%lu. ", (unsigned long)level.index]
        : @"- "];
    self.atItemStart = YES;
}

- (void)openCell
{
    if (!self.rows.count)
        return;
    self.cell = [NSMutableString string];
}

- (void)closeCell
{
    NSMutableString *cell = self.cell;
    self.cell = nil;
    if (!cell || !self.rows.count)
        return;

    NSString *text = [cell stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    text = [text stringByReplacingOccurrencesOfString:@"|" withString:@"\\|"];
    [self.rows.lastObject addObject:text];
}

/** Lays out the collected cells as a pipe table.
 *
 * A Markdown table has to have a header row, so the first row becomes one
 * whether the page used `th` or not: the alternative is not a table.
 */
- (void)closeTable
{
    NSArray<NSMutableArray<NSString *> *> *rows = self.rows;
    self.rows = nil;
    self.cell = nil;
    if (!rows.count)
        return;

    NSUInteger columns = 0;
    for (NSArray *row in rows)
        columns = MAX(columns, row.count);
    if (!columns)
        return;

    [self requestBreaks:2];
    for (NSUInteger r = 0; r < rows.count; r++)
    {
        NSArray<NSString *> *row = rows[r];
        NSMutableString *line = [NSMutableString stringWithString:@"|"];
        for (NSUInteger c = 0; c < columns; c++)
            [line appendFormat:@" %@ |", c < row.count ? row[c] : @""];
        [self write:line];
        [self requestBreaks:1];

        if (r == 0)
        {
            NSMutableString *rule = [NSMutableString stringWithString:@"|"];
            for (NSUInteger c = 0; c < columns; c++)
                [rule appendString:@" --- |"];
            [self write:rule];
            [self requestBreaks:1];
        }
    }
    [self requestBreaks:2];
}

/// Wraps what `<pre>` collected in a fence, now that the language is known.
- (void)closePreformatted
{
    NSMutableString *body = self.preformatted;
    self.preformatted = nil;
    if (!body)
        return;

    NSString *code = [body stringByTrimmingCharactersInSet:
                      [NSCharacterSet newlineCharacterSet]];
    if (!code.length)
    {
        self.preLanguage = nil;
        return;
    }

    [self requestBreaks:2];
    [self write:[NSString stringWithFormat:@"```%@", self.preLanguage ?: @""]];
    for (NSString *line in [code componentsSeparatedByString:@"\n"])
    {
        [self requestBreaks:1];
        // Written even when empty, so a blank line inside the code survives
        // the break that would otherwise be folded away.
        [self write:line.length ? line : @" "];
    }
    [self requestBreaks:1];
    [self write:@"```"];
    [self requestBreaks:2];
    self.preLanguage = nil;
}


#pragma mark - Tags

- (BOOL)isHeading:(NSString *)name
{
    return name.length == 2 && [name hasPrefix:@"h"]
        && [name characterAtIndex:1] >= '1'
        && [name characterAtIndex:1] <= '6';
}

- (BOOL)isIgnored:(NSString *)name
{
    return [name isEqualToString:@"script"] || [name isEqualToString:@"style"]
        || [name isEqualToString:@"head"]
        || [name isEqualToString:@"noscript"];
}

/// Tags whose contents are a block of their own, however they are styled.
- (BOOL)isParagraphish:(NSString *)name
{
    static NSSet *names = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = [NSSet setWithArray:@[@"p", @"div", @"section", @"article",
                                      @"header", @"footer", @"main",
                                      @"aside", @"nav", @"figure",
                                      @"figcaption", @"caption", @"dl",
                                      @"dt", @"dd", @"address", @"details",
                                      @"summary", @"form", @"fieldset"]];
    });
    return [names containsObject:name];
}

- (void)handleOpenTag:(NSString *)name
           attributes:(NSDictionary<NSString *, NSString *> *)attributes
          selfClosing:(BOOL)selfClosing
{
    if ([self isIgnored:name])
    {
        if (!selfClosing)
            self.skipDepth++;
        return;
    }
    if (self.skipDepth)
        return;

    if ([name isEqualToString:@"br"])
    {
        if (self.preformatted)
            [self.preformatted appendString:@"\n"];
        else
        {
            // Two spaces: the only line break Markdown keeps inside a
            // paragraph.
            [self write:@"  "];
            [self requestBreaks:1];
        }
        return;
    }
    if ([name isEqualToString:@"hr"])
    {
        [self requestBreaks:2];
        [self write:@"---"];
        [self requestBreaks:2];
        return;
    }
    if ([name isEqualToString:@"img"])
    {
        NSString *src = attributes[@"src"] ?: @"";
        if (src.length)
            [self write:[NSString stringWithFormat:@"![%@](%@)",
                         attributes[@"alt"] ?: @"", src]];
        return;
    }

    if ([self isHeading:name])
    {
        [self requestBreaks:2];
        NSUInteger level = [name characterAtIndex:1] - '0';
        NSMutableString *hashes = [NSMutableString string];
        for (NSUInteger i = 0; i < level; i++)
            [hashes appendString:@"#"];
        [self write:[hashes stringByAppendingString:@" "]];
        return;
    }
    if ([self isParagraphish:name])
        return [self requestBlockBreak];

    if ([name isEqualToString:@"blockquote"])
    {
        [self requestBreaks:2];
        self.quoteDepth++;
        return;
    }
    if ([name isEqualToString:@"ul"])
        return [self openList:NO];
    if ([name isEqualToString:@"ol"])
        return [self openList:YES];
    if ([name isEqualToString:@"li"])
        return [self openItem];

    if ([name isEqualToString:@"pre"])
    {
        self.preformatted = [NSMutableString string];
        return;
    }
    if ([name isEqualToString:@"code"] || [name isEqualToString:@"tt"]
            || [name isEqualToString:@"kbd"] || [name isEqualToString:@"samp"])
    {
        if (self.preformatted)
        {
            self.preLanguage = [self languageFromClass:attributes[@"class"]];
            return;
        }
        return [self openInline:@"`" closing:@"`"];
    }

    // `**uno***due*` is three asterisks and a guess. When one emphasis ends
    // exactly where the next begins, the second one switches character.
    BOOL adjacent = !self.pendingBreaks && [[self sink] hasSuffix:@"*"];

    // Google Docs wraps a whole document in `<b style="font-weight:normal">`,
    // and taking that at its word makes the entire paste bold.
    NSString *style = (attributes[@"style"] ?: @"").lowercaseString;
    if ([name isEqualToString:@"strong"] || [name isEqualToString:@"b"])
    {
        if ([style rangeOfString:@"font-weight:normal"].location != NSNotFound
                || [style rangeOfString:@"font-weight: normal"].location != NSNotFound
                || [style rangeOfString:@"font-weight:400"].location != NSNotFound
                || [style rangeOfString:@"font-weight: 400"].location != NSNotFound)
            return [self openInline:@"" closing:@""];
        NSString *mark = adjacent ? @"__" : @"**";
        return [self openInline:mark closing:mark];
    }
    if ([name isEqualToString:@"em"] || [name isEqualToString:@"i"])
    {
        if ([style rangeOfString:@"font-style:normal"].location != NSNotFound
                || [style rangeOfString:@"font-style: normal"].location != NSNotFound)
            return [self openInline:@"" closing:@""];
        NSString *mark = adjacent ? @"_" : @"*";
        return [self openInline:mark closing:mark];
    }
    if ([name isEqualToString:@"del"] || [name isEqualToString:@"s"]
            || [name isEqualToString:@"strike"])
        return [self openInline:@"~~" closing:@"~~"];

    if ([name isEqualToString:@"a"])
    {
        NSString *href = attributes[@"href"] ?: @"";
        // A link with nowhere to go contributes its text and no brackets.
        if (!href.length || [href hasPrefix:@"javascript:"]
                || [href hasPrefix:@"#"])
            return [self openInline:@"" closing:@""];
        return [self openInline:@"["
                        closing:[NSString stringWithFormat:@"](%@)", href]];
    }

    if ([name isEqualToString:@"table"])
    {
        self.rows = [NSMutableArray array];
        return;
    }
    if ([name isEqualToString:@"tr"])
    {
        if (self.rows)
            [self.rows addObject:[NSMutableArray array]];
        return;
    }
    if ([name isEqualToString:@"td"] || [name isEqualToString:@"th"])
        return [self openCell];
}

- (void)handleCloseTag:(NSString *)name
{
    if ([self isIgnored:name])
    {
        if (self.skipDepth)
            self.skipDepth--;
        return;
    }
    if (self.skipDepth)
        return;

    if ([name isEqualToString:@"strong"] || [name isEqualToString:@"b"]
            || [name isEqualToString:@"em"] || [name isEqualToString:@"i"]
            || [name isEqualToString:@"del"] || [name isEqualToString:@"s"]
            || [name isEqualToString:@"strike"]
            || [name isEqualToString:@"a"])
        return [self closeInline];

    if ([name isEqualToString:@"code"] || [name isEqualToString:@"tt"]
            || [name isEqualToString:@"kbd"] || [name isEqualToString:@"samp"])
    {
        if (!self.preformatted)
            [self closeInline];
        return;
    }
    if ([name isEqualToString:@"pre"])
        return [self closePreformatted];

    if ([self isHeading:name] || [self isParagraphish:name])
        return [self requestBlockBreak];

    if ([name isEqualToString:@"blockquote"])
    {
        if (self.quoteDepth)
            self.quoteDepth--;
        return [self requestBreaks:2];
    }
    if ([name isEqualToString:@"ul"] || [name isEqualToString:@"ol"])
        return [self closeList];

    if ([name isEqualToString:@"td"] || [name isEqualToString:@"th"])
        return [self closeCell];
    if ([name isEqualToString:@"table"])
        return [self closeTable];
}

/// `language-swift`, `lang-swift`, or just `swift`, as pages write it.
- (NSString *)languageFromClass:(NSString *)value
{
    if (!value.length)
        return nil;
    for (NSString *name in [value componentsSeparatedByString:@" "])
    {
        if ([name hasPrefix:@"language-"])
            return [name substringFromIndex:9];
        if ([name hasPrefix:@"lang-"])
            return [name substringFromIndex:5];
    }
    return nil;
}


#pragma mark - Parsing

/// The named entities worth knowing; the numeric ones are decoded directly.
+ (NSDictionary<NSString *, NSString *> *)entities
{
    static NSDictionary *entities = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        entities = @{@"amp": @"&", @"lt": @"<", @"gt": @">", @"quot": @"\"",
                     @"apos": @"'", @"nbsp": @" ", @"mdash": @"—",
                     @"ndash": @"–", @"hellip": @"…", @"rsquo": @"’",
                     @"lsquo": @"‘", @"ldquo": @"“", @"rdquo": @"”",
                     @"copy": @"©", @"reg": @"®", @"trade": @"™",
                     @"middot": @"·", @"bull": @"•", @"laquo": @"«",
                     @"raquo": @"»", @"times": @"×", @"deg": @"°",
                     @"euro": @"€", @"pound": @"£", @"sect": @"§"};
    });
    return entities;
}

- (NSString *)decoded:(NSString *)text
{
    if ([text rangeOfString:@"&"].location == NSNotFound)
        return text;

    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    NSUInteger i = 0;
    while (i < text.length)
    {
        unichar c = [text characterAtIndex:i];
        if (c != '&')
        {
            [out appendFormat:@"%C", c];
            i++;
            continue;
        }

        NSRange window = NSMakeRange(i, MIN((NSUInteger)12, text.length - i));
        NSRange end = [text rangeOfString:@";" options:0 range:window];
        if (end.location == NSNotFound || end.location == i + 1)
        {
            [out appendString:@"&"];
            i++;
            continue;
        }

        NSString *name = [text substringWithRange:
                          NSMakeRange(i + 1, end.location - i - 1)];
        NSString *value = [[self class] entities][name.lowercaseString];
        if (value)
        {
            [out appendString:value];
        }
        else if ([name hasPrefix:@"#"])
        {
            NSString *digits = [name substringFromIndex:1];
            BOOL hex = [digits.lowercaseString hasPrefix:@"x"];
            unsigned int hexCode = 0;
            unsigned long long decCode = 0;
            NSScanner *scanner = [NSScanner scannerWithString:
                                  hex ? [digits substringFromIndex:1] : digits];
            BOOL ok = hex ? [scanner scanHexInt:&hexCode]
                          : [scanner scanUnsignedLongLong:&decCode];
            unsigned long long code = hex ? hexCode : decCode;
            NSString *character = nil;
            if (ok && code && code <= 0x10FFFF)
            {
                uint32_t point = (uint32_t)code;
                character = [[NSString alloc]
                    initWithBytes:&point length:sizeof(point)
                         encoding:NSUTF32LittleEndianStringEncoding];
            }
            [out appendString:character ?: @""];
        }
        else
        {
            // Not an entity after all: leave it as the page wrote it.
            [out appendString:[text substringWithRange:
                NSMakeRange(i, end.location - i + 1)]];
        }
        i = end.location + 1;
    }
    return out;
}

/// Name and attributes of one tag, from just inside the angle brackets.
- (NSString *)parseTag:(NSString *)body
            attributes:(NSMutableDictionary<NSString *, NSString *> *)attributes
           selfClosing:(BOOL *)selfClosing
{
    static NSCharacterSet *nameChars = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        nameChars = [NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:-_"];
    });

    NSScanner *scanner = [NSScanner scannerWithString:body];
    scanner.charactersToBeSkipped = nil;
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    [scanner scanCharactersFromSet:space intoString:NULL];

    NSString *name = nil;
    if (![scanner scanCharactersFromSet:nameChars intoString:&name])
        return nil;

    while (!scanner.isAtEnd)
    {
        [scanner scanCharactersFromSet:space intoString:NULL];
        NSString *key = nil;
        if (![scanner scanCharactersFromSet:nameChars intoString:&key])
        {
            if (scanner.isAtEnd)
                break;
            scanner.scanLocation = scanner.scanLocation + 1;
            continue;
        }
        [scanner scanCharactersFromSet:space intoString:NULL];
        if (![scanner scanString:@"=" intoString:NULL])
        {
            attributes[key.lowercaseString] = @"";
            continue;
        }
        [scanner scanCharactersFromSet:space intoString:NULL];

        NSString *value = nil;
        if ([scanner scanString:@"\"" intoString:NULL])
        {
            [scanner scanUpToString:@"\"" intoString:&value];
            [scanner scanString:@"\"" intoString:NULL];
        }
        else if ([scanner scanString:@"'" intoString:NULL])
        {
            [scanner scanUpToString:@"'" intoString:&value];
            [scanner scanString:@"'" intoString:NULL];
        }
        else
        {
            [scanner scanUpToCharactersFromSet:space intoString:&value];
        }
        attributes[key.lowercaseString] = [self decoded:value ?: @""];
    }

    if (selfClosing)
        *selfClosing = [[body stringByTrimmingCharactersInSet:space]
                        hasSuffix:@"/"];
    return name.lowercaseString;
}

- (NSString *)convert:(NSString *)html
{
    NSUInteger i = 0;
    NSUInteger length = html.length;

    while (i < length)
    {
        NSRange open = [html rangeOfString:@"<" options:0
                                     range:NSMakeRange(i, length - i)];
        if (open.location == NSNotFound)
        {
            [self writeText:[self decoded:[html substringFromIndex:i]]];
            break;
        }

        if (open.location > i)
        {
            NSString *text = [html substringWithRange:
                              NSMakeRange(i, open.location - i)];
            [self writeText:[self decoded:text]];
        }

        // Comments first: their contents can hold anything, including what
        // looks like a tag.
        NSUInteger left = length - open.location;
        if (left >= 4 && [[html substringWithRange:NSMakeRange(open.location, 4)]
                isEqualToString:@"<!--"])
        {
            NSRange end = [html rangeOfString:@"-->" options:0
                                        range:NSMakeRange(open.location,
                                                          left)];
            i = end.location == NSNotFound ? length : NSMaxRange(end);
            continue;
        }

        NSRange close = [html rangeOfString:@">" options:0
                                      range:NSMakeRange(open.location, left)];
        if (close.location == NSNotFound)
        {
            [self writeText:[self decoded:
                [html substringFromIndex:open.location]]];
            break;
        }

        NSString *body = [html substringWithRange:
                          NSMakeRange(open.location + 1,
                                      close.location - open.location - 1)];
        i = NSMaxRange(close);

        if ([body hasPrefix:@"!"] || [body hasPrefix:@"?"])
            continue;

        NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
        if ([body hasPrefix:@"/"])
        {
            NSString *name = [self parseTag:[body substringFromIndex:1]
                                 attributes:attributes selfClosing:NULL];
            if (name)
                [self handleCloseTag:name];
            continue;
        }

        BOOL selfClosing = NO;
        NSString *name = [self parseTag:body attributes:attributes
                            selfClosing:&selfClosing];
        if (!name)
            continue;
        [self handleOpenTag:name attributes:attributes
                selfClosing:selfClosing];
        if (selfClosing)
            [self handleCloseTag:name];
    }

    while (self.inlines.count)
        [self closeInline];
    if (self.preformatted)
        [self closePreformatted];

    return [self tidied:self.out];
}

/// Trailing spaces, runs of blank lines, and the edges of the fragment.
- (NSString *)tidied:(NSString *)text
{
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    NSUInteger blanks = 0;

    for (NSString *line in [text componentsSeparatedByString:@"\n"])
    {
        // A line ending in exactly two spaces is a Markdown line break and
        // keeps them; anything else loses its trailing whitespace.
        NSString *trimmed = line;
        if (![trimmed hasSuffix:@"  "])
        {
            while ([trimmed hasSuffix:@" "] || [trimmed hasSuffix:@"\t"])
                trimmed = [trimmed substringToIndex:trimmed.length - 1];
        }

        BOOL blank = ![[trimmed stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]] length];
        if (blank)
        {
            blanks++;
            if (blanks > 1 || !kept.count)
                continue;
            [kept addObject:trimmed];
            continue;
        }
        blanks = 0;
        [kept addObject:trimmed];
    }
    while (kept.count && ![kept.lastObject length])
        [kept removeLastObject];

    return [kept componentsJoinedByString:@"\n"];
}


#pragma mark - Styled text

+ (NSString *)markdownFromAttributedString:(NSAttributedString *)text
{
    if (!text.length)
        return @"";

    NSMutableString *out = [NSMutableString string];
    NSFontManager *fonts = [NSFontManager sharedFontManager];

    [text enumerateAttributesInRange:NSMakeRange(0, text.length) options:0
        usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attributes,
                     NSRange range, BOOL *stop) {
        NSString *run = [text.string substringWithRange:range];
        if (!run.length)
            return;

        NSFont *font = attributes[NSFontAttributeName];
        NSFontTraitMask traits = font ? [fonts traitsOfFont:font] : 0;
        BOOL bold = (traits & NSBoldFontMask) != 0;
        BOOL italic = (traits & NSItalicFontMask) != 0;
        BOOL mono = (font.fontDescriptor.symbolicTraits
                     & NSFontDescriptorTraitMonoSpace) != 0;

        id link = attributes[NSLinkAttributeName];
        NSString *href = nil;
        if ([link isKindOfClass:[NSURL class]])
            href = [(NSURL *)link absoluteString];
        else if ([link isKindOfClass:[NSString class]])
            href = link;

        // The markers go inside the run's whitespace, not outside it:
        // `** bold **` is four asterisks and a word, not emphasis.
        NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        NSString *core = [run stringByTrimmingCharactersInSet:space];
        if (!core.length || (!bold && !italic && !mono && !href.length))
        {
            [out appendString:run];
            return;
        }

        NSRange coreRange = [run rangeOfString:core];
        NSMutableString *marked = [NSMutableString stringWithString:core];
        if (mono)
        {
            [marked insertString:@"`" atIndex:0];
            [marked appendString:@"`"];
        }
        if (bold)
        {
            [marked insertString:@"**" atIndex:0];
            [marked appendString:@"**"];
        }
        if (italic)
        {
            [marked insertString:@"*" atIndex:0];
            [marked appendString:@"*"];
        }
        if (href.length)
        {
            [marked insertString:@"[" atIndex:0];
            [marked appendFormat:@"](%@)", href];
        }

        [out appendFormat:@"%@%@%@",
            [run substringToIndex:coreRange.location], marked,
            [run substringFromIndex:NSMaxRange(coreRange)]];
    }];

    // The separators a text view stores, in the forms a file uses. Ordered,
    // because turning a CR into a newline after a CRLF would make two.
    NSArray<NSArray<NSString *> *> *breaks = @[
        @[@"\r\n", @"\n"], @[@"\r", @"\n"],
        @[@"\u2028", @"\n"], @[@"\u2029", @"\n\n"]];
    for (NSArray<NSString *> *pair in breaks)
    {
        [out replaceOccurrencesOfString:pair[0] withString:pair[1]
                                options:0 range:NSMakeRange(0, out.length)];
    }
    return out;
}

@end
