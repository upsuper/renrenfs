//
//  RenrenFS.h
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kAPIKey;
extern NSString * const kSecretKey;

@interface RenrenFS : NSObject {
    NSString *accessToken_;
    long uid_;
    NSString *name_;
    NSSet *friends_;
    
    NSMutableDictionary *baseCache_;
    NSMutableDictionary *countCache_;
    NSMutableDictionary *albumsCache_;
    NSMutableDictionary *photosCache_;
    
    NSString *cacheDir_;
    NSString *photosCacheDir_;
}

@property (readonly) long uid;
@property (readonly) NSString *name;

- (id)initWithAccessToken:(NSString *)accessToken cacheDir:(NSString *)cacheDir;

@end
