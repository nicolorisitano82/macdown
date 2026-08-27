//
//  MPProseChecker.m
//  MacDown
//

#import "MPProseChecker.h"
#import "NSColor+HTML.h"
#import "NSJSONSerialization+File.h"


@implementation MPProseIssue
@end


/// A compiled category: one regex covering its whole word list.
@interface MPProseCategory : NSObject
@property (copy, nonatomic) NSString *identifier;
@property (copy, nonatomic) NSString *name;
@property (strong, nonatomic) NSColor *color;
@property (strong, nonatomic) NSRegularExpression *regex;
@end

@implementation MPProseCategory
@end


@interface MPProseChecker ()
@property (copy, nonatomic) NSArray<MPProseCategory *> *categories;
@property (strong, nonatomic) MPProseCategory *repeated;
@property (strong, nonatomic) NSRegularExpression *skipRegex;
@end


@implementation MPProseChecker

+ (instancetype)sharedChecker
{
    static MPProseChecker *checker = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        checker = [[self alloc] init];
    });
    return checker;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    // Fenced code, indented code, inline code and link destinations. Matches
    // inside any of these are not prose and are dropped.
    _skipRegex = [[NSRegularExpression alloc] initWithPattern:
        @"```[\\s\\S]*?```"          // fenced block
        @"|~~~[\\s\\S]*?~~~"         // fenced block, tilde form
        @"|`[^`\\n]*`"               // inline code
        @"|^(?: {4}|\\t).*$"         // indented code line
        @"|\\]\\([^)]*\\)"           // link destination
        @"|<[^>\\s]+>"               // autolink or raw tag
                                                     options:
        NSRegularExpressionAnchorsMatchLines error:NULL];

    [self loadLists];
    return self;
}

- (BOOL)ready
{
    return self.categories.count > 0 || self.repeated != nil;
}

#pragma mark - Loading

/// Escapes a list entry for use inside a regex, and lets a phrase match with
/// any run of whitespace — including a line break — between its words.
NS_INLINE NSString *MPProsePattern(NSString *entry, BOOL isPhrase)
{
    NSString *escaped =
        [NSRegularExpression escapedPatternForString:entry];
    if (!isPhrase)
        return escaped;

    // The escaped form has literal spaces; widen them.
    return [escaped stringByReplacingOccurrencesOfString:@" "
                                             withString:@"\\s+"];
}

