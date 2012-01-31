//
//  RenrenFS.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <errno.h>
#import <unistd.h>
#import <sys/stat.h>
#import "RenrenFS.h"
#import <OSXFUSE/OSXFUSE.h>
#import <SBJson/SBJson.h>
#import "NSError+POSIX.h"
#import "NSString+MD5.h"
#import "NSDictionary+QueryBuilder.h"
#import "NSString+EscapeQuotes.h"
#import "NSURLDownload+Synchronous.h"
#import "NSImage+IconData.h"
#import "Renren.h"

typedef enum {
    RRFSPathTypeUnknown = 0,
    RRFSPathTypeUser,
    RRFSPathTypeFriends,
    RRFSPathTypePhotos,
    RRFSPathTypeAlbum,
    RRFSPathTypePhoto,
    RRFSPathTypeLocalize,
    RRFSPathTypeStrings,
    RRFSPathTypeIcon
} RRFSPathType;

typedef enum {
    RRFSOwnerSelf,
    RRFSOwnerFriend,
    RRFSOwnerOther
} RRFSOwner;

@interface RRFSPathParsingResult : NSObject {
@public
    RRFSPathType _type;
    id _object;
    BOOL _isLocalized;
    RRFSPathType _origType;
    BOOL _isRoot;
}

@property RRFSPathType type;
@property (strong) id object;
@property BOOL isLocalized;
@property RRFSPathType origType;
@property BOOL isRoot;

@end

@implementation RRFSPathParsingResult

@synthesize type = _type;
@synthesize object = _object;
@synthesize isLocalized = _isLocalized;
@synthesize origType = _origType;
@synthesize isRoot = _isRoot;

@end

static NSString * const RRFSPathNameFriends = @"Friends";
static NSString * const RRFSPathNamePhotos = @"Photos";
static NSString * const RRFSPathNameUser = @"user_%@.localized";
static NSString * const RRFSPathNameAlbum = @"album_%@.localized";
static NSString * const RRFSPathNamePhoto = @"photo_%@.jpg";
static NSString * const RRFSPathNameStrings = @"%@.strings";
static NSString * const RRFSPathNameLocalized = @".localized";
static NSString * const RRFSPathNameIcon = @"Icon\r";
static NSString * const RRFSPathPrefixUser = @"user_";
static NSString * const RRFSPathPrefixAlbum = @"album_";
static NSString * const RRFSPathPrefixPhoto = @"photo_";
static NSString * const RRFSPathSuffixPhoto = @".jpg";
static NSString * const RRFSPathSuffixStrings = @".strings";
static NSString * const RRFSPathSuffixLocalized = @".localized";

static NSString *RRFSStringsName;
static uid_t RRFSUid;
static gid_t RRFSGid;
static NSImage *RRFSIconUser;
static NSImage *RRFSIconAlbum;

@interface NSString (NumberValueWithPrefix)

- (NSNumber *)numberByRemovingPrefix:(NSString *)prefix;

@end

@implementation NSString (NumberValueWithPrefix)

- (NSNumber *)numberByRemovingPrefix:(NSString *)prefix
{
    long number = [[self substringFromIndex:[prefix length]] integerValue];
    return [NSNumber numberWithInteger:number];
}

@end

@interface RenrenFS (Private)

- (RRFSPathParsingResult *)parsePath:(NSString *)path;

- (NSString *)pathOfHeadOfUser:(RRUser *)user;
- (BOOL)generateHeadOfUser:(RRUser *)user error:(NSError **)error;
- (NSString *)pathOfCoverOfAlbum:(RRAlbum *)album;
- (BOOL)generateCoverOfAlbum:(RRAlbum *)album error:(NSError **)error;
- (NSString *)pathOfPhoto:(RRPhoto *)photo;
- (BOOL)downloadPhoto:(RRPhoto *)photo error:(NSError **)error;
- (NSString *)localizedFileForUser:(RRUser *)user;
- (NSString *)localizedFileForAlbum:(RRAlbum *)album;
- (NSData *)readFileAtPath:(NSString *)path;

@end

@implementation RenrenFS

