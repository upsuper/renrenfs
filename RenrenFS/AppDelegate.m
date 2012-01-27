//
//  AppDelegate.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "AppDelegate.h"
#import "RenrenFS.h"
#import <OSXFUSE/OSXFUSE.h>
#import <WebKit/WebKit.h>
#import "NSDictionary+QueryBuilder.h"

static NSString * const kCallbackURI = @"http://graph.renren.com/oauth/login_success.html";

@implementation AppDelegate

@synthesize window = _window;
@synthesize webView = _webView;

- (void)didMount:(NSNotification *)notification 
{
    NSDictionary *userInfo = [notification userInfo];
    NSString *mountPath = [userInfo objectForKey:kGMUserFileSystemMountPathKey];
    NSString *parentPath = [mountPath stringByDeletingLastPathComponent];
    [[NSWorkspace sharedWorkspace] selectFile:mountPath 
                     inFileViewerRootedAtPath:parentPath];
}

- (void)didUnmount:(NSNotification *)notification 
{
    [[NSApplication sharedApplication] terminate:nil];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    NSURL *currentURL = [[[frame dataSource] request] URL];
    NSString *callbackPath = [[NSURL URLWithString:kCallbackURI] path];
    if ([[currentURL path] isEqualToString:callbackPath]) {
        NSString *fragment = [currentURL fragment];
        NSDictionary *response = [NSDictionary dictionaryWithQueryString:fragment];
        NSString *accessToken = [response valueForKey:@"access_token"];
        NSLog(@"scope: %@", [response valueForKey:@"scope"]);
        
        renren_ = [[RenrenFS alloc] initWithAccessToken:accessToken 
                                               cacheDir:@"/tmp/renrenfs"];
        fs_ = [[GMUserFileSystem alloc] initWithDelegate:renren_ isThreadSafe:NO];
        NSMutableArray *options = [NSMutableArray array];
        [options addObject:@"volname=RenrenFS"];
        [fs_ mountAtPath:@"/Volumes/Renren" withOptions:options];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(didMount:) 
                   name:kGMUserFileSystemDidMount object:nil];
    [center addObserver:self selector:@selector(didUnmount:) 
                   name:kGMUserFileSystemDidUnmount object:nil];
    
    NSDictionary *authorizeQuery = [NSDictionary dictionaryWithObjectsAndKeys:
                                    kAPIKey, @"client_id",
                                    kCallbackURI, @"redirect_uri",
                                    @"token", @"response_type",
                                    @"read_user_blog read_user_album read_user_photo", @"scope", 
                                    nil];
    NSString *authorizeURL = [NSString stringWithFormat:@"%@?%@", 
                              @"https://graph.renren.com/oauth/authorize",
                              [authorizeQuery buildQueryString]];
    [[_webView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:authorizeURL]]];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender 
{
    [fs_ unmount];
    return NSTerminateNow;
}

@end
