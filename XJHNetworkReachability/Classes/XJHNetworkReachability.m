//
//  XJHNetworkReachability.m
//  XJHNetworkReachability
//
//  Created by xujunhao on 2018/9/5.
//

#import "XJHNetworkReachability.h"
#import <UIKit/UIKit.h>
#import <SystemConfiguration/CaptiveNetwork.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCellularData.h>
#import <CoreTelephony/CTCarrier.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import <netdb.h>
#import <sys/socket.h>
#import <netinet/in.h>

typedef NS_ENUM(NSInteger, XJHNetworkInnerType) {
	XJHNetworkInnerTypeUnknown = 0,
	XJHNetworkInnerTypeOffline,
	XJHNetworkInnerTypeWiFi,
	XJHNetworkInnerTypeCellularData
};

NSString * const kXJHNetworkReachabilityChangeNotification = @"XJHNetworkReachabilityChangeNotification";
NSString * const kXJHNetworkReachabilityFirstRunFlag	=	@"XJHNetworkReachabilityFirstRunFlag";

static XJHNetworkReachability *instance = nil;

API_AVAILABLE(ios(9.0))
@interface XJHNetworkReachability () {
	SCNetworkReachabilityRef reachabilityRef;
}

///是否弹框告知用户网络状态
@property (nonatomic, assign) BOOL popAlert;
///
@property (nonatomic, assign) BOOL checkActiveLaterWhenDidBecomeActive;
///
@property (nonatomic, assign) BOOL checkingActiveLater;
///
@property (nonatomic, assign) BOOL hasLaunched;

///蜂窝网络数据
@property (nonatomic, strong) CTCellularData *cellularData;
///回调数组
@property (nonatomic, strong) NSMutableArray<dispatch_block_t> *callbackArray;
///最近的可达性状态
@property (nonatomic, assign) XJHNetworkReachabilityStatus preStatus;

@property (nonatomic, copy) XJHNetworkReachabilityCompletion completion;
@property (nonatomic, copy) XJHNetworkReachabilityRestriction restriction;
@property (nonatomic, copy) XJHNetworkReachabilityServiceShutdown shutdown;
@property (nonatomic, copy) XJHNetworkReachabilityMonitor monitor;
@property (nonatomic, strong) XJHNRParamBuilder *restrictionBuilder;
@property (nonatomic, strong) XJHNRParamBuilder *shutdownBuilder;

@property (nonatomic, assign) XJHNetworkConnectType connect;
@property (nonatomic, assign) XJHNetworkCarrierType carrier;


@end

@implementation XJHNetworkReachability

#pragma mark - Life Cycle Method

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	NSLog(@"---XJHNetworkReachability---dealloc---");
}

- (instancetype)init {
	if (self = [super init]) {
		
	}
	return self;
}

#pragma mark - Singleton Method

+ (instancetype)sharedInstance {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[self alloc] init];
	});
	return instance;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [super allocWithZone:zone];
	});
	return instance;
}

#pragma mark - Public Methods

+ (void)popAlertEnable:(BOOL)enable {
	[[self sharedInstance] setPopAlert:enable];
}

+ (void)startWithCompletion:(XJHNetworkReachabilityCompletion)completion
				restriction:(XJHNetworkReachabilityRestriction)restriction
				   shutdown:(XJHNetworkReachabilityServiceShutdown)shutdown {
	[[self sharedInstance] setCompletion:completion];
	[[self sharedInstance] setRestriction:restriction];
	[[self sharedInstance] setShutdown:shutdown];
	[[self sharedInstance] setRestrictionBuilder:[[XJHNRParamBuilder alloc] init]];
	[[self sharedInstance] setShutdownBuilder:[[XJHNRParamBuilder alloc] init]];
	[[self sharedInstance] restriction]([[self sharedInstance] restrictionBuilder]);
	[[self sharedInstance] shutdown]([[self sharedInstance] shutdownBuilder]);
	[[self sharedInstance] setupNetworkReachability];
}

+ (void)stop {
	[[self sharedInstance] cleanNetworkReachability];
}

+ (void)monitor:(XJHNetworkReachabilityMonitor)monitor {
	[[self sharedInstance] setMonitor:monitor];
}

+ (XJHNetworkReachabilityStatus)currentStatus {
	return [[self sharedInstance] preStatus];
}