+ (void)initialize
{
    // 初始化默认语言名称
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSString *lang = [[defs objectForKey:@"AppleLanguages"] objectAtIndex:0];
    RRFSStringsName = [NSString stringWithFormat:RRFSPathNameStrings, lang];
    // 初始化当前用户和当前组
    RRFSUid = getuid();
    RRFSGid = getgid();
    // 初始化图标模板
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    RRFSIconUser = [workspace iconForFileType:
                    NSFileTypeForHFSTypeCode(kWorkgroupFolderIcon)];
    RRFSIconAlbum = [workspace iconForFile:
                     [@"~/Pictures" stringByExpandingTildeInPath]];
}

- (id)initWithConnection:(RRConnection *)conn cacheDir:(NSString *)cacheDir
{
    if (self = [super init]) {
        _conn = conn;
        _cacheDir = [cacheDir stringByStandardizingPath];
        _headsCacheDir = [_cacheDir stringByAppendingPathComponent:@"heads"];
        _coversCacheDir = [_cacheDir stringByAppendingPathComponent:@"covers"];
        _photosCacheDir = [_cacheDir stringByAppendingPathComponent:@"photos"];
    }
    return self;
}

- (NSString *)pathOfHeadOfUser:(RRUser *)user
{
    return [_headsCacheDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.icns", [user uid]]];
}

- (BOOL)generateHeadOfUser:(RRUser *)user 
                     error:(NSError *__autoreleasing *)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filename = [self pathOfHeadOfUser:user];
    BOOL result = YES;
    if (! [fileManager fileExistsAtPath:filename]) {
        NSString *dirname = [filename stringByDeletingLastPathComponent];
        result = [fileManager createDirectoryAtPath:dirname 
                        withIntermediateDirectories:YES 
                                         attributes:nil 
                                              error:error];
        if (! result)
            return NO;
        // 获取头像图片
        NSImage *headImage = [[NSImage alloc] 
                              initByReferencingURL:[user tinyHeadURL]];
        if (! headImage)
            return NO;
        // 根据头像图片生成图标
        const int kIconSize = 256;
        NSImage *folderIcon = [RRFSIconUser copy];
        NSSize iconSize = NSMakeSize(kIconSize, kIconSize);
        [folderIcon setSize:iconSize];
        [folderIcon lockFocus];
        NSSize headSize = [headImage size];
        NSRect sourceRect = NSMakeRect(0, 0, headSize.width, headSize.height);
        NSSize folderSize = [folderIcon size];
        NSRect destRect = NSMakeRect(folderSize.width * 0.5, 
                                     0, 
                                     folderSize.width * 0.5, 
                                     folderSize.height * 0.5);
        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        NSImageInterpolation interpolation = [context imageInterpolation];
        [context setImageInterpolation:NSImageInterpolationHigh];
        [headImage drawInRect:destRect
                     fromRect:sourceRect
                    operation:NSCompositeSourceOver
                     fraction:1.0];
        [context setImageInterpolation:interpolation];
        [folderIcon unlockFocus];
        // 保存图标到文件
        NSData *icnsData = [folderIcon icnsDataWithWidth:256];
        result = [icnsData writeToFile:filename atomically:YES];
    }
    return result;
}

- (NSString *)pathOfCoverOfAlbum:(RRAlbum *)album
{
    return [_coversCacheDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@/%@.icns", 
             [album uid], [album aid]]];
}

