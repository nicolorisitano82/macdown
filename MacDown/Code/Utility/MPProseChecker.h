//
//  MPProseChecker.h
//  MacDown
//
//  Flags words and phrases that usually weaken prose: qualifiers, weasel
//  words, hedges, wordy constructions and accidental repetitions.
//

#import <Cocoa/Cocoa.h>


/// One flagged word or phrase, with where it sits and which list caught it.
@interface MPProseIssue : NSObject
@property (copy, nonatomic) NSString *text;
@property (copy, nonatomic) NSString *categoryIdentifier;
@property (copy, nonatomic) NSString *categoryName;
@property (strong, nonatomic) NSColor *color;
@property (assign, nonatomic) NSRange range;
@end


@interface MPProseChecker : NSObject

/// The lists are read once from Resources/Data/prose-issues.json.
+ (instancetype)sharedChecker;

/// Whether any lists were loaded. NO means the resource is missing or
/// malformed, and -issuesInString: will always come back empty.
@property (readonly, nonatomic) BOOL ready;

/** Flagged words in `text`, in the order they appear.
 *
 * Markdown is respected to the extent that matters here: matches inside
 * fenced or inline code are dropped, along with matches inside link
 * destinations, since none of those are prose.
 */
- (NSArray<MPProseIssue *> *)issuesInString:(NSString *)text;

/// A short "3 qualifiers · 1 hedging" line, or nil when there is nothing to
/// report. Categories appear in the order they are declared in the resource.
- (NSString *)summaryForIssues:(NSArray<MPProseIssue *> *)issues;

@end
