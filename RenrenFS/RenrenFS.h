//
//  RenrenFS.h
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RRConnection;

@interface RenrenFS : NSObject {
    RRConnection *_conn;    
    NSString *_cacheDir;
    NSString *_headsCacheDir;
    NSString *_coversCacheDir;
    NSString *_photosCacheDir;
}

- (id)initWithConnection:(RRConnection *)conn cacheDir:(NSString *)cacheDir;

@end
