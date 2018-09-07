//
//  XJHNetworkReachability.h
//  XJHNetworkReachability
//
//  Created by xujunhao on 2018/9/5.
//  网络数据连接可达性检测

#import <Foundation/Foundation.h>
#import "XJHNRParamBuilder.h"

extern NSString * const XJHNetworkReachabilityChangeNotification;

typedef NS_ENUM(NSInteger, XJHNetworkReachabilityStatus) {
	///网络可达性未知
	XJHNetworkReachabilityStatusUnknown = 0,
	///网络可达性正常
	XJHNetworkReachabilityStatusNormal,
	///网络可达性受限
	XJHNetworkReachabilityStatusRestricted
};

///网络连接类型
typedef NS_ENUM(NSInteger, XJHNetworkConnectType) {
	XJHNetworkConnectTypeUnknown = 0,
	XJHNetworkConnectType2G,
	XJHNetworkConnectType3G,
	XJHNetworkConnectType4G,
	XJHNetworkConnectTypeLTE,
	XJHNetworkConnectTypeWiFi
};

///网络运营商类型
typedef NS_ENUM(NSInteger, XJHNetworkCarrierType) {
	XJHNetworkCarrierTypeUnknown = 0,
	XJHNetworkCarrierTypeWiFi,
	XJHNetworkCarrierTypeChinaMobile,
	XJHNetworkCarrierTypeChinaTelecom,
	XJHNetworkCarrierTypeChinaUnicom
};

/**
 网络可达性监测回调

 @param status 网络可达性状态
 @param connect 网络连接类型
 @param carrier 网络运营商类型
 */
typedef void(^XJHNetworkReachabilityMonitor)(XJHNetworkReachabilityStatus status, XJHNetworkConnectType connect, XJHNetworkCarrierType carrier);

/**
 网络服务正常回调

 @param connect 网络连接类型
 @param carrier 网络运营商类型
 */
typedef void(^XJHNetworkReachabilityCompletion)(XJHNetworkConnectType connect, XJHNetworkCarrierType carrier);

/**
 网络服务关闭回调

 @param builder 参数配置builder
 */
typedef void(^XJHNetworkReachabilityServiceShutdown)(XJHNRParamBuilder *builder);

/**
 网络服务受限回调

 @param builder 参数配置builder
 */
typedef void(^XJHNetworkReachabilityRestriction)(XJHNRParamBuilder *builder);



@interface XJHNetworkReachability : NSObject


/**
 是否弹框提示用户开启网络数据权限

 @param enable 是否开启
 */
+ (void)popAlertEnable:(BOOL)enable;

/**
 开始检测网络可达性状态

 @param completion 网络可达性正常
 @param restriction 网络可达性受限
 @param shutdown 网络服务关闭
 */
+ (void)startWithCompletion:(XJHNetworkReachabilityCompletion)completion
				restriction:(XJHNetworkReachabilityRestriction)restriction
				   shutdown:(XJHNetworkReachabilityServiceShutdown)shutdown;

/**
 监测网络可达性

 @param monitor 网络可达性监测回调
 */
+ (void)monitor:(XJHNetworkReachabilityMonitor)monitor;

/**
 停止监测网络可达性状态
 */
+ (void)stop;

/**
 获取最近网络可达性

 @return 返回的是最近一次的网络状态检查结果，若距离上一次检测结果短时间内网络授权状态发生变化，该值可能会不准确
 */
+ (XJHNetworkReachabilityStatus)currentStatus;


@end
