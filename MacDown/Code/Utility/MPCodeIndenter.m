//
//  MPCodeIndenter.m
//  MacDown
//

#import "MPCodeIndenter.h"
#import "MPCodeLanguages.h"


@interface MPCodeIndentRule ()
@property (nonatomic) MPCodeIndentFamily family;
@property (copy, nonatomic) NSString *unit;
@property (nonatomic) NSUInteger width;
@property (copy, nonatomic) NSArray<NSString *> *lineComments;
@property (nonatomic) BOOL blockComments;
@property (copy, nonatomic) NSString *quotes;
@property (nonatomic) BOOL rawStrings;
@property (copy, nonatomic) NSArray<NSString *> *multilineStrings;
@end


@implementation MPCodeIndentRule
@end


/// A step of `width` spaces, or a tab when `width` is zero.
NS_INLINE NSString *MPIndentUnit(NSUInteger width)
{
    if (!width)
        return @"\t";
    return [@"" stringByPaddingToLength:width withString:@" "
                        startingAtIndex:0];
}

NS_INLINE MPCodeIndentRule *MPRule(MPCodeIndentFamily family,
                                   NSUInteger width,
                                   NSArray *lineComments,
                                   BOOL blockComments,
                                   NSString *quotes,
                                   BOOL rawStrings)
{
    MPCodeIndentRule *rule = [[MPCodeIndentRule alloc] init];
    rule.family = family;
    // A tab is written as a tab and read as eight columns, which is what a
    // terminal and a diff will both show.
    rule.width = width ?: 8;
    rule.unit = MPIndentUnit(width);
    rule.lineComments = lineComments ?: @[];
    rule.blockComments = blockComments;
    rule.quotes = quotes ?: @"";
    rule.rawStrings = rawStrings;
    return rule;
}


/// Python, with the triple quotes that hold text over several lines.
NS_INLINE MPCodeIndentRule *MPPythonRule(void)
{
    MPCodeIndentRule *rule = MPRule(MPCodeIndentFamilyOffside, 4, @[@"#"],
                                    NO, @"\"'", NO);
    rule.multilineStrings = @[@"\"\"\"", @"'''"];
    return rule;
}


MPCodeIndentRule *MPCodeIndentRuleForLanguage(NSString *language)
{
    static NSDictionary *rules = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSArray *slashes = @[@"//"];
        NSArray *hashes = @[@"#"];

        // Four spaces, braces, C's comments: the family that grew out of C.
        MPCodeIndentRule *cLike =
            MPRule(MPCodeIndentFamilyBrackets, 4, slashes, YES, @"\"'", NO);
        // Two spaces is the convention on the web side of the same family.
        MPCodeIndentRule *webLike =
            MPRule(MPCodeIndentFamilyBrackets, 2, slashes, YES, @"\"'", YES);
        MPCodeIndentRule *styleLike =
            MPRule(MPCodeIndentFamilyBrackets, 2, slashes, YES, @"\"'", NO);
        MPCodeIndentRule *tags =
            MPRule(MPCodeIndentFamilyTags, 2, nil, NO, @"\"'", NO);

        rules = @{
            // Brackets say the depth, so these are laid out from scratch.
            @"c": cLike, @"cpp": cLike, @"csharp": cLike, @"java": cLike,
            @"objectivec": cLike, @"rust": cLike, @"swift": cLike,
            @"kotlin": cLike, @"dart": cLike, @"scala": cLike,
            @"php": MPRule(MPCodeIndentFamilyBrackets, 4, @[@"//", @"#"],
                           YES, @"\"'", NO),
            @"javascript": webLike, @"typescript": webLike,
            @"json": MPRule(MPCodeIndentFamilyBrackets, 2, nil, NO, @"\"",
                            NO),
            @"css": styleLike, @"scss": styleLike, @"less": styleLike,
            @"go": MPRule(MPCodeIndentFamilyBrackets, 0, slashes, YES,
                          @"\"'", YES),

            // Tags say the depth.
            @"markup": tags,

            // The indentation *is* the depth: only its unit can change.
            @"python": MPPythonRule(),
            @"ruby": MPRule(MPCodeIndentFamilyOffside, 2, hashes, NO,
                            @"\"'", NO),
            @"yaml": MPRule(MPCodeIndentFamilyOffside, 2, hashes, NO,
                            @"\"'", NO),
            @"bash": MPRule(MPCodeIndentFamilyOffside, 2, hashes, NO,
                            @"\"'", NO),
            @"coffeescript": MPRule(MPCodeIndentFamilyOffside, 2, hashes, NO,
                                    @"\"'", NO),
            // A recipe line has to begin with a tab. Nothing else will do,
            // which makes this the one language where getting the unit
            // wrong stops the file from working at all.
            @"makefile": MPRule(MPCodeIndentFamilyOffside, 0, hashes, NO,
                                @"\"'", NO),
        };
    });

    NSString *name = MPCanonicalCodeLanguage(language);
    return name.length ? rules[name] : nil;
}


