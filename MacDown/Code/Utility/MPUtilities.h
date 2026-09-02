//
//  MPUtilities.h
//  MacDown
//
//  Created by Tzu-ping Chung  on 8/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kMPStylesDirectoryName;
extern NSString * const kMPStyleFileExtension;
extern NSString * const kMPThemesDirectoryName;
extern NSString * const kMPThemeFileExtension;
extern NSString * const kMPPlugInsDirectoryName;
extern NSString * const kMPPlugInFileExtension;

NSString *MPDataDirectory(NSString *relativePath);
NSString *MPPathToDataFile(NSString *name, NSString *dirPath);

NSArray *MPListEntriesForDirectory(
    NSString *dirName, NSString *(^processor)(NSString *absolutePath)
);

// Block factory for MPListEntriesForDirectory
NSString *(^MPFileNameHasExtensionProcessor(NSString *ext))(NSString *path);

/** Where `index` falls once the string is written out as UTF-8.
 *
 * The renderer records, for each block it produces, the byte offset it came
 * from — the file is UTF-8, so those are byte offsets. A text view counts in
 * UTF-16 units instead, and the two agree only while the text stays ASCII.
 * In Italian they part company at the first accent and never meet again: a
 * few dozen characters in, everything the preview is told is off by one
 * block, and further down by two.
 */
NSUInteger MPUTF8ByteOffsetForCharacterIndex(NSString *string,
                                             NSUInteger index);

/** The other way: a byte offset in the UTF-8 form back to a character index.
 *
 * Both are defined on character boundaries. An index between the halves of
 * a surrogate pair is not one — a text view never puts the caret there —
 * and neither function promises anything about it.
 */
NSUInteger MPCharacterIndexForUTF8ByteOffset(NSString *string,
                                             NSUInteger offset);

/** An HTML attribute value with its five escapes put back.
 *
 * Markup is HTML, so a picture called `a&b.png` arrives written
 * `a&amp;b.png` and is then looked for under a name it does not have; a web
 * address arrives with its query separators escaped and is fetched as a
 * different address from the one the writer meant.
 */
NSString *MPStringByUnescapingHTMLEntities(NSString *value);

BOOL MPCharacterIsWhitespace(unichar character);
BOOL MPCharacterIsNewline(unichar character);
BOOL MPStringIsNewline(NSString *str);

NSString *MPStylePathForName(NSString *name);
NSString *MPThemePathForName(NSString *name);
NSURL *MPHighlightingThemeURLForName(NSString *name);
NSString *MPReadFileOfPath(NSString *path);

NSDictionary *MPGetDataMap(NSString *name);

id MPGetObjectFromJavaScript(NSString *code, NSString *variableName);


static void (^MPDocumentOpenCompletionEmpty)(
        NSDocument *doc, BOOL wasOpen, NSError *error) = ^(
        NSDocument *doc, BOOL wasOpen, NSError *error) {

};
