//
//  MPInstructionFiles.h
//  MacDown
//
//  CLAUDE.md and AGENTS.md read as what they are: files with a hierarchy,
//  imports, and ways of going wrong.
//

#import <Cocoa/Cocoa.h>


/// Where an instruction file sits, which is what decides when it is read.
typedef NS_ENUM(NSUInteger, MPInstructionScope) {
    /// /Library/Application Support/ClaudeCode/CLAUDE.md — the machine's.
    MPInstructionScopeManaged,
    /// ~/.claude/CLAUDE.md — yours, in every project.
    MPInstructionScopeUser,
    /// CLAUDE.md, or .claude/CLAUDE.md, in a folder on the way down.
    MPInstructionScopeProject,
    /// CLAUDE.local.md — yours, in this project, and not committed.
    MPInstructionScopeLocal,
    /// AGENTS.md, which Claude Code does not read: another agent's file.
    MPInstructionScopeAgents,
};


/// One file that takes part, whether or not it is there.
@interface MPInstructionFile : NSObject
@property (readonly, copy, nonatomic) NSURL *fileURL;
@property (readonly, nonatomic) MPInstructionScope scope;
@property (readonly, nonatomic) BOOL exists;
/// Lines, for the two-hundred the documentation asks you to stay under.
@property (readonly, nonatomic) NSUInteger lines;
@property (readonly, nonatomic) unsigned long long size;
/// What to call the scope, in a list.
@property (readonly, copy, nonatomic) NSString *scopeName;
@end


/// One `@path` inside a file, and where it is written.
@interface MPInstructionImport : NSObject
@property (readonly, copy, nonatomic) NSString *path;   // as written
@property (readonly, nonatomic) NSRange range;          // in the text
@property (readonly, nonatomic) NSUInteger line;        // counting from one
@end


/// A file and what it pulls in, to the depth the loader would go.
@interface MPInstructionNode : NSObject
@property (readonly, copy, nonatomic) NSURL *fileURL;
@property (readonly, copy, nonatomic) NSString *writtenAs;  // the @path
@property (readonly, nonatomic) NSUInteger depth;
@property (readonly, nonatomic) BOOL exists;
/// Whether this import closes a circle, and is therefore not followed.
@property (readonly, nonatomic) BOOL circular;
/// Whether it sits past the fourth hop, where the loader stops.
@property (readonly, nonatomic) BOOL tooDeep;
@property (readonly, copy, nonatomic) NSArray<MPInstructionNode *> *imports;
@end


/// Something worth saying about the set: a broken import, a circle, a file
/// long enough to be ignored, an AGENTS.md nobody imports.
@interface MPInstructionIssue : NSObject
@property (readonly, copy, nonatomic) NSString *message;
@property (readonly, copy, nonatomic) NSURL *fileURL;
@property (readonly, nonatomic) NSUInteger line;    // 0 when it is the file
@end


#pragma mark - Reading them

/// Whether that file is one of these at all.
extern BOOL MPIsInstructionFile(NSURL *fileURL);

/** Every instruction file that applies to a document, in load order.
 *
 * Broadest first, as the loader reads them: the machine's, then yours, then
 * the project's from the top of the tree down to the document's own folder,
 * with each folder's local file after its shared one. Files that are not
 * there are in the list too, marked absent: knowing where one *would* be
 * read from is half the question.
 *
 * `home` and `managedRoot` are given rather than looked up so that this can
 * be tested against a folder made for the purpose.
 */
extern NSArray<MPInstructionFile *> *MPInstructionHierarchyForDocument(
    NSURL *documentURL, NSURL *home, NSURL *managedRoot);

/** The `@path` imports in a text, in the order they are written.
 *
 * Code spans and fenced blocks are skipped, as the loader skips them: a
 * path inside backticks is a path being talked about, not imported.
 */
extern NSArray<MPInstructionImport *> *MPInstructionImportsInText(
    NSString *text);

/** What a file pulls in, following imports as the loader does.
 *
 * Four hops at most — that is where the loader stops — and a circle is
 * marked rather than walked.
 */
extern MPInstructionNode *MPResolveInstructionImports(NSURL *fileURL);

/// What is wrong with that tree and that hierarchy, in reading order.
extern NSArray<MPInstructionIssue *> *MPInstructionIssues(
    MPInstructionNode *tree, NSArray<MPInstructionFile *> *hierarchy);
