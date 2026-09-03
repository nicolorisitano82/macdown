//
//  MPCodeLanguages.m
//  MacDown
//

#import "MPCodeLanguages.h"
#import "MPUtilities.h"


/** The handful worth putting first.
 *
 * Not a judgement about languages, a judgement about this list: 113 names
 * in one menu means scrolling past ABAP to reach Python. Anything not here
 * is still in the list, just below the line.
 */
static NSString * const kMPCommonLanguages[] = {
    @"bash", @"c", @"cpp", @"csharp", @"css", @"diff", @"docker", @"go",
    @"html", @"ini", @"java", @"javascript", @"json", @"kotlin",
    @"makefile", @"markdown", @"objectivec", @"php", @"powershell",
    @"python", @"ruby", @"rust", @"sql", @"swift", @"typescript", @"yaml",
};


@implementation MPCodeLanguage

- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                            common:(BOOL)common
{
    self = [super init];
    if (!self)
        return nil;
    _identifier = [identifier copy];
    _title = [title copy];
    _isCommon = common;
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@ (%@)>",
            self.class, self.identifier, self.title];
}

@end


/// The title Prism gives a language, whether it is spelled out or not.
NS_INLINE NSString *MPTitleFromIndexEntry(id entry, NSString *identifier)
{
    if ([entry isKindOfClass:[NSString class]])
        return entry;
    if ([entry isKindOfClass:[NSDictionary class]])
    {
        NSString *title = entry[@"title"];
        if ([title isKindOfClass:[NSString class]] && title.length)
            return title;
    }
    return identifier;
}


NSArray<MPCodeLanguage *> *MPCodeLanguagesFromIndex(
    NSDictionary *index, NSSet<NSString *> *available, NSDictionary *aliases)
{
    NSSet *common = [NSSet setWithObjects:kMPCommonLanguages
                                   count:sizeof(kMPCommonLanguages)
                                         / sizeof(kMPCommonLanguages[0])];

    NSMutableArray *found = [NSMutableArray array];
    NSMutableSet *taken = [NSMutableSet set];

    void (^add)(NSString *, NSString *) = ^(NSString *ident, NSString *title) {
        if (!ident.length || [taken containsObject:ident])
            return;
        [taken addObject:ident];
        [found addObject:[[MPCodeLanguage alloc]
                          initWithIdentifier:ident title:title
                                      common:[common containsObject:ident]]];
    };

    for (NSString *identifier in index)
    {
        // Prism keeps its own bookkeeping under this key, next to the
        // languages, and it is not one.
        if ([identifier isEqualToString:@"meta"])
            continue;
        if (![available containsObject:identifier])
            continue;

        id entry = index[identifier];
        add(identifier, MPTitleFromIndexEntry(entry, identifier));

        // An alias is offered only when Prism has a name for it and the
        // renderer knows where to send it. That leaves the ones that are
        // read as languages in their own right — HTML, XML — and drops the
        // abbreviations, which would only repeat what is already listed.
        NSDictionary *titles = [entry isKindOfClass:[NSDictionary class]]
            ? entry[@"aliasTitles"] : nil;
        if (![titles isKindOfClass:[NSDictionary class]])
            continue;
        for (NSString *alias in titles)
        {
            if (![aliases[alias] isEqualToString:identifier])
                continue;
            add(alias, MPTitleFromIndexEntry(titles[alias], alias));
        }
    }

    return [found sortedArrayUsingComparator:^NSComparisonResult(
                MPCodeLanguage *a, MPCodeLanguage *b) {
        if (a.isCommon != b.isCommon)
            return a.isCommon ? NSOrderedAscending : NSOrderedDescending;
        return [a.title localizedStandardCompare:b.title];
    }];
}


NSArray<MPCodeLanguage *> *MPAvailableCodeLanguages(void)
{
    static NSArray *languages = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSBundle *bundle = [NSBundle mainBundle];

        NSURL *url = [bundle URLForResource:@"components" withExtension:@"js"
                               subdirectory:@"Prism"];
        NSString *code = [NSString stringWithContentsOfURL:url
                                                 encoding:NSUTF8StringEncoding
                                                    error:NULL];
        NSDictionary *index =
            MPGetObjectFromJavaScript(code, @"components")[@"languages"];

        // What is on disk, rather than what the catalogue claims: the
        // components are chosen at packaging time and the catalogue is
        // copied whole.
        NSMutableSet *available = [NSMutableSet set];
        NSArray *files = [bundle URLsForResourcesWithExtension:@"js"
                                                 subdirectory:@"Prism/components"];
        for (NSURL *file in files)
        {
            NSString *name = file.lastPathComponent;
            if (![name hasPrefix:@"prism-"] || ![name hasSuffix:@".min.js"])
                continue;
            NSUInteger start = @"prism-".length;
            NSRange range = NSMakeRange(start,
                name.length - start - @".min.js".length);
            [available addObject:[name substringWithRange:range]];
        }

        url = [bundle URLForResource:@"syntax_highlighting"
                       withExtension:@"json"];
        NSData *json = url ? [NSData dataWithContentsOfURL:url] : nil;
        NSDictionary *info = json
            ? [NSJSONSerialization JSONObjectWithData:json options:0
                                                error:NULL]
            : nil;

        languages = MPCodeLanguagesFromIndex(index, available,
                                             info[@"aliases"] ?: @{});
    });
    return languages;
}