- (MPProseCategory *)categoryFromDictionary:(NSDictionary *)info
{
    NSString *identifier = info[@"id"];
    NSString *name = info[@"name"];
    NSString *colorName = info[@"color"];
    if (![identifier isKindOfClass:[NSString class]]
            || ![name isKindOfClass:[NSString class]])
        return nil;

    NSMutableArray<NSString *> *alternatives = [NSMutableArray array];
    for (NSString *word in info[@"words"])
    {
        if ([word isKindOfClass:[NSString class]] && word.length)
            [alternatives addObject:MPProsePattern(word, NO)];
    }
    for (NSString *phrase in info[@"phrases"])
    {
        if ([phrase isKindOfClass:[NSString class]] && phrase.length)
            [alternatives addObject:MPProsePattern(phrase, YES)];
    }
    if (!alternatives.count)
        return nil;

    // Longest first, so "in order to" wins over a shorter overlapping entry.
    [alternatives sortUsingComparator:^NSComparisonResult(NSString *a,
                                                          NSString *b) {
        if (a.length > b.length) return NSOrderedAscending;
        if (a.length < b.length) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSString *pattern = [NSString stringWithFormat:@"\\b(?:%@)\\b",
        [alternatives componentsJoinedByString:@"|"]];
    NSRegularExpression *regex = [[NSRegularExpression alloc]
        initWithPattern:pattern
                options:NSRegularExpressionCaseInsensitive error:NULL];
    if (!regex)
        return nil;

    MPProseCategory *category = [[MPProseCategory alloc] init];
    category.identifier = identifier;
    category.name = name;
    category.regex = regex;
    category.color = [colorName isKindOfClass:[NSString class]]
        ? [NSColor colorWithHTMLName:colorName] : nil;
    if (!category.color)
        category.color = [NSColor systemOrangeColor];
    return category;
}

- (void)loadLists
{
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"prose-issues"
                                         withExtension:@"json"
                                          subdirectory:@"Data"];
    if (!url)
        return;

    NSDictionary *root = [NSJSONSerialization JSONObjectWithFileAtURL:url
                                                             options:0
                                                               error:NULL];
    if (![root isKindOfClass:[NSDictionary class]])
        return;

    NSMutableArray<MPProseCategory *> *categories = [NSMutableArray array];
    for (NSDictionary *info in root[@"categories"])
    {
        if (![info isKindOfClass:[NSDictionary class]])
            continue;
        MPProseCategory *category = [self categoryFromDictionary:info];
        if (category)
            [categories addObject:category];
    }
    self.categories = categories;

    NSDictionary *repeatedInfo = root[@"repeated"];
    if ([repeatedInfo isKindOfClass:[NSDictionary class]])
    {
        MPProseCategory *repeated = [[MPProseCategory alloc] init];
        repeated.identifier = repeatedInfo[@"id"] ?: @"repeated";
        repeated.name = repeatedInfo[@"name"] ?: @"Repeated words";
        NSString *colorName = repeatedInfo[@"color"];
        repeated.color = [colorName isKindOfClass:[NSString class]]
            ? [NSColor colorWithHTMLName:colorName] : nil;
        if (!repeated.color)
            repeated.color = [NSColor systemRedColor];

        // A word, then the same word again with only whitespace between. The
        // backreference is why this one is not part of a word list.
        repeated.regex = [[NSRegularExpression alloc] initWithPattern:
            @"\\b(\\w+)\\s+\\1\\b"
                                                             options:
            NSRegularExpressionCaseInsensitive error:NULL];
        self.repeated = repeated.regex ? repeated : nil;
    }
}

#pragma mark - Checking

- (NSArray<MPProseIssue *> *)issuesInString:(NSString *)text
{
    if (!text.length || !self.ready)
        return @[];

    NSRange whole = NSMakeRange(0, text.length);
    NSArray<NSTextCheckingResult *> *skips =
        [self.skipRegex matchesInString:text options:0 range:whole];

    NSMutableArray<MPProseIssue *> *issues = [NSMutableArray array];
    NSMutableArray<MPProseCategory *> *all =
        [self.categories mutableCopy] ?: [NSMutableArray array];
    if (self.repeated)
        [all addObject:self.repeated];

    for (MPProseCategory *category in all)
    {
        NSArray<NSTextCheckingResult *> *matches =
            [category.regex matchesInString:text options:0 range:whole];
        for (NSTextCheckingResult *match in matches)
        {
            BOOL skip = NO;
            for (NSTextCheckingResult *span in skips)
            {
                if (NSIntersectionRange(span.range, match.range).length)
                {
                    skip = YES;
                    break;
                }
            }
            if (skip)
                continue;

            MPProseIssue *issue = [[MPProseIssue alloc] init];
            issue.range = match.range;
            issue.text = [text substringWithRange:match.range];
            issue.categoryIdentifier = category.identifier;
            issue.categoryName = category.name;
            issue.color = category.color;
            [issues addObject:issue];
        }
    }

    [issues sortUsingComparator:^NSComparisonResult(MPProseIssue *a,
                                                    MPProseIssue *b) {
        if (a.range.location < b.range.location) return NSOrderedAscending;
        if (a.range.location > b.range.location) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return issues;
}

- (NSString *)summaryForIssues:(NSArray<MPProseIssue *> *)issues
{
    if (!issues.count)
        return nil;

    NSCountedSet *counts = [NSCountedSet set];
    NSMutableDictionary<NSString *, NSString *> *names =
        [NSMutableDictionary dictionary];
    for (MPProseIssue *issue in issues)
    {
        [counts addObject:issue.categoryIdentifier];
        names[issue.categoryIdentifier] = issue.categoryName;
    }

    NSMutableArray<MPProseCategory *> *ordered =
        [self.categories mutableCopy] ?: [NSMutableArray array];
    if (self.repeated)
        [ordered addObject:self.repeated];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (MPProseCategory *category in ordered)
    {
        NSUInteger count = [counts countForObject:category.identifier];
        if (!count)
            continue;
        // "Qualifiers: 2" rather than "2 qualifiers", so the line reads
        // correctly for any count without needing a plural for every name.
        [parts addObject:[NSString stringWithFormat:@"%@: %lu",
            category.name, (unsigned long)count]];
    }
    return [parts componentsJoinedByString:@" · "];
}

@end
