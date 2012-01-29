//
//  RRAlbum.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-29.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "Renren.h"

@implementation RRAlbum

@synthesize aid = _aid;
@synthesize uid = _uid;
@synthesize name = _name;
@synthesize cover = _cover;
@synthesize createTime = _createTime;
@synthesize updateTime = _updateTime;
@synthesize description = _description;
@synthesize location = _location;
@synthesize visible = _visible;

@synthesize photos = _photos;

@synthesize infoLastUpdated = _infoLastUpdated;
@synthesize photosLastUpdated = _photosLastUpdated;

- (id)initWithDictionary:(NSDictionary *)data
{
    if (self = [super init]) {
        if (! [self updateWithDictionary:data])
            self = nil;
        _photos = nil;
        _photosLastUpdated = nil;
    }
    return self;
}

- (BOOL)updateWithDictionary:(NSDictionary *)data
{
    NSNumber *aid = [data valueForKey:@"aid"];
    NSNumber *uid = [data valueForKey:@"uid"];
    NSString *name = [data valueForKey:@"name"];
    NSString *coverURL = [data valueForKey:@"url"];
    NSString *createTime = [data valueForKey:@"create_time"];
    NSString *updateTime = [data valueForKey:@"update_time"];
    NSString *description = [data valueForKey:@"description"];
    NSString *location = [data valueForKey:@"location"];
    NSNumber *visible = [data valueForKey:@"visible"];
    if (! aid || ! uid || ! name || ! coverURL || 
        ! createTime || ! updateTime || ! description || 
        ! location || ! visible)
        return NO;
    
    _aid = aid;
    _uid = uid;
    _name = name;
    _cover = [NSURL URLWithString:coverURL];
    _createTime = [NSDate dateWithRenrenString:createTime];
    _updateTime = [NSDate dateWithRenrenString:updateTime];
    _description = description;
    _location = location;
    _visible = [visible intValue];
    _infoLastUpdated = [NSDate date];
    return YES;
}

- (void)updatePhotos:(NSSet *)photos
{
    _photos = photos;
    _photosLastUpdated = [NSDate date];
}

@end