- (BOOL)generateCoverOfAlbum:(RRAlbum *)album 
                       error:(NSError *__autoreleasing *)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filename = [self pathOfCoverOfAlbum:album];
    BOOL result = YES;
    if (! [fileManager fileExistsAtPath:filename]) {
        NSString *dirname = [filename stringByDeletingLastPathComponent];
        result = [fileManager createDirectoryAtPath:dirname 
                        withIntermediateDirectories:YES 
                                         attributes:nil 
                                              error:error];
        if (! result)
            return NO;
        // 获取头像图片
        NSImage *coverImage = [[NSImage alloc] 
                               initByReferencingURL:[album cover]];
        if (! coverImage)
            return NO;
        // 根据头像图片生成图标
        const int kIconSize = 256;
        NSImage *folderIcon = [RRFSIconAlbum copy];
        NSSize iconSize = NSMakeSize(kIconSize, kIconSize);
        [folderIcon setSize:iconSize];
        [folderIcon lockFocus];
        NSSize headSize = [coverImage size];
        NSRect sourceRect = NSMakeRect(0, 0, headSize.width, headSize.height);
        NSSize folderSize = [folderIcon size];
        NSRect destRect = NSMakeRect(folderSize.width * 0.5, 
                                     0, 
                                     folderSize.width * 0.5, 
                                     folderSize.height * 0.5);
        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        NSImageInterpolation interpolation = [context imageInterpolation];
        [context setImageInterpolation:NSImageInterpolationHigh];
        [coverImage drawInRect:destRect
                     fromRect:sourceRect
                    operation:NSCompositeSourceOver
                     fraction:1.0];
        [context setImageInterpolation:interpolation];
        [folderIcon unlockFocus];
        // 保存图标到文件
        NSData *icnsData = [folderIcon icnsDataWithWidth:256];
        result = [icnsData writeToFile:filename atomically:YES];
    }
    return result;
}

- (NSString *)pathOfPhoto:(RRPhoto *)photo
{
    return [_photosCacheDir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@/%@/%@.jpg", 
             [photo uid], [photo aid], [photo pid]]];
}

- (BOOL)downloadPhoto:(RRPhoto *)photo error:(NSError *__autoreleasing *)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filename = [self pathOfPhoto:photo];
    BOOL result = YES;
    if (! [fileManager fileExistsAtPath:filename]) {
        NSString *dirname = [filename stringByDeletingLastPathComponent];
        result = [fileManager createDirectoryAtPath:dirname 
                        withIntermediateDirectories:YES 
                                         attributes:nil 
                                              error:error];
        if (! result)
            return NO;
        NSURLRequest *request = [NSURLRequest requestWithURL:[photo url]];
        result = [NSURLDownload sendSynchoronousRequest:request 
                                                 saveTo:filename 
                                                  error:error];
    }
    return result;
}

