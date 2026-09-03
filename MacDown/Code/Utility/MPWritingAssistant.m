//
//  MPWritingAssistant.m
//  MacDown
//

#import "MPWritingAssistant.h"
#import <NaturalLanguage/NaturalLanguage.h>

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

+ (NSString *)languageNameOfText:(NSString *)text
{
    if (text.length < 12)
        return nil;     // Too little to tell, and a wrong guess is worse.

    NLLanguageRecognizer *recogniser = [[NLLanguageRecognizer alloc] init];
    [recogniser processString:text];
    NSString *code = recogniser.dominantLanguage;
    if (!code.length)
        return nil;

    // In English, because that is the language the instruction is written
    // in, and the one the model was given the name in when this was tried.
    NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    return [english localizedStringForLanguageCode:code];
}

/** The instruction for a command.
 *
 * Written to be read by a small model, which is what these will mostly be:
 * one sentence saying what to do, and a plain demand for the text and
 * nothing else. A model given room to comment will comment, and its
 * commentary would land in the document.
 *
 * Not translated, and that is a decision from measurement rather than
 * laziness. Asked the same thing with the instruction in English and in
 * Italian, the model answered the same way both times: what it follows is
 * the named output language below, not the language it was asked in. One
 * wording to keep good instead of twenty-six.
 *
 * The naming is the part that matters. An earlier version said "answer in
 * the same language as the text" and hedged with "keeping its meaning":
 * the model returned an Italian paragraph completely unchanged. With the
 * hedging removed it rewrote it — into Spanish. Told "the text is in
 * Italian, and your answer must be in Italian", it rewrites it in Italian.
 */
+ (NSString *)instructionForCommand:(MPWritingCommand)command
                         inLanguage:(NSString *)language
{
    NSString *opening = nil;
    switch (command)
    {
        case MPWritingCommandImprove:
            opening = @"You are an editor. Rewrite the text so that it reads "
                       "better: change the wording, keep the facts.";
            break;
        case MPWritingCommandCorrect:
            opening = @"You are a proofreader. Correct the spelling, the "
                       "agreement and the punctuation, and change nothing "
                       "else.";
            break;
        case MPWritingCommandFormal:
            opening = @"You are an editor. Rewrite the text in a formal, "
                       "impersonal register, as a report would be written: "
                       "change the wording, keep the facts.";
            break;
        case MPWritingCommandPlain:
            opening = @"You are an editor. Rewrite the text in plain "
                       "language: short sentences, everyday words, no "
                       "jargon.";
            break;
        case MPWritingCommandShorter:
            opening = @"You are an editor. Say the same thing in fewer "
                       "words. Drop what repeats and what adds nothing, and "
                       "keep every fact.";
            break;
        case MPWritingCommandLonger:
            opening = @"You are an editor. Develop the text into a fuller "
                       "paragraph, staying on what it says and inventing no "
                       "facts, no figures and no names.";
            break;
    }

    NSMutableString *instruction = [opening mutableCopy];
    if (language.length)
    {
        [instruction appendFormat:@" The text is in %@, and your answer must "
                                   @"be in %@.", language, language];
    }
    [instruction appendString:@" Answer with the rewritten text only, with "
                              @"no preamble and no quotation marks, keeping "
                              @"any Markdown formatting."];
    return instruction;
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
        [[self class] instructionForCommand:command
                                 inLanguage:[[self class]
                                     languageNameOfText:text]]
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
