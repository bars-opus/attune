// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>

@class MBMIndoorState;
@protocol MBXCancelable;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Interface for managing indoor features.
 * EXPERIMENTAL: Not intended for usage in current stata. Subject to change or deletion.
 */
NS_SWIFT_NAME(__IndoorManager)
__attribute__((visibility ("default")))
@interface MBMIndoorManager : NSObject

// This class provides custom init which should be called
- (nonnull instancetype)init NS_UNAVAILABLE;

// This class provides custom init which should be called
+ (nonnull instancetype)new NS_UNAVAILABLE;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Emits a new state when indoor state updated.
 * State is updated either when a new floor is selected through API or user moved the camera to focus on another building.
 * EXPERIMENTAL: Not intended for usage in current stata. Subject to change or deletion.
 *
 */
- (nonnull id<MBXCancelable>)registerOnIndoorUpdatedSignal:(void (^_Nonnull)(MBMIndoorState * _Nonnull onIndoorUpdated))callback
__attribute__((swift_name("registerOnIndoorUpdatedSignal(callback:)")));
/**
 * Selects an indoor floor for rendering.
 * When a floor is selected, the map will render features associated with that floor and connected floors.
 * EXPERIMENTAL: Not intended for usage in current stata. Subject to change or deletion.
 *
 * @param selectedFloorId The ID of the floor to select.
 */
- (void)selectFloorForSelectedFloorId:(nullable NSString *)selectedFloorId
__attribute__((swift_name("selectFloor(selectedFloorId:)")));

@end
