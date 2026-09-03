//
//  MPWritingAssistant.m
//  MacDown
//

#import "MPWritingAssistant.h"

const MPWritingCommand MPWritingCommandsInOrder[6] = {
    MPWritingCommandImprove,
    MPWritingCommandCorrect,
    MPWritingCommandFormal,
    MPWritingCommandPlain,
    MPWritingCommandShorter,
    MPWritingCommandLonger,
};
const NSUInteger MPWritingCommandCount = 6;


@interface MPWritingAssistant ()
@property (assign, nonatomic, getter=isWorking) BOOL working;
/// What has been written into the document so far, this command.
@property (assign, nonatomic) NSRange written;
/// The text still waiting to be replaced, until the first piece arrives.
@property (assign, nonatomic) NSRange pending;
@property (weak, nonatomic) NSTextView *textView;
@end


@implementation MPWritingAssistant

- (instancetype)initWithGenerator:(id<MPTextGenerator>)generator
{
    self = [super init];
    if (!self)
        return nil;
    _generator = generator;
    return self;
}


#pragma mark - What the model is told

/** The instruction for a command.
 *
 * Written to be read by a small model, which is what these will mostly be:
 * one sentence saying what to do, one saying what not to, and a plain
 * demand for the text and nothing else. A model given room to comment will
 * comment, and its commentary would land in the document.
 *
 * The language is not named. A model told to answer in Italian will answer
 * in Italian even when the paragraph is in English, and the language of the
 * text is the one thing the text itself already says.
 */
+ (NSString *)instructionForCommand:(MPWritingCommand)command
{
    NSString *ending = NSLocalizedString(
        @" Answer with the rewritten text only: no preamble, no commentary, "
        @"no quotation marks around it. Keep the Markdown formatting that is "
        @"already there, and answer in the same language as the text.",
        @"Writing command instruction");

    NSString *opening = nil;
    switch (command)
    {
        case MPWritingCommandImprove:
            opening = NSLocalizedString(
                @"You are an editor. Rewrite the text so it reads better, "
                @"keeping its meaning and its facts exactly as they are.",
                @"Writing command instruction");
            break;
        case MPWritingCommandCorrect:
            opening = NSLocalizedString(
                @"You are a proofreader. Correct spelling, agreement and "
                @"punctuation. Change nothing else: not the wording, not the "
                @"order, not the register.",
                @"Writing command instruction");
            break;
        case MPWritingCommandFormal:
            opening = NSLocalizedString(
                @"You are an editor. Rewrite the text in a formal, impersonal "
                @"register, as a report would be written, keeping its meaning.",
                @"Writing command instruction");
            break;
        case MPWritingCommandPlain:
            opening = NSLocalizedString(
                @"You are an editor. Rewrite the text in plain language: "
                @"short sentences, everyday words, no jargon, same meaning.",
                @"Writing command instruction");
            break;
        case MPWritingCommandShorter:
            opening = NSLocalizedString(
                @"You are an editor. Say the same thing in fewer words. Drop "
                @"what repeats and what adds nothing; keep every fact.",
                @"Writing command instruction");
            break;
        case MPWritingCommandLonger:
            opening = NSLocalizedString(
                @"You are an editor. Develop the text into a fuller "
                @"paragraph, staying on what it says and inventing no facts, "
                @"no figures and no names.",
                @"Writing command instruction");
            break;
    }
    return [opening stringByAppendingString:ending];
}

+ (NSString *)titleForCommand:(MPWritingCommand)command
{
    switch (command)
    {
        case MPWritingCommandImprove:
            return NSLocalizedString(@"Improve the Writing",
                                     @"Writing command");
        case MPWritingCommandCorrect:
            return NSLocalizedString(@"Correct Mistakes Only",
                                     @"Writing command");
        case MPWritingCommandFormal:
            return NSLocalizedString(@"Make It Formal", @"Writing command");
        case MPWritingCommandPlain:
            return NSLocalizedString(@"Make It Plain", @"Writing command");
        case MPWritingCommandShorter:
            return NSLocalizedString(@"Make It Shorter", @"Writing command");
        case MPWritingCommandLonger:
            return NSLocalizedString(@"Make It Longer", @"Writing command");
    }
    return @"";
}


#pragma mark - What it works on

