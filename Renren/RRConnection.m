//
//  RRConnection.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-28.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "Renren.h"
#import "NSString+MD5.h"
#import "NSDictionary+QueryBuilder.h"

static NSURL *RRApiUrl;

@interface RRConnection (Private)

- (id)requestAPI:(NSString *)method withParams:(NSDictionary *)params;

@end

@implementation RRConnection

@synthesize user = _user;

+ (void)initialize
{
    if (self == [RRConnection class]) {
        RRApiUrl = [NSURL URLWithString:@"http://api.renren.com/restserver.do"];
    }
}

- (id)initWithAccessToken:(NSString *)accessToken secret:(NSString *)secret
{
    if (self = [super init]) {
        _accessToken = accessToken;
        _secret = secret;
        _uid = [[self requestAPI:@"users.getLoggedInUser" withParams:nil] 
                valueForKey:@"uid"];
        _user = [self user:_uid];
        
        _users = [NSMutableDictionary dictionary];
        _albums = [NSMutableDictionary dictionary];
        _photos = [NSMutableDictionary dictionary];
    }
    return self;
}

- (id)requestAPI:(NSString *)method withParams:(NSDictionary *)params
{
    NSLog(@"Request: %@ %@", method, params);
    // 构造请求内容
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    [query setValuesForKeysWithDictionary:params];
    [query setObject:method forKey:@"method"];
    [query setObject:@"1.0" forKey:@"v"];
    [query setObject:_accessToken forKey:@"access_token"];
    [query setObject:@"JSON" forKey:@"format"];
    
    // 生成签名
    NSMutableArray *sigArray = [NSMutableArray array];
    for (NSString *key in query) {
        id value = [query valueForKey:key];
        [sigArray addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    }
    [sigArray sortUsingSelector:@selector(compare:)];
    [sigArray addObject:_secret];
    NSString *sig = [[sigArray componentsJoinedByString:@""] md5];
    [query setObject:sig forKey:@"sig"];
    
    // 构造请求对象
    NSMutableURLRequest *request = [NSMutableURLRequest 
                                    requestWithURL:RRApiUrl];
    [request setHTTPMethod:@"POST"];
    [request setHTTPShouldHandleCookies:NO];
    NSString *queryStr = [query buildQueryString];
    [request setHTTPBody:[queryStr dataUsingEncoding:NSUTF8StringEncoding]];
    [request setValue:@"application/x-www-form-urlencoded"
             forHTTPHeaderField:@"Content-Type"];
    
    // 同步请求数据
    NSURLResponse *response;
    NSError *error;
    NSData *rawData = [NSURLConnection sendSynchronousRequest:request
                                            returningResponse:&response
                                                        error:&error];
    
    // 解码数据并返回
    id data = [NSJSONSerialization JSONObjectWithData:rawData 
                                              options:0 error:nil];
    NSLog(@"Result: %@", data);
    return data;
}

- (RRUser *)user:(NSNumber *)uid
{
    return [self user:uid forceUpdate:NO];
}

- (RRUser *)user:(NSNumber *)uid forceUpdate:(BOOL)forceUpdate
{
    RRUser *user = [_users objectForKey:uid];
    if (forceUpdate || ! user) {
        NSString *fields = [[NSArray arrayWithObjects:
                             @"base_info", @"blogs_count", 
                             @"albums_count", @"friends_count", nil]
                            componentsJoinedByString:@","];
        NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                uid, @"uid", fields, @"fields", nil];
        id data = [self requestAPI:@"users.getProfileInfo" withParams:params];
        if (! user) {
            user = [[RRUser alloc] initWithDictionary:data];
            [_users setObject:user forKey:uid];
        }
        else {
            [user updateBaseInfoWithDictionary:data];
            [user updateAdditionInfoWithDictionary:data];
        }
    }
    return user;
}

- (void)updateUsers:(NSArray *)users
{
    NSString *uids = [users componentsJoinedByString:@","];
    NSString *fields = [[NSArray arrayWithObjects:
                         @"uid", @"name", @"sex", @"tinyurl", @"headurl", nil] 
                        componentsJoinedByString:@","];
    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                            uids, @"uids", fields, @"fields", nil];
    id data = [self requestAPI:@"users.getInfo" withParams:params];
    for (NSDictionary *item in data) {
        NSNumber *uid = [item valueForKey:@"uid"];
        RRUser *user = [_users objectForKey:uid];
        if (user) {
            [user updateBaseInfoWithDictionary:item];
        }
        else {
            user = [[RRUser alloc] initWithDictionary:item];
            [_users setObject:user forKey:uid];
        }
    }
}

