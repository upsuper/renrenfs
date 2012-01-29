//
//  RRAlbum.h
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-29.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    RRAlbumVisibleSelf = -1,
    RRAlbumVisibleFriends = 1,
    RRAlbumVisibleSameNetwork = 3,
    RRAlbumVisiblePassword = 4,
    RRAlbumVisibleAll = 99
} RRAlbumVisible;

@interface RRAlbum : NSObject {
    NSNumber *_aid;
    NSNumber *_uid;
    NSString *_name;
    NSURL *_cover;
    NSDate *_createTime;
    NSDate *_updateTime;
    NSString *_description;
    NSString *_location;
    RRAlbumVisible _visible;
    
    NSSet *_photos;
    
    NSDate *_infoLastUpdated;
    NSDate *_photosLastUpdated;
}

@property (readonly) NSNumber *aid;
@property (readonly) NSNumber *uid;
@property (readonly) NSString *name;
@property (readonly) NSURL *cover;
@property (readonly) NSDate *createTime;
@property (readonly) NSDate *updateTime;
@property (readonly) NSString *description;
@property (readonly) NSString *location;
@property (readonly) RRAlbumVisible visible;

@property (readonly) NSSet *photos;

@property (readonly) NSDate *infoLastUpdated;
@property (readonly) NSDate *photosLastUpdated;

- (id)initWithDictionary:(NSDictionary *)data;
- (BOOL)updateWithDictionary:(NSDictionary *)data;
- (void)updatePhotos:(NSSet *)photos;

@end
