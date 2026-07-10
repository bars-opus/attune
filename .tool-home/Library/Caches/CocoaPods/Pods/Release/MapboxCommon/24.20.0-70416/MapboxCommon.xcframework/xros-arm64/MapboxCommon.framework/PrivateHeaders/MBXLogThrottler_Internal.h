// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Log throttler.
 */
NS_SWIFT_NAME(LogThrottler)
__attribute__((visibility ("default")))
@interface MBXLogThrottler : NSObject

// This class provides custom init which should be called
- (nonnull instancetype)init NS_UNAVAILABLE;

// This class provides custom init which should be called
+ (nonnull instancetype)new NS_UNAVAILABLE;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Constructs LogThrottler with specified logging interval.
 * @param interval interval, defaults to 1 minute.
 */
- (nonnull instancetype)initWithInterval:(nullable NSNumber *)interval;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Checks if logging is allowed based on the throttling interval.
 * If allowed, updates the last log time and returns true. If not allowed, returns false without updating.
 */
- (BOOL)onLog;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Allow to log next message right away without waiting for throttling timeout.
 */
- (void)allowLog;

@end
