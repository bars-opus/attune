// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapboxCoreMaps/MBMFeatureStateOperationCallback_Internal.h>
#import <MapboxCoreMaps/MBMPerformanceStatisticsCallback.h>
#import <MapboxCoreMaps/MBMQueryFeatureExtensionCallback_Internal.h>
#import <MapboxCoreMaps/MBMQueryFeatureStateCallback_Internal.h>
#import <MapboxCoreMaps/MBMQueryRenderedFeaturesCallback_Internal.h>
#import <MapboxCoreMaps/MBMQueryRenderedRasterValuesCallback_Internal.h>
#import <MapboxCoreMaps/MBMQuerySourceFeaturesCallback_Internal.h>
@class MBXExpected<__covariant Value, __covariant Error>;
@class MBXFeature;
#import <MapboxCoreMaps/MBMCameraManager_Internal.h>

@class MBMCameraAnimationHint;
@class MBMFeaturesetDescriptor;
@class MBMFeaturesetFeatureId;
@class MBMFeaturesetQueryTarget;
@class MBMIndoorManager;
@class MBMInteraction;
@class MBMMapOptions;
@class MBMPerformanceStatisticsOptions;
@class MBMPlatformEventInfo;
@class MBMRenderedQueryGeometry;
@class MBMRenderedQueryOptions;
@class MBMRenderedRasterQueryOptions;
@class MBMScreenCoordinate;
@class MBMSize;
@class MBMSourceQueryOptions;
@class MBMTileCacheBudget;
@class MBMVec2;
@class MBMViewAnnotationOptions;
@protocol MBMMapClient;
@protocol MBMViewAnnotationPositionsUpdateListener;
@protocol MBXCancelable;
typedef NS_ENUM(NSInteger, MBMConstrainMode);
typedef NS_ENUM(NSInteger, MBMMapCenterAltitudeMode);
typedef NS_ENUM(NSInteger, MBMMapDebugOptions);
typedef NS_ENUM(NSInteger, MBMNorthOrientation);
typedef NS_ENUM(NSInteger, MBMViewportMode);

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Map class provides map rendering functionality.
 *
 */
NS_SWIFT_NAME(Map)
__attribute__((visibility ("default")))
@interface MBMMap : MBMCameraManager

// This class provides custom init which should be called
- (nonnull instancetype)init NS_UNAVAILABLE;

// This class provides custom init which should be called
+ (nonnull instancetype)new NS_UNAVAILABLE;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Initializes the map object.
 *
 * @param client The `map client` of the map.
 * @param mapOptions The `map options` that the map adheres to.
 */
- (nonnull instancetype)initWithClient:(nonnull id<MBMMapClient>)client
                            mapOptions:(nonnull MBMMapOptions *)mapOptions;

/**
 * Creates the infrastructure needed for rendering the map.
 * It should be called before any call to `render` method. Must be called on the render thread.
 */
- (void)createRenderer;
/**
 * Destroys the infrastructure needed for rendering the map, releasing resources.
 * Must be called on the render thread.
 */
- (void)destroyRenderer;
/** Renders the map. */
- (void)render;
/**
 * Sets the size of the map.
 * @param size The new `size` of the map in `platform pixels`.
 */
- (void)setSizeForSize:(nonnull MBMSize *)size;
/**
 * Gets the size of the map.
 *
 * @return The `size` of the map in `platform pixels`.
 */
- (nonnull MBMSize *)getSize __attribute((ns_returns_retained));
/** Triggers a repaint of the map. */
- (void)triggerRepaint;
/**
 * Tells the map rendering engine that there is currently a gesture in progress. This
 * affects how the map renders labels, as it will use different texture filters if a gesture
 * is ongoing.
 *
 * @param inProgress The `boolean` value representing if a gesture is in progress.
 */
- (void)setGestureInProgressForInProgress:(BOOL)inProgress;
/**
 * Returns `true` if a gesture is currently in progress.
 *
 * @return `true` if a gesture is currently in progress, `false` otherwise.
 */
- (BOOL)isGestureInProgress;
/**
 * Tells the map rendering engine that the animation is currently performed by the
 * user (e.g. with a `setCamera` calls series). It adjusts the engine for the animation use case.
 * In particular, it brings more stability to symbol placement and rendering.
 *
 * @param inProgress The `boolean` value representing if user animation is in progress
 */
