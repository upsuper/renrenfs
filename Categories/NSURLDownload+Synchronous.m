//
//  NSURLDownload+Synchronous.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-26.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "NSURLDownload+Synchronous.h"

@interface DownloadDelegate : NSObject <NSURLDownloadDelegate> {
    NSString *_path;
    NSError *_error;
}

@property (readonly) NSError *error;

- (id)initWithPath:(NSString *)path;

@end

@implementation DownloadDelegate

@synthesize error = _error;

- (id)initWithPath:(NSString *)path
{
    if (self = [super init]) {
        _path = path;
        _error = nil;
    }
    return self;
}

- (void)download:(NSURLDownload *)download decideDestinationWithSuggestedFilename:(NSString *)filename
{
    [download setDestination:_path allowOverwrite:YES];
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
    CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
    _error = error;
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
        if (error)
            *error = [delegate error];
        if (! [delegate error])
            result = YES;
    }
    return result;
}

@end
