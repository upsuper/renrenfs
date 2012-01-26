//
//  RenrenFS.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <errno.h>
#import "RenrenFS.h"
#import <OSXFUSE/OSXFUSE.h>
#import <SBJson/SBJson.h>
#import "NSError+POSIX.h"
#import "NSString+MD5.h"
#import "NSDictionary+QueryBuilder.h"
#import "NSString+EscapeQuotes.h"

NSString * const kAPIKey = @"e66f8c48f1eb40409d10041968abbb6a";
NSString * const kSecretKey = @"e46c3a125106408fb02e08e02ffb398e";

static NSString * const kRenrenApi = @"http://api.renren.com/restserver.do";

static NSString * const TYPE = @"type";
static NSString * const UID = @"uid";
static NSString * const AID = @"aid";
static NSString * const PID = @"pid";
static NSString * const LOCALIZED = @"localized";
static NSString * const ORIGTYPE = @"orig_type";

@interface RenrenFS ( Private )

- (id)requestApi:(NSString *)method withParams:(NSDictionary *)params;
- (NSDictionary *)getUserBaseInfo:(long)uid;
- (NSDictionary *)getUserCountInfo:(long)uid;
- (NSDictionary *)getUserAlbumsInfo:(long)uid;
- (NSDictionary *)getAlbumInfo:(long)aid ofUser:(long)uid;
- (NSDictionary *)getPhotos:(long)uid album:(long)aid;
- (NSDictionary *)parsePath:(NSString *)path;

- (NSString *)getLocalizedFileForUser:(long)uid;
- (NSString *)getLocalizedFileForAlbum:(long)aid ofUser:(long)uid;

@end

@implementation RenrenFS

- (id)initWithAccessToken:(NSString *)accessToken 
                 cacheDir:(NSString *)cacheDir
{
    if (self = [super init]) {
        accessToken_ = accessToken;
        cacheDir_ = cacheDir;
        baseCache_ = [NSMutableDictionary dictionary];
        countCache_ = [NSMutableDictionary dictionary];
        albumsCache_ = [NSMutableDictionary dictionary];
        
        uid_ = [[[self requestApi:@"users.getLoggedInUser" withParams:nil] 
                 valueForKey:@"uid"] integerValue];
        NSDictionary *params = [NSDictionary 
                                dictionaryWithObject:@"2000" forKey:@"count"];
        NSArray *friends = [self requestApi:@"friends.getFriends" withParams:params];
        NSMutableArray *friendIDs = [NSMutableArray arrayWithCapacity:[friends count]];
        for (NSDictionary *friend in friends) {
            NSNumber *uid = [friend valueForKey:@"id"];
            [friendIDs addObject:uid];
            NSDictionary *userItem = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [friend valueForKey:@"name"], @"name",
                                      [friend valueForKey:@"headurl"], @"head",
                                      [friend valueForKey:@"sex"], @"sex", 
                                      nil];
            [baseCache_ setObject:userItem forKey:uid];
        }
        friends_ = [NSSet setWithArray:friendIDs];
    }
    return self;
}

- (id)requestApi:(NSString *)method withParams:(NSDictionary *)params
{
    NSLog(@"request api: %@ %@", method, params);
    
    NSMutableURLRequest *request = [NSMutableURLRequest 
                                    requestWithURL:[NSURL URLWithString:kRenrenApi]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPShouldHandleCookies:NO];
    
    NSMutableDictionary *query = [NSMutableDictionary dictionaryWithDictionary:params];
    [query setObject:method forKey:@"method"];
    [query setObject:@"1.0" forKey:@"v"];
    [query setObject:accessToken_ forKey:@"access_token"];
    [query setObject:@"JSON" forKey:@"format"];
    
    NSMutableArray *sigArray = [NSMutableArray array];
    for (NSString *key in query) {
        id value = [query valueForKey:key];
        [sigArray addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    }
    [sigArray sortUsingSelector:@selector(compare:)];
    [sigArray addObject:kSecretKey];
    NSString *sig = [[sigArray componentsJoinedByString:@""] md5];
    [query setObject:sig forKey:@"sig"];
    
    NSString *dataStr = [query buildQueryString];
    [request setHTTPBody:[dataStr dataUsingEncoding:NSUTF8StringEncoding]];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    NSURLResponse *response;
    NSError *error;
    NSData *data = [NSURLConnection sendSynchronousRequest:request 
                                         returningResponse:&response error:&error];
    
    return [data JSONValue];
}

- (NSDictionary *)getUserBaseInfo:(long)uid
{
    NSNumber *uidKey = [NSNumber numberWithInteger:uid];
    NSDictionary *result = [baseCache_ objectForKey:uidKey];
    if (! result) {
        NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                uidKey, @"uid", @"base_info", @"fields", nil];
        NSDictionary *data = [self requestApi:@"users.getProfileInfo" 
                                   withParams:params];
        result = [NSDictionary dictionaryWithObjectsAndKeys:
                  [data valueForKey:@"name"], @"name",
                  [data valueForKey:@"headurl"], @"head",
                  [[data valueForKey:@"base_info"] valueForKey:@"gender"], @"sex",
                  nil];
        [baseCache_ setObject:result forKey:uidKey];
    }
    return result;
}