- (void)setUserAnimationInProgressForInProgress:(BOOL)inProgress;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * This method provides hints for animations, enabling the rendering engine to pre-process animation
 * frames and apply performance optimizations.
 *
 * The provided data is taken into action on the next
 * `setUserAnimationInProgress(true)` call.
 *
 * @param userAnimationData user animation data
 */
- (void)setCameraAnimationHintForCameraAnimationHint:(nonnull MBMCameraAnimationHint *)cameraAnimationHint;
/**
 * Returns `true` if user animation is currently in progress.
 *
 * @return `true` if a user animation is currently in progress, `false` otherwise.
 */
- (BOOL)isUserAnimationInProgress;
/**
 * When loading a map, if prefetch zoom `delta` is set to any number greater than 0,
 * the map will first request a tile at zoom level lower than `zoom - delta`, with requested
 * zoom level a multiple of `delta`, in an attempt to display a full map at lower resolution as quick as possible.
 *
 * @param delta The new prefetch zoom delta.
 */
- (void)setPrefetchZoomDeltaForDelta:(uint8_t)delta;
/**
 * Returns the map's prefetch zoom delta.
 *
 * @return The map's prefetch zoom `delta`.
 */
- (uint8_t)getPrefetchZoomDelta;
/** Sets the north `orientation mode`. */
- (void)setNorthOrientationForOrientation:(MBMNorthOrientation)orientation;
/** Sets the map `constrain mode`. */
- (void)setConstrainModeForMode:(MBMConstrainMode)mode;
/** Sets the `viewport mode`. */
- (void)setViewportModeForMode:(MBMViewportMode)mode;
/**
 * Sets the map `center altitude mode` that defines behavior of the center point
 * altitude for all subsequent camera manipulations.
 */
- (void)setCenterAltitudeModeForMode:(MBMMapCenterAltitudeMode)mode;
/**
 * Returns the map's `center altitude mode`.
 *
 * @return The map's `center altitude mode`.
 */
- (MBMMapCenterAltitudeMode)getCenterAltitudeMode;
/**
 * Returns the `map options`.
 *
 * @return The map's `map options`.
 */
- (nonnull MBMMapOptions *)getMapOptions __attribute((ns_returns_retained));
/**
 * Returns the `map debug options`.
 *
 * @return An array of `map debug options` flags currently set to the map.
 */
- (nonnull NSArray<NSNumber *> *)getDebug __attribute((ns_returns_retained));
/**
 * Sets the `map debug options` and enables debug mode based on the passed value.
 *
 * @param debugOptions An array of `map debug options` to be set.
 * @param value A `boolean` value representing the state for a given `map debug options`.
 *
 */
- (void)setDebugForDebugOptions:(nonnull NSArray<NSNumber *> *)debugOptions
                          value:(BOOL)value;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Queries the map for rendered features.
 *
 * @param geometry The `screen pixel coordinates` (point, line string or box) to query for rendered features.
 * @param options The `render query options` for querying rendered features.
 * @param callback The `query features callback` called when the query completes.
 * @return A `cancelable` object that could be used to cancel the pending query.
 */
