//
//  MPPlugIn.m
//  MacDown
//
//  Created by Tzu-ping Chung on 02/3.
//  Copyright © 2016 Tzu-ping Chung . All rights reserved.
//

#import "MPPlugIn.h"


@interface MPPlugIn ()
@property (nonatomic) id content;
@end


@implementation MPPlugIn

- (void)setName:(NSString *)name
{
    _name = name;
}

- (void)setIdentifier:(NSString *)identifier
{
    _identifier = identifier;
}

- (void)setVersion:(NSString *)version
{
    _version = version;
}

- (void)setBundleURL:(NSURL *)bundleURL
{
    _bundleURL = bundleURL;
}

- (instancetype)initWithBundle:(NSBundle *)bundle
{
    self = [super init];
    if (!self)
        return nil;

    if (!bundle.isLoaded)
    {
        NSError *e = nil;
        BOOL ok = [bundle loadAndReturnError:&e];
        if (!ok)
            return nil;
    }
    Class plugInClass = bundle.principalClass;
    if (!plugInClass)
        return nil;
    self.content = [[plugInClass alloc] init];

    if ([self.content respondsToSelector:@selector(name)])
        self.name = [self.content name];
    if (!self.name)
    {
        NSURL *url = bundle.bundleURL;
        self.name = url.lastPathComponent.stringByDeletingPathExtension;
    }

    self.bundleURL = bundle.bundleURL;
    self.version = bundle.infoDictionary[@"CFBundleShortVersionString"];

    // The identifier is what the disabled list is keyed on, so it has to
    // exist even for a bundle that declares none: the file name is stable
    // enough, and is what such a plug-in is called in the menu anyway.
    NSString *identifier = bundle.bundleIdentifier;
    if (!identifier.length)
    {
        identifier = bundle.bundleURL.lastPathComponent
            .stringByDeletingPathExtension;
    }
    self.identifier = identifier;

    return self;
}

- (void)plugInDidInitialize
{
    if ([self.content respondsToSelector:@selector(plugInDidInitialize)])
        [self.content plugInDidInitialize];
}

- (BOOL)run:(id)sender
{
    if ([self.content respondsToSelector:@selector(run:)])
        return [self.content run:sender];
    return NO;
}

@end
