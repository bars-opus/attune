// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>
@class MBXDataRef;
@class MBXExpected<__covariant Value, __covariant Error>;

typedef NS_ENUM(NSInteger, MBXSignatureAlgorithm);
typedef NS_ENUM(NSInteger, MBXSignatureEncoding);

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Represents a cryptographic signature. To interact with signatures, use the interfaces provided by PublicKey and
 * PrivateKey.
 */
NS_SWIFT_NAME(Signature)
__attribute__((visibility ("default")))
@interface MBXSignature : NSObject

// This class provides custom init which should be called
- (nonnull instancetype)init NS_UNAVAILABLE;

// This class provides custom init which should be called
+ (nonnull instancetype)new NS_UNAVAILABLE;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Constructs a Signature object from the signature bytes and the relevant metadata.
 */
- (nonnull instancetype)initWithData:(nonnull MBXDataRef *)data
                            encoding:(MBXSignatureEncoding)encoding
                           algorithm:(MBXSignatureAlgorithm)algorithm;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * The raw bytes of the signature.
 */
- (nonnull MBXDataRef *)getData __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * The algorithm used for the signature.
 */
- (MBXSignatureAlgorithm)getAlgorithm;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * The encoding format of the signature.
 */
- (MBXSignatureEncoding)getEncoding;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Re-encodes the signature to the specified encoding format.
 */
- (nonnull MBXExpected<MBXSignature *, NSString *> *)reEncodeForNewEncoding:(MBXSignatureEncoding)newEncoding __attribute((ns_returns_retained));

@end
