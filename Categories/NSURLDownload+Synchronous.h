//
//  NSURLDownload+Synchronous.h
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-26.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSURLDownload (Synchronous)

+ (BOOL)sendSynchoronousRequest:(NSURLRequest *)request 
                         saveTo:(NSString *)path error:(NSError **)error;

@end
