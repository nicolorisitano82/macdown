//
//  MPTaskList.m
//  MacDown
//

#import "MPTaskList.h"


BOOL MPLineIsTaskItem(NSString *line, BOOL *outDone)
{
    static NSRegularExpression *item = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        // A bullet, a box, and something after it. Either case of x, which
        // is what this editor's parser accepts as well.
        item = [[NSRegularExpression alloc] initWithPattern:
            @"^[ \\t]*[-*+][ \\t]+\\[([ xX])\\][ \\t]" options:0 error:NULL];
    });

    NSTextCheckingResult *match = [item firstMatchInString:line ?: @""
        options:0 range:NSMakeRange(0, line.length)];
    if (!match)
        return NO;
    if (outDone)
    {
        NSString *box = [line substringWithRange:[match rangeAtIndex:1]];
        *outDone = ![box isEqualToString:@" "];
    }
    return YES;
}

/// How far in a line starts, in characters, tabs counted as one.
NS_INLINE NSUInteger MPIndentOfLine(NSString *line)
{
    NSUInteger indent = 0;
    while (indent < line.length)
    {
        unichar c = [line characterAtIndex:indent];
        if (c != ' ' && c != '\t')
            break;
        indent++;
    }
    return indent;
}


NSString *MPTasksMovedToEnd(NSString *text, NSUInteger index,
                            NSRange *replaced)
{
    if (!text.length)
        return nil;
    index = MIN(index, text.length - 1);

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];

    // Which line the caret is on, and where each line begins.
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSUInteger at = 0;
    NSUInteger caretLine = NSNotFound;
    for (NSString *line in lines)
    {
        [starts addObject:@(at)];
        if (caretLine == NSNotFound && index <= at + line.length)
            caretLine = starts.count - 1;
        at += line.length + 1;
    }
    if (caretLine == NSNotFound)
        return nil;

    // The list around that line: task items, their continuations, and
    // nothing else. A blank line ends it, which is where a Markdown list
    // ends as well unless it is a loose one — and a loose list is not
    // something to reshuffle without being asked twice.
    NSInteger first = (NSInteger)caretLine;
    while (first >= 0)
    {
        NSString *line = lines[(NSUInteger)first];
        BOOL done = NO;
        if (MPLineIsTaskItem(line, &done))
        {
            first--;
            continue;
        }
        // A continuation belongs to the item above it, so keep walking up.
        if (line.length && MPIndentOfLine(line) > 0)
        {
            first--;
            continue;
        }
        break;
    }
    first++;

    NSUInteger last = caretLine;
    while (last + 1 < lines.count)
    {
        NSString *line = lines[last + 1];
        BOOL done = NO;
        if (MPLineIsTaskItem(line, &done)
                || (line.length && MPIndentOfLine(line) > 0))
        {
            last++;
            continue;
        }
        break;
    }

    // Every item, with whatever hangs under it.
    NSMutableArray<NSArray<NSString *> *> *items = [NSMutableArray array];
    NSMutableArray<NSNumber *> *finished = [NSMutableArray array];
    NSMutableArray<NSString *> *current = nil;
    BOOL currentDone = NO;
    // The list's own indentation, from its first item. A task further in
    // than that is somebody's child, not an item of this list: it belongs
    // to the item above it and travels with it, because reordering across
    // levels would take the list apart rather than sort it.
    NSUInteger baseIndent = MPIndentOfLine(lines[(NSUInteger)first]);

    for (NSUInteger line = (NSUInteger)first; line <= last; line++)
    {
        BOOL done = NO;
        if (MPLineIsTaskItem(lines[line], &done)
                && MPIndentOfLine(lines[line]) <= baseIndent)
        {
            if (current)
            {
                [items addObject:current];
                [finished addObject:@(currentDone)];
            }
            current = [NSMutableArray arrayWithObject:lines[line]];
            currentDone = done;
            continue;
        }
        if (!current)
            return nil;   // a continuation with nothing to continue
        [current addObject:lines[line]];
    }
    if (current)
    {
        [items addObject:current];
        [finished addObject:@(currentDone)];
    }
    if (items.count < 2)
        return nil;

    // Already in that order? Then nothing is written. Asked of the list as
    // it stands, before it is rebuilt: an unfinished item after a finished
    // one is the only thing that has to move.
    BOOL ordered = YES;
    BOOL sawFinished = NO;
    for (NSNumber *done in finished)
    {
        if (done.boolValue)
            sawFinished = YES;
        else if (sawFinished)
        {
            ordered = NO;
            break;
        }
    }
    if (ordered)
        return nil;

    // Unfinished first, in the order they were in; then the finished ones,
    // likewise. A stable partition, so nothing moves that need not.
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSUInteger pass = 0; pass < 2; pass++)
    {
        for (NSUInteger i = 0; i < items.count; i++)
        {
            if (finished[i].boolValue != (pass == 1))
                continue;
            [out addObjectsFromArray:items[i]];
        }
    }

    NSUInteger from = starts[(NSUInteger)first].unsignedIntegerValue;
    NSUInteger to = starts[last].unsignedIntegerValue
        + lines[last].length;
    if (replaced)
        *replaced = NSMakeRange(from, to - from);
    return [out componentsJoinedByString:@"\n"];
}
