// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>
#import <MapboxCommon/MBXReadStream_Internal.h>

NS_SWIFT_NAME(SizedReadStream)
@protocol MBXSizedReadStream<MBXReadStream>
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Returns the total size of the stream in bytes, if known.
 */
- (nullable NSNumber *)getTotalSize;
@end
