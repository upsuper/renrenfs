//
//  NSString+EscapeQuotes.m
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-26.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "NSString+EscapeQuotes.h"

@implementation NSString (EscapeQuotes)

- (NSString *)stringByAddingSlashes
{
    NSString *result = [self stringByReplacingOccurrencesOfString:@"\\" 
                                                       withString:@"\\\\"];
    result = [result stringByReplacingOccurrencesOfString:@"\"" 
                                               withString:@"\\\""];
    return result;
}

@end
