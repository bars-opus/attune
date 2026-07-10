// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>

@protocol MBXSizedReadStream;
typedef NS_ENUM(NSInteger, MBXHttpMethod);
typedef NS_ENUM(NSInteger, MBXNetworkRestriction);

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * HTTP Request representation used by the backend Service
 */
NS_SWIFT_NAME(Request)
__attribute__((visibility ("default")))
@interface MBXHttpBackendRequest : NSObject

// This class provides custom init which should be called
- (nonnull instancetype)init NS_UNAVAILABLE;

// This class provides custom init which should be called
+ (nonnull instancetype)new NS_UNAVAILABLE;

- (nonnull instancetype)initWithMethod:(MBXHttpMethod)method
                                   url:(nonnull NSString *)url
                               headers:(nonnull NSDictionary<NSString *, NSString *> *)headers
                               timeout:(uint64_t)timeout
                    networkRestriction:(MBXNetworkRestriction)networkRestriction
                                  body:(nullable id<MBXSizedReadStream>)body
                                 flags:(uint32_t)flags;

/** HTTP request method. See HttpRequest for details. */
@property (nonatomic, readwrite) MBXHttpMethod method;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * HTTP request url. See HttpRequest for details.
 */
@property (nonatomic, readonly, nonnull, copy) NSString *url;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * HTTP request headers. See HttpRequest for details.
 */
@property (nonatomic, readwrite, nonnull, copy) NSDictionary<NSString *, NSString *> *headers;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Connection timeout. See HttpRequest for details.
 */
@property (nonatomic, readonly) uint64_t timeout;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * See HttpRequest for details.
 */
@property (nonatomic, readonly) MBXNetworkRestriction networkRestriction;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * The body for the request
 */
@property (nonatomic, readonly, nullable) id<MBXSizedReadStream> body;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * See HttpRequest for details.
 */
@property (nonatomic, readonly) uint32_t flags;


@end
