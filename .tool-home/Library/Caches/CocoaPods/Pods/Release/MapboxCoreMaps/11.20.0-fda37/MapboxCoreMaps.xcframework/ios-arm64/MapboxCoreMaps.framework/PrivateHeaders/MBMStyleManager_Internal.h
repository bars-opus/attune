// This file is generated and will be overwritten automatically.

#import <Foundation/Foundation.h>
#import <MapboxCoreMaps/MBMAsyncOperationResultCallback_Internal.h>
@class MBXExpected<__covariant Value, __covariant Error>;
@class MBXFeature;
#import <MapboxCoreMaps/MBMObservable_Internal.h>

@class MBMCameraOptions;
@class MBMCanonicalTileID;
@class MBMColorTheme;
@class MBMCoordinateBounds;
@class MBMCustomGeometrySourceOptions;
@class MBMCustomRasterSourceOptions;
@class MBMCustomRasterSourceTileData;
@class MBMFeaturesetDescriptor;
@class MBMGeoJSONSourceData;
@class MBMImage;
@class MBMImageContent;
@class MBMImageStretches;
@class MBMImportPosition;
@class MBMLayerPosition;
@class MBMRuntimeStylingOptions;
@class MBMStyleObjectInfo;
@class MBMStylePropertyValue;
@class MBMTransitionOptions;
@protocol MBMCustomLayerHost;
@protocol MBXCancelable;

/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Interface for managing style of the `map`.
 */
NS_SWIFT_NAME(StyleManager)
__attribute__((visibility ("default")))
@interface MBMStyleManager : MBMObservable

/**
 * Get the URI of the current style in use.
 *
 * @return A string containing a style URI.
 */
- (nonnull NSString *)getStyleURI __attribute((ns_returns_retained));
/**
 * Load style from provided URI.
 *
 * This is an asynchronous call. To check the result of this operation, `MapLoaded` or `MapLoadingError` events
 * should be observed. In case of successful style load, StyleLoaded event will be also emitted.
 *
 * @param uri URI where the style should be loaded from.
 */
- (void)setStyleURIForUri:(nonnull NSString *)uri;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Load style from provided URI.
 *
 * This is an asynchronous call. To check the result of this operation, `MapLoaded` or `MapLoadingError` events
 * should be observed. In case of successful style load, StyleLoaded event will be also emitted.
 * The optional runtime styling callbacks will be invoked during style loading when the corresponding part of the
 * style document is loaded and can be modified.
 *
 * @param uri URI where the style should be loaded from.
 * @param stylingOptions Runtime styling callbacks
 */
- (void)setStyleURIForUri:(nonnull NSString *)uri
           stylingOptions:(nonnull MBMRuntimeStylingOptions *)stylingOptions;
/**
 * Get the JSON serialization string of the current style in use.
 *
 * @return A JSON string containing a serialized style.
 */
- (nonnull NSString *)getStyleJSON __attribute((ns_returns_retained));
/**
 * Load the style from a provided JSON string.
 *
 * @param json A JSON string containing a serialized style.
 */
- (void)setStyleJSONForJson:(nonnull NSString *)json;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Load the style from a provided JSON string.
 *
 * The optional runtime styling callbacks will be invoked during style loading when the corresponding part of the style
 * document is loaded and can be modified.
 *
 * @param json A JSON string containing a serialized style.
 * @param stylingOptions Runtime styling callbacks
 */
- (void)setStyleJSONForJson:(nonnull NSString *)json
             stylingOptions:(nonnull MBMRuntimeStylingOptions *)stylingOptions;
/**
 * Load the style glyphs from a provided URL.
 *
 * @param url URL where the glyphs should be loaded from.
 */
- (void)setStyleGlyphURLForUrl:(nonnull NSString *)url;
/**
 * Get the glyph URL of the current style in use.
 *
 * @return A string containing a glyph URI.
 */