- (RRFSPathParsingResult *)parsePath:(NSString *)path
{
    NSArray *pathComponents = [path componentsSeparatedByString:@"/"];
        
    // 初始化文件系统根目录为当前用户的用户目录
    RRFSPathParsingResult *result = [[RRFSPathParsingResult alloc] init];
    [result setType:RRFSPathTypeUser];
    [result setObject:[_conn user]];
    
    for (NSString *component in pathComponents) {
        NSUInteger length = [component length];
        if (length == 0)
            continue;
        
        // 删除无关后缀
        NSString *fileName = component;
        if (length > 10 && [fileName hasSuffix:RRFSPathSuffixLocalized]) {
            [result setIsLocalized:YES];
            fileName = [fileName substringToIndex:length - 10];
        }
        else {
            [result setIsLocalized:NO];
        }
        
        // 层级递进分析目录
        switch ([result type]) {
            case RRFSPathTypeUser:
                // 用户目录
                if ([fileName isEqualToString:RRFSPathNameFriends]) {
                    if ([result object] == [_conn user])
                        [result setType:RRFSPathTypeFriends];
                    else
                        [result setType:RRFSPathTypeUnknown];
                }
                else if ([fileName isEqualToString:RRFSPathNamePhotos]) {
                    [result setType:RRFSPathTypePhotos];
                }
                else if ([fileName isEqualToString:RRFSPathNameLocalized]) {
                    [result setOrigType:RRFSPathTypeUser];
                    [result setType:RRFSPathTypeLocalize];
                }
                else if ([fileName isEqualToString:RRFSPathNameIcon]) {
                    [result setOrigType:RRFSPathTypeUser];
                    [result setType:RRFSPathTypeIcon];
                }
                else {
                    [result setType:RRFSPathTypeUnknown];
                }
                break;
            
            case RRFSPathTypeFriends:
                // 好友目录
                // 断言：好友目录只能存在于当前用户下
                assert([result object] == [_conn user]);
                if ([fileName hasPrefix:RRFSPathPrefixUser]) {
                    NSNumber *uid;
                    uid = [fileName numberByRemovingPrefix:RRFSPathPrefixUser];
                    if ([[_conn friends] containsObject:uid]) {
                        [result setType:RRFSPathTypeUser];
                        [result setObject:[_conn user:uid]];
                    }
                    else {
                        [result setType:RRFSPathTypeUnknown];
                    }
                }
                else {
                    [result setType:RRFSPathTypeUnknown];
                }
                break;
            
            case RRFSPathTypePhotos:
                // 照片目录
                if ([fileName hasPrefix:RRFSPathPrefixAlbum]) {
                    NSNumber *aid;
                    aid = [fileName numberByRemovingPrefix:RRFSPathPrefixAlbum];
                    NSSet *albums = [_conn albumsOfUser:[result object]];
                    if ([albums containsObject:aid]) {
                        [result setType:RRFSPathTypeAlbum];
                        [result setObject:[_conn album:aid]];
                    }
                    else {
                        [result setType:RRFSPathTypeUnknown];
                    }
                }
                else {
                    [result setType:RRFSPathTypeUnknown];
                }
                break;
                
            case RRFSPathTypeAlbum:
                // 相册目录
                if ([fileName hasPrefix:RRFSPathPrefixPhoto] &&
                    [fileName hasSuffix:RRFSPathSuffixPhoto]) {
                    NSNumber *pid;
                    pid = [fileName numberByRemovingPrefix:RRFSPathPrefixPhoto];
                    NSLog(@"photo: %@ %@", pid, [fileName substringFromIndex:
                                                 [RRFSPathPrefixPhoto length]]);
                    NSSet *photos = [_conn photosOfAlbum:[result object]];
                    if ([photos containsObject:pid]) {
                        [result setType:RRFSPathTypePhoto];
                        [result setObject:[_conn photo:pid]];
                    }
                    else {
                        [result setType:RRFSPathTypeUnknown];
                    }
                }
                else if ([fileName isEqualToString:RRFSPathNameLocalized]) {
                    [result setOrigType:RRFSPathTypeAlbum];
                    [result setType:RRFSPathTypeLocalize];
                }
                else if ([fileName isEqualToString:RRFSPathNameIcon]) {
                    [result setOrigType:RRFSPathTypeAlbum];
                    [result setType:RRFSPathTypeIcon];
                }
                else {
                    [result setType:RRFSPathTypeUnknown];
                }
                break;
                
            case RRFSPathTypeLocalize:
                // 别名目录
                if ([fileName hasSuffix:RRFSPathSuffixStrings]) {
                    [result setType:RRFSPathTypeStrings];
                }
                else {
                    [result setType:RRFSPathTypeUnknown];
                }
                break;
                
            default:
                [result setType:RRFSPathTypeUnknown];
                break;
        }
        
        if ([result type] == RRFSPathTypeUnknown)
            break;
    }
    
    // 是否为根目录
    [result setIsRoot:[path isEqualToString:@"/"]];
    
    return result;
}

- (NSString *)localizedFileForUser:(RRUser *)user
{
    return [NSString stringWithFormat:@"\"user_%@\" = \"%@\";\n",
            [user uid], [[user name] stringByAddingSlashes]];
}

