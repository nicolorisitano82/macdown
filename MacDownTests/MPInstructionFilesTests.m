//
//  MPInstructionFilesTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPInstructionFiles.h"


/// CLAUDE.md and AGENTS.md: which files apply, what they pull in, and what
/// is wrong with the set.
@interface MPInstructionFilesTests : XCTestCase
@property (strong) NSURL *root;
@end


@implementation MPInstructionFilesTests

- (void)setUp
{
    [super setUp];
    self.root = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.root
        withIntermediateDirectories:YES attributes:nil error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.root error:NULL];
    [super tearDown];
}

- (NSURL *)write:(NSString *)text to:(NSString *)relative
{
    NSURL *url = [self.root URLByAppendingPathComponent:relative];
    [[NSFileManager defaultManager]
        createDirectoryAtURL:url.URLByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding
               error:NULL];
    return url;
}


#pragma mark - Which files are these

- (void)testTheThreeNamesThatCount
{
    XCTAssertTrue(MPIsInstructionFile(
        [NSURL fileURLWithPath:@"/x/CLAUDE.md"]));
    XCTAssertTrue(MPIsInstructionFile(
        [NSURL fileURLWithPath:@"/x/CLAUDE.local.md"]));
    XCTAssertTrue(MPIsInstructionFile(
        [NSURL fileURLWithPath:@"/x/AGENTS.md"]));
    XCTAssertFalse(MPIsInstructionFile(
        [NSURL fileURLWithPath:@"/x/README.md"]));
}


#pragma mark - The imports in a file

- (void)testWhatCountsAsAnImport
{
    NSString *text =
        @"See @README for the overview and @docs/git.md for the workflow.\n"
        @"- personal @~/.claude/mine.md\n"
        @"- absolute @/opt/rules.md\n";
    NSArray<MPInstructionImport *> *found = MPInstructionImportsInText(text);

    XCTAssertEqual(found.count, 4u);
    XCTAssertEqualObjects(found[0].path, @"README");
    XCTAssertEqualObjects(found[1].path, @"docs/git.md");
    XCTAssertEqualObjects(found[2].path, @"~/.claude/mine.md");
    XCTAssertEqualObjects(found[3].path, @"/opt/rules.md");
    XCTAssertEqual(found[1].line, 1u);
    XCTAssertEqual(found[2].line, 2u);
}

- (void)testBackticksMeanTheWordAndNotTheFile
{
    NSString *text = @"Write `@README` to mention it, @README to import it.\n"
                     @"```\n@dentro/al/codice.md\n```\n";
    NSArray<MPInstructionImport *> *found = MPInstructionImportsInText(text);
    XCTAssertEqual(found.count, 1u, @"%@", [found valueForKey:@"path"]);
    XCTAssertEqualObjects(found.firstObject.path, @"README");
}

- (void)testAnAddressIsNotAnImport
{
    NSArray *found = MPInstructionImportsInText(
        @"Scrivi a qualcuno@esempio.it, non è un'importazione.\n");
    XCTAssertEqual(found.count, 0u);
}


#pragma mark - What a file pulls in

- (void)testTheTreeOfImports
{
    [self write:@"@rules/uno.md e @rules/due.md\n" to:@"CLAUDE.md"];
    [self write:@"niente\n" to:@"rules/uno.md"];
    [self write:@"@tre.md\n" to:@"rules/due.md"];
    [self write:@"foglia\n" to:@"rules/tre.md"];

    MPInstructionNode *tree = MPResolveInstructionImports(
        [self.root URLByAppendingPathComponent:@"CLAUDE.md"]);

    XCTAssertEqual(tree.imports.count, 2u);
    XCTAssertTrue(tree.imports[0].exists);
    // Relative to the file that wrote it, not to where we started.
    XCTAssertEqualObjects(tree.imports[1].imports.firstObject.fileURL
        .lastPathComponent, @"tre.md");
    XCTAssertEqual(tree.imports[1].imports.firstObject.depth, 2u);
}

- (void)testAnImportThatPointsAtNothing
{
    [self write:@"@manca.md\n" to:@"CLAUDE.md"];
    MPInstructionNode *tree = MPResolveInstructionImports(
        [self.root URLByAppendingPathComponent:@"CLAUDE.md"]);

    XCTAssertEqual(tree.imports.count, 1u);
    XCTAssertFalse(tree.imports.firstObject.exists);

    NSArray<MPInstructionIssue *> *issues =
        MPInstructionIssues(tree, @[]);
    XCTAssertEqual(issues.count, 1u);
    XCTAssertTrue([issues.firstObject.message containsString:@"manca.md"]);
}

- (void)testACircleIsMarkedAndNotWalked
{
    [self write:@"@b.md\n" to:@"CLAUDE.md"];
    [self write:@"@CLAUDE.md\n" to:@"b.md"];

    MPInstructionNode *tree = MPResolveInstructionImports(
        [self.root URLByAppendingPathComponent:@"CLAUDE.md"]);
    MPInstructionNode *back = tree.imports.firstObject.imports.firstObject;
    XCTAssertTrue(back.circular, @"il cerchio non è stato riconosciuto");

    NSArray<MPInstructionIssue *> *issues = MPInstructionIssues(tree, @[]);
    XCTAssertTrue([issues.firstObject.message containsString:@"cerchio"]);
}