- (nonnull NSString *)getStyleGlyphURL __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Returns the map style's default camera, if any, or a default camera otherwise.
 * The map style's default camera is defined as follows:
 * - [center](https://docs.mapbox.com/mapbox-gl-js/style-spec/#root-center)
 * - [zoom](https://docs.mapbox.com/mapbox-gl-js/style-spec/#root-zoom)
 * - [bearing](https://docs.mapbox.com/mapbox-gl-js/style-spec/#root-bearing)
 * - [pitch](https://docs.mapbox.com/mapbox-gl-js/style-spec/#root-pitch)
 *
 * The style default camera is re-evaluated when a new style is loaded.
 *
 * @return The default `camera options` of the current style in use.
 */
- (nonnull MBMCameraOptions *)getStyleDefaultCamera __attribute((ns_returns_retained));
/**
 * Returns the map style's transition options. By default, the style parser will attempt
 * to read the style default transition options, if any, fallbacking to an immediate transition
 * otherwise. Transition options can be overriden via `setStyleTransition`, but the options are
 * reset once a new style has been loaded.
 *
 * The style transition is re-evaluated when a new style is loaded.
 *
 * @return The `transition options` of the current style in use.
 */
- (nonnull MBMTransitionOptions *)getStyleTransition __attribute((ns_returns_retained));
/**
 * Overrides the map style's transition options with user-provided options.
 *
 * The style transition is re-evaluated when a new style is loaded.
 *
 * @param transitionOptions The `transition options`.
 */
- (void)setStyleTransitionForTransitionOptions:(nonnull MBMTransitionOptions *)transitionOptions;
/**
 * Returns the existing style imports.
 *
 * @return The list containing the information about existing style import objects.
 */
- (nonnull NSArray<MBMStyleObjectInfo *> *)getStyleImports __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes an existing style import.
 *
 * @param importId An identifier of the style import to remove.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)removeStyleImportForImportId:(nonnull NSString *)importId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds new import to current style, loaded from an URI.
 *
 * @param importId Identifier of import to update.
 * @param uri URI of the import.
 * @param config A map containing the configuration options of the import.
 * @param importPosition The import will be positioned according to the ImportPosition parameters. If not specified, then the import is moved to the top of the import stack.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addStyleImportFromURIForImportId:(nonnull NSString *)importId
                                                                            uri:(nonnull NSString *)uri
                                                                         config:(nullable NSDictionary<NSString *, id> *)config
                                                                 importPosition:(nullable MBMImportPosition *)importPosition __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds new import to current style, loaded from a JSON string.
 *
 * @param importId Identifier of import to update.
 * @param json The JSON string to be loaded directly as the import.
 * @param config A map containing the configuration options of the import.
 * @param importPosition The import will be positioned according to the ImportPosition parameters. If not specified, then the import is moved to the top of the import stack.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addStyleImportFromJSONForImportId:(nonnull NSString *)importId
                                                                            json:(nonnull NSString *)json
                                                                          config:(nullable NSDictionary<NSString *, id> *)config
                                                                  importPosition:(nullable MBMImportPosition *)importPosition __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Updates an existing import in the style.
 * The function replaces the content of the import, with the content loaded from the provided URI.
 * The configuration values of the import are merged with the configuration provided in the update.
 *
 * @param importId Identifier of import to update.
 * @param uri URI of the import.
 * @param config A map containing the configuration options of the import.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)updateStyleImportWithURIForImportId:(nonnull NSString *)importId
                                                                               uri:(nonnull NSString *)uri
                                                                            config:(nullable NSDictionary<NSString *, id> *)config __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Updates an existing import in the style.
 * The function replaces the content of the import, with the content loaded from the provided JSON string.
 * The configuration values of the import are merged with the configuration provided in the update.
 *
 * @param importId Identifier of import to update.
 * @param json The JSON string to be loaded directly as the import.
 * @param config A map containing the configuration options of the import.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)updateStyleImportWithJSONForImportId:(nonnull NSString *)importId
                                                                               json:(nonnull NSString *)json
                                                                             config:(nullable NSDictionary<NSString *, id> *)config __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Moves import to position before another import, specified with `beforeId`. Order of imported styles corresponds to order of their layers.
 *
 * @param importId Identifier of import to move.
 * @param importPosition The import will be positioned according to the ImportPosition parameters. If not specified, then the import is moved to the top of the import stack.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)moveStyleImportForImportId:(nonnull NSString *)importId
                                                           importPosition:(nullable MBMImportPosition *)importPosition __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets style import schema.
 *
 * @param importId A style import identifier.
 *
 * @return The style import schema or a string describing an error if the operation was not successful.
 */
- (nonnull MBXExpected<id, NSString *> *)getStyleImportSchemaForImportId:(nonnull NSString *)importId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets style import config.
 *
 * @return The style import configuration or a string describing an error if the operation was not successful.
 */
- (nonnull MBXExpected<NSDictionary<NSString *, MBMStylePropertyValue *> *, NSString *> *)getStyleImportConfigPropertiesForImportId:(nonnull NSString *)importId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the value of style import config.
 *
 * @param importId A style import identifier.
 * @param config The style import config name.
 * @return The style import config value.
 */
- (nonnull MBXExpected<MBMStylePropertyValue *, NSString *> *)getStyleImportConfigPropertyForImportId:(nonnull NSString *)importId
                                                                                               config:(nonnull NSString *)config __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets style import config.
 * This method can be used to perform batch update for a style import configurations.
 *
 * @param importId A style import identifier.
 * @param properties A map of style import configurations.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleImportConfigPropertiesForImportId:(nonnull NSString *)importId
                                                                                 configs:(nonnull NSDictionary<NSString *, id> *)configs __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets a value to a style import config.
 *
 * @param importId A style import identifier.
 * @param property The style import config name.
 * @param value The style import config value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleImportConfigPropertyForImportId:(nonnull NSString *)importId
                                                                                config:(nonnull NSString *)config
                                                                                 value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Set color theme for the root style.
 * @param colorTheme: Color theme to apply on the style. Providing nil in colorTheme means deleting the theme.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleColorThemeForColorTheme:(nullable MBMColorTheme *)colorTheme __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Set root style color theme to the initial value from Style JSON. Effectively resetting all runtime modifications to style color theme.
 */