- (NSDictionary *)getUserCountInfo:(long)uid
{
    NSNumber *uidKey = [NSNumber numberWithInteger:uid];
    NSDictionary *result = [countCache_ objectForKey:uidKey];
    if (! result) {
        NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                uidKey, @"uid",
                                @"blogs_count,albums_count,friends_count", @"fields", 
                                nil];
        NSDictionary *data = [self requestApi:@"users.getProfileInfo" 
                                   withParams:params];
        result = [NSDictionary dictionaryWithObjectsAndKeys:
                  [data valueForKey:@"blogs_count"], @"blogs",
                  [data valueForKey:@"albums_count"], @"albums",
                  [data valueForKey:@"friends_count"], @"friends", 
                  nil];
        [countCache_ setObject:result forKey:uidKey];
    }
    return result;
}

- (NSDictionary *)getUserAlbumsInfo:(long)uid
{
    NSNumber *uidKey = [NSNumber numberWithInteger:uid];
    NSDictionary *result = [albumsCache_ objectForKey:uidKey];
    if (! result) {
        NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
                                uidKey, @"uid", @"1000", @"count", nil];
        NSDictionary *data = [self requestApi:@"photos.getAlbums" 
                                   withParams:params];
        NSMutableDictionary *albums = [NSMutableDictionary dictionary];
        for (NSDictionary *album in data) {
            [albums setObject:album forKey:[album valueForKey:@"aid"]];
        }
        result = [NSDictionary dictionaryWithDictionary:albums];
        [albumsCache_ setObject:result forKey:uidKey];
    }
    return result;
}

- (NSDictionary *)getAlbumInfo:(long)aid ofUser:(long)uid
{
    return [[self getUserAlbumsInfo:uid] 
            objectForKey:[NSNumber numberWithInteger:aid]];
}

- (NSDictionary *)getPhotos:(long)uid album:(long)aid
{
    return nil;
}