- (NSSet *)friends
{
    NSSet *friends = _friends;
    if (! friends) {
        NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"2000", @"count", nil];
        id data = [self requestAPI:@"friends.getFriends" withParams:params];
        NSMutableSet *friends_ = [NSMutableSet setWithCapacity:[data count]];
        for (NSDictionary *item in data) {
            NSNumber *uid = [item valueForKey:@"id"];
            RRUser *user = [_users objectForKey:uid];
            if (user) {
                [user updateBaseInfoWithDictionary:item];
            }
            else {
                user = [[RRUser alloc] initWithDictionary:item];
                [_users setObject:user forKey:uid];
            }
            [friends_ addObject:uid];
        }
        friends = [NSSet setWithSet:friends_];
        _friends = friends;
        _friendsLastUpdated = [NSDate date];
    }
    return friends;
}

- (NSSet *)visitors
{
    NSSet *visitors = _visitors;
    if (! visitors) {
        NSDictionary *params = [NSDictionary 
                                dictionaryWithObject:@"20" forKey:@"count"];
        id data = [self requestAPI:@"users.getVisitors" withParams:params];
        data = [data valueForKey:@"visitors"];
        NSMutableSet *visitors_ = [NSMutableSet setWithCapacity:[data count]];
        NSMutableArray *needUpdate = [NSMutableArray array];
        for (NSDictionary *item in data) {
            NSNumber *uid = [item valueForKey:@"uid"];
            RRUser *user = [_users objectForKey:uid];
            if (! user)
                [needUpdate addObject:uid];
            [visitors_ addObject:uid];
        }
        if ([needUpdate count] > 0)
            [self updateUsers:needUpdate];
        visitors = [NSSet setWithSet:visitors_];
        _visitors = visitors;
        _visitorsLastUpdated = [NSDate date];
    }
    return visitors;
}

- (RRAlbum *)album:(NSNumber *)aid
{
    RRAlbum *album = [_albums objectForKey:aid];
    return album;
}

- (NSSet *)albumsOfUser:(RRUser *)user
{
    NSSet *albums = [user albums];
    if (! albums) {
        NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                [user uid], @"uid", @"1000", @"count", nil];
        id data = [self requestAPI:@"photos.getAlbums" withParams:params];
        NSMutableSet *albums_ = [NSMutableSet setWithCapacity:[data count]];
        for (NSDictionary *item in data) {
            NSNumber *aid = [item valueForKey:@"aid"];
            RRAlbum *album = [self album:aid];
            if (album) {
                [album updateWithDictionary:item];
            }
            else {
                album = [[RRAlbum alloc] initWithDictionary:item];
                [_albums setObject:album forKey:aid];
            }
            [albums_ addObject:aid];
        }
        albums = [NSSet setWithSet:albums_];
        [user updateAlbums:albums];
    }
    return albums;
}

- (RRPhoto *)photo:(NSNumber *)pid
{
    RRPhoto *photo = [_photos objectForKey:pid];
    return photo;
}

- (NSSet *)photosOfAlbum:(RRAlbum *)album
{
    NSSet *photos = [album photos];
    if (! photos) {
        NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                [album uid], @"uid", [album aid], @"aid",
                                @"200", @"count", nil];
        id data = [self requestAPI:@"photos.get" withParams:params];
        NSMutableSet *photos_ = [NSMutableSet setWithCapacity:[data count]];
        for (NSDictionary *item in data) {
            NSNumber *pid = [item valueForKey:@"pid"];
            RRPhoto *photo = [self photo:pid];
            if (photo) {
                [photo updateWithDictionary:item];
            }
            else {
                photo = [[RRPhoto alloc] initWithDictionary:item];
                [_photos setObject:photo forKey:pid];
            }
            [photos_ addObject:pid];
        }
        photos = [NSSet setWithSet:photos_];
        [album updatePhotos:photos];
    }
    return photos;
}

@end