#pragma mark - Reading a line

/// Carried from line to line, since a comment or a string may span them.
typedef struct {
    BOOL inBlockComment;
    BOOL inRawString;
} MPScanState;

/** Counts the brackets in one line, ignoring what is quoted or commented.
 *
 * `leadingClosers` comes back as the number of brackets the line closes
 * before it opens anything: those belong to the line's own indentation,
 * which is why `}` sits with the `{` and not with the body.
 */
static NSInteger MPBracketBalanceOfLine(NSString *line,
                                        MPCodeIndentRule *rule,
                                        MPScanState *state,
                                        NSUInteger *leadingClosers)
{
    NSInteger balance = 0;
    NSUInteger closers = 0;
    // Still at the head of the line, where a closing bracket belongs to
    // the line's own indentation rather than to what follows it.
    BOOL atStart = YES;

    NSUInteger i = 0;
    while (i < line.length)
    {
        unichar c = [line characterAtIndex:i];

        if (state->inBlockComment)
        {
            if (c == '*' && i + 1 < line.length
                    && [line characterAtIndex:i + 1] == '/')
            {
                state->inBlockComment = NO;
                i += 2;
                continue;
            }
            i++;
            continue;
        }

        if (state->inRawString)
        {
            if (c == '`')
                state->inRawString = NO;
            i++;
            continue;
        }

        BOOL commented = NO;
        for (NSString *marker in rule.lineComments)
        {
            if (i + marker.length <= line.length
                    && [[line substringWithRange:
                            NSMakeRange(i, marker.length)]
                        isEqualToString:marker])
            {
                commented = YES;
                break;
            }
        }
        if (commented)
            break;

        if (rule.blockComments && c == '/' && i + 1 < line.length
                && [line characterAtIndex:i + 1] == '*')
        {
            state->inBlockComment = YES;
            i += 2;
            continue;
        }

        if (rule.rawStrings && c == '`')
        {
            state->inRawString = YES;
            i++;
            continue;
        }

        if ([rule.quotes rangeOfString:
                [NSString stringWithCharacters:&c length:1]].location
                    != NSNotFound)
        {
            // To the matching quote, or to the end of the line: an
            // unterminated quote is a broken line, and guessing past it
            // would count brackets that are really text.
            unichar quote = c;
            i++;
            while (i < line.length)
            {
                unichar d = [line characterAtIndex:i];
                if (d == '\\')
                {
                    i += 2;
                    continue;
                }
                i++;
                if (d == quote)
                    break;
            }
            continue;
        }

        if (c == '{' || c == '[' || c == '(')
        {
            balance++;
            atStart = NO;
        }
        else if (c == '}' || c == ']' || c == ')')
        {
            balance--;
            if (atStart)
                closers++;
        }
        else if (c != ' ' && c != '\t')
        {
            atStart = NO;
        }
        i++;
    }

    if (leadingClosers)
        *leadingClosers = closers;
    return balance;
}

