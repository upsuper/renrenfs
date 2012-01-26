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
@class RenrenFS;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    GMUserFileSystem *fs_;
    RenrenFS *renren_;
}

@property (assign) IBOutlet NSWindow *window;
@property (weak) IBOutlet WebView *webView;

@end