- (NSString *)localizedFileForAlbum:(RRAlbum *)album
{
    return [NSString stringWithFormat:@"\"album_%@\" = \"%@\";\n",
            [album aid], [[album name] stringByAddingSlashes]];
}

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path 
                                 error:(NSError *__autoreleasing *)error
{
    RRFSPathParsingResult *pathInfo = [self parsePath:path];
    NSMutableArray *result = [NSMutableArray array];
    
    // 添加别名文件夹
    if ([pathInfo isLocalized]) {
        [result addObject:RRFSPathNameLocalized];
    }
    
    switch ([pathInfo type]) {
        case RRFSPathTypeUser:
            if ([pathInfo object] == [_conn user])
                [result addObject:RRFSPathNameFriends];
            [result addObject:RRFSPathNamePhotos];
            if (! [pathInfo isRoot])
                [result addObject:RRFSPathNameIcon];
            break;
        
        case RRFSPathTypeFriends:
            for (NSNumber *uid in [_conn friends]) {
                [result addObject:[NSString 
                                   stringWithFormat:RRFSPathNameUser, uid]];
            }
            break;
            
        case RRFSPathTypePhotos:
            for (NSNumber *aid in [_conn albumsOfUser:[pathInfo object]]) {
                [result addObject:[NSString 
                                   stringWithFormat:RRFSPathNameAlbum, aid]];
            }
            break;
            
        case RRFSPathTypeAlbum:
            for (NSNumber *pid in [_conn photosOfAlbum:[pathInfo object]]) {
                [result addObject:[NSString 
                                   stringWithFormat:RRFSPathNamePhoto, pid]];
            }
            [result addObject:RRFSPathNameIcon];
            break;
        
        case RRFSPathTypeLocalize:
            [result addObject:RRFSStringsName];
            break;
            
        default:
            result = nil;
            *error = [NSError errorWithPOSIXCode:ENOENT];
            break;
    }
    
    return result;
}

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path 
                                userData:(id)userData 
                                   error:(NSError *__autoreleasing *)error
{
    RRFSPathParsingResult *pathInfo = [self parsePath:path];
    
    BOOL failed = NO;
    BOOL isDirectory;
    NSUInteger referenceCount;
    NSUInteger fileSize;
    NSDate *creationTime = [NSDate date];
    NSDate *modificationTime = [NSDate date];
    NSNumber *pathUid = [[pathInfo object] uid];
    RRFSOwner whosOwner;
    if ([pathUid isEqualToNumber:[[_conn user] uid]])
        whosOwner = RRFSOwnerSelf;
    else if ([[_conn friends] containsObject:pathUid])
        whosOwner = RRFSOwnerFriend;
    else
        whosOwner = RRFSOwnerOther;
    mode_t permission = 0644;
    
    RRUser *user;
    RRAlbum *album;
    NSData *data;
    
    switch ([pathInfo type]) {
        case RRFSPathTypeUser:
            isDirectory = YES;
            permission = 0555;
            referenceCount = whosOwner == RRFSOwnerSelf ? 4 : 3;
            break;
        
        case RRFSPathTypeFriends:
            isDirectory = YES;
            referenceCount = [[_conn friends] count] + 2;
            permission = 0755;
            break;
        
        case RRFSPathTypePhotos:
            isDirectory = YES;
            user = [pathInfo object];
            if (! [user isAdditionInfoExists])
                user = [_conn user:[user uid] forceUpdate:YES];
            referenceCount = [user albumsCount] + 2;
            permission = 0755;
            break;
            
        case RRFSPathTypeAlbum:
            isDirectory = YES;
            referenceCount = 2;
            album = [pathInfo object];
            creationTime = [album createTime];
            modificationTime = [album updateTime];
            switch ([album visible]) {
                case RRAlbumVisibleSameNetwork:
                case RRAlbumVisiblePassword:
                case RRAlbumVisibleSelf:
                    permission = 0700;
                    break;
                case RRAlbumVisibleFriends:
                    permission = 0750;
                    break;
                case RRAlbumVisibleAll:
                    permission = 0755;
                    break;
                default:
                    break;
            }
            break;
            
        case RRFSPathTypePhoto:
            isDirectory = NO;
            creationTime = modificationTime = [[pathInfo object] time];
            permission = 0644;
            if (! [self downloadPhoto:[pathInfo object] error:error]) {
                failed = YES;
            }
            else {
                NSString *filename = [self pathOfPhoto:[pathInfo object]];
                NSFileManager *fileManager = [NSFileManager defaultManager];
                NSDictionary *fileAttr = [fileManager 
                                          attributesOfItemAtPath:filename 
                                          error:error];
                if (! fileAttr) {
                    failed = YES;
                }
                else {
                    fileSize = [[fileAttr objectForKey:NSFileSize] 
                                unsignedIntegerValue];
                }
            }
            break;
        
        case RRFSPathTypeLocalize:
            isDirectory = YES;
            referenceCount = 2;
            permission = 0555;
            break;
            
        case RRFSPathTypeIcon:
        case RRFSPathTypeStrings:
            permission = 0444;
            
        case RRFSPathTypeUnknown:
        default:
            data = [self readFileAtPath:path];
            if (data) {
                isDirectory = NO;
                fileSize = [data length];
            }
            else {
                *error = [NSError errorWithPOSIXCode:ENOENT];
                failed = YES;
            }
            
            break;
    }
    
    NSMutableDictionary *result;
    uid_t uid;
    gid_t gid;
    u_int flags = 0;
    if (failed) {
        result = nil;
    }
    else {
        result = [NSMutableDictionary dictionary];
        // 设置文件类型和基本属性
        if (isDirectory) {
            [result setObject:NSFileTypeDirectory forKey:NSFileType];
            [result setObject:
             [NSNumber numberWithUnsignedInteger:referenceCount] 
                       forKey:NSFileReferenceCount];
        }
        else {
            [result setObject:NSFileTypeRegular forKey:NSFileType];
            [result setObject:[NSNumber numberWithUnsignedInteger:fileSize] 
                                                           forKey:NSFileSize];
        }
        // 时间相关属性
        [result setObject:creationTime forKey:NSFileCreationDate];
        [result setObject:modificationTime forKey:NSFileModificationDate];
        // 访问权限
        [result setObject:[NSNumber numberWithShort:permission]
                   forKey:NSFilePosixPermissions];
        
        // 设置所有者 ID 和组 ID
        switch (whosOwner) {
            case RRFSOwnerSelf:
                uid = RRFSUid; gid = RRFSGid;
                break;
            case RRFSOwnerFriend:
                uid = 0; gid = RRFSGid;
                break;
            case RRFSOwnerOther:
                uid = 0; gid = 0;
                break;
                
        }
        [result setObject:[NSNumber numberWithUnsignedInt:uid]
                   forKey:NSFileOwnerAccountID];
        [result setObject:[NSNumber numberWithUnsignedInt:gid]
                   forKey:NSFileGroupOwnerAccountID];
        
        // 检查当前用户是否有访问权限
        BOOL isAllowed = YES;
        if (whosOwner == RRFSOwnerFriend) {
            if (isDirectory)
                isAllowed = (permission & 0050) == 0050;
            else
                isAllowed = (permission & 0040) == 0040;
        }
        else if (whosOwner == RRFSOwnerOther) {
            if (isDirectory)
                isAllowed = (permission & 0005) == 0005;
            else
                isAllowed = (permission & 0004) == 0004;
        }
        // 如果没有访问权限则自动隐藏
        if (! isAllowed)
            flags |= UF_HIDDEN;
        
        // 设置附加标志
        [result setObject:[NSNumber numberWithUnsignedInt:flags] 
                   forKey:kGMUserFileSystemFileFlagsKey];
    }
    
    return result;
}

