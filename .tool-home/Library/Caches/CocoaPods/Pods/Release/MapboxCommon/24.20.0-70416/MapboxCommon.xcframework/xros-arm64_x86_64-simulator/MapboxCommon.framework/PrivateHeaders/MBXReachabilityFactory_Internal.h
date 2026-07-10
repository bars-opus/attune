// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>

@protocol MBXReachabilityInterface;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * A factory class used to instantiate a platform-specific interface to
 * monitor network reachability.
 */
NS_SWIFT_NAME(ReachabilityFactory)
__attribute__((visibility ("default")))
@interface MBXReachabilityFactory : NSObject

// This class provides custom init which should be called
- (nonnull instancetype)init NS_UNAVAILABLE;

// This class provides custom init which should be called
+ (nonnull instancetype)new NS_UNAVAILABLE;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Releases the instances of the Reachability service.
 *
 * The strong references from the factory to the Reachability service instance
 * will be released.
 * This can be used to release the Reachability service once it is no longer needed.
 * It may otherwise be kept until the end of the program.
 */
+ (void)reset;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * A factory method used to instantiate a platform-specific interface
 * to monitor network reachability.
 *
 * A singleton instance is allocated on the first call of this method or on call of this method after calling reset().
 * The instance is kept until a call to reset() releases it.
 * Subsequent calls to reachability will return the already allocated platform instance.
 *
 * @param hostname Optional DEPRECATED. This hostname is not used for anything.
 * @return A reachability interface
 */
+ (nonnull id<MBXReachabilityInterface>)reachabilityForHostname:(nullable NSString *)hostname __attribute((ns_returns_retained));

@end