#pragma mark - Config Methods

- (void)setupNetworkReachability {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
	
	reachabilityRef = ({
		struct sockaddr_in zeroAddress;
		bzero(&zeroAddress, sizeof(zeroAddress));
		zeroAddress.sin_len = sizeof(zeroAddress);
		zeroAddress.sin_family = AF_INET;
		SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *) &zeroAddress);
	});
	
	// 此句会触发系统弹出权限询问框
	SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	
	BOOL firstRun = ({
		BOOL value = [[NSUserDefaults standardUserDefaults] boolForKey:kXJHNetworkReachabilityFirstRunFlag];
		if (!value) {
			[[NSUserDefaults standardUserDefaults] setBool:YES forKey:kXJHNetworkReachabilityFirstRunFlag];
			[[NSUserDefaults standardUserDefaults] synchronize];
		}
		!value;
	});
	
	__weak typeof(self) weakSelf = self;
	dispatch_block_t startBlock = ^{
		__strong typeof(weakSelf) strongSelf = weakSelf;
		[strongSelf startReachabilityObserve];
		[strongSelf startCellularDataObserve];
	};
	
	if (firstRun) {
		//第一次运行系统会弹框，需要延迟一下再判断，否则会拿到不准确的结果
		[self waitActive:^{
			startBlock();
		}];
	} else {
		if (!self.hasLaunched) {
			startBlock();
			self.hasLaunched = YES;
		} else {
			[self startCheck];
		}
	}
}

- (void)cleanNetworkReachability {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (@available(iOS 9.0, *)) {
		self.cellularData.cellularDataRestrictionDidUpdateNotifier = nil;
	} else {
		// Fallback on earlier versions
	}
	self.cellularData = nil;
	SCNetworkReachabilityUnscheduleFromRunLoop(reachabilityRef, CFRunLoopGetMain(), kCFRunLoopCommonModes);
	reachabilityRef = nil;
	
	[self cancelEnsureActive];
	[self hideNetworkAlert];
	
	[self.callbackArray removeAllObjects];
	self.callbackArray = nil;
	
	self.preStatus = XJHNetworkReachabilityStatusUnknown;
	self.checkActiveLaterWhenDidBecomeActive = NO;
	self.checkingActiveLater = NO;
	
	self.completion = nil;
	self.restriction = nil;
	self.shutdown = nil;
	self.restrictionBuilder = nil;
	self.shutdownBuilder = nil;
	self.monitor = nil;
	
	self.connect = XJHNetworkConnectTypeUnknown;
	self.carrier = XJHNetworkCarrierTypeUnknown;
}

#pragma mark - Active Check Method

/**
 如果当前 app 是非可响应状态（一般是启动的时候），则等到 app 激活且保持一秒以上，再回调
 因为启动完成后，2 秒内可能会再次弹出「是否允许 XXX 使用网络」，此时的 applicationState 是 UIApplicationStateInactive）

 @param block 待执行block
 */
- (void)waitActive:(dispatch_block_t)block {
	if (block) {
		[self.callbackArray addObject:[block copy]];
	}
	if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
		self.checkActiveLaterWhenDidBecomeActive = YES;
	} else {
		[self checkActiveLater];
	}
}

- (void)checkActiveLater {
	self.checkingActiveLater = YES;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self ensureActive];
	});
}

- (void)ensureActive {
	self.checkingActiveLater = NO;
	for (dispatch_block_t block in self.callbackArray) {
		block();
	}
	[self.callbackArray removeAllObjects];
}

- (void)cancelEnsureActive {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(ensureActive) object:nil];
}

#pragma mark - System Reachability Methods

static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void* info) {
	XJHNetworkReachability *reachability = (__bridge XJHNetworkReachability*)info;
	if (![reachability isKindOfClass:[XJHNetworkReachability class]]) {
		return;
	}
	[reachability startCheck];
}


/**
 监听用户从 Wi-Fi 切换到 蜂窝数据，或者从蜂窝数据切换到 Wi-Fi，另外当从授权到未授权，或者未授权到授权也会调用该方法
 */
- (void)startReachabilityObserve {
	SCNetworkReachabilityContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
	if (SCNetworkReachabilitySetCallback(reachabilityRef, ReachabilityCallback, &context)) {
		if (SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode)) {
			NSLog(@"成功设置网络可达性监测观察者");
		}
	}
}

