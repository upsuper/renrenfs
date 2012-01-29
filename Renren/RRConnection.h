//
//  RRConnection.h
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-28.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class RRUser;
@class RRAlbum;
@class RRPhoto;

@interface RRConnection : NSObject {
    NSString *_accessToken;
    NSString *_secret;
    NSNumber *_uid;
    RRUser *_user;
    NSSet *_friends;
    
    NSMutableDictionary *_users;
    NSMutableDictionary *_albums;
    NSMutableDictionary *_photos;
    
    NSDate *_friendsLastUpdated;
}

@property (readonly) RRUser *user;

- (id)initWithAccessToken:(NSString *)accessToken secret:(NSString *)secret;
- (RRUser *)user:(NSNumber *)uid;
- (RRUser *)user:(NSNumber *)uid forceUpdate:(BOOL)forceUpdate;
- (NSSet *)friends;
- (RRAlbum *)album:(NSNumber *)aid;
- (NSSet *)albumsOfUser:(RRUser *)user;
- (RRPhoto *)photo:(NSNumber *)pid;
- (NSSet *)photosOfAlbum:(RRAlbum *)album;

@end
