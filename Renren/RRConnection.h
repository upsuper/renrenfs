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
    NSSet *_visitors;
    
    NSMutableDictionary *_users;
    NSMutableDictionary *_albums;
    NSMutableDictionary *_photos;
    
    NSDate *_friendsLastUpdated;
    NSDate *_visitorsLastUpdated;
}

@property (readonly) RRUser *user;

- (id)initWithAccessToken:(NSString *)accessToken secret:(NSString *)secret;
- (RRUser *)user:(NSNumber *)uid;
- (RRUser *)user:(NSNumber *)uid forceUpdate:(BOOL)forceUpdate;
- (void)updateUsers:(NSArray *)users;
- (NSSet *)friends;
- (NSSet *)visitors;
- (RRAlbum *)album:(NSNumber *)aid;
- (NSSet *)albumsOfUser:(RRUser *)user;
- (RRPhoto *)photo:(NSNumber *)pid;
- (NSSet *)photosOfAlbum:(RRAlbum *)album;

@end
