//
//  RRPhoto.h
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-29.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RRPhoto : NSObject {
    NSNumber *_pid;
    NSNumber *_aid;
    NSNumber *_uid;
    NSURL *_url;
    NSString *_caption;
    NSDate *_time;
    
    NSDate *_lastUpdated;
}

@property (readonly) NSNumber *pid;
@property (readonly) NSNumber *aid;
@property (readonly) NSNumber *uid;
@property (readonly) NSURL *url;
@property (readonly) NSString *caption;
@property (readonly) NSDate *time;

@property (readonly) NSDate *lastUpdated;

- (id)initWithDictionary:(NSDictionary *)data;
- (BOOL)updateWithDictionary:(NSDictionary *)data;

@end
