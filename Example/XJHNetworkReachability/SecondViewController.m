//
//  SecondViewController.m
//  XJHNetworkReachability_Example
//
//  Created by xujunhao on 2018/9/6.
//  Copyright © 2018年 cocoadogs. All rights reserved.
//

#import "SecondViewController.h"
#import <Masonry/Masonry.h>
#import <ReactiveObjC/ReactiveObjC.h>
#import "XJHNetworkReachability.h"
#import "UIView+ViewTracker.h"

@interface SecondViewController ()

@property (nonatomic, strong) UIButton *reachabilityBtn;

@end

@implementation SecondViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
	[self buildUI];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc {
	NSLog(@"---SecondViewController---dealloc---");
}

#pragma mark - UI Build Method

- (void)buildUI {
	self.view.backgroundColor = [UIColor whiteColor];
	[self.view addSubview:self.reachabilityBtn];
	[self.reachabilityBtn mas_makeConstraints:^(MASConstraintMaker *make) {
		make.center.equalTo(self.view);
		make.size.mas_equalTo(CGSizeMake(100, 40));
	}];
}

#pragma mark - Private Method

- (void)checkReachability {
	[self printStatusBar];
	[XJHNetworkReachability popAlertEnable:YES];
	[XJHNetworkReachability startWithCompletion:^(XJHNetworkConnectType connect, XJHNetworkCarrierType carrier) {
		NSLog(@"网络正常，连接类型 = %@，运营商 = %@", @(connect), @(carrier));
	} restriction:^(XJHNRParamBuilder *builder) {
		builder.title = @"是谁把网络权限关掉了";
	} shutdown:^(XJHNRParamBuilder *builder) {
		builder.title = @"我去，网络被关掉了";
	}];
	[XJHNetworkReachability monitor:^(XJHNetworkReachabilityStatus status, XJHNetworkConnectType connect, XJHNetworkCarrierType carrier) {
		NSLog(@"网络可达性发生改变\n网络状态 = %@，连接类型 = %@，运营商 = %@", @(status), @(connect), @(carrier));

	}];
}

- (void)printStatusBar {
	UIApplication *app = [UIApplication sharedApplication];
	UIView *statusBar = [app valueForKeyPath:@"statusBar"];
	[statusBar traversing];
}

#pragma mark - Lazy Load Methods

- (UIButton *)reachabilityBtn {
	if (!_reachabilityBtn) {
		_reachabilityBtn = [[UIButton alloc] init];
		[_reachabilityBtn setTitle:@"网络状态" forState:UIControlStateNormal];
		[_reachabilityBtn setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
		[_reachabilityBtn setBackgroundColor:[UIColor whiteColor]];
		_reachabilityBtn.layer.cornerRadius = 5.0f;
		_reachabilityBtn.layer.borderWidth = 0.5f;
		_reachabilityBtn.layer.borderColor = [UIColor lightGrayColor].CGColor;
		@weakify(self)
		[[_reachabilityBtn rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(__kindof UIControl * _Nullable x) {
			@strongify(self)
			[self checkReachability];
		}];
	}
	return _reachabilityBtn;
}

@end
