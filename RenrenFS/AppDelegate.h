//
//  AppDelegate.h
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@class GMUserFileSystem;
@class RRConnection;
@class RenrenFS;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    GMUserFileSystem *_fs;
    RRConnection *_conn;
    RenrenFS *_rrfs;
}

@property (assign) IBOutlet NSWindow *window;
@property (weak) IBOutlet WebView *webView;

@end
