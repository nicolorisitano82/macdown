//
//  MPSendTo.m
//  MacDown
//

#import "MPSendTo.h"


/// What Claude's desktop application accepts in a link, per its own
/// documentation: past this it truncates, and a truncated document is worse
/// than one the clipboard carries whole.
static const NSUInteger kMPClaudeLinkAtMost = 14000;

/// And what to put in a web address without finding out the hard way which
/// server draws the line where.
static const NSUInteger kMPWebLinkAtMost = 4000;


NS_INLINE NSString *MPSchemeForTarget(MPSendToTarget target)
{
    return (target == MPSendToClaude) ? @"claude" : @"chatgpt";
}


BOOL MPSendToDesktopAppIsInstalled(MPSendToTarget target)
{
    NSURL *probe = [NSURL URLWithString:
        [MPSchemeForTarget(target) stringByAppendingString:@"://x"]];
    if (!probe)
        return NO;
    return [[NSWorkspace sharedWorkspace]
        URLForApplicationToOpenURL:probe] != nil;
}


/// The text, escaped for a query, or nil when there is nothing to say.
static NSString *MPQueryEscaped(NSString *text)
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length)
        return nil;
    NSCharacterSet *allowed = [NSCharacterSet
        characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            @"-._~"];
    return [trimmed stringByAddingPercentEncodingWithAllowedCharacters:
        allowed];
}


BOOL MPSendToLinkCarriesText(MPSendToTarget target, NSString *text,
                             BOOL desktopAppPresent)
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length)
        return NO;

    if (target == MPSendToClaude)
    {
        // Only the desktop application takes it: the web dropped `q`.
        return desktopAppPresent && trimmed.length <= kMPClaudeLinkAtMost;
    }
    return trimmed.length <= kMPWebLinkAtMost;
}


NSURL *MPSendToURL(MPSendToTarget target, NSString *text,
                   BOOL desktopAppPresent)
{
    BOOL carried = MPSendToLinkCarriesText(target, text, desktopAppPresent);
    NSString *query = carried ? MPQueryEscaped(text) : nil;

    if (target == MPSendToClaude)
    {
        if (desktopAppPresent)
        {
            NSString *address = query.length
                ? [NSString stringWithFormat:
                    @"claude://claude.ai/new?q=%@", query]
                : @"claude://claude.ai/new";
            return [NSURL URLWithString:address];
        }
        return [NSURL URLWithString:@"https://claude.ai/new"];
    }

    NSString *address = query.length
        ? [NSString stringWithFormat:@"https://chatgpt.com/?q=%@", query]
        : @"https://chatgpt.com/";
    return [NSURL URLWithString:address];
}
