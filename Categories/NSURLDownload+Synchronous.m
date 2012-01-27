//
//  NSURLDownload+Synchronous.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-26.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "NSURLDownload+Synchronous.h"

@interface DownloadDelegate : NSObject <NSURLDownloadDelegate> {
    NSString *path_;
    NSError *error_;
}

@property (readonly) NSError *error;

- (id)initWithPath:(NSString *)path;

@end

@implementation DownloadDelegate

@synthesize error = error_;

- (id)initWithPath:(NSString *)path
{
    if (self = [super init]) {
        path_ = path;
        error_ = nil;
    }
    return self;
}

- (void)download:(NSURLDownload *)download decideDestinationWithSuggestedFilename:(NSString *)filename
{
    [download setDestination:path_ allowOverwrite:YES];
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    error_ = error;
    CFRunLoopStop(CFRunLoopGetCurrent());
}

@end

@implementation NSURLDownload (Synchronous)

+ (BOOL)sendSynchoronousRequest:(NSURLRequest *)request 
                         saveTo:(NSString *)path 
                          error:(NSError *__autoreleasing *)error
{
    DownloadDelegate *delegate = [[DownloadDelegate alloc] initWithPath:path];
    NSURLDownload *download = [[NSURLDownload alloc] initWithRequest:request 
                                                            delegate:delegate];
    BOOL result = NO;
    if (download) {
        [[NSRunLoop currentRunLoop] run];
        *error = [delegate error];
        result = ! *error;
    }
    return result;
}

@end