- (void)startCellularDataObserve {
	// 利用 cellularDataRestrictionDidUpdateNotifier 的回调时机来进行首次检查，因为如果启动时就去检查 会得到 kCTCellularDataRestrictedStateUnknown 的结果
	if (@available(iOS 9.0, *)) {
		__weak typeof(self) weakSelf = self;
		self.cellularData.cellularDataRestrictionDidUpdateNotifier = ^(CTCellularDataRestrictedState state) {
			__strong typeof(weakSelf) strongSelf = weakSelf;
			dispatch_async(dispatch_get_main_queue(), ^{
				[strongSelf startCheck];
			});
		};
	} else {
		// Fallback on earlier versions
	}
}

#pragma mark - Notification Dispatch Method

- (void)applicationWillResignActive {
	[self hideNetworkAlert];
	if (self.checkingActiveLater) {
		[self cancelEnsureActive];
		self.checkActiveLaterWhenDidBecomeActive = YES;
	}
}

- (void)applicationDidBecomeActive {
	if (self.checkActiveLaterWhenDidBecomeActive) {
		[self checkingActiveLater];
		self.checkActiveLaterWhenDidBecomeActive = NO;
	}
}

#pragma mark - CellularData State Dispatch Method

- (void)dispatchCellularDataState:(CTCellularDataRestrictedState)state {
	switch (state) {
		case kCTCellularDataRestricted:
		{
			// 系统 API 返回 无蜂窝数据访问权限
			__weak typeof(self) weakSelf = self;
			[self getCurrentNetworkType:^(XJHNetworkInnerType type) {
				__strong typeof(weakSelf) strongSelf = weakSelf;
				switch (type) {
					case XJHNetworkInnerTypeCellularData:
					case XJHNetworkInnerTypeWiFi:
					{
						//若用户是通过蜂窝数据 或 WLAN 上网，走到这里来 说明权限被关闭
						[strongSelf notifyUser:XJHNetworkReachabilityStatusRestricted];
					}
						break;
					default:
						//可能开了飞行模式，无法判断
						[strongSelf notifyUser:XJHNetworkReachabilityStatusUnknown];
						break;
				}
			}];
		}
			break;
		case kCTCellularDataNotRestricted:
		{
			//系统 API 访问有有蜂窝数据访问权限，那就必定有 Wi-Fi 数据访问权限
			__weak typeof(self) weakSelf = self;
			[self getCurrentNetworkType:^(XJHNetworkInnerType type) {
				__strong typeof(weakSelf) strongSelf = weakSelf;
				switch (type) {
					case XJHNetworkInnerTypeUnknown:
					case XJHNetworkInnerTypeOffline:
					{
						//可能开了飞行模式
						[strongSelf notifyUser:XJHNetworkReachabilityStatusUnknown];
					}
						break;
					default:
						//网络正常可达
						[strongSelf notifyUser:XJHNetworkReachabilityStatusNormal];
						break;
				}
			}];
		}
			break;
		case kCTCellularDataRestrictedStateUnknown:
		{
			//CTCellularData 刚开始初始化的时候，可能会拿到 kCTCellularDataRestrictedStateUnknown 延迟一下再试就好了
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				if (@available(iOS 9.0, *)) {
					[self startCheck];
				} else {
					// Fallback on earlier versions
				}
			});
		}
			break;
		default:
			break;
	}
}

#pragma mark - Check Methods

- (void)startCheck {
//	if ([UIDevice currentDevice].systemVersion.floatValue < 10.0) {
//		if ([self currentReachable]) {
//			//用 currentReachable 判断，若返回的为 YES 则说明：
//			//1. 用户选择了 「WALN 与蜂窝移动网」并处于其中一种网络环境下 2. 用户选择了 「WALN」并处于 WALN 网络环境下
//			[self notifyUser:XJHNetworkReachabilityStatusNormal];
//		} else {
//			[self notifyUser:XJHNetworkReachabilityStatusUnknown];
//		}
//		return;
//	}
	if (@available(iOS 9.0, *)) {
		[self dispatchCellularDataState:self.cellularData.restrictedState];
	} else {
		// Fallback on earlier versions
	}
}