+ (NSRange)rangeForCommandInTextView:(NSTextView *)textView
{
    NSRange selection = textView.selectedRange;
    if (selection.length)
        return selection;

    NSString *text = textView.string;
    if (!text.length)
        return NSMakeRange(NSNotFound, 0);

    // The paragraph the caret is in, without the line break that ends it:
    // a command that swallowed the break would join two paragraphs into one.
    NSRange paragraph = [text paragraphRangeForRange:
        NSMakeRange(MIN(selection.location, text.length), 0)];
    while (paragraph.length > 0)
    {
        unichar last = [text characterAtIndex:NSMaxRange(paragraph) - 1];
        if (last != '\n' && last != '\r')
            break;
        paragraph.length--;
    }

    // Nothing but whitespace is nothing to rewrite.
    NSString *body = [[text substringWithRange:paragraph]
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!body.length)
        return NSMakeRange(NSNotFound, 0);

    return paragraph;
}


#pragma mark - Running

- (BOOL)runCommand:(MPWritingCommand)command
        onTextView:(NSTextView *)textView
        completion:(void (^)(NSError *))completion
{
    if (self.working || !textView || !self.generator.isAvailable)
        return NO;

    NSRange range = [[self class] rangeForCommandInTextView:textView];
    if (range.location == NSNotFound || !range.length)
        return NO;

    NSString *text = [textView.string substringWithRange:range];

    self.working = YES;
    self.textView = textView;
    // Nothing written yet, but the place it will go is known.
    self.written = NSMakeRange(range.location, 0);
    self.pending = NSMakeRange(range.location, 0);

    // One group around the whole answer, so the reader takes it all back
    // with one undo rather than a token at a time.
    [textView.undoManager beginUndoGrouping];

    // The text stays until there is something to put in its place.
    //
    // It used to go at once, so that the document would not sit there
    // looking untouched while the model started. Then the model was
    // measured starting: on a machine that has never compiled the Metal
    // shaders it is three and a half seconds, and for all of it the
    // reader's paragraph was simply gone. A paragraph that vanishes and
    // stays vanished is worse than one that waits, and the waiting is
    // accounted for now by something that says so on screen.
    self.pending = range;

    __weak MPWritingAssistant *weakSelf = self;
    [self.generator generateWithInstruction:
        [[self class] instructionForCommand:command]
                                     onText:text
                                    onChunk:^(NSString *piece) {
        [weakSelf appendPiece:piece];
    } completion:^(NSError *error) {
        MPWritingAssistant *assistant = weakSelf;
        [assistant finishWithError:error originalText:text];
        if (completion)
            completion(error);
    }];
    return YES;
}

/// Puts one piece at the end of what this command has written.
- (void)appendPiece:(NSString *)piece
{
    NSTextView *textView = self.textView;
    if (!textView || !piece.length)
        return;

    // The first piece is what the old text makes way for.
    if (self.pending.length)
    {
        NSRange going = self.pending;
        self.pending = NSMakeRange(going.location, 0);
        if ([textView shouldChangeTextInRange:going replacementString:@""])
        {
            [textView.textStorage replaceCharactersInRange:going
                                               withString:@""];
            [textView didChangeText];
        }
    }

    NSRange at = NSMakeRange(NSMaxRange(self.written), 0);
    if (at.location > textView.textStorage.length)
        return;

    if (![textView shouldChangeTextInRange:at replacementString:piece])
        return;
    [textView.textStorage replaceCharactersInRange:at withString:piece];
    [textView didChangeText];

    NSRange written = self.written;
    written.length += piece.length;
    self.written = written;

    // The caret follows the writing, so a long answer scrolls into view
    // instead of being produced somewhere off screen.
    textView.selectedRange = NSMakeRange(NSMaxRange(written), 0);
    [textView scrollRangeToVisible:textView.selectedRange];
}

- (void)finishWithError:(NSError *)error originalText:(NSString *)original
{
    NSTextView *textView = self.textView;

    // Nothing came back at all: the text was never taken away, so there is
    // nothing to put back — only the selection to leave as it was found.
    if (textView && !self.written.length)
    {
        textView.selectedRange = self.pending.length
            ? self.pending
            : NSMakeRange(self.written.location, 0);
    }
    else if (textView)
    {
        // The answer, selected: it is the reader's turn now, and what they
        // are looking at is what arrived.
        textView.selectedRange = self.written;
    }

    [textView.undoManager endUndoGrouping];
    self.working = NO;
    self.textView = nil;
}

- (void)cancel
{
    if (self.working)
        [self.generator cancel];
}

@end
