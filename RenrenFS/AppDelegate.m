//
//  AppDelegate.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "AppDelegate.h"
#import "Renren.h"
#import "RenrenFS.h"
#import <OSXFUSE/OSXFUSE.h>
#import <WebKit/WebKit.h>
#import "NSDictionary+QueryBuilder.h"

static NSString * const RRCallbackURL = 
    @"http://graph.renren.com/oauth/login_success.html";

NSString * const RRFSApiKey = @"e66f8c48f1eb40409d10041968abbb6a";
NSString * const RRFSSecretKey = @"e46c3a125106408fb02e08e02ffb398e";

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
    NSString *callbackPath = [[NSURL URLWithString:RRCallbackURL] path];
    if ([[currentURL path] isEqualToString:callbackPath]) {
        NSString *fragment = [currentURL fragment];
        NSDictionary *response = [NSDictionary 
                                  dictionaryWithQueryString:fragment];
        NSString *accessToken = [response valueForKey:@"access_token"];
        NSLog(@"scope: %@", [response valueForKey:@"scope"]);
        
        _conn = [[RRConnection alloc] initWithAccessToken:accessToken 
                                                   secret:RRFSSecretKey];
        _rrfs = [[RenrenFS alloc] initWithConnection:_conn 
                                            cacheDir:@"/tmp/renrenfs"];
        NSString *volname = [NSString stringWithFormat:@"%@'s RenrenFS", 
                             [[_conn user] name]];
        _fs = [[GMUserFileSystem alloc] initWithDelegate:_rrfs isThreadSafe:NO];
        NSMutableArray *options = [NSMutableArray array];
        [options addObject:[NSString stringWithFormat:@"volname=%@", volname]];
        [_fs mountAtPath:
         [NSString stringWithFormat:@"/Volumes/Renren_%@", [[_conn user] uid]] 
             withOptions:options];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(didMount:) 
                   name:kGMUserFileSystemDidMount object:nil];
    [center addObserver:self selector:@selector(didUnmount:) 
                   name:kGMUserFileSystemDidUnmount object:nil];
    
    NSDictionary *authorizeQuery = 
        [NSDictionary dictionaryWithObjectsAndKeys:
         RRFSApiKey, @"client_id",
         RRCallbackURL, @"redirect_uri",
         @"token", @"response_type",
         @"read_user_album read_user_photo", @"scope", 
         nil];
    NSString *authorizeURL = [NSString stringWithFormat:@"%@?%@", 
                              @"https://graph.renren.com/oauth/authorize",
                              [authorizeQuery buildQueryString]];
    [[_webView mainFrame] loadRequest:[NSURLRequest requestWithURL:
                                       [NSURL URLWithString:authorizeURL]]];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
        (NSApplication *)sender 
{
    [_fs unmount];
    return NSTerminateNow;
}

@end