#pragma mark - Notify User Methods

- (void)notifyUser:(XJHNetworkReachabilityStatus)status {
	if (self.popAlert) {
		switch (status) {
			case XJHNetworkReachabilityStatusUnknown:
			{
				[self showNetworkShutdownAlert];
			}
				break;
			case XJHNetworkReachabilityStatusRestricted:
			{
				[self showNetworkRestrictionAlert];
			}
				break;
			case XJHNetworkReachabilityStatusNormal:
			{
				[self hideNetworkAlert];
				!self.completion?:self.completion(self.connect, self.carrier);
			}
				break;
			default:
				break;
		}
	}
	if (_preStatus != status) {
		_preStatus = status;
		if (status == XJHNetworkReachabilityStatusNormal) {
			//隐藏弹出的alert
			UIViewController *presentedVC = [[[[UIApplication sharedApplication] delegate] window] rootViewController].presentedViewController;
			if ([presentedVC isKindOfClass:[UIAlertController class]]) {
				[presentedVC dismissViewControllerAnimated:YES completion:nil];
			}
		}
		!self.monitor?:self.monitor(status, self.connect, self.carrier);
		[[NSNotificationCenter defaultCenter] postNotificationName:kXJHNetworkReachabilityChangeNotification object:nil];
	}
}

- (void)showNetworkRestrictionAlert {
	UIAlertController *alertController = [UIAlertController alertControllerWithTitle:self.restrictionBuilder.title?:@"网络连接受限" message:self.restrictionBuilder.message?:@"检测到网络权限可能未开启，您可以在\"设置\"中检查蜂窝移动网络" preferredStyle:UIAlertControllerStyleAlert];
	[alertController addAction:[UIAlertAction actionWithTitle:self.restrictionBuilder.cancel?:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[alertController addAction:[UIAlertAction actionWithTitle:self.restrictionBuilder.setting?:@"设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
	}]];
	[[[[[UIApplication sharedApplication] delegate] window] rootViewController] presentViewController:alertController animated:YES completion:nil];
}

- (void)showNetworkShutdownAlert {
	UIAlertController *alertController = [UIAlertController alertControllerWithTitle:self.shutdownBuilder.title?:@"网络连接失败" message:self.shutdownBuilder.message?:@"检测网络连接可能被关闭或处于飞行模式，请确认" preferredStyle:UIAlertControllerStyleAlert];
	[alertController addAction:[UIAlertAction actionWithTitle:self.shutdownBuilder.cancel?:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[alertController addAction:[UIAlertAction actionWithTitle:self.shutdownBuilder.setting?:@"设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
	}]];
	[[[[[UIApplication sharedApplication] delegate] window] rootViewController] presentViewController:alertController animated:YES completion:nil];
}

- (void)hideNetworkAlert {
	
}

#pragma mark - Network Related Method

- (void)getCurrentNetworkType:(void(^)(XJHNetworkInnerType type))block {
	if ([self isWiFiEnable]) {
		self.connect = XJHNetworkConnectTypeWiFi;
		self.carrier = XJHNetworkCarrierTypeWiFi;
		!block?:block(XJHNetworkInnerTypeWiFi);
		return;
	}
	XJHNetworkInnerType innerType = [self getNetworkTypeFromStatusBar];
	if (innerType == XJHNetworkInnerTypeWiFi) {
		// 这时候从状态栏拿到的是 Wi-Fi 说明状态栏没有刷新，延迟一会再获取
		self.connect = XJHNetworkConnectTypeUnknown;
		self.carrier = XJHNetworkCarrierTypeUnknown;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[self getCurrentNetworkType:block];
		});
	} else {
		!block?:block(innerType);
	}
}