- (NSData *)readFileAtPath:(NSString *)path
{
    RRFSPathParsingResult *pathInfo = [self parsePath:path];
    RRFSPathType type = [pathInfo type];
    RRFSPathType origType = [pathInfo origType];
    NSData *data;
    
    if (type == RRFSPathTypeStrings) {
        NSString *strings;
        if (origType == RRFSPathTypeUser) {
            strings = [self localizedFileForUser:[pathInfo object]];
        }
        else if (origType == RRFSPathTypeAlbum) {
            strings = [self localizedFileForAlbum:[pathInfo object]];
        }
        else {
            strings = nil;
        }
        data = [strings dataUsingEncoding:NSUTF16StringEncoding];
    }
    else if (type == RRFSPathTypeIcon) {
        data = [NSData dataWithBytes:"" length:0];
    }
    else {
        data = nil;
    }
    
    return data;
}

- (BOOL)openFileAtPath:(NSString *)path mode:(int)mode 
              userData:(__autoreleasing id *)userData 
                 error:(NSError *__autoreleasing *)error
{
    RRFSPathParsingResult *pathInfo = [self parsePath:path];
    RRFSPathType type = [pathInfo type];
    BOOL result;
    
    if (type == RRFSPathTypePhoto) {
        NSString *filename = [self pathOfPhoto:[pathInfo object]];
        int fd = open([filename UTF8String], mode);
        if (fd < 0) {
            if (error) {
                *error = [NSError errorWithPOSIXCode:errno];
            }
            result = NO;
        }
        else {
            *userData = [NSNumber numberWithInt:fd];
            result = YES;
        }
    }
    else if (type == RRFSPathTypeStrings || type == RRFSPathTypeIcon) {
        *userData = [NSNumber numberWithInt:0];
        result = YES;
    }
    else {
        result = NO;
    }
    
    return result;
}

