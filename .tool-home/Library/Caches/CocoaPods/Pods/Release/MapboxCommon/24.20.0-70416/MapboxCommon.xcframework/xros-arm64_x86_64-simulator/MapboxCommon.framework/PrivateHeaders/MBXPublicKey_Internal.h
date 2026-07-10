// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>
@class MBXDataRef;
@class MBXExpected<__covariant Value, __covariant Error>;

@class MBXSignature;
typedef NS_ENUM(NSInteger, MBXSignatureAlgorithm);

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Represents a public key used for cryptographic operations.
 */
NS_SWIFT_NAME(PublicKey)
@protocol MBXPublicKey
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Retrieves the algorithm associated with the key.
 */
- (MBXSignatureAlgorithm)getAlgorithm;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Verifies the given signature against the provided data.
 */
- (nonnull MBXExpected<NSNumber *, NSString *> *)verifyForSignature:(nonnull MBXSignature *)signature
                                                               data:(nonnull MBXDataRef *)data;
@end
