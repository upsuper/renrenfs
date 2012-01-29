//
//  RRUser.h
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-28.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    RRGenderNoInfo = -1,
    RRGenderFemale = 0,
    RRGenderMale = 1
} RRGender;

@interface RRUser : NSObject {
    // 基础信息，对象存在时一定存在
    NSNumber *_uid;
    NSString *_name;
    NSURL *_headurl;
    RRGender _gender;
    // 附加信息，可能不存在，需要另外获取
    size_t _blogsCount;
    size_t _albumsCount;
    size_t _friendsCount;
    // 相册和日志列表
    NSSet *_blogs;
    NSSet *_albums;
    // 更新时间
    NSDate *_baseLastUpdated;
    NSDate *_additionLastUpdated;
    NSDate *_blogsLastUpdated;
    NSDate *_albumsLastUpdated;
}

// 基础信息
@property (readonly) NSNumber *uid;
@property (readonly) NSString *name;
@property (readonly) NSURL *headurl;
@property (readonly) RRGender gender;
// 附加信息
@property (readonly) size_t blogsCount;
@property (readonly) size_t albumsCount;
@property (readonly) size_t friendsCount;
// 相册和日志列表
@property (readonly) NSSet *blogs;
@property (readonly) NSSet *albums;
// 更新时间
@property (readonly) NSDate *baseLastUpdated;
@property (readonly) NSDate *additionLastUpdated;
@property (readonly) NSDate *blogsLastUpdated;
@property (readonly) NSDate *albumsLastUpdated;

- (id)initWithDictionary:(NSDictionary *)data;
- (BOOL)updateBaseInfoWithDictionary:(NSDictionary *)data;
- (BOOL)updateAdditionInfoWithDictionary:(NSDictionary *)data;
- (BOOL)isAdditionInfoExists;
- (void)updateBlogs:(NSSet *)blogs;
- (void)updateAlbums:(NSSet *)albums;

@end
