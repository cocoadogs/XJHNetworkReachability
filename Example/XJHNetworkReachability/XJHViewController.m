//
//  XJHViewController.m
//  XJHNetworkReachability_Example
//
//  Created by xujunhao on 2018/9/5.
//  Copyright © 2018年 cocoadogs. All rights reserved.
//

#import "XJHViewController.h"
#import "SecondViewController.h"
#import <Masonry/Masonry.h>
#import <ReactiveObjC/ReactiveObjC.h>

@interface XJHViewController ()

@property (nonatomic, strong) UIButton *nextBtn;

@end

@implementation XJHViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
	[self buildUI];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UI Build Method

- (void)buildUI {
	self.view.backgroundColor = [UIColor whiteColor];
	self.navigationItem.title = @"YOYO";
	[self.view addSubview:self.nextBtn];
	[self.nextBtn mas_makeConstraints:^(MASConstraintMaker *make) {
		make.center.equalTo(self.view);
		make.size.mas_equalTo(CGSizeMake(100, 40));
	}];
}

#pragma mark - Lazy Load Methods

- (UIButton *)nextBtn {
	if (!_nextBtn) {
		_nextBtn = [[UIButton alloc] init];
		[_nextBtn setTitle:@"下一步" forState:UIControlStateNormal];
		[_nextBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
		[_nextBtn setBackgroundColor:[UIColor whiteColor]];
		_nextBtn.layer.cornerRadius = 5.0f;
		_nextBtn.layer.borderWidth = 0.5f;
		_nextBtn.layer.borderColor = [UIColor lightGrayColor].CGColor;
		@weakify(self)
		[[_nextBtn rac_signalForControlEvents:UIControlEventTouchUpInside] subscribeNext:^(__kindof UIControl * _Nullable x) {
			@strongify(self)
			[self.navigationController pushViewController:[[SecondViewController alloc] init] animated:YES];
		}];
	}
	return _nextBtn;
}

@end
