//
//  MPTextGeneratorTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPLlamaGenerator.h"

/** What can be checked without a model, and what needs one.
 *
 * A GGUF worth generating from is two gigabytes, so the generating test
 * skips unless one is installed where the application keeps them. The rest
 * — refusing what is not there, and saying why — runs on every build, and
 * is the part a reader actually meets when something is wrong.
 */
@interface MPTextGeneratorTests : XCTestCase
@end

@implementation MPTextGeneratorTests

/// The first model in the application's own model folder, or nil.
- (NSURL *)installedModel
{
    NSArray<NSString *> *support = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    if (!support.count)
        return nil;

    NSString *folder = [support[0]
        stringByAppendingPathComponent:@"MacDown/Models"];
    NSArray<NSString *> *names = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:folder error:NULL];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(compare:)])
    {
        if ([name.pathExtension.lowercaseString isEqualToString:@"gguf"])
        {
            return [NSURL fileURLWithPath:
                [folder stringByAppendingPathComponent:name]];
        }
    }
    return nil;
}


- (void)testAMissingFileIsRefusedWithAReason
{
    NSError *error = nil;
    MPLlamaGenerator *generator = [[MPLlamaGenerator alloc]
        initWithModelURL:[NSURL fileURLWithPath:@"/tmp/non-esiste.gguf"]
                   error:&error];

    XCTAssertNil(generator);
    XCTAssertEqualObjects(error.domain, MPTextGeneratorErrorDomain);
    XCTAssertEqual(error.code, MPTextGeneratorErrorNoModel);
    XCTAssertTrue(error.localizedDescription.length > 0,
                  @"un errore senza spiegazione non serve a nessuno");
}

- (void)testSomethingThatIsNotAModelIsRefused
{
    NSString *path = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"finto.gguf"];
    [@"non sono un modello" writeToFile:path atomically:YES
                              encoding:NSUTF8StringEncoding error:NULL];

    NSError *error = nil;
    MPLlamaGenerator *generator = [[MPLlamaGenerator alloc]
        initWithModelURL:[NSURL fileURLWithPath:path] error:&error];

    XCTAssertNil(generator);
    XCTAssertEqual(error.code, MPTextGeneratorErrorLoadFailed);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (void)testARemoteURLIsNotAModelPath
{
    NSError *error = nil;
    XCTAssertNil([[MPLlamaGenerator alloc]
        initWithModelURL:[NSURL URLWithString:@"https://esempio.it/m.gguf"]
                   error:&error]);
    XCTAssertEqual(error.code, MPTextGeneratorErrorNoModel);
}

/// End to end, when there is something to run.
- (void)testRewritesASentence
{
    NSURL *model = [self installedModel];
    if (!model)
    {
        XCTSkip(@"Nessun .gguf in Application Support/MacDown/Models: "
                @"la generazione vera si prova quando ce n'e uno.");
    }

    NSError *error = nil;
    MPLlamaGenerator *generator =
        [[MPLlamaGenerator alloc] initWithModelURL:model error:&error];
    XCTAssertNotNil(generator, @"%@", error);
    XCTAssertTrue(generator.isAvailable);

    NSString *expected =
        model.lastPathComponent.stringByDeletingPathExtension;
    XCTAssertEqualObjects(generator.displayName, expected);

    generator.temperature = 0.0f;    // la stessa risposta ogni volta
    generator.maximumTokens = 80;

    XCTestExpectation *finished = [self expectationWithDescription:@"generato"];
    NSMutableString *answer = [NSMutableString string];
    [generator generateWithInstruction:
        @"Riscrivi il testo in italiano, in tono formale. Rispondi solo col "
        @"testo riscritto."
                                onText:@"Il collaudo e andato bene."
                               onChunk:^(NSString *piece) {
        XCTAssertTrue([NSThread isMainThread], @"i pezzi arrivano sul main");
        [answer appendString:piece];
    } completion:^(NSError *failure) {
        XCTAssertNil(failure, @"%@", failure);
        [finished fulfill];
    }];

    [self waitForExpectationsWithTimeout:120.0 handler:nil];
    XCTAssertTrue(answer.length > 0, @"qualcosa deve pure uscirne");
    XCTAssertEqual([answer rangeOfString:@"<|im_"].location,
                   (NSUInteger)NSNotFound,
                   @"nessun marcatore del template nel testo");
}

@end
