//
//  UIView+ViewTracker.m
//  XJHNetworkReachability_Example
//
//  Created by xujunhao on 2018/9/6.
//  Copyright © 2018年 cocoadogs. All rights reserved.
//

#import "UIView+ViewTracker.h"

#ifdef DEBUG
#define VTLog(FORMAT, ...) fprintf(stderr,"%s\n\n", [[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] UTF8String]);
#else
#define VTLog(...)
#endif

@implementation UIView (ViewTracker)

- (void)traversing {
	VTLog(@"The level structure of %@:",NSStringFromClass([self class]));
	VTLog(@"----------  begin   ----------");
	[self traversingSubView:self level:1];
	VTLog(@"----------  end   ----------")
}

- (void)traversingSubView:(UIView *)view level:(NSUInteger)level {
	NSArray *subviews = view.subviews;
	//if there is no subview, then return
	if (subviews.count == 0) return;
	for (UIView *subview in subviews) {
		//display indentation by the space character of the 'level'
		NSString *blank = @"";
		for (NSUInteger i = 1; i < level; i++) {
			blank = [NSString stringWithFormat:@" %@", blank];
		}
		//print subview's class name
		VTLog(@"%@%@: %@", blank, @(level), NSStringFromClass([subview class]));
		//recursive fetch the subview of 'subview'
		[self traversingSubView:subview level:(level+1)];
	}
}

@end
