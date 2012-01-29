//
//  NSDate+Renren.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-29.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "NSDate+Renren.h"

@implementation NSDate (Renren)

+ (id)dateWithRenrenString:(NSString *)aString
{
    return [NSDate dateWithString:
            [aString stringByAppendingString:@" +0800"]];
}

@end
