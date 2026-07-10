// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>
@class MBXDataRef;
@class MBXExpected<__covariant Value, __covariant Error>;

@class MBXSignature;
typedef NS_ENUM(NSInteger, MBXSignatureAlgorithm);

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Represents a private key used for cryptographic operations.
 */
NS_SWIFT_NAME(PrivateKey)
@protocol MBXPrivateKey
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Retrieves the algorithm associated with the key.
 */
- (MBXSignatureAlgorithm)getAlgorithm;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Signs the given data.
 */
- (nonnull MBXExpected<MBXSignature *, NSString *> *)signForData:(nonnull MBXDataRef *)data;
@end