/// The void elements, which open nothing and so close nothing.
static NSSet *MPVoidTags(void)
{
    static NSSet *tags = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        tags = [NSSet setWithArray:@[@"area", @"base", @"br", @"col",
            @"embed", @"hr", @"img", @"input", @"link", @"meta", @"param",
            @"source", @"track", @"wbr"]];
    });
    return tags;
}

/// The same count for markup, where tags do the work brackets do elsewhere.
static NSInteger MPTagBalanceOfLine(NSString *line, MPScanState *state,
                                    NSUInteger *leadingClosers)
{
    NSInteger balance = 0;
    NSUInteger closers = 0;
    BOOL atStart = YES;

    NSUInteger i = 0;
    while (i < line.length)
    {
        if (state->inBlockComment)
        {
            NSRange end = [line rangeOfString:@"-->"
                                      options:0
                                        range:NSMakeRange(i,
                                                  line.length - i)];
            if (end.location == NSNotFound)
                break;
            state->inBlockComment = NO;
            i = NSMaxRange(end);
            continue;
        }

        if ([line characterAtIndex:i] != '<')
        {
            i++;
            continue;
        }

        NSString *rest = [line substringFromIndex:i];
        if ([rest hasPrefix:@"<!--"])
        {
            state->inBlockComment = YES;
            i += 4;
            continue;
        }
        // A declaration or an instruction is neither open nor shut.
        if ([rest hasPrefix:@"<!"] || [rest hasPrefix:@"<?"])
        {
            i++;
            continue;
        }

        NSRange close = [rest rangeOfString:@">"];
        if (close.location == NSNotFound)
            break;
        NSString *tag = [rest substringWithRange:
            NSMakeRange(1, close.location - 1)];
        i += NSMaxRange(close);

        BOOL closing = [tag hasPrefix:@"/"];
        BOOL selfClosing = [tag hasSuffix:@"/"];
        if (closing)
            tag = [tag substringFromIndex:1];

        NSRange space = [tag rangeOfCharacterFromSet:
            [NSCharacterSet whitespaceCharacterSet]];
        NSString *name = space.location == NSNotFound
            ? tag : [tag substringToIndex:space.location];
        name = name.lowercaseString;
        if (!name.length || [MPVoidTags() containsObject:name]
                || selfClosing)
            continue;

        if (closing)
        {
            balance--;
            if (atStart)
                closers++;
        }
        else
        {
            balance++;
        }
        atStart = NO;
    }

    if (leadingClosers)
        *leadingClosers = closers;
    return balance;
}


#pragma mark - Laying out a block

/// The lines of `body`, and their content without leading whitespace.
NS_INLINE NSArray *MPLinesOf(NSString *body)
{
    return [body componentsSeparatedByString:@"\n"];
}

NS_INLINE NSString *MPWithoutLeadingSpace(NSString *line)
{
    NSRange first = [line rangeOfCharacterFromSet:
        [[NSCharacterSet whitespaceCharacterSet] invertedSet]];
    if (first.location == NSNotFound)
        return @"";
    return [line substringFromIndex:first.location];
}

/// Depth from structure, then written out with the language's own step.
/** One line moves the depth by one step at most, in either direction.
 *
 * Counting every bracket looks right until JavaScript: `f(function () {`
 * leaves two open and would push its body two steps in, where everybody
 * writes it one. The cost of the clamp is the opposite case — two blocks
 * opened on the same line — which is rarer by far, and under-indented
 * rather than misleading.
 */
NS_INLINE NSInteger MPOneStepAtMost(NSInteger balance)
{
    return MAX(-1, MIN(1, balance));
}

/// The leading whitespace of a line, as it was written.
NS_INLINE NSString *MPLeadingSpaceOf(NSString *line, NSString *content)
{
    return [line substringToIndex:line.length - content.length];
}

