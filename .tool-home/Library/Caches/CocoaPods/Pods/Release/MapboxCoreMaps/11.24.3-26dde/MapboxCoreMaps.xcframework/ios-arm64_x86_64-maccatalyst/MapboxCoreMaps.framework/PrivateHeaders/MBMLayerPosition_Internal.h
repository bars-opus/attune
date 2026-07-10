// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Specifies position of a layer that is added via addStyleLayer method.
 */
NS_SWIFT_NAME(__LayerPosition)
__attribute__((visibility ("default")))
@interface MBMLayerPosition : NSObject

// This class provides custom init which should be called
- (nonnull instancetype)init NS_UNAVAILABLE;

// This class provides custom init which should be called
+ (nonnull instancetype)new NS_UNAVAILABLE;

- (nonnull instancetype)initWithAbove:(nullable NSString *)above
                                below:(nullable NSString *)below
                                   at:(nullable NSNumber *)at;

/** Layer should be positioned above specified layer id. */
@property (nonatomic, readonly, nullable, copy) NSString *above;

/** Layer should be positioned below specified layer id. */
@property (nonatomic, readonly, nullable, copy) NSString *below;

/** Layer should be positioned at specified index in a layers stack. */
@property (nonatomic, readonly, nullable) NSNumber *at;


- (BOOL)isEqualToLayerPosition:(nonnull MBMLayerPosition *)other;

@end
