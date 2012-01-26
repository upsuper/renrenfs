//
//  NSDictionary+QueryBuilder.h
//  RenrenFS
//
//  Created by Xidorn Quan on 12-1-25.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDictionary (QueryBuilder)

- (NSString *)buildQueryString;
+ (NSDictionary *)dictionaryWithQueryString:(NSString *)queryString;

@end
