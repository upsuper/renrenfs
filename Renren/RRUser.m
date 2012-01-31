//
//  RRUser.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-28.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "RRUser.h"

@implementation RRUser

@synthesize uid = _uid;
@synthesize name = _name;
@synthesize gender = _gender;
@synthesize tinyHeadURL = _tinyHeadURL;

@synthesize blogsCount = _blogsCount;
@synthesize albumsCount = _albumsCount;
@synthesize friendsCount = _friendsCount;

@synthesize blogs = _blogs;
@synthesize albums = _albums;

@synthesize baseLastUpdated = _baseLastUpdated;
@synthesize additionLastUpdated = _additionLastUpdated;
@synthesize blogsLastUpdated = _blogsLastUpdated;
@synthesize albumsLastUpdated = _albumsLastUpdated;

- (id)initWithDictionary:(NSDictionary *)data
{
    if (self = [super init]) {
        if (! [self updateBaseInfoWithDictionary:data])
            self = nil;
        if (! [self updateAdditionInfoWithDictionary:data]) {
            _blogsCount = _albumsCount = _friendsCount = 0;
            _additionLastUpdated = nil;
        }
        _blogs = _albums = nil;
        _blogsLastUpdated = _albumsLastUpdated = nil;
    }
    return self;
}

- (BOOL)updateBaseInfoWithDictionary:(NSDictionary *)data
{
    NSNumber *uid = [data valueForKey:@"uid"];
    if (! uid)
        uid = [data valueForKey:@"id"];
    NSString *name = [data valueForKey:@"name"];
    NSNumber *gender = [data valueForKey:@"sex"];
    if (! gender)
        gender = [[data valueForKey:@"base_info"] valueForKey:@"gender"];
    NSString *headurl = [data valueForKey:@"tinyurl"];
    if (! headurl)
        headurl = [data valueForKey:@"headurl"];
    if (! uid || ! name || ! gender | ! headurl)
        return NO;
        
    _uid = uid;
    _name = name;
    _gender = [gender intValue];
    _tinyHeadURL = [NSURL URLWithString:headurl];
    _baseLastUpdated = [NSDate date];
    return YES;
}

- (BOOL)updateAdditionInfoWithDictionary:(NSDictionary *)data
{
    NSNumber *blogsCount = [data valueForKey:@"blogs_count"];    
    NSNumber *albumsCount = [data valueForKey:@"albums_count"];
    NSNumber *friendsCount = [data valueForKey:@"friends_count"];
    if (! blogsCount || ! albumsCount || ! friendsCount)
        return NO;
    
    _blogsCount = [blogsCount unsignedIntegerValue];
    _albumsCount = [albumsCount unsignedIntegerValue];
    _friendsCount = [friendsCount unsignedIntegerValue];
    _additionLastUpdated = [NSDate date];
    return YES;
}

- (BOOL)isAdditionInfoExists
{
    return _additionLastUpdated != nil;
}

- (void)updateBlogs:(NSSet *)blogs
{
    _blogs = blogs;
    _blogsLastUpdated = [NSDate date];
}

- (void)updateAlbums:(NSSet *)albums
{
    _albums = albums;
    _albumsLastUpdated = [NSDate date];
}

@end
