//
//  MPSendTo.h
//  MacDown
//
//  Handing the document to Claude or to ChatGPT.
//

#import <Cocoa/Cocoa.h>


typedef NS_ENUM(NSUInteger, MPSendToTarget) {
    MPSendToClaude,
    MPSendToChatGPT,
};


/** Where to open, for that target and that text.
 *
 * Claude's desktop application answers `claude://claude.ai/new?q=…` by
 * opening a new chat with the prompt field filled in — filled in, not sent,
 * which is the right side of the line for something a menu item does. The
 * web takes the text no longer, so there the link is plain and the clipboard
 * carries the document. ChatGPT prefills from `?q=` on the web.
 *
 * `desktopAppPresent` is what the workspace answered when asked who opens
 * that scheme, so this function stays a function.
 */
extern NSURL *MPSendToURL(MPSendToTarget target, NSString *text,
                          BOOL desktopAppPresent);

/** Whether the link itself carries the text.
 *
 * When it does not — no room, or nowhere to put it — the clipboard does, and
 * the reader pastes. The text goes on the clipboard either way: a link that
 * silently drops half a document would be worse than one that carries none.
 */
extern BOOL MPSendToLinkCarriesText(MPSendToTarget target, NSString *text,
                                    BOOL desktopAppPresent);

/// Whether an application is installed that answers that target's scheme.
extern BOOL MPSendToDesktopAppIsInstalled(MPSendToTarget target);
