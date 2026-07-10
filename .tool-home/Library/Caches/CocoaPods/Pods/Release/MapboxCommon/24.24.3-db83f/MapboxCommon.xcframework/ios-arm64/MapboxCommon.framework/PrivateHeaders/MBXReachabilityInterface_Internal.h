// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>
#import <MapboxCommon/MBXReachabilityChanged_Internal.h>

typedef NS_ENUM(NSInteger, MBXNetworkStatus);

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Interface to platform reachability module.
 */
NS_SWIFT_NAME(ReachabilityInterface)
@protocol MBXReachabilityInterface
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds a new listener.
 * The listener will be called immediately with the current network status.
 * @param listener The callback to receive the update.
 * @return int ID handle to remove the listener.
 */
- (uint64_t)addListenerForListener:(nonnull MBXReachabilityChanged)listener;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes a listener
 * The listener represented by this handle will be removed.
 * @param id Handle given by the addListener() method.
 * @return True in case of success, False otherwise
 */
- (BOOL)removeListenerForId:(uint64_t)id_;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Indicates whether the network is reachable or not.
 */
- (BOOL)isReachable;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the current network status
 */
- (MBXNetworkStatus)currentNetworkStatus;
@end
