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
#import "NSURLDownload+Synchronous.h"
#import "Renren.h"

typedef enum {
    RRFSPathTypeUnknown = 0,
    RRFSPathTypeUser,
    RRFSPathTypeFriends,
    RRFSPathTypePhotos,
    RRFSPathTypeAlbum,
    RRFSPathTypePhoto,
    RRFSPathTypeLocalize,
    RRFSPathTypeStrings
} RRFSPathType;

@interface RRFSPathParsingResult : NSObject {
@public
    RRFSPathType _type;
    id _object;
    BOOL _isLocalized;
    RRFSPathType _origType;
}

@property RRFSPathType type;
@property (strong) id object;
@property BOOL isLocalized;
@property RRFSPathType origType;

@end

@implementation RRFSPathParsingResult

@synthesize type = _type;
@synthesize object = _object;
@synthesize isLocalized = _isLocalized;
@synthesize origType = _origType;

@end

static NSString * const RRFSPathNameFriends = @"Friends";
static NSString * const RRFSPathNamePhotos = @"Photos";
static NSString * const RRFSPathNameUser = @"user_%@.localized";
static NSString * const RRFSPathNameAlbum = @"album_%@.localized";
static NSString * const RRFSPathNamePhoto = @"photo_%@.jpg";
static NSString * const RRFSPathNameStrings = @"%@.strings";
static NSString * const RRFSPathNameLocalized = @".localized";
static NSString * const RRFSPathPrefixUser = @"user_";
static NSString * const RRFSPathPrefixAlbum = @"album_";
static NSString * const RRFSPathPrefixPhoto = @"photo_";
static NSString * const RRFSPathSuffixPhoto = @".jpg";
static NSString * const RRFSPathSuffixStrings = @".strings";
static NSString * const RRFSPathSuffixLocalized = @".localized";

static NSString *RRFSStringsName;

@interface RRPhoto (Path)

- (NSString *)pathWithRoot:(NSString *)root;

@end

@implementation RRPhoto (Path)

- (NSString *)pathWithRoot:(NSString *)root
{
    return [root stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@/%@/%@.jpg", _uid, _aid, _pid]];
}

@end

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

- (NSString *)pathOfPhoto:(RRPhoto *)photo;
- (BOOL)downloadPhoto:(RRPhoto *)photo error:(NSError **)error;
- (NSString *)localizedFileForUser:(RRUser *)user;
- (NSString *)localizedFileForAlbum:(RRAlbum *)album;
- (NSData *)readFileAtPath:(NSString *)path;

@end

@implementation RenrenFS

+ (void)initialize
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSString *lang = [[defs objectForKey:@"AppleLanguages"] objectAtIndex:0];
    RRFSStringsName = [NSString stringWithFormat:RRFSPathNameStrings, lang];
}

- (id)initWithConnection:(RRConnection *)conn cacheDir:(NSString *)cacheDir
{
    if (self = [super init]) {
        _conn = conn;
        _cacheDir = [cacheDir stringByStandardizingPath];
        _photosCacheDir = [_cacheDir stringByAppendingPathComponent:@"photos"];
    }
    return self;
}

- (NSString *)pathOfPhoto:(RRPhoto *)photo
{
    return [photo pathWithRoot:_photosCacheDir];
}

- (BOOL)downloadPhoto:(RRPhoto *)photo error:(NSError *__autoreleasing *)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *filename = [self pathOfPhoto:photo];
    BOOL result = YES;
    if (! [fileManager fileExistsAtPath:filename]) {
        NSString *dirname = [filename stringByDeletingLastPathComponent];
        [fileManager createDirectoryAtPath:dirname 
               withIntermediateDirectories:YES attributes:nil error:nil];
        NSURLRequest *request = [NSURLRequest requestWithURL:[photo url]];
        result = [NSURLDownload sendSynchoronousRequest:request 
                                                 saveTo:filename error:error];
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
                    [result setOrigType:[result type]];
                    [result setType:RRFSPathTypeLocalize];
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
                    [result setOrigType:[result type]];
                    [result setType:RRFSPathTypeLocalize];
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
    NSLog(@"attr: %@ %d", path, [pathInfo type]);
    
    BOOL failed = NO;
    BOOL isDirectory;
    NSUInteger referenceCount;
    NSUInteger fileSize;
    NSDate *creationTime = [NSDate date];
    NSDate *modificationTime = [NSDate date];
    
    RRUser *user;
    NSData *data;
    
    switch ([pathInfo type]) {
        case RRFSPathTypeUser:
            isDirectory = YES;
            referenceCount = [pathInfo object] == [_conn user] ? 4 : 3;
            break;
        
        case RRFSPathTypeFriends:
            isDirectory = YES;
            referenceCount = [[_conn friends] count] + 2;
            break;
        
        case RRFSPathTypePhotos:
            isDirectory = YES;
            user = [pathInfo object];
            if (! [user isAdditionInfoExists])
                user = [_conn user:[user uid] forceUpdate:YES];
            referenceCount = [user albumsCount] + 2;
            break;
            
        case RRFSPathTypeAlbum:
            isDirectory = YES;
            referenceCount = 2;
            creationTime = [[pathInfo object] createTime];
            modificationTime = [[pathInfo object] updateTime];
            break;
            
        case RRFSPathTypePhoto:
            isDirectory = NO;
            creationTime = modificationTime = [[pathInfo object] time];
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
            break;
        
        case RRFSPathTypeStrings:
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
    
    NSDictionary *result;
    if (failed) {
        result = nil;
    }
    else if (isDirectory) {
        result = [NSDictionary dictionaryWithObjectsAndKeys:
                  NSFileTypeDirectory, NSFileType,
                  [NSNumber numberWithUnsignedInteger:referenceCount], 
                  NSFileReferenceCount,
                  creationTime, NSFileCreationDate,
                  modificationTime, NSFileModificationDate,
                  nil];
    }
    else {
        result = [NSDictionary dictionaryWithObjectsAndKeys:
                  NSFileTypeRegular, NSFileType,
                  [NSNumber numberWithUnsignedInteger:fileSize], NSFileSize,
                  creationTime, NSFileCreationDate,
                  modificationTime, NSFileModificationDate,
                  nil];
    }
    
    return result;
}

- (NSData *)readFileAtPath:(NSString *)path
{
    RRFSPathParsingResult *pathInfo = [self parsePath:path];
    NSData *data;
    
    if ([pathInfo type] == RRFSPathTypeStrings) {
        NSString *strings;
        if ([pathInfo origType] == RRFSPathTypeUser) {
            strings = [self localizedFileForUser:[pathInfo object]];
        }
        else if ([pathInfo origType] == RRFSPathTypeAlbum) {
            strings = [self localizedFileForAlbum:[pathInfo object]];
        }
        else {
            strings = nil;
        }
        data = [strings dataUsingEncoding:NSUTF16StringEncoding];
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
    BOOL result;
    
    if ([pathInfo type] == RRFSPathTypePhoto) {
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
    else if ([pathInfo type] == RRFSPathTypeStrings) {
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

@end