NSString *MPFencedCodeBlock(NSString *language, NSString *body)
{
    body = body ?: @"";

    // Long enough that nothing inside can close it. A block quoting
    // Markdown holds fences of its own, and three backticks would end at
    // the first of them.
    NSUInteger longest = 0;
    NSUInteger run = 0;
    for (NSUInteger i = 0; i < body.length; i++)
    {
        if ([body characterAtIndex:i] == '`')
        {
            run++;
            longest = MAX(longest, run);
        }
        else
        {
            run = 0;
        }
    }

    NSUInteger count = MAX(3, longest + 1);
    NSString *fence = [@"" stringByPaddingToLength:count withString:@"`"
                                startingAtIndex:0];

    return [NSString stringWithFormat:@"%@%@\n%@\n%@",
            fence, language ?: @"", body, fence];
}


NSString *MPBodyOfFencedCodeBlock(NSString *text)
{
    NSArray *lines = [(text ?: @"") componentsSeparatedByString:@"\n"];
    if (lines.count < 2)
        return nil;

    NSString *first = lines.firstObject;
    NSCharacterSet *backticks = [NSCharacterSet
        characterSetWithCharactersInString:@"`"];
    NSRange info = [first rangeOfCharacterFromSet:
        backticks.invertedSet];
    NSUInteger fenceLength = (info.location == NSNotFound)
        ? first.length : info.location;
    if (fenceLength < 3)
        return nil;

    // The last line that is nothing but a fence at least as long closes it.
    // Everything between the two is what was written.
    NSString *closing = [lines.lastObject
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
    NSUInteger last = lines.count - 1;
    if (closing.length == 0 && lines.count > 2)
    {
        last -= 1;
        closing = [lines[last] stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
    }
    if (closing.length < fenceLength
            || [closing rangeOfCharacterFromSet:backticks.invertedSet]
                .location != NSNotFound)
        return nil;

    NSArray *body = [lines subarrayWithRange:NSMakeRange(1, last - 1)];
    return [body componentsJoinedByString:@"\n"];
}


@implementation MPCodeFenceEdit

- (instancetype)initWithRange:(NSRange)range
                  replacement:(NSString *)replacement
                     selected:(NSRange)selected
                      removes:(BOOL)removes
{
    self = [super init];
    if (!self)
        return nil;
    _replacedRange = range;
    _replacement = [replacement copy];
    _selectedRange = selected;
    _removesFence = removes;
    return self;
}

@end


MPCodeFenceEdit *MPCodeFenceEditForText(NSString *text, NSRange selection,
                                        NSString *language)
{
    NSRange lines = [text lineRangeForRange:selection];
    NSString *chunk = [text substringWithRange:lines];

    // The newline that ends the last line belongs to the document, not to
    // the block: it goes back on afterwards.
    BOOL endsWithNewline = [chunk hasSuffix:@"\n"];
    NSString *body = endsWithNewline
        ? [chunk substringToIndex:chunk.length - 1] : chunk;

    NSString *inside = MPBodyOfFencedCodeBlock(body);
    NSString *markup = inside ?: MPFencedCodeBlock(language, body);
    if (endsWithNewline)
        markup = [markup stringByAppendingString:@"\n"];

    NSRange selected;
    if (inside)
    {
        selected = NSMakeRange(lines.location, inside.length);
    }
    else if (!body.length)
    {
        // An empty block is a place to type, so the caret goes inside it:
        // past the line that names the language, and its newline.
        NSString *opening =
            [markup componentsSeparatedByString:@"\n"].firstObject;
        selected = NSMakeRange(lines.location + opening.length + 1, 0);
    }
    else
    {
        selected = NSMakeRange(lines.location + markup.length, 0);
    }

    return [[MPCodeFenceEdit alloc] initWithRange:lines replacement:markup
                                         selected:selected
                                          removes:inside != nil];
}