- (NSDictionary *)parsePath:(NSString *)path
{
    NSArray *pathComponents = [path componentsSeparatedByString:@"/"];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:@"user" forKey:TYPE];
    [result setObject:[NSNumber numberWithInteger:uid_] forKey:UID];
    [result setObject:[NSNumber numberWithBool:NO] forKey:LOCALIZED];
    
    for (NSString *component in pathComponents) {
        NSUInteger length = [component length];
        if (length == 0)
            continue;
        BOOL isLocalized = NO;
        NSString *fileName = component;
        if (length > 10 && [fileName hasSuffix:@".localized"]) {
            isLocalized = YES;
            fileName = [fileName substringToIndex:length - 10];
        }
        
        NSString *currentType = [result valueForKey:TYPE];
        if ([currentType isEqualToString:@"user"]) {
            if ([fileName isEqualToString:@"Friends"]) {
                if ([[result valueForKey:@"uid"] integerValue] != uid_) {
                    result = nil;
                }
                else {
                    [result setObject:@"friends" forKey:TYPE];
                }
            }
            else if ([fileName isEqualToString:@"Photos"]) {
                [result setObject:@"photos" forKey:TYPE];
            }
            else if ([fileName isEqualToString:@".localized"] && 
                     [[result valueForKey:LOCALIZED] boolValue]) {
                [result setObject:currentType forKey:ORIGTYPE];
                [result setObject:@"localize" forKey:TYPE];
            }
            else {
                result = nil;
            }
        }
        else if ([currentType isEqualToString:@"friends"]) {
            assert([[result valueForKey:UID] integerValue] == uid_);
            if ([fileName hasPrefix:@"user_"]) {
                long uid = [[fileName substringFromIndex:5] integerValue];
                if ([friends_ containsObject:[NSNumber numberWithInteger:uid]]) {
                    [result setObject:@"user" forKey:TYPE];
                    [result setObject:[NSNumber numberWithInteger:uid] forKey:UID];
                }
                else {
                    result = nil;
                }
            }
            else {
                result = nil;
            }
        }
        else if ([currentType isEqualToString:@"photos"]) {
            if ([fileName hasPrefix:@"album_"]) {
                long aid = [[fileName substringFromIndex:6] integerValue];
                long uid = [[result valueForKey:UID] integerValue];
                if ([self getAlbumInfo:aid ofUser:uid]) {
                    [result setObject:@"album" forKey:TYPE];
                    [result setObject:[NSNumber numberWithInteger:aid] 
                               forKey:AID];
                }
                else {
                    result = nil;
                }
            }
            else {
                result = nil;
            }
        }
        else if ([currentType isEqualToString:@"album"]) {
            if ([fileName hasPrefix:@"photo_"] && [fileName hasSuffix:@".jpg"]) {
                long pid = [[fileName substringFromIndex:6] integerValue];
                long aid = [[result valueForKey:AID] integerValue];
                long uid = [[result valueForKey:UID] integerValue];
                NSNumber *pidKey = [NSNumber numberWithInteger:pid];
                if ([[self getPhotos:uid album:aid] objectForKey:pidKey]) {
                    [result setObject:@"photo" forKey:TYPE];
                    [result setObject:pidKey forKey:PID];
                }
                else {
                    result = nil;
                }
            }
            else if ([fileName isEqualToString:@".localized"] && 
                     [[result valueForKey:LOCALIZED] boolValue]) {
                [result setObject:currentType forKey:ORIGTYPE];
                [result setObject:@"localize" forKey:TYPE];
            }
            else {
                result = nil;
            }
        }
        else if ([currentType isEqualToString:@"localize"]) {
            if ([fileName hasSuffix:@".strings"]) {
                [result setObject:@"strings" forKey:TYPE];
            }
            else {
                result = nil;
            }
        }
        else {
            result = nil;
        }
        
        [result setObject:[NSNumber numberWithBool:isLocalized] forKey:LOCALIZED];
        if (! result) {
            return nil;
        }
    }
    
    return result;
}

- (NSString *)getLocalizedFileForUser:(long)uid
{
    NSString *name = [[self getUserBaseInfo:uid] valueForKey:@"name"];
    return [NSString stringWithFormat:@"\"user_%ld\" = \"%@\";\n",
            uid, [name stringByAddingSlashes]];
}

