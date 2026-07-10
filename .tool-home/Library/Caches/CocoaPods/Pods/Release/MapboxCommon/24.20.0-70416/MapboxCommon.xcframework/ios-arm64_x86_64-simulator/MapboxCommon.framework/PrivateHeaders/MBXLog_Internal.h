// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>

@class MBXLogThrottler;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Write log messages.
 *
 * The backends shipped with the SDK Common Library are thread-safe.
 */
NS_SWIFT_NAME(Log)
__attribute__((visibility ("default")))
@interface MBXLog : NSObject

// This class provides custom init which should be called
- (nonnull instancetype)init NS_UNAVAILABLE;

// This class provides custom init which should be called
+ (nonnull instancetype)new NS_UNAVAILABLE;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Writes a debug message. Use it to output verbose data to understand how your app executes.
 *
 * @param message The log message.
 * @param category An optional string representing a log category.
 */
+ (void)debugForMessage:(nonnull NSString *)message
               category:(nullable NSString *)category;
+ (void)debugForMessage:(nonnull NSString *)message
               category:(nullable NSString *)category
              throttler:(nonnull MBXLogThrottler *)throttler;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Writes an info message. Use it to log normal app behavior.
 *
 * @param message The log message.
 * @param category An optional string representing a log category.
 */
+ (void)infoForMessage:(nonnull NSString *)message
              category:(nullable NSString *)category;
+ (void)infoForMessage:(nonnull NSString *)message
              category:(nullable NSString *)category
             throttler:(nonnull MBXLogThrottler *)throttler;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Writes a warning. Use it to output data in a situation that might be a problem, or in an unusual situation.
 *
 * @param message The log message.
 * @param category An optional string representing a log category.
 */
+ (void)warningForMessage:(nonnull NSString *)message
                 category:(nullable NSString *)category;
+ (void)warningForMessage:(nonnull NSString *)message
                 category:(nullable NSString *)category
                throttler:(nonnull MBXLogThrottler *)throttler;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Writes an error message. Use it to output data when a significant error occurred.
 *
 * @param message The log message.
 * @param category An optional string representing a log category.
 */
+ (void)errorForMessage:(nonnull NSString *)message
               category:(nullable NSString *)category;
+ (void)errorForMessage:(nonnull NSString *)message
               category:(nullable NSString *)category
              throttler:(nonnull MBXLogThrottler *)throttler;

@end
