//
//  NSString+MD5.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "NSString+MD5.h"
#import <CommonCrypto/CommonDigest.h>

@implementation NSString (MD5)

- (NSString *)md5
{
    const char *str = [self UTF8String];
    unsigned char hash[16];
    CC_MD5(str, (CC_LONG)strlen(str), hash);
    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < 16; ++i) {
        [result appendFormat:@"%02x", hash[i]];
    }
    return result;
}

@end