- (void)testPastTheFourthHopNothingIsRead
{
    [self write:@"@1.md\n" to:@"CLAUDE.md"];
    for (NSUInteger i = 1; i <= 5; i++)
    {
        [self write:[NSString stringWithFormat:@"@%lu.md\n",
                     (unsigned long)i + 1]
                 to:[NSString stringWithFormat:@"%lu.md", (unsigned long)i]];
    }

    MPInstructionNode *node = MPResolveInstructionImports(
        [self.root URLByAppendingPathComponent:@"CLAUDE.md"]);
    NSUInteger depth = 0;
    while (node.imports.count)
    {
        node = node.imports.firstObject;
        depth++;
        if (node.tooDeep)
            break;
    }
    XCTAssertTrue(node.tooDeep, @"nessuno ha detto dove si ferma");
    XCTAssertEqual(depth, 4u);

    NSArray<MPInstructionIssue *> *issues = MPInstructionIssues(node, @[]);
    XCTAssertEqual(issues.count, 0u, @"l'avviso sta sul padre, non qui");
}


#pragma mark - The hierarchy

- (void)testFromTheTopOfTheTreeDownToTheDocument
{
    [self write:@"# progetto\n" to:@"CLAUDE.md"];
    [self write:@"# sotto\n" to:@"verbali/CLAUDE.md"];
    [self write:@"# mio\n" to:@"verbali/CLAUDE.local.md"];
    NSURL *document = [self write:@"# documento\n" to:@"verbali/uno.md"];

    NSArray<MPInstructionFile *> *files =
        MPInstructionHierarchyForDocument(document, nil, nil);
    NSMutableArray *names = [NSMutableArray array];
    for (MPInstructionFile *file in files)
    {
        if (file.exists)
            [names addObject:file.fileURL.path.stringByAbbreviatingWithTildeInPath
                .lastPathComponent];
    }

    // The project's file is read before the folder's, and the local one last.
    XCTAssertEqual(names.count, 3u, @"%@", names);
    XCTAssertEqualObjects(names.lastObject, @"CLAUDE.local.md");
    XCTAssertEqual(files.lastObject.scope, MPInstructionScopeLocal);
}

- (void)testWhereYoursAndTheMachinesWouldBe
{
    NSURL *document = [self write:@"# x\n" to:@"uno.md"];
    NSURL *home = [self.root URLByAppendingPathComponent:@"casa"];
    NSURL *managed = [self.root URLByAppendingPathComponent:@"macchina"];

    NSArray<MPInstructionFile *> *files =
        MPInstructionHierarchyForDocument(document, home, managed);
    XCTAssertEqual(files.firstObject.scope, MPInstructionScopeManaged);
    XCTAssertEqual(files[1].scope, MPInstructionScopeUser);
    // Absent, and listed anyway: knowing where one would go is the answer to
    // half the question.
    XCTAssertFalse(files.firstObject.exists);
    XCTAssertTrue([files[1].fileURL.path hasSuffix:@".claude/CLAUDE.md"]);
}


#pragma mark - What is worth saying

- (void)testAFileTooLongToBeReadWell
{
    NSMutableString *long_ = [NSMutableString string];
    for (NSUInteger i = 0; i < 250; i++)
        [long_ appendFormat:@"riga %lu\n", (unsigned long)i];
    NSURL *url = [self write:long_ to:@"CLAUDE.md"];
    NSURL *document = [self write:@"# x\n" to:@"uno.md"];

    NSArray<MPInstructionFile *> *files =
        MPInstructionHierarchyForDocument(document, nil, nil);
    NSArray<MPInstructionIssue *> *issues = MPInstructionIssues(nil, files);

    XCTAssertEqual(issues.count, 1u);
    XCTAssertTrue([issues.firstObject.message containsString:@"250 righe"],
                  @"%@", issues.firstObject.message);
    XCTAssertEqualObjects(issues.firstObject.fileURL.path, url.path);
}

- (void)testAnAgentsFileNobodyImports
{
    [self write:@"# per altri\n" to:@"AGENTS.md"];
    [self write:@"# claude\n" to:@"CLAUDE.md"];
    NSURL *document = [self write:@"# x\n" to:@"uno.md"];

    NSArray<MPInstructionFile *> *files =
        MPInstructionHierarchyForDocument(document, nil, nil);
    MPInstructionNode *tree = MPResolveInstructionImports(
        [self.root URLByAppendingPathComponent:@"CLAUDE.md"]);
    NSArray<MPInstructionIssue *> *issues =
        MPInstructionIssues(tree, files);

    XCTAssertEqual(issues.count, 1u, @"%@", [issues valueForKey:@"message"]);
    XCTAssertTrue([issues.firstObject.message containsString:@"@AGENTS.md"]);
}

- (void)testAnAgentsFileThatIsImportedIsFine
{
    [self write:@"# per altri\n" to:@"AGENTS.md"];
    [self write:@"@AGENTS.md\n\n## Claude\n" to:@"CLAUDE.md"];
    NSURL *document = [self write:@"# x\n" to:@"uno.md"];

    NSArray<MPInstructionFile *> *files =
        MPInstructionHierarchyForDocument(document, nil, nil);
    MPInstructionNode *tree = MPResolveInstructionImports(
        [self.root URLByAppendingPathComponent:@"CLAUDE.md"]);
    XCTAssertEqual(MPInstructionIssues(tree, files).count, 0u);
}

@end