- (XJHNetworkInnerType)getNetworkTypeFromStatusBar {
	@try {
		UIApplication *app = [UIApplication sharedApplication];
		UIView *statusBar = [app valueForKeyPath:@"statusBar"];
		if (!statusBar) {
			XJHNetworkInnerType type = XJHNetworkInnerTypeUnknown;
			self.connect = XJHNetworkConnectTypeUnknown;
			self.carrier = XJHNetworkCarrierTypeUnknown;
			
			CTTelephonyNetworkInfo *telephonyInfo = [[CTTelephonyNetworkInfo alloc] init];
			NSString *access = telephonyInfo.currentRadioAccessTechnology;
			if (!access) {
				self.connect = XJHNetworkConnectTypeUnknown;
				self.carrier = XJHNetworkCarrierTypeUnknown;
				type = XJHNetworkInnerTypeUnknown;
			} else {
				type =XJHNetworkInnerTypeCellularData;
				if ([access isEqualToString:@"CTRadioAccessTechnologyGPRS"]) {
					self.connect = XJHNetworkConnectType2G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyEdge"]) {
					self.connect = XJHNetworkConnectType2G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyWCDMA"]) {
					self.connect = XJHNetworkConnectType3G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyHSDPA"]) {
					self.connect = XJHNetworkConnectType3G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyHSUPA"]) {
					self.connect = XJHNetworkConnectType3G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyCDMA1x"]) {
					self.connect = XJHNetworkConnectType2G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyCDMAEVDORev0"]) {
					self.connect = XJHNetworkConnectType3G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyCDMAEVDORevA"]) {
					self.connect = XJHNetworkConnectType3G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyCDMAEVDORevB"]) {
					self.connect = XJHNetworkConnectType3G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyeHRPD"]) {
					self.connect = XJHNetworkConnectType3G;
				} else if ([access isEqualToString:@"CTRadioAccessTechnologyLTE"]) {
					self.connect = XJHNetworkConnectType4G;
				} else {
					self.connect = XJHNetworkConnectTypeUnknown;
					type = XJHNetworkInnerTypeUnknown;
				}
				[self getCurrentNetworkCarrierInfo];
			}
			return type;
		}
		BOOL isModernStatusBar = [statusBar isKindOfClass:NSClassFromString(@"UIStatusBar_Modern")];
		if (isModernStatusBar) {
			// 在 iPhone X 上 statusBar 属于 UIStatusBar_Modern ，需要特殊处理
			id currentData = [statusBar valueForKeyPath:@"statusBar.currentData"];
			BOOL wifiEnable = [[currentData valueForKeyPath:@"_wifiEntry.isEnabled"] boolValue];
			// 这里不能用 _cellularEntry.isEnabled 来判断，该值即使关闭仍然有是 YES
			BOOL cellularEnable = [[currentData valueForKeyPath:@"_cellularEntry.type"] boolValue];
			if (wifiEnable) {
				self.connect = XJHNetworkConnectTypeWiFi;
				self.carrier = XJHNetworkCarrierTypeWiFi;
			} else {
				if (cellularEnable) {
					[self getCurrentNetworkCarrierInfo];
					///获取蜂窝数据类型
					UIView *foregroundView = [statusBar valueForKeyPath:@"foregroundView"];
					if (foregroundView.subviews.count >= 3) {
						for (id child in foregroundView.subviews[2].subviews) {
							if ([child isKindOfClass:NSClassFromString(@"_UIStatusBarWifiSignalView")]) {
								self.connect = XJHNetworkConnectTypeWiFi;
								break;
							} else if ([child isKindOfClass:NSClassFromString(@"_UIStatusBarStringView")]) {
								NSString *type = [child valueForKey:@"_originalText"];
								if ([type containsString:@"G"]) {
									if ([type isEqualToString:@"2G"]) {
										self.connect = XJHNetworkConnectType2G;
									} else if ([type isEqualToString:@"3G"]) {
										self.connect = XJHNetworkConnectType3G;
									} else if ([type isEqualToString:@"4G"]) {
										self.connect = XJHNetworkConnectType4G;
									} else {
										self.connect = XJHNetworkConnectTypeUnknown;
									}
								} else {
									self.connect = XJHNetworkConnectTypeUnknown;
								}
								break;
							} else {
								self.connect = XJHNetworkConnectTypeUnknown;
								break;
							}
						}
					} else {
						self.connect = XJHNetworkConnectTypeUnknown;
					}
				} else {
					self.connect = XJHNetworkConnectTypeUnknown;
					self.carrier = XJHNetworkCarrierTypeUnknown;
				}
			}
			return wifiEnable ? XJHNetworkInnerTypeWiFi : cellularEnable ? XJHNetworkInnerTypeCellularData : XJHNetworkInnerTypeOffline;
		} else {
			// 传统的 statusBar
			NSInteger type = 0;
			NSArray *children = [[statusBar valueForKeyPath:@"foregroundView"] subviews];
			for (id child in children) {
				if ([child isKindOfClass:NSClassFromString(@"UIStatusBarDataNetworkItemView")]) {
					type = [[child valueForKeyPath:@"dataNetworkType"] intValue];
					switch (type) {
						case 0://无网络
							self.connect = XJHNetworkConnectTypeUnknown;
							self.carrier = XJHNetworkCarrierTypeUnknown;
							break;
						case 1:
							self.connect = XJHNetworkConnectType2G;
							break;
						case 2:
							self.connect = XJHNetworkConnectType3G;
							break;
						case 3:
							self.connect = XJHNetworkConnectType4G;
							break;
						case 5:
							self.connect = XJHNetworkConnectTypeWiFi;
							self.carrier = XJHNetworkCarrierTypeWiFi;
							break;
						default:
							self.connect = XJHNetworkConnectTypeUnknown;
							self.carrier = XJHNetworkCarrierTypeUnknown;
							break;
					}
					break;
				}
			}
			if (self.connect != XJHNetworkConnectTypeUnknown && self.connect != XJHNetworkConnectTypeWiFi) {
				[self getCurrentNetworkCarrierInfo];
			}
			return type == 0 ? XJHNetworkInnerTypeOffline : type == 5 ? XJHNetworkInnerTypeWiFi : XJHNetworkInnerTypeCellularData;
		}
	} @catch (NSException *exception) {
		NSLog(@"从状态栏获取网络类型发生异常：%@", exception);
		self.connect = XJHNetworkConnectTypeUnknown;
		self.carrier = XJHNetworkCarrierTypeUnknown;
	}
	return XJHNetworkInnerTypeUnknown;
}