- (void)setInitialStyleColorTheme;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Set color theme for the style import.
 * @param importId String id of the style import to which the color theme will be applied.
 * @param colorTheme: Color theme to apply on the style. Providing nil in colorTheme means deleting the theme.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setImportColorThemeForImportId:(nonnull NSString *)importId
                                                                   colorTheme:(nullable MBMColorTheme *)colorTheme __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Returns the available featuresets in the currently loaded style.
 *
 * Note: This function should only be called after the style is fully loaded; otherwise, the result may be unreliable.
 */
- (nonnull NSArray<MBMFeaturesetDescriptor *> *)getStyleFeaturesets __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds a new [style layer](https://docs.mapbox.com/mapbox-gl-js/style-spec/#layers).
 *
 * Runtime style layers are valid until they are either removed or a new style is loaded.
 *
 * @param properties A map of style layer properties.
 * @param layerPosition If not empty, the new layer will be positioned according to `layer position` parameters.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addStyleLayerForProperties:(nonnull id)properties
                                                            layerPosition:(nullable MBMLayerPosition *)layerPosition __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds a new [style custom layer](https://docs.mapbox.com/mapbox-gl-js/style-spec/#layers).
 *
 * Runtime style layers are valid until they are either removed or a new style is loaded.
 *
 * @param layerId A style layer identifier.
 * @param layerHost The `custom layer host`.
 * @param layerPosition If not empty, the new layer will be positioned according to `layer position` parameters.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addStyleCustomLayerForLayerId:(nonnull NSString *)layerId
                                                                   layerHost:(nonnull id<MBMCustomLayerHost>)layerHost
                                                               layerPosition:(nullable MBMLayerPosition *)layerPosition __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds a new [style layer](https://docs.mapbox.com/mapbox-gl-js/style-spec/#layers).
 *
 * Whenever a new style is being parsed and currently used style has persistent layers,
 * an engine will try to do following:
 *   - keep the persistent layer at its relative position
 *   - keep the source used by a persistent layer
 *   - keep images added through `addStyleImage` method
 *
 * In cases when a new style has the same layer, source or image resource, style's resources would be
 * used instead and `MapLoadingError` event will be emitted.
 *
 * @param properties A map of style layer properties.
 * @param layerPosition If not empty, the new layer will be positioned according to `layer position` parameters.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addPersistentStyleLayerForProperties:(nonnull id)properties
                                                                      layerPosition:(nullable MBMLayerPosition *)layerPosition __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds a new [style custom layer](https://docs.mapbox.com/mapbox-gl-js/style-spec/#layers).
 *
 * Whenever a new style is being parsed and currently used style has persistent layers,
 * an engine will try to do following:
 *   - keep the persistent layer at its relative position
 *   - keep the source used by a persistent layer
 *   - keep images added through `addStyleImage` method
 *
 * In cases when a new style has the same layer, source or image resource, style's resources would be
 * used instead and `MapLoadingError` event will be emitted.
 *
 * @param layerId A style layer identifier.
 * @param layerHost The `custom layer host`.
 * @param layerPosition If not empty, the new layer will be positioned according to `layer position` parameters.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addPersistentStyleCustomLayerForLayerId:(nonnull NSString *)layerId
                                                                             layerHost:(nonnull id<MBMCustomLayerHost>)layerHost
                                                                         layerPosition:(nullable MBMLayerPosition *)layerPosition __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Checks if a style layer is persistent.
 *
 * @param layerId A style layer identifier.
 * @return A string describing an error if the operation was not successful, boolean representing state otherwise.
 */
- (nonnull MBXExpected<NSNumber *, NSString *> *)isStyleLayerPersistentForLayerId:(nonnull NSString *)layerId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes an existing style layer.
 *
 * @param layerId An identifier of the style layer to remove.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)removeStyleLayerForLayerId:(nonnull NSString *)layerId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * @brief Moves an existing style layer
 *
 * @param layerId Identifier of the style layer to move.
 * @param layerPosition The layer will be positioned according to the LayerPosition parameters. If an empty LayerPosition
 *                      is provided then the layer is moved to the top of the layerstack.
 *
 * @return A string describing an error if the operation was not successful, or empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)moveStyleLayerForLayerId:(nonnull NSString *)layerId
                                                          layerPosition:(nullable MBMLayerPosition *)layerPosition __attribute((ns_returns_retained));
/**
 * Checks whether a given style layer exists.
 *
 * @param layerId Style layer identifier.
 *
 * @return A `true` value if the given style layer exists, `false` otherwise.
 */
- (BOOL)styleLayerExistsForLayerId:(nonnull NSString *)layerId;
/**
 * Returns the existing style layers.
 *
 * @return The list containing the information about existing style layer objects.
 */
- (nonnull NSArray<MBMStyleObjectInfo *> *)getStyleLayers __attribute((ns_returns_retained));
/**
 * Returns slots available in the style and its imports.
 *
 * @return The list of slots identifiers.
 */
- (nonnull NSArray<NSString *> *)getStyleSlots __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the value of style layer property.
 *
 * @param layerId A style layer identifier.
 * @param property The style layer property name.
 * @return The `style property value`.
 */
- (nonnull MBMStylePropertyValue *)getStyleLayerPropertyForLayerId:(nonnull NSString *)layerId
                                                          property:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets a value to a style layer property.
 *
 * @param layerId A style layer identifier.
 * @param property The style layer property name.
 * @param value The style layer property value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleLayerPropertyForLayerId:(nonnull NSString *)layerId
                                                                      property:(nonnull NSString *)property
                                                                         value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Experimental. Sets a value to a style layer property asynchronously.
 *
 * This method provides asynchronous argument parsing which is beneficial when working with
 * large or complex style expressions that could block the main thread during parsing.
 * The operation is performed on a background thread and the callback is invoked on the
 * main thread once the operation completes.
 *
 * Values will be applied asynchronously at some moment in the future. If multiple calls
 * to this method are made, the corresponding values will be applied in the same order
 * as the calls were made.
 *
 * Note: This method should be used only if the given argument is a massive expression
 * and its parsing would block the main thread otherwise. For simple property values,
 * prefer the synchronous setStyleLayerProperty method.
 *
 * If the style is modified during this asynchronous method call, the scheduled layer
 * property change will still be applied as long as a layer with the original name and
 * type still exists.
 *
 * @param layerId A style layer identifier.
 * @param property The style layer property name.
 * @param value The style layer property value.
 * @param callback Called once the request is complete or an error occurred.
 *
 * @return A `Cancelable` object that can be used to cancel the asynchronous operation.
 */
- (nonnull id<MBXCancelable>)setStyleLayerPropertyAsyncForLayerId:(nonnull NSString *)layerId
                                                         property:(nonnull NSString *)property
                                                            value:(nonnull id)value
                                                         callback:(nonnull MBMAsyncOperationResultCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the default value of style layer property
 *
 * @param layerType A style [layer type](https://docs.mapbox.com/mapbox-gl-js/style-spec/#layers).
 * @param property The style layer property name.
 * @return The default `style property value` for a given `layerType` and `property` name.
 */
+ (nonnull MBMStylePropertyValue *)getStyleLayerPropertyDefaultValueForLayerType:(nonnull NSString *)layerType
                                                                        property:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets style layer properties.
 *
 * @return The style layer properties or a string describing an error if the operation was not successful.
 */
- (nonnull MBXExpected<id, NSString *> *)getStyleLayerPropertiesForLayerId:(nonnull NSString *)layerId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets style layer properties.
 * This method can be used to perform batch update for a style layer properties. The structure of a
 * provided `properties` value must conform to a format for a corresponding [layer type](https://docs.mapbox.com/mapbox-gl-js/style-spec/layers/).
 * Modification of a layer [id](https://docs.mapbox.com/mapbox-gl-js/style-spec/layers/#id) and/or a [layer type] (https://docs.mapbox.com/mapbox-gl-js/style-spec/layers/#type) is not allowed.
 *
 * @param layerId A style layer identifier.
 * @param properties A map of style layer properties.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleLayerPropertiesForLayerId:(nonnull NSString *)layerId
                                                                      properties:(nonnull id)properties __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Experimental. Sets style layer properties asynchronously.
 *
 * This method can be used to perform batch update for a style layer properties with asynchronous
 * argument parsing which is beneficial when working with large or complex style expressions that
 * could block the main thread during parsing. The operation is performed on a background thread
 * and the callback is invoked on the main thread once the operation completes.
 *
 * Properties will be applied asynchronously at some moment in the future. If multiple calls
 * to this method are made, the corresponding properties will be applied in the same order
 * as the calls were made.
 *
 * Note: This method should be used only if the given arguments contain massive expressions
 * and their parsing would block the main thread otherwise. For simple property values,
 * prefer the synchronous setStyleLayerProperties method.
 *
 * The structure of the provided `properties` value must conform to a format for a corresponding
 * [layer type](https://docs.mapbox.com/mapbox-gl-js/style-spec/layers/).
 * Modification of a layer [id](https://docs.mapbox.com/mapbox-gl-js/style-spec/layers/#id) and/or
 * a [layer type](https://docs.mapbox.com/mapbox-gl-js/style-spec/layers/#type) is not allowed.
 *
 * If the style is modified during this asynchronous method call, the scheduled layer
 * properties change will still be applied as long as a layer with the original name and
 * type still exists.
 *
 * @param layerId A style layer identifier.
 * @param properties A map of style layer properties.
 * @param callback Called once the request is complete or an error occurred.
 *
 * @return A `Cancelable` object that can be used to cancel the asynchronous operation.
 */
- (nonnull id<MBXCancelable>)setStyleLayerPropertiesAsyncForLayerId:(nonnull NSString *)layerId
                                                         properties:(nonnull id)properties
                                                           callback:(nonnull MBMAsyncOperationResultCallback)callback __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds a new [style source](https://docs.mapbox.com/mapbox-gl-js/style-spec/#sources).
 * Note: When adding a `geojson` source, this method does not synchronously parse the GeoJSON data.
 * The events API shall be used to make sure the provided GeoJSON data is valid.
 * In case the GeoJSON is valid, a `map-loaded` event will be propagated. In case of errors, a `map-loading-error` event will be propagated instead.
 *
 * @param sourceId An identifier for the style source.
 * @param properties A map of style source properties.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addStyleSourceForSourceId:(nonnull NSString *)sourceId
                                                              properties:(nonnull id)properties __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the value of style source property.
 *
 * @param sourceId A style source identifier.
 * @param property The style source property name.
 * @return The value of a `property` in the source with a `sourceId`.
 */
- (nonnull MBMStylePropertyValue *)getStyleSourcePropertyForSourceId:(nonnull NSString *)sourceId
                                                            property:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets a value to a style source property.
 * Note: When setting the `data` property of a `geojson` source, this method does not synchronously parse the GeoJSON data.
 * The events API shall be used to make sure the provided GeoJSON data is valid.
 * In case the GeoJSON is valid, a `map-loaded` event will be propagated. In case of errors, a `map-loading-error` event will be propagated instead.
 *
 * @param sourceId A style source identifier.
 * @param property The style source property name.
 * @param value The style source property value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleSourcePropertyForSourceId:(nonnull NSString *)sourceId
                                                                        property:(nonnull NSString *)property
                                                                           value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets a value to a style source property for a source that belongs to a specific style import.
 *
 * This method allows modification of source properties within imported styles, enabling
 * fine-grained control over sources from different style fragments or imports.
 * If `importId` is empty, this method falls back to updating the root style.
 *
 * @param importId An identifier of the style import containing the target source.
 * @param sourceId A style source identifier within the specified import.
 * @param property The style source property name.
 * @param value The style source property value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleSourcePropertyForImportId:(nonnull NSString *)importId
                                                                        sourceId:(nonnull NSString *)sourceId
                                                                        property:(nonnull NSString *)property
                                                                           value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets style source properties.
 *
 * @param sourceId A style source identifier.
 *
 * @return The style source properties or a string describing an error if the operation was not successful.
 */
- (nonnull MBXExpected<id, NSString *> *)getStyleSourcePropertiesForSourceId:(nonnull NSString *)sourceId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets style source properties.
 *
 * This method can be used to perform batch update for a style source properties. The structure of a
 * provided `properties` value must conform to a format for a corresponding [source type](https://docs.mapbox.com/mapbox-gl-js/style-spec/sources/).
 * Modification of a source [type](https://docs.mapbox.com/mapbox-gl-js/style-spec/sources/#type) is not allowed.
 *
 * @param sourceId A style source identifier.
 * @param properties A map of Style source properties.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleSourcePropertiesForSourceId:(nonnull NSString *)sourceId
                                                                        properties:(nonnull id)properties __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets GeoJSON data to a GeoJSON style source.
 *
 * This method is thread safe.
 *
 * Note that if this method is called from a thread other than the main thread
 * the return value does not contain the actual operation status and
 * the events API shall be used to make sure that the operation succeeded.
 * In case of success, a `map-loaded` event will be propagated. In case of errors,
 * a `map-loading-error` event will be propagated instead.
 *
 * The method allows for passing data id - a user-provided string that will be
 * returned as a `data-id` parameter of the `source-data-loaded` event argument.
 * In this way, the client can determine which instance of the data
 * actually applies to the map if multiple instances were set in a row.
 *
 * @param sourceId A style source identifier.
 * @param dataId An arbitrary string used to track the given GeoJSON data.
 * @param data the GeoJSON data.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleGeoJSONSourceDataForSourceId:(nonnull NSString *)sourceId
                                                                             dataId:(nonnull NSString *)dataId
                                                                               data:(nonnull MBMGeoJSONSourceData *)data __attribute((ns_returns_retained)) NS_REFINED_FOR_SWIFT;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Add additional features to a GeoJSON style source.
 *
 * This method is thread-safe.
 *
 * Note that when calling this method from a thread other than the main thread, the return value does
 * not contain the actual operation status. To ensure the success of the operation, use the events API,
 * which will propagate a `map-loaded` event upon success or a `map-loading-error` event upon failure.
 *
 * Partially updating a GeoJSON source is not compatible with using shared cache and generated IDs.
 * It is important to ensure that every feature in the GeoJSON style source, as well as the newly added
 * feature, has a unique ID (or a unique promote ID if in use). Failure to provide unique IDs will result
 * in a `map-loading-error`.
 *
 * The method allows the user to provide a data ID, which will be returned as the dataId parameter in the
 * `source-data-loaded` event. However, it's important to note that multiple partial updates can be queued
 * for the same GeoJSON source when ongoing source parsing is taking place. In these cases, the partial
 * updates will be applied to the source in batches. Only the data ID provided in the most recent call within
 * each batch will be included in the `source-data-loaded` event. If no data ID is provided in the most recent
 * call, the data ID in the `source-data-loaded`event will be null.
 *
 * @param sourceId The identifier of the style source.
 * @param dataId An arbitrary string used to track the given GeoJSON data, empty string means null ID.
 * @param features An array of GeoJSON features to be added to the source.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addGeoJSONSourceFeaturesForSourceId:(nonnull NSString *)sourceId
                                                                            dataId:(nonnull NSString *)dataId
                                                                          features:(nonnull NSArray<MBXFeature *> *)features __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Update existing features in a GeoJSON style source.
 *
 * This method is thread safe.
 *
 * Note that when calling this method from a thread other than the main thread, the return value does
 * not contain the actual operation status. To ensure the success of the operation, use the events API,
 * which will propagate a `map-loaded` event upon success or a `map-loading-error` event upon failure.
 *
 * Partially updating a GeoJSON source is not compatible with using shared cache and generated IDs.
 * It is important to ensure that every feature in the GeoJSON style source, as well as the newly added
 * feature, has a unique ID (or a unique promote ID if in use). Failure to provide unique IDs will result
 * in a `map-loading-error`.
 *
 * The method allows the user to provide a data ID, which will be returned as the dataId parameter in the
 * `source-data-loaded` event. However, it's important to note that multiple partial updates can be queued
 * for the same GeoJSON source when ongoing source parsing is taking place. In these cases, the partial
 * updates will be applied to the source in batches. Only the data ID provided in the most recent call within
 * each batch will be included in the `source-data-loaded` event. If no data ID is provided in the most recent
 * call, the data ID in the `source-data-loaded`event will be null.
 *
 * @param sourceId A style source identifier.
 * @param dataId An arbitrary string used to track the given GeoJSON data, empty string means null ID.
 * @param features the GeoJSON features to be updated in the source.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)updateGeoJSONSourceFeaturesForSourceId:(nonnull NSString *)sourceId
                                                                               dataId:(nonnull NSString *)dataId
                                                                             features:(nonnull NSArray<MBXFeature *> *)features __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Remove features from a GeoJSON style source.
 *
 * This method is thread safe.
 *
 * Note that when calling this method from a thread other than the main thread, the return value does
 * not contain the actual operation status. To ensure the success of the operation, use the events API,
 * which will propagate a `map-loaded` event upon success or a `map-loading-error` event upon failure.
 *
 * Partially updating a GeoJSON source is not compatible with using shared cache and generated IDs.
 * It is important to ensure that every feature in the GeoJSON style source, as well as the newly added
 * feature, has a unique ID (or a unique promote ID if in use). Failure to provide unique IDs will result
 * in a `map-loading-error`.
 *
 * The method allows the user to provide a data ID, which will be returned as the dataId parameter in the
 * `source-data-loaded` event. However, it's important to note that multiple partial updates can be queued
 * for the same GeoJSON source when ongoing source parsing is taking place. In these cases, the partial
 * updates will be applied to the source in batches. Only the data ID provided in the most recent call within
 * each batch will be included in the `source-data-loaded` event. If no data ID is provided in the most recent
 * call, the data ID in the `source-data-loaded`event will be null.
 *
 * @param sourceId A style source identifier.
 * @param dataId An arbitrary string used to track the given GeoJSON data, empty string means null ID.
 * @param featureIds the Ids of the features that need to be removed from the source.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)removeGeoJSONSourceFeaturesForSourceId:(nonnull NSString *)sourceId
                                                                               dataId:(nonnull NSString *)dataId
                                                                           featureIds:(nonnull NSArray<NSString *> *)featureIds __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the default value of style source property.
 *
 * @param sourceType A style source type.
 * @param property The style source property name.
 * @return The default value of a `property` for the sources with of a `sourceType` type.
 */
+ (nonnull MBMStylePropertyValue *)getStyleSourcePropertyDefaultValueForSourceType:(nonnull NSString *)sourceType
                                                                          property:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Updates the image of an [image style source](https://docs.mapbox.com/mapbox-gl-js/style-spec/#sources-image).
 *
 * @param sourceId A style source identifier.
 * @param image An `image`.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)updateStyleImageSourceImageForSourceId:(nonnull NSString *)sourceId
                                                                                image:(nonnull MBMImage *)image __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes an existing style source.
 *
 * If there's any layer that uses the source, the source will not be removed and an error will be returned.
 *
 * @param sourceId An identifier of the style source to remove.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)removeStyleSourceForSourceId:(nonnull NSString *)sourceId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes an existing style source.
 *
 * Any layer that uses the source will not be rendered, but not removed.
 *
 * @param sourceId An identifier of the style source to remove.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)removeStyleSourceUncheckedForSourceId:(nonnull NSString *)sourceId __attribute((ns_returns_retained));
/**
 * Checks whether a given style source exists.
 *
 * @param sourceId A style source identifier.
 *
 * @return `true` if the given source exists, `false` otherwise.
 */
- (BOOL)styleSourceExistsForSourceId:(nonnull NSString *)sourceId;
/**
 * Returns the existing style sources.
 *
 * @return The list containing the information about existing style source objects.
 */
- (nonnull NSArray<MBMStyleObjectInfo *> *)getStyleSources __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Returns the existing style lights.
 *
 * @return The list containing the information about existing style lights.
 */
- (nonnull NSArray<MBMStyleObjectInfo *> *)getStyleLights __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets the style lights.
 *
 * @param lights An array of style lights.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleLightsForLights:(nonnull id)lights __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the value of a style light property in lights array.
 *
 * @param id The id of the style light in lights array.
 * @param property The style light property name.
 * @return The style light property value.
 */
- (nonnull MBMStylePropertyValue *)getStyleLightPropertyForId:(nonnull NSString *)id_
                                                     property:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets a value to the the style light property.
 *
 * @param id The style light id.
 * @param property The style light property name.
 * @param value The style light property value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleLightPropertyForId:(nonnull NSString *)id_
                                                                 property:(nonnull NSString *)property
                                                                    value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets the style global [atmosphere](https://docs.mapbox.com/mapbox-gl-js/style-spec/#fog) properties.
 *
 * @param properties A map of style atmosphere properties values, with their names as a key.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleAtmosphereForProperties:(nonnull id)properties __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the value of a style atmosphere property.
 *
 * @param property The style atmosphere property name.
 * @return The style atmosphere property value.
 */
- (nonnull MBMStylePropertyValue *)getStyleAtmospherePropertyForProperty:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Experimental. Sets the style global snow properties.
 *
 * @param properties A map of style snow properties values, with their names as a key.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleSnowForProperties:(nonnull id)properties __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Experimental. Sets a value to the the style snow property.
 *
 * @param property The style snow property name.
 * @param value The style snow property value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleSnowPropertyForProperty:(nonnull NSString *)property
                                                                         value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Experimental. Gets the value of a style snow property.
 *
 * @param property The style snow property name.
 * @return The style snow property value.
 */
- (nonnull MBMStylePropertyValue *)getStyleSnowPropertyForProperty:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Experimental. Sets the style global rain properties.
 *
 * @param properties A map of style rain properties values, with their names as a key.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleRainForProperties:(nonnull id)properties __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Experimental. Sets a value to the the style rain property.
 *
 * @param property The style rain property name.
 * @param value The style rain property value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleRainPropertyForProperty:(nonnull NSString *)property
                                                                         value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Experimental. Gets the value of a style rain property.
 *
 * @param property The style rain property name.
 * @return The style rain property value.
 */
- (nonnull MBMStylePropertyValue *)getStyleRainPropertyForProperty:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets a value to the the style atmosphere property.
 *
 * @param property The style atmosphere property name.
 * @param value The style atmosphere property value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleAtmospherePropertyForProperty:(nonnull NSString *)property
                                                                               value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets the style global [terrain](https://docs.mapbox.com/mapbox-gl-js/style-spec/#terrain) properties.
 *
 * @param properties A map of style terrain properties values, with their names as a key.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleTerrainForProperties:(nonnull id)properties __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the value of a style terrain property.
 *
 * @param property The style terrain property name.
 * @return The style terrain property value.
 */
- (nonnull MBMStylePropertyValue *)getStyleTerrainPropertyForProperty:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets a value to the the style terrain property.
 *
 * @param property The style terrain property name.
 * @param value The style terrain property value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleTerrainPropertyForProperty:(nonnull NSString *)property
                                                                            value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets the map's [projection](https://docs.mapbox.com/mapbox-gl-js/style-spec/projection/). If called with `null`, the map will reset the projection defined by the style.
 *
 * @param properties A map of style projection values, with their names as a key.
 * Supported projections are:
 *  * Mercator
 *  * Globe
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleProjectionForProperties:(nonnull id)properties __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Gets the value of a style projection property.
 *
 * @param property The style projection property name.
 * @return The style projection property value.
 */
- (nonnull MBMStylePropertyValue *)getStyleProjectionPropertyForProperty:(nonnull NSString *)property __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Sets a value to the the style projection property.
 *
 * @param property The style projection property name.
 * @param value The style projection property value.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleProjectionPropertyForProperty:(nonnull NSString *)property
                                                                               value:(nonnull id)value __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Get an `image` from the style.
 *
 * @param imageId The identifier of the `image`.
 *
 * @return The `image` for the given `imageId`, or empty if no image is associated with the `imageId`.
 */
- (nullable MBMImage *)getStyleImageForImageId:(nonnull NSString *)imageId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds an image to be used in the style. This API can also be used for updating
 * an image. If the image for a given `imageId` was already added, it gets replaced by the new image.
 *
 * The image can be used in [`icon-image`](https://www.mapbox.com/mapbox-gl-js/style-spec/#layout-symbol-icon-image),
 * [`fill-pattern`](https://www.mapbox.com/mapbox-gl-js/style-spec/#paint-fill-fill-pattern),
 * [`line-pattern`](https://www.mapbox.com/mapbox-gl-js/style-spec/#paint-line-line-pattern) and
 * [`text-field`](https://www.mapbox.com/mapbox-gl-js/style-spec/#layout-symbol-text-field) properties.
 *
 * @param imageId An identifier of the image.
 * @param scale A scale factor for the image.
 * @param image A pixel data of the image.
 * @param sdf An option to treat whether image is SDF(signed distance field) or not.
 * @param stretchX An array of two-element arrays, consisting of two numbers that represent
 * the from position and the to position of areas that can be stretched horizontally.
 * @param stretchY An array of two-element arrays, consisting of two numbers that represent
 * the from position and the to position of areas that can be stretched vertically.
 * @param content An array of four numbers, with the first two specifying the left, top
 * corner, and the last two specifying the right, bottom corner. If present, and if the
 * icon uses icon-text-fit, the symbol's text will be fit inside the content box.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addStyleImageForImageId:(nonnull NSString *)imageId
                                                                 scale:(float)scale
                                                                 image:(nonnull MBMImage *)image
                                                                   sdf:(BOOL)sdf
                                                              stretchX:(nonnull NSArray<MBMImageStretches *> *)stretchX
                                                              stretchY:(nonnull NSArray<MBMImageStretches *> *)stretchY
                                                               content:(nullable MBMImageContent *)content __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes an image from the style.
 *
 * @param imageId The identifier of the image to remove.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)removeStyleImageForImageId:(nonnull NSString *)imageId __attribute((ns_returns_retained));
/**
 * Checks whether an image exists.
 *
 * @param imageId The identifier of the image.
 *
 * @return True if image exists, false otherwise.
 */
- (BOOL)hasStyleImageForImageId:(nonnull NSString *)imageId;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds a model to be used in the style. This API can also be used for updating
 * a model. If the model for a given `modelId` was already added, it gets replaced by the new model.
 *
 * The model can be used in `model-id` property in model layer.
 *
 * @param modelId An identifier of the model.
 * @param modelUri A URI for the model.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addStyleModelForModelId:(nonnull NSString *)modelId
                                                              modelUri:(nonnull NSString *)modelUri __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Removes a model from the style.
 *
 * @param modelId The identifier of the model to remove.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)removeStyleModelForModelId:(nonnull NSString *)modelId __attribute((ns_returns_retained));
/**
 * Checks whether a model exists.
 *
 * @param modelId The identifier of the model.
 *
 * @return True if model exists, false otherwise.
 */
- (BOOL)hasStyleModelForModelId:(nonnull NSString *)modelId;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Adds a custom geometry to be used in the style. To add the data, implement the fetchTileFunction callback in the options and call setStyleCustomGeometrySourceTileData()
 *
 * @param sourceId A style source identifier
 * @param options The `custom geometry source options` for the custom geometry.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addStyleCustomGeometrySourceForSourceId:(nonnull NSString *)sourceId
                                                                               options:(nonnull MBMCustomGeometrySourceOptions *)options __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Set tile data of a custom geometry.
 *
 * @param sourceId A style source identifier.
 * @param tileId A `canonical tile id` of the tile.
 * @param featureCollection An array with the features to add.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleCustomGeometrySourceTileDataForSourceId:(nonnull NSString *)sourceId
                                                                                        tileId:(nonnull MBMCanonicalTileID *)tileId
                                                                             featureCollection:(nonnull NSArray<MBXFeature *> *)featureCollection __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Invalidate tile for provided custom geometry source.
 *
 * @param sourceId A style source identifier,.
 * @param tileId A `canonical tile id` of the tile.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)invalidateStyleCustomGeometrySourceTileForSourceId:(nonnull NSString *)sourceId
                                                                                           tileId:(nonnull MBMCanonicalTileID *)tileId __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Invalidate region for provided custom geometry source.
 *
 * @param sourceId A style source identifier
 * @param bounds A `coordinate bounds` object.
 *
 * @return A string describing an error if the operation was not successful, empty otherwise.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)invalidateStyleCustomGeometrySourceRegionForSourceId:(nonnull NSString *)sourceId
                                                                                             bounds:(nonnull MBMCoordinateBounds *)bounds __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Note! This is an experimental feature. It can be changed or removed in future versions.
 *
 * Adds a custom raster source to be used in the style. To add the data, implement the fetchTileFunction callback in the options and call setStyleCustomRasterSourceTileData()
 *
 * @param sourceId A style source identifier
 * @param options The `custom raster source options` for the custom raster source.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)addStyleCustomRasterSourceForSourceId:(nonnull NSString *)sourceId
                                                                             options:(nonnull MBMCustomRasterSourceOptions *)options __attribute((ns_returns_retained));
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Note! This is an experimental feature. It can be changed or removed in future versions.
 *
 * Set tile data for raster tiles.
 *
 * The provided data is not cached, and the implementation will call the fetch callback each time the tile reappears.
 *
 * @param sourceId A style source identifier.
 * @param tiles Array with new tile data.
 */
- (nonnull MBXExpected<NSNull *, NSString *> *)setStyleCustomRasterSourceTileDataForSourceId:(nonnull NSString *)sourceId
                                                                                       tiles:(nonnull NSArray<MBMCustomRasterSourceTileData *> *)tiles __attribute((ns_returns_retained));
/**
 * Check if the style is completely loaded.
 *
 * Note: The style specified sprite would be marked as loaded even with sprite loading error (An error will be emitted via `MapLoadingError`).
 * Sprite loading error is not fatal and we don't want it to block the map rendering, thus the function will still return `true` if style and sources are fully loaded.
 *
 * @return `true` if the style JSON contents, the style specified sprite and sources are all loaded, otherwise returns `false`.
 *
 */
- (BOOL)isStyleLoaded;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Cancels pending style loading request.
 */
- (void)cancelStyleLoading;
/**
 * WARNING: This API is not intended for public usage. It can be deleted or changed without any notice.
 * Check if style loading process is finished.
 *
 * @return `true` if the style loading process has finished, otherwise returns `false`.
 */
- (BOOL)isStyleLoadingFinished;

@end