- (void)releaseFileAtPath:(NSString *)path userData:(id)userData
{
    int fd = [userData intValue];
    if (fd > 0) {
        close(fd);
    }
}

- (int)readFileAtPath:(NSString *)path userData:(id)userData 
               buffer:(char *)buffer size:(size_t)size 
               offset:(off_t)offset 
                error:(NSError *__autoreleasing *)error
{
    int fd = [userData intValue];
    if (fd > 0) {
        ssize_t ret = pread(fd, buffer, size, offset);
        if (ret < 0) {
            if (error) {
                *error = [NSError errorWithPOSIXCode:errno];
            }
        }
        return (int)ret;
    }
    else {
        NSData *data = [self readFileAtPath:path];
        ssize_t length = [data length] - offset;
        length = MIN(length, size);
        if (length < 0) {
            if (error) {
                *error = [NSError errorWithPOSIXCode:EINVAL];
            }
            length = -1;
        }
        else {
            [data getBytes:buffer range:NSMakeRange(offset, length)];
        }
        return (int)length;
    }
}

- (NSArray *)extendedAttributesOfItemAtPath:(id)path 
                                      error:(NSError *__autoreleasing *)error
{
    // 如果不实现该过程，要求列出 xattr 时不会正确地输出数据
    
    RRFSPathParsingResult *pathInfo = [self parsePath:path];
    RRFSPathType type = [pathInfo type];
    NSArray *result;
    
    if (type == RRFSPathTypeUser && ! [pathInfo isRoot]) {
        result = [NSArray arrayWithObject:@"com.apple.FinderInfo"];
    }
    else if (type == RRFSPathTypeAlbum) {
        result = [NSArray arrayWithObject:@"com.apple.FinderInfo"];
    }
    else if (type == RRFSPathTypeIcon) {
        result = [NSArray arrayWithObjects:
                  @"com.apple.FinderInfo", 
                  @"com.apple.ResourceFork", nil];
    }
    else {
        result = [NSArray array];
    }
    
    return result;
}

- (NSDictionary *)finderAttributesAtPath:(NSString *)path 
                                   error:(NSError *__autoreleasing *)error
{
    RRFSPathParsingResult *pathInfo = [self parsePath:path];
    RRFSPathType type = [pathInfo type];
    long finderFlags = 0;
    NSDictionary *result;
    
    if (type == RRFSPathTypeUser && ! [pathInfo isRoot])
        finderFlags = kHasCustomIcon;
    else if (type == RRFSPathTypeAlbum)
        finderFlags = kHasCustomIcon;
    
    if (finderFlags) {
        result = [NSDictionary 
                  dictionaryWithObject:[NSNumber numberWithLong:finderFlags] 
                  forKey:kGMUserFileSystemFinderFlagsKey];
    }
    else {
        result = [NSDictionary dictionary];
    }
    
    return result;
}

- (NSDictionary *)resourceAttributesAtPath:(NSString *)path 
                                     error:(NSError *__autoreleasing *)error
{
    RRFSPathParsingResult *pathInfo = [self parsePath:path];
    RRFSPathType type = [pathInfo type];
    NSDictionary *result = nil;
    
    if (type == RRFSPathTypeUser && ! [pathInfo isRoot]) {
        RRUser *user = [pathInfo object];
        if ([self generateHeadOfUser:user error:error]) {
            result = [NSDictionary 
                      dictionaryWithObject:
                      [NSData dataWithContentsOfFile:
                       [self pathOfHeadOfUser:user]] 
                      forKey:kGMUserFileSystemCustomIconDataKey];
        }
    }
    else if (type == RRFSPathTypeAlbum) {
        RRAlbum *album = [pathInfo object];
        if ([self generateCoverOfAlbum:album error:error]) {
            result = [NSDictionary
                      dictionaryWithObject:
                      [NSData dataWithContentsOfFile:
                       [self pathOfCoverOfAlbum:album]] 
                      forKey:kGMUserFileSystemCustomIconDataKey];
        }
    }
    else {
        result = [NSDictionary dictionary];
    }
    
    return result;
}

@end
