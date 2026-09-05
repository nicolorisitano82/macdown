//
//  MPExporterPlugInTests.m
//  MacDown
//

#import <XCTest/XCTest.h>
#import "MPPlugIn.h"
#import "MPExporterPlugIn.h"


/// A plug-in that adds a format: what a real one would look like, minus the
/// bundle around it.
@interface MPFakeExporter : NSObject <MPExporterPlugIn>
@property (copy) NSString *lastHTML;
@property (copy) NSString *lastMarkdown;
@property (strong) NSURL *lastURL;
@property (assign) BOOL refuse;
@end

@implementation MPFakeExporter

- (NSString *)exportFormatName { return @"LaTeX"; }
- (NSString *)exportFileExtension { return @"tex"; }
- (NSString *)exportFormatDescription { return @"Per chi compone in TeX"; }

- (NSData *)exportDataFromHTML:(NSString *)html markdown:(NSString *)markdown
                       fileURL:(NSURL *)fileURL error:(NSError **)error
{
    self.lastHTML = html;
    self.lastMarkdown = markdown;
    self.lastURL = fileURL;
    if (self.refuse)
        return nil;
    return [@"\\documentclass{article}" dataUsingEncoding:NSUTF8StringEncoding];
}

@end


/// A plug-in of the ordinary kind: a command, and nothing to export.
@interface MPFakeCommand : NSObject
- (BOOL)run:(id)sender;
@end

@implementation MPFakeCommand
- (BOOL)run:(id)sender { return YES; }
@end


/// One that answers nothing when asked what it is called.
@interface MPNamelessExporter : NSObject <MPExporterPlugIn>
@end

@implementation MPNamelessExporter
- (NSString *)exportFormatName { return nil; }
- (NSString *)exportFileExtension { return @"bin"; }
- (NSData *)exportDataFromHTML:(NSString *)html markdown:(NSString *)markdown
                       fileURL:(NSURL *)fileURL error:(NSError **)error
{
    return [NSData data];
}
@end


@interface MPExporterPlugInTests : XCTestCase
@end


@implementation MPExporterPlugInTests

- (MPPlugIn *)plugInAround:(id)content
{
    return [[MPPlugIn alloc] initWithContent:content name:@"Prova"
                                  identifier:@"it.esempio.prova"];
}


- (void)testAnExporterIsRecognisedAsOne
{
    MPPlugIn *plugin = [self plugInAround:[[MPFakeExporter alloc] init]];
    XCTAssertTrue(plugin.isExporter);
    XCTAssertEqualObjects(plugin.exportFormatName, @"LaTeX");
    XCTAssertEqualObjects(plugin.exportFileExtension, @"tex");
    XCTAssertEqualObjects(plugin.exportFormatDescription,
                          @"Per chi compone in TeX");
}

- (void)testAnOrdinaryPlugInIsNotAnExporter
{
    MPPlugIn *plugin = [self plugInAround:[[MPFakeCommand alloc] init]];
    XCTAssertFalse(plugin.isExporter);
    // And it answers nothing rather than something wrong.
    XCTAssertNil(plugin.exportFormatName);
    XCTAssertNil(plugin.exportFileExtension);
    XCTAssertNil(plugin.exportFormatDescription);
    XCTAssertNil([plugin exportDataFromHTML:@"<p>x</p>" markdown:@"x"
                                    fileURL:nil error:NULL]);
}

- (void)testTheDocumentIsHandedOverRendered
{
    MPFakeExporter *content = [[MPFakeExporter alloc] init];
    MPPlugIn *plugin = [self plugInAround:content];
    NSURL *file = [NSURL fileURLWithPath:@"/tmp/verbale.md"];

    NSError *error = nil;
    NSData *data = [plugin exportDataFromHTML:@"<h1>Verbale</h1>"
                                     markdown:@"# Verbale\n"
                                      fileURL:file error:&error];

    XCTAssertGreaterThan(data.length, 0u);
    XCTAssertNil(error);
    XCTAssertEqualObjects(content.lastHTML, @"<h1>Verbale</h1>");
    XCTAssertEqualObjects(content.lastMarkdown, @"# Verbale\n");
    XCTAssertEqualObjects(content.lastURL, file);
}

- (void)testAnExporterThatRefusesSaysSoWithNothing
{
    MPFakeExporter *content = [[MPFakeExporter alloc] init];
    content.refuse = YES;
    MPPlugIn *plugin = [self plugInAround:content];

    XCTAssertNil([plugin exportDataFromHTML:@"<p>x</p>" markdown:@"x"
                                    fileURL:nil error:NULL]);
}

- (void)testAFormatWithNoNameFallsBackToThePlugInsOwn
{
    // A bundle whose exporter forgets the name is still worth an item, and
    // the plug-in's name is what everything else calls it.
    id content = [[MPFakeExporter alloc] init];
    MPPlugIn *plugin = [[MPPlugIn alloc] initWithContent:content
        name:@"Il mio esportatore" identifier:@"it.esempio.senza-nome"];
    XCTAssertEqualObjects(plugin.exportFormatName, @"LaTeX");

    // And when it really answers nothing, the plug-in's name stands in.
    MPPlugIn *nameless = [[MPPlugIn alloc]
        initWithContent:[[MPNamelessExporter alloc] init]
                   name:@"Il mio esportatore" identifier:@"it.esempio.x"];
    XCTAssertEqualObjects(nameless.exportFormatName, @"Il mio esportatore");
}

@end
