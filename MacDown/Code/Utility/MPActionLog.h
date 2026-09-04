//
//  MPActionLog.h
//  MacDown
//

#import <Cocoa/Cocoa.h>


/** Writes down what was asked of the editor, and what it decided.
 *
 * For the case that keeps happening: something does not work, and neither
 * of us can see what the other sees. A recording of the screen is not the
 * answer — it is a recording of everything else on it too — and a
 * transcript of what was pressed and what came back is what a diagnosis
 * actually needs.
 *
 * Off unless it is switched on, written to a file next to the other logs,
 * and it holds what the editor did: the command, the section or the
 * document it acted on, and the answer. Document paths and heading titles
 * are in there, which is why nothing goes anywhere: it is a file on this
 * Mac, shown in the Finder when you ask and cleared when you ask.
 */
@interface MPActionLog : NSObject

+ (instancetype)sharedLog;

/// Whether anything is being written down. Kept in the preferences.
@property (assign, nonatomic) BOOL recording;

/// Where the file is, whether or not it exists yet.
@property (readonly, nonatomic) NSURL *fileURL;

/** Adds a line, with the time and the sequence number.
 *
 * Costs a format and a comparison when recording is off, so a call in a
 * hot path is not a reason to leave one out.
 */
- (void)note:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

/// What has been written, for showing it without opening the Finder.
- (NSString *)text;

/// Starts the file again, so a recording covers one attempt and not a week.
- (void)clear;

@end


/// Short of writing `[[MPActionLog sharedLog] note:…]` at every call site.
#define MPNote(...) [[MPActionLog sharedLog] note:__VA_ARGS__]