- (BOOL)isWiFiEnable {
	NSArray *interfaces = (__bridge_transfer NSArray *)CNCopySupportedInterfaces();
	if (!interfaces) {
		return NO;
	}
	NSDictionary *info = nil;
	for (NSString *ifnam in interfaces) {
		info = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam);
		if (info && [info count]) { break; }
	}
	return info != nil;
}

//查询mnc的wiki:https://en.wikipedia.org/wiki/Mobile_country_code
- (void)getCurrentNetworkCarrierInfo {
	CTTelephonyNetworkInfo *telephonyInfo = [[CTTelephonyNetworkInfo alloc] init];
	CTCarrier *carrier = [telephonyInfo subscriberCellularProvider];
	if ([carrier.mobileCountryCode isEqualToString:@"460"]) {
		NSString *mnc = carrier.mobileNetworkCode;
		if ([mnc isEqualToString:@"00"] || [mnc isEqualToString:@"02"] || [mnc isEqualToString:@"04"] || [mnc isEqualToString:@"07"] || [mnc isEqualToString:@"08"]) {
			self.carrier = XJHNetworkCarrierTypeChinaMobile;
		} else if ([mnc isEqualToString:@"01"] || [mnc isEqualToString:@"06"] || [mnc isEqualToString:@"09"]) {
			self.carrier = XJHNetworkCarrierTypeChinaUnicom;
		} else if ([mnc isEqualToString:@"03"] || [mnc isEqualToString:@"05"] || [mnc isEqualToString:@"11"] || [mnc isEqualToString:@"20"]) {
			self.carrier = XJHNetworkCarrierTypeChinaTelecom;
		} else {
			self.carrier = XJHNetworkCarrierTypeUnknown;
		}
	} else {
		self.carrier = XJHNetworkCarrierTypeUnknown;
	}
}

- (BOOL)currentReachable {
	SCNetworkReachabilityFlags flags;
	if (SCNetworkReachabilityGetFlags(reachabilityRef, &flags)) {
		if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
			return NO;
		} else {
			return YES;
		}
	}
	return NO;
}

#pragma mark - Lazy Load Method

- (CTCellularData *)cellularData  API_AVAILABLE(ios(9.0)){
	if (!_cellularData) {
		_cellularData = [[CTCellularData alloc] init];
	}
	return _cellularData;
}

- (NSMutableArray<dispatch_block_t> *)callbackArray {
	if (!_callbackArray) {
		_callbackArray = [[NSMutableArray alloc] initWithCapacity:10];
	}
	return _callbackArray;
}

@end
