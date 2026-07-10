// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>
@class MBXExpected<__covariant Value, __covariant Error>;

@protocol MBXPrivateKey;
@protocol MBXPublicKey;
typedef NS_ENUM(NSInteger, MBXSignatureAlgorithm);

NS_SWIFT_NAME(KeyReader)
__attribute__((visibility ("default")))
@interface MBXKeyReader : NSObject

// This class provides custom init which should be called
- (nonnull instancetype)init NS_UNAVAILABLE;

// This class provides custom init which should be called
+ (nonnull instancetype)new NS_UNAVAILABLE;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Reads a private key from PKCS#8 PEM formatted data.
 */
+ (nonnull MBXExpected<id<MBXPrivateKey>, NSString *> *)readPrivateKeyFromPKCS8PEMForPemData:(nonnull NSString *)pemData
                                                                                   algorithm:(MBXSignatureAlgorithm)algorithm __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Reads a public key from a X.509 certificate formatted in PEM.
 */
+ (nonnull MBXExpected<id<MBXPublicKey>, NSString *> *)readPublicKeyFromCertificatePEMForPemData:(nonnull NSString *)pemData
                                                                                       algorithm:(MBXSignatureAlgorithm)algorithm __attribute((ns_returns_retained));

@end