static NSString *MPCodeByCounting(NSString *body, MPCodeIndentRule *rule)
{
    MPScanState state = {NO, NO};
    NSInteger depth = 0;
    NSMutableArray *out = [NSMutableArray array];

    // A comment that runs over lines moves as one piece: the line that
    // opens it is indented like code, and the rest keep the offset they had
    // from it. That is what holds a column of asterisks together, and it
    // holds anything else in there too — a diagram, a sample — without
    // knowing what it is.
    NSString *commentIndent = @"";
    NSUInteger commentWasIndented = 0;

    for (NSString *line in MPLinesOf(body))
    {
        // Inside a string that runs over lines the whitespace is part of
        // what the string says, so the line stays exactly as written and
        // is only read for where it ends.
        if (state.inRawString)
        {
            NSInteger carried =
                MPBracketBalanceOfLine(line, rule, &state, NULL);
            [out addObject:line];
            depth = MAX(0, depth + MPOneStepAtMost(carried));
            continue;
        }

        if (state.inBlockComment)
        {
            NSString *content = MPWithoutLeadingSpace(line);
            NSInteger carried = (rule.family == MPCodeIndentFamilyTags)
                ? MPTagBalanceOfLine(content, &state, NULL)
                : MPBracketBalanceOfLine(content, rule, &state, NULL);

            if (content.length)
            {
                NSInteger moved = (NSInteger)MPLeadingSpaceOf(line,
                    content).length - (NSInteger)commentWasIndented;
                NSMutableString *written =
                    [NSMutableString stringWithString:commentIndent];
                for (NSInteger i = 0; i < moved; i++)
                    [written appendString:@" "];
                // Further left than the line that opened it: rare, and the
                // most that can be honoured is the opening line's own
                // indentation.
                for (NSInteger i = 0; i > moved && written.length; i--)
                    [written deleteCharactersInRange:
                        NSMakeRange(written.length - 1, 1)];
                [written appendString:content];
                [out addObject:written];
            }
            else
            {
                [out addObject:@""];
            }

            depth = MAX(0, depth + MPOneStepAtMost(carried));
            continue;
        }

        NSString *content = MPWithoutLeadingSpace(line);
        if (!content.length)
        {
            // A blank line stays blank rather than carrying spaces.
            [out addObject:@""];
            continue;
        }

        NSUInteger closers = 0;
        NSInteger balance = (rule.family == MPCodeIndentFamilyTags)
            ? MPTagBalanceOfLine(content, &state, &closers)
            : MPBracketBalanceOfLine(content, rule, &state, &closers);

        NSInteger here = depth - (closers ? 1 : 0);
        if (here < 0)
            here = 0;

        NSMutableString *indent = [NSMutableString string];
        for (NSInteger i = 0; i < here; i++)
            [indent appendString:rule.unit];
        [out addObject:[indent stringByAppendingString:content]];

        // This line opened a comment that the next one continues, so the
        // rest of it will be measured from where this one ended up.
        if (state.inBlockComment)
        {
            commentIndent = [indent copy];
            commentWasIndented = MPLeadingSpaceOf(line, content).length;
        }

        depth = depth + MPOneStepAtMost(balance);
        if (depth < 0)
            depth = 0;
    }

    return [out componentsJoinedByString:@"\n"];
}

NS_INLINE NSUInteger MPGreatestCommonDivisor(NSUInteger a, NSUInteger b)
{
    while (b)
    {
        NSUInteger r = a % b;
        a = b;
        b = r;
    }
    return a;
}

/** Depth left where it is, written out in the language's own step.
 *
 * Where the indentation is the syntax, nothing can be worked out from
 * scratch: what a line means is exactly how far in it sits. So the block's
 * own step is measured — the greatest common measure of the indentations
 * it uses — and each line is written out at the same depth in the step the
 * language wants.
 *
 * A block whose measure comes out at one column has no step to speak of:
 * something in it is aligned rather than indented, arguments under an open
 * bracket most likely, and multiplying those columns would wreck it. Such a
 * block is returned untouched.
 */