- (nonnull id<MBXCancelable>)queryRenderedFeaturesForGeometry:(nonnull MBMRenderedQueryGeometry *)geometry
                                                      options:(nonnull MBMRenderedQueryOptions *)options
                                                     callback:(nonnull MBMQueryRenderedFeaturesCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Queries the map for rendered features.
 *
 * @param geometry The `screen pixel coordinates` (point, line string or box) to query for rendered features.
 * @param targets An array of `FeaturesetQueryTarget` used to filter and query interactive features.
 * @param callback The `query features callback` called when the query operation completes.
 * @return A `cancelable` object that could be used to cancel the pending query.
 */
- (nonnull id<MBXCancelable>)queryRenderedFeaturesForGeometry:(nonnull MBMRenderedQueryGeometry *)geometry
                                                      targets:(nullable NSArray<MBMFeaturesetQueryTarget *> *)targets
                                                     callback:(nonnull MBMQueryRenderedFeaturesCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Queries the map for source features.
 *
 * @param sourceId The style source identifier used to query for source features.
 * @param options The `source query options` for querying source features.
 * @param callback The `query features callback` called when the query completes.
 * @return A `cancelable` object that could be used to cancel the pending query.
 *
 * Note: In order to get expected results, the corresponding source needs to be in use and the query shall be made after the corresponding source data is loaded.
 */
- (nonnull id<MBXCancelable>)querySourceFeaturesForSourceId:(nonnull NSString *)sourceId
                                                    options:(nonnull MBMSourceQueryOptions *)options
                                                   callback:(nonnull MBMQuerySourceFeaturesCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Queries the map for source features.
 *
 * @param target A `FeaturesetQueryTarget` used to filter and query source features.
 * @param callback The `query features callback` called when the query completes.
 * @return A `cancelable` object that could be used to cancel the pending query.
 *
 * Note: In order to get expected results, the corresponding source needs to be in use and the query shall be made after the corresponding source data is loaded.
 */
- (nonnull id<MBXCancelable>)querySourceFeaturesForTarget:(nonnull MBMFeaturesetQueryTarget *)target
                                                 callback:(nonnull MBMQuerySourceFeaturesCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Queries for feature extension values in a GeoJSON source.
 *
 * @param sourceIdentifier The `source identifier` of the source to query.
 * @param feature The `feature` to look for in the query.
 * @param extension The `extension`, now only support keyword 'supercluster'.
 * @param extensionField The `extension field`, now only support following extensions:
 *        'children': returns the children of a cluster (on the next zoom level).
 *        'leaves': returns all the leaves of a cluster (given its cluster_id)
 *        'expansion-zoom': returns the zoom on which the cluster expands into several children (useful for "click to zoom" feature).
 * @param args The `args` parameter used for further query specification when using 'leaves' extensionField. Now only support following args:
 *        'limit': the number of points to return from the query (must use type 'uint64_t', set to maximum for all points)
 *        'offset': the amount of points to skip (for pagination, must use type 'uint64_t')
 * @return A `cancelable` object that could be used to cancel the pending query.
 *
 * The result will be returned through the `query featureExtension callback`.
 * The result could be a feature extension value containing either a value (expansion-zoom) or a feature collection (children or leaves).
 * Or a string describing an error if the operation was not successful.
 */
- (nonnull id<MBXCancelable>)queryFeatureExtensionsForSourceIdentifier:(nonnull NSString *)sourceIdentifier
                                                               feature:(nonnull MBXFeature *)feature
                                                             extension:(nonnull NSString *)extension
                                                        extensionField:(nonnull NSString *)extensionField
                                                                  args:(nullable NSDictionary<NSString *, id> *)args
                                                              callback:(nonnull MBMQueryFeatureExtensionCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Queries raster array sources for values at a specific coordinate.
 *
 * @param screenCoordinate The position on the screen to query
 * @param options The options for configuring the rendered raster value query.
 * @param callback Callback invoked when the query completes
 * @return A cancelable object that can be used to cancel the pending query
 */
- (nonnull id<MBXCancelable>)queryRenderedRasterValuesForScreenCoordinate:(nonnull MBMScreenCoordinate *)screenCoordinate
                                                                  options:(nonnull MBMRenderedRasterQueryOptions *)options
                                                                 callback:(nonnull MBMQueryRenderedRasterValuesCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Updates the state object of a feature within a style source.
 *
 * Update entries in the `state` object of a given feature within a style source. Only properties of the
 * `state` object will be updated. A property in the feature `state` object that is not listed in `state` will
 * retain its previous value. The properties must be paint properties, layout properties are not supported.
 *
 * Note that updates to feature `state` are asynchronous, so changes made by this method might not be
 * immediately visible using `getStateFeature`. And the corresponding source needs to be in use to ensure the
 * feature data it contains can be successfully updated.
 *
 * @param sourceId The style source identifier.
 * @param sourceLayerId The style source layer identifier (for multi-layer sources such as vector sources).
 * @param featureId The feature identifier of the feature whose state should be updated.
 * @param state The `state` object with properties to update with their respective new values.
 * @param callback The `feature state operation callback` called when the operation completes or ends.
 * @return A `cancelable` object that could be used to cancel the pending operation.
 *
 */
- (nonnull id<MBXCancelable>)setFeatureStateForSourceId:(nonnull NSString *)sourceId
                                          sourceLayerId:(nullable NSString *)sourceLayerId
                                              featureId:(nonnull NSString *)featureId
                                                  state:(nonnull id)state
                                               callback:(nonnull MBMFeatureStateOperationCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Updates the state object of a feature within a style source.
 *
 * Update entries in the `state` object of a given feature within a style source. Only properties of the
 * `state` object will be updated. A property in the feature `state` object that is not listed in `state` will
 * retain its previous value. The properties must be paint properties, layout properties are not supported.
 *
 * Note that updates to feature `state` are asynchronous, so changes made by this method might not be
 * immediately visible using `getStateFeature`. And the corresponding source needs to be in use to ensure the
 * feature data it contains can be successfully updated.
 *
 * @param featureset The featureset identifier.
 * @param featureId The feature identifier of the feature whose state should be updated.
 * @param state The `state` object with properties to update with their respective new values.
 * @param callback The `feature state operation callback` called when the operation completes or ends.
 * @return A `cancelable` object that could be used to cancel the pending operation.
 *
 */
- (nonnull id<MBXCancelable>)setFeatureStateForFeatureset:(nonnull MBMFeaturesetDescriptor *)featureset
                                                featureId:(nonnull MBMFeaturesetFeatureId *)featureId
                                                    state:(nonnull id)state
                                                 callback:(nonnull MBMFeatureStateOperationCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets a feature state expression that applies to features within the specified featureset.
 *
 * All feature states with expressions that evaluate to true will be applied to the feature.
 * Feature states from later added feature state expressions have higher priority. Regular feature states have higher priority than feature state expressions.
 * The final feature state is determined by applying states in order from lower to higher priority. As a result, multiple expressions that set states with different keys can affect the same features simultaneously.
 * If an expression is added for a feature set, properties from that feature set are used, not the properties from original sources.
 *
 * Note that updates to feature state expressions are asynchronous, so changes made by this method might not be
 * immediately visible and will have some delay. The displayed data will not be affected immediately.
 *
 * @param featureStateExpressionId Unique identifier for the state expression.
 * @param featureset The featureset descriptor that specifies which featureset the expression applies to.
 * @param expression The expression to evaluate for the state. Should return boolean.
 * @param state The `state` object with properties to update with their respective new values.
 * @param callback The `feature state operation callback` called when the operation completes.
 *
 */
- (void)setFeatureStateExpressionForFeatureStateExpressionId:(uint64_t)featureStateExpressionId
                                                  featureset:(nonnull MBMFeaturesetDescriptor *)featureset
                                                  expression:(nonnull id)expression
                                                       state:(nonnull id)state
                                                    callback:(nonnull MBMFeatureStateOperationCallback)callback NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the state map of a feature within a style source.
 *
 * Note that updates to feature state are asynchronous, so changes made by other methods might not be
 * immediately visible.
 * Note: doesn't include states evaluated from feature state expressions.
 *
 * @param sourceId The style source identifier.
 * @param sourceLayerId The style source layer identifier (for multi-layer sources such as vector sources).
 * @param featureId The feature identifier of the feature whose state should be queried.
 * @param callback The `query feature state callback` called when the query completes.
 * @return A `cancelable` object that could be used to cancel the pending query.
 *
 */
- (nonnull id<MBXCancelable>)getFeatureStateForSourceId:(nonnull NSString *)sourceId
                                          sourceLayerId:(nullable NSString *)sourceLayerId
                                              featureId:(nonnull NSString *)featureId
                                               callback:(nonnull MBMQueryFeatureStateCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the state map of a feature within a style source.
 *
 * Note that updates to feature state are asynchronous, so changes made by other methods might not be
 * immediately visible.
 * Note: doesn't include states evaluated from feature state expressions.
 *
 * @param featureset The featureset identifier.
 * @param featureId The feature identifier of the feature whose state should be queried.
 * @param callback The `query feature state callback` called when the query completes.
 * @return A `cancelable` object that could be used to cancel the pending query.
 *
 */
- (nonnull id<MBXCancelable>)getFeatureStateForFeatureset:(nonnull MBMFeaturesetDescriptor *)featureset
                                                featureId:(nonnull MBMFeaturesetFeatureId *)featureId
                                                 callback:(nonnull MBMQueryFeatureStateCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes entries from a feature state object.
 *
 * Remove a specified property or all property from a feature's state object, depending on the value of
 * `stateKey`.
 *
 * Note that updates to feature state are asynchronous, so changes made by this method might not be
 * immediately visible using `getStateFeature`.
 *
 * @param sourceId The style source identifier.
 * @param sourceLayerId The style source layer identifier (for multi-layer sources such as vector sources).
 * @param featureId The feature identifier of the feature whose state should be removed.
 * @param stateKey The key of the property to remove. If `null`, all feature's state object properties are removed.
 * @param callback The `feature state operation callback` called when the operation completes or ends.
 * @return A `cancelable` object that could be used to cancel the pending operation.
 */
- (nonnull id<MBXCancelable>)removeFeatureStateForSourceId:(nonnull NSString *)sourceId
                                             sourceLayerId:(nullable NSString *)sourceLayerId
                                                 featureId:(nonnull NSString *)featureId
                                                  stateKey:(nullable NSString *)stateKey
                                                  callback:(nonnull MBMFeatureStateOperationCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes entries from a feature state object.
 *
 * Remove a specified property or all property from a feature's state object, depending on the value of
 * `stateKey`.
 *
 * Note that updates to feature state are asynchronous, so changes made by this method might not be
 * immediately visible using `getStateFeature`.
 *
 * @param featureset The featureset identifier.
 * @param featureId The feature identifier of the feature whose state should be removed.
 * @param stateKey The key of the property to remove. If `null`, all feature's state object properties are removed.
 * @param callback The `feature state operation callback` called when the operation completes or ends.
 * @return A `cancelable` object that could be used to cancel the pending operation.
 */
- (nonnull id<MBXCancelable>)removeFeatureStateForFeatureset:(nonnull MBMFeaturesetDescriptor *)featureset
                                                   featureId:(nonnull MBMFeaturesetFeatureId *)featureId
                                                    stateKey:(nullable NSString *)stateKey
                                                    callback:(nonnull MBMFeatureStateOperationCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes a specific feature state expression.
 *
 * Remove a specific expression from the feature state expressions based on the expression ID.
 *
 * Note that updates to feature state expressions are asynchronous, so changes made by this method might not be
 * immediately visible and will have some delay.
 *
 * @param featureStateExpressionId The unique identifier of the expression to remove.
 * @param callback The `feature state operation callback` called when the operation completes.
 */
- (void)removeFeatureStateExpressionForFeatureStateExpressionId:(uint64_t)featureStateExpressionId
                                                       callback:(nonnull MBMFeatureStateOperationCallback)callback NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Reset all the feature states within a style source.
 *
 * Remove all feature state entries from the specified style source or source layer.
 *
 * Note that updates to feature state are asynchronous, so changes made by this method might not be
 * immediately visible using `getStateFeature`.
 *
 * @param sourceId The style source identifier.
 * @param sourceLayerId The style source layer identifier (for multi-layer sources such as vector sources).
 * @param callback The `feature state operation callback` called when the operation completes or ends.
 * @return A `cancelable` object that could be used to cancel the pending operation.
 */
- (nonnull id<MBXCancelable>)resetFeatureStatesForSourceId:(nonnull NSString *)sourceId
                                             sourceLayerId:(nullable NSString *)sourceLayerId
                                                  callback:(nonnull MBMFeatureStateOperationCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Reset all the feature states within a style source.
 *
 * Remove all feature state entries from the specified style source or source layer.
 *
 * Note that updates to feature state are asynchronous, so changes made by this method might not be
 * immediately visible using `getStateFeature`.
 *
 * @param featureset The featureset identifier.
 * @param callback The `feature state operation callback` called when the operation completes or ends.
 * @return A `cancelable` object that could be used to cancel the pending operation.
 */
- (nonnull id<MBXCancelable>)resetFeatureStatesForFeatureset:(nonnull MBMFeaturesetDescriptor *)featureset
                                                    callback:(nonnull MBMFeatureStateOperationCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Reset all feature state expressions.
 *
 * Note that updates to feature state expressions are asynchronous, so changes made by this method might not be
 * immediately visible and will have some delay.
 *
 * @param callback The `feature state operation callback` called when the operation completes.
 */
- (void)resetFeatureStateExpressionsForCallback:(nonnull MBMFeatureStateOperationCallback)callback NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * The tile cache budget hint to be used by the map. The budget can be given in
 * tile units or in megabytes. A Map will do the best effort to keep memory
 * allocations for a non essential resources within the budget.
 *
 * If the tile cache budget is specified in megabytes, the engine will attempt
 * to use ETC2 texture compression for raster layers.
 *
 * If null is set, the tile cache budget in tile units will be dynamically calculated based on
 * the current viewport size.
 *
 * @param tileCacheBudget The tile cache budget hint to be used by the Map.
 */
- (void)setTileCacheBudgetForTileCacheBudget:(nullable MBMTileCacheBudget *)tileCacheBudget NS_REFINED_FOR_SWIFT;
/** Reduces memory use. Useful to call when the application gets paused or sent to background. */
- (void)reduceMemoryUse;
/**
 * Gets elevation for the given coordinate.
 * Note: Elevation is only available for the visible region on the screen.
 *
 * @param coordinate The `coordinate` defined as longitude-latitude pair.
 * @return The elevation (in meters) multiplied by current terrain exaggeration, or empty if elevation for the coordinate is not available.
 */
- (nullable NSNumber *)getElevationForCoordinate:(CLLocationCoordinate2D)coordinate __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Subscribe to the view annotations updates. The callback will be envoked whenever the position is updated. i.e. Camera changed, projection changed, projection transitions, etc.
 *
 * @param listener The listener that will be subscribed to view annotation postion updates.
 *
 * Note: If the user want to invalidate the listener, setViewAnnotationPositionsUpdateListener(nullptr) should be explicitly called.
 */
- (void)setViewAnnotationPositionsUpdateListenerForListener:(nullable id<MBMViewAnnotationPositionsUpdateListener>)listener;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Add a new view annotation.
 *
 * @param identifier An identifier for the annotation to be added.
 * @param options The options for the annotation to be added.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addViewAnnotationForIdentifier:(nonnull NSString *)identifier
                                                                      options:(nonnull MBMViewAnnotationOptions *)options __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Update view annotation if it exists.
 *
 * @param identifier An identifier for the annotation to be updated.
 * @param options The options for the annotation to be updated.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)updateViewAnnotationForIdentifier:(nonnull NSString *)identifier
                                                                         options:(nonnull MBMViewAnnotationOptions *)options __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Specify layers that view annotations should avoid. This applies to ALL view annotations associated to any layer.
 * The API currently only supports line and symbol layers.
 *
 * @param layerIds A list of layerIDs of layers on the features of which the view annotation should not be placed. Passing `null` will clear the list of layers.
 *
 * @return  A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setViewAnnotationAvoidLayersForLayerIds:(nullable NSSet<NSString *> *)layerIds __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Returns a list of layer ids of layers that all layer associated view annotations are set to avoid.
 *
 * @return  A list of layer ids if there are any, empty set otherwise.
 */
- (nonnull NSSet<NSString *> *)getViewAnnotationAvoidLayers __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Remove view annotation if it exists.
 *
 * @param identifier An identifier for the annotation to be removed.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)removeViewAnnotationForIdentifier:(nonnull NSString *)identifier __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Fetch the `ViewAnnotationOptions` that the identifier is binding to.
 *
 * @param identifier The identifier for the `ViewAnnotationOptions` that needs to be fetched.
 *
 * @return The `ViewAnnotationOptions` data if operation succeeded, otherwise a string describing an error if the operation was not successful.
 */
- (nonnull MBXExpected<MBMViewAnnotationOptions *, NSString *> *)getViewAnnotationOptionsForIdentifier:(nonnull NSString *)identifier __attribute((ns_returns_retained));
/**
 * Enable real-time collection of map rendering performance statistics, for development purposes. Use after `render()` has
 * been called for the first time.
 *
 * Collects CPU, GPU resource usage and timings of layers and rendering groups over a user-configurable sampling duration.
 * Use the collected information to find which layers or rendering groups might be performing poorly. Use
 * `PerformanceStatisticsOptions` to configure the following statistics collection behaviors:
 * <ul>
 *     <li>Specify the types of sampling: cumulative, per-frame, or both.</li>
 *     <li>Define the minimum amount of time over which to perform sampling.</li>
 * </ul>
 *
 * Utilize `PerformanceStatisticsCallback` to observe the collected performance statistics. The callback function is invoked
 * after the configured sampling duration has elapsed. The callback is invoked on the main thread. The collection process is
 * continuous; without user-input, it restarts after each callback invocation. Note: Specifying a negative sampling duration
 * or omitting the callback function will result in no operation, which will be logged for visibility.
 *
 * In order to stop the collection process, call `stopPerformanceStatisticsCollection.`
 *
 * @param options Statistics collection options
 * @param callback The callback to be invoked when statistics are available after the configured amount of
 * time.
 */
- (void)startPerformanceStatisticsCollectionForOptions:(nonnull MBMPerformanceStatisticsOptions *)options
                                              callback:(nonnull MBMPerformanceStatisticsCallback)callback;
/**
 * Disable performance statistics collection.
 *
 * Calling `stopPerformanceStatisticsCollection` when no collection is enabled is a no-op. After calling
 * `startPerformanceStatisticsCollection`, `stopPerformanceStatisticsCollection` must be called before collection can be
 * restarted.
 */
- (void)stopPerformanceStatisticsCollection;
/**
 * Returns attributions for the data used by the Map's style.
 *
 * @return An array of attributions for the data sources used by the Map's style.
 *
 */
- (nonnull NSArray<NSString *> *)getAttributions __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds an interaction to the map.
 * The interaction will be called when the matching feature receives the corresponding event.
 * The interaction handler is called in the order that features are rendered in.
 * If multiple interactions objects handle a an iteracton on one feature, the last added interaction handles it first.
 *
 * @param interaction An interaction object.
 * @return Cancelable token. Must be cancelled on main thread.
 */
- (nonnull id<MBXCancelable>)addInteractionForInteraction:(nonnull MBMInteraction *)interaction __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Dispatches the platform event.
 */
- (void)dispatchForEventInfo:(nonnull MBMPlatformEventInfo *)eventInfo;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * A convex polygon that describes the shape for culling the map in case it is non-rectangular.
 * Every coordinate is in 0 to 1 range, with (0, 0) being the map view top-left and (1, 1) the bottom-right.
 * The points have to be given in clockwise winding order and may not be colinear.
 * The polygon will be closed automatically, so for a rectangular shape, pass in 4 points.
 * If any constraint is not met, the shape is rejected and a default rectangle shape is used instead.
 * Use this if the visible map area is obscured enough that using a custom shape improves performance.
 */
- (void)setScreenCullingShapeForShape:(nonnull NSArray<MBMVec2 *> *)shape;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * A convex polygon that describes the shape for culling the map in case it is non-rectangular.
 * Every coordinate is in 0 to 1 range, with (0, 0) being the map view top-left and (1, 1) the bottom-right.
 * The points have to be given in clockwise winding order and may not be colinear.
 * The polygon will be closed automatically, so for a rectangular shape, pass in 4 points.
 *
 * Returns the custom culling shape polygon, if set. Returns an empty array otherwise.
 */
- (nonnull NSArray<MBMVec2 *> *)getScreenCullingShape __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Resets the thread service type to Interactive for Render thread and for
 * owning thread (if setting `main_thread_prioritized` is true).
 */
- (void)resetThreadServiceType;
/**
 * Sets custom scale factor for the Map symbols: icons and texts.
 * Scales values set with 'icon-size', 'icon-halo-width', 'icon-halo-blur', 'text-size', 'text-halo-width', 'text-halo-blur' properties.
 * Layers may respond to scaling differently according to the 'icon-size-scale-range', 'text-size-scale-range' properties that limit possible scale range for the icon/text.
 */
- (void)setScaleFactorForScaleFactor:(float)scaleFactor;
/** Gets the custom scale factor for the Map symbols. */
- (float)getScaleFactor;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the indoor manager for managing indoor features.
 * Returns indoorManager instance which is stored in the map and not intended for creation on the client.
 */
- (nonnull MBMIndoorManager *)getIndoorManager __attribute((ns_returns_retained));

@end
