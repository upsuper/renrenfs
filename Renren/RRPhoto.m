//
//  RRPhoto.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-29.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "Renren.h"

@implementation RRPhoto

@synthesize pid = _pid;
@synthesize aid = _aid;
@synthesize uid = _uid;
@synthesize url = _url;
@synthesize caption = _caption;
@synthesize time = _time;

@synthesize lastUpdated = _lastUpdated;

- (id)initWithDictionary:(NSDictionary *)data
{
    if (self = [super init]) {
        if (! [self updateWithDictionary:data])
            self = nil;
    }
    return self;
}

- (BOOL)updateWithDictionary:(NSDictionary *)data
{
    NSNumber *pid = [data valueForKey:@"pid"];
    NSNumber *aid = [data valueForKey:@"aid"];
    NSNumber *uid = [data valueForKey:@"uid"];
    NSString *url = [data valueForKey:@"url_large"];
    NSString *caption = [data valueForKey:@"caption"];
    NSString *time = [data valueForKey:@"time"];
    if (! pid || ! aid || ! uid || ! url || ! caption || ! time)
        return NO;
    
    _pid = pid;
    _aid = aid;
    _uid = uid;
    _url = [NSURL URLWithString:url];
    _caption = caption;
    _time = [NSDate dateWithRenrenString:time];
    _lastUpdated = [NSDate date];
    return YES;
}

@end
