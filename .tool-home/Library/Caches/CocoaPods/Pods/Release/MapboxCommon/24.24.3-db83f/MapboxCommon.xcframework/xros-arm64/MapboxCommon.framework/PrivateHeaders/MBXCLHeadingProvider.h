#import <Foundation/Foundation.h>

@class CLHeading;

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(13.0), watchos(6.0))
API_UNAVAILABLE(macos, tvos, visionos)
@protocol MBXCLHeadingObserver
- (void)onHeadingUpdate:(CLHeading *)heading;
@end

API_AVAILABLE(ios(13.0), watchos(6.0))
API_UNAVAILABLE(macos, tvos, visionos)
@protocol MBXCLHeadingProvider
- (void)addHeadingObserver:(id<MBXCLHeadingObserver>)observer;
- (void)removeHeadingObserver:(id<MBXCLHeadingObserver>)observer;
@end

NS_ASSUME_NONNULL_END