- (NSString *)getLocalizedFileForAlbum:(long)aid ofUser:(long)uid
{
    NSString *name = [[self getAlbumInfo:aid ofUser:uid] valueForKey:@"name"];
    return [NSString stringWithFormat:@"\"album_%ld\" = \"%@\";\n",
            aid, [name stringByAddingSlashes]];
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path 
                                 error:(NSError *__autoreleasing *)error
{
    NSDictionary *pathInfo = [self parsePath:path];
    NSMutableArray *result = [NSMutableArray array];
    if ([[pathInfo valueForKey:LOCALIZED] boolValue]) {
        [result addObject:@".localized"];
    }
    
    NSString *type = [pathInfo valueForKey:TYPE];
    if ([type isEqualToString:@"user"]) {
        if ([[pathInfo valueForKey:UID] integerValue] == uid_) {
            [result addObject:@"Friends"];
        }
        [result addObject:@"Photos"];
    }
    else if ([type isEqualToString:@"friends"]) {
        for (NSNumber *friend in friends_) {
            [result addObject:[NSString stringWithFormat:@"user_%@.localized", friend]];
        }
    }
    else if ([type isEqualToString:@"photos"]) {
        long uid = [[pathInfo valueForKey:UID] integerValue];
        for (NSNumber *album in [self getUserAlbumsInfo:uid]) {
            [result addObject:[NSString stringWithFormat:@"album_%@.localized", album]];
        }
    }
    else if ([type isEqualToString:@"album"]) {
        long uid = [[pathInfo valueForKey:UID] integerValue];
        long aid = [[pathInfo valueForKey:AID] integerValue];
        for (NSNumber *photo in [self getPhotos:uid album:aid]) {
            [result addObject:[NSString stringWithFormat:@"photo_%@.jpg", photo]];
        }
    }
    else if ([type isEqualToString:@"localize"]) {
        [result addObject:@"zh_CN.strings"];
    }
    else {
        result = nil;
        *error = [NSError errorWithPOSIXCode:ENOENT];
    }
    
    return result;
}

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path 
                                userData:(id)userData 
                                   error:(NSError *__autoreleasing *)error
{
    NSDictionary *pathInfo = [self parsePath:path];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    NSString *type = [pathInfo valueForKey:TYPE];
    long uid = [[pathInfo valueForKey:UID] integerValue];
    if ([type isEqualToString:@"user"]) {
        [result setObject:NSFileTypeDirectory forKey:NSFileType];
        [result setObject:[NSNumber numberWithInt:(uid == uid_ ? 5 : 4)] 
                   forKey:NSFileReferenceCount];
    }
    else if ([type isEqualToString:@"friends"]) {
        NSUInteger friendsCount = [friends_ count];
        [result setObject:NSFileTypeDirectory forKey:NSFileType];
        [result setObject:[NSNumber numberWithUnsignedInteger:friendsCount + 2] 
                   forKey:NSFileReferenceCount];
    }
    else if ([type isEqualToString:@"photos"]) {
        NSUInteger albumsCount = [[[self getUserCountInfo:uid] 
                                   valueForKey:@"albums"] integerValue];
        [result setObject:NSFileTypeDirectory forKey:NSFileType];
        [result setObject:[NSNumber numberWithUnsignedInteger:albumsCount + 2]
                   forKey:NSFileReferenceCount];
    }
    else if ([type isEqualToString:@"album"]) {
        [result setObject:NSFileTypeDirectory forKey:NSFileType];
        [result setObject:[NSNumber numberWithInt:2] forKey:NSFileReferenceCount];
    }
    else if ([type isEqualToString:@"localize"]) {
        [result setObject:NSFileTypeDirectory forKey:NSFileType];
        [result setObject:[NSNumber numberWithInteger:2] 
                   forKey:NSFileReferenceCount];
    }
    else if ([type isEqualToString:@"strings"]) {
        [result setObject:NSFileTypeRegular forKey:NSFileType];
        NSString *data;
        NSString *origType = [pathInfo valueForKey:ORIGTYPE];
        if ([origType isEqualToString:@"user"]) {
            data = [self getLocalizedFileForUser:uid];
        }
        else if ([origType isEqualToString:@"album"]) {
            long aid = [[pathInfo valueForKey:AID] integerValue];
            data = [self getLocalizedFileForAlbum:aid ofUser:uid];
        }
        NSUInteger length = [data lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        [result setObject:[NSNumber numberWithUnsignedInteger:length] 
                   forKey:NSFileSize];
    }
    else {
        *error = [NSError errorWithPOSIXCode:ENOENT];
        result = nil;
    }
    
    return result;
}

- (NSData *)contentsAtPath:(NSString *)path
{
    NSDictionary *pathInfo = [self parsePath:path];
    NSString *type = [pathInfo valueForKey:TYPE];
    long uid = [[pathInfo valueForKey:UID] integerValue];
    NSString *data;
    if ([type isEqualToString:@"strings"]) {
        NSString *origType = [pathInfo valueForKey:ORIGTYPE];
        if ([origType isEqualToString:@"user"]) {
            data = [self getLocalizedFileForUser:uid];
        }
        else if ([origType isEqualToString:@"album"]) {
            long aid = [[pathInfo valueForKey:AID] integerValue];
            data = [self getLocalizedFileForAlbum:aid ofUser:uid];
        }
        else {
            data = nil;
        }
    }
    else {
        data = nil;
    }
    return [data dataUsingEncoding:NSUTF8StringEncoding];
}

@end
