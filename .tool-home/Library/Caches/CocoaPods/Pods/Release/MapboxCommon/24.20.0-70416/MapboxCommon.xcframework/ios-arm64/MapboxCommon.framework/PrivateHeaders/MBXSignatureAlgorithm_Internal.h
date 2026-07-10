// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>

// NOLINTNEXTLINE(modernize-use-using)
typedef NS_ENUM(NSInteger, MBXSignatureAlgorithm)
{
    /**
     * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
     * ECDSA signing algorithm (the curve is defined by the key size: P-256, P-384, or P-521)
     */
    MBXSignatureAlgorithmECDSA
} NS_SWIFT_NAME(SignatureAlgorithm);

NSString* MBXSignatureAlgorithmToString(MBXSignatureAlgorithm signature_algorithm);