/** Which lines lie inside a string that runs over several lines.
 *
 * Those lines are text: their indentation is part of what the string says,
 * so it is neither measured nor rewritten. The line that opens the string
 * is code, and counts.
 */
static NSArray<NSNumber *> *MPTextLinesOf(NSArray *lines,
                                          NSArray<NSString *> *markers)
{
    NSMutableArray *inside = [NSMutableArray array];
    BOOL open = NO;

    for (NSString *line in lines)
    {
        [inside addObject:@(open)];
        if (!markers.count)
            continue;

        // Every marker on the line turns it round, so a string opened and
        // shut on one line leaves the state as it was.
        NSUInteger i = 0;
        while (i < line.length)
        {
            NSString *hit = nil;
            for (NSString *marker in markers)
            {
                if (i + marker.length <= line.length
                        && [[line substringWithRange:
                                NSMakeRange(i, marker.length)]
                            isEqualToString:marker])
                {
                    hit = marker;
                    break;
                }
            }
            if (hit)
            {
                open = !open;
                i += hit.length;
            }
            else
            {
                i++;
            }
        }
    }
    return inside;
}

static NSString *MPCodeByMeasuring(NSString *body, MPCodeIndentRule *rule)
{
    NSArray *lines = MPLinesOf(body);
    NSArray<NSNumber *> *isText =
        MPTextLinesOf(lines, rule.multilineStrings);

    BOOL anyTabs = NO;
    BOOL anySpaces = NO;
    NSUInteger measure = 0;
    for (NSUInteger n = 0; n < lines.count; n++)
    {
        if (isText[n].boolValue)
            continue;
        NSString *line = lines[n];
        NSString *content = MPWithoutLeadingSpace(line);
        if (!content.length)
            continue;
        NSUInteger indent = line.length - content.length;
        NSString *lead = [line substringToIndex:indent];
        if ([lead rangeOfString:@"\t"].location != NSNotFound)
            anyTabs = YES;
        if ([lead rangeOfString:@" "].location != NSNotFound)
            anySpaces = YES;
        if (indent)
            measure = MPGreatestCommonDivisor(measure, indent);
    }

    // Tabs and spaces both, in the leading whitespace: which of the two
    // stands for a step is a guess, and a wrong guess moves lines.
    if (anyTabs && anySpaces)
        return body;
    if (!measure)
        return body;
    // One tab is one step; one space is not a step at all.
    if (anySpaces && measure < 2)
        return body;

    // Already laid out the way the language wants it. Worth saying
    // separately, because rewriting it would carry the contents of any
    // string that runs over several lines along with the code.
    BOOL wantsTabs = [rule.unit isEqualToString:@"\t"];
    if (wantsTabs && anyTabs)
        return body;
    if (!wantsTabs && !anyTabs && measure == rule.width)
        return body;

    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger n = 0; n < lines.count; n++)
    {
        NSString *line = lines[n];
        if (isText[n].boolValue)
        {
            [out addObject:line];
            continue;
        }
        NSString *content = MPWithoutLeadingSpace(line);
        if (!content.length)
        {
            [out addObject:@""];
            continue;
        }
        NSUInteger indent = line.length - content.length;
        NSUInteger steps = indent / measure;

        NSMutableString *written = [NSMutableString string];
        for (NSUInteger i = 0; i < steps; i++)
            [written appendString:rule.unit];
        [written appendString:content];
        [out addObject:written];
    }
    return [out componentsJoinedByString:@"\n"];
}


NSString *MPReindentedCode(NSString *body, NSString *language)
{
    MPCodeIndentRule *rule = MPCodeIndentRuleForLanguage(language);
    if (!rule || !body)
        return body;

    switch (rule.family)
    {
        case MPCodeIndentFamilyBrackets:
        case MPCodeIndentFamilyTags:
            return MPCodeByCounting(body, rule);
        case MPCodeIndentFamilyOffside:
            return MPCodeByMeasuring(body, rule);
        case MPCodeIndentFamilyNone:
            return body;
    }
}
