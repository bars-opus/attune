// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$locationServiceHash() => r'f7b3dbe3e362693a99dbd0c857f576f80a3f5f74';

/// See also [locationService].
@ProviderFor(locationService)
final locationServiceProvider = AutoDisposeProvider<LocationService>.internal(
  locationService,
  name: r'locationServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$locationServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LocationServiceRef = AutoDisposeProviderRef<LocationService>;
String _$hasLocationHash() => r'b3f843056b12c82bca96c245936c6c4c762b4657';

/// See also [hasLocation].
@ProviderFor(hasLocation)
final hasLocationProvider = AutoDisposeProvider<bool>.internal(
  hasLocation,
  name: r'hasLocationProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$hasLocationHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HasLocationRef = AutoDisposeProviderRef<bool>;
String _$userLocationNotifierHash() =>
    r'4644a7750f138e2506cd8a475b1f2dc5b7002b3c';

/// See also [UserLocationNotifier].
@ProviderFor(UserLocationNotifier)
final userLocationNotifierProvider =
    AutoDisposeNotifierProvider<UserLocationNotifier, UserLocation?>.internal(
  UserLocationNotifier.new,
  name: r'userLocationNotifierProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$userLocationNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$UserLocationNotifier = AutoDisposeNotifier<UserLocation?>;
String _$distanceToShopHash() => r'fed0f920b813037e32027ed04d0a0156e8f721a8';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$DistanceToShop extends BuildlessAutoDisposeNotifier<double?> {
  late final double shopLat;
  late final double shopLng;

  double? build(
    double shopLat,
    double shopLng,
  );
}

/// See also [DistanceToShop].
@ProviderFor(DistanceToShop)
const distanceToShopProvider = DistanceToShopFamily();

/// See also [DistanceToShop].
class DistanceToShopFamily extends Family<double?> {
  /// See also [DistanceToShop].
  const DistanceToShopFamily();

  /// See also [DistanceToShop].
  DistanceToShopProvider call(
    double shopLat,
    double shopLng,
  ) {
    return DistanceToShopProvider(
      shopLat,
      shopLng,
    );
  }

  @override
  DistanceToShopProvider getProviderOverride(
    covariant DistanceToShopProvider provider,
  ) {
    return call(
      provider.shopLat,
      provider.shopLng,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'distanceToShopProvider';
}

/// See also [DistanceToShop].
class DistanceToShopProvider
    extends AutoDisposeNotifierProviderImpl<DistanceToShop, double?> {
  /// See also [DistanceToShop].
  DistanceToShopProvider(
    double shopLat,
    double shopLng,
  ) : this._internal(
          () => DistanceToShop()
            ..shopLat = shopLat
            ..shopLng = shopLng,
          from: distanceToShopProvider,
          name: r'distanceToShopProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$distanceToShopHash,
          dependencies: DistanceToShopFamily._dependencies,
          allTransitiveDependencies:
              DistanceToShopFamily._allTransitiveDependencies,
          shopLat: shopLat,
          shopLng: shopLng,
        );

  DistanceToShopProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.shopLat,
    required this.shopLng,
  }) : super.internal();

  final double shopLat;
  final double shopLng;

  @override
  double? runNotifierBuild(
    covariant DistanceToShop notifier,
  ) {
    return notifier.build(
      shopLat,
      shopLng,
    );
  }

  @override
  Override overrideWith(DistanceToShop Function() create) {
    return ProviderOverride(
      origin: this,
      override: DistanceToShopProvider._internal(
        () => create()
          ..shopLat = shopLat
          ..shopLng = shopLng,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        shopLat: shopLat,
        shopLng: shopLng,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<DistanceToShop, double?> createElement() {
    return _DistanceToShopProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is DistanceToShopProvider &&
        other.shopLat == shopLat &&
        other.shopLng == shopLng;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, shopLat.hashCode);
    hash = _SystemHash.combine(hash, shopLng.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin DistanceToShopRef on AutoDisposeNotifierProviderRef<double?> {
  /// The parameter `shopLat` of this provider.
  double get shopLat;

  /// The parameter `shopLng` of this provider.
  double get shopLng;
}

class _DistanceToShopProviderElement
    extends AutoDisposeNotifierProviderElement<DistanceToShop, double?>
    with DistanceToShopRef {
  _DistanceToShopProviderElement(super.provider);

  @override
  double get shopLat => (origin as DistanceToShopProvider).shopLat;
  @override
  double get shopLng => (origin as DistanceToShopProvider).shopLng;
}

String _$distanceToFreelancerHash() =>
    r'5c9dba4a3581220955bdd3829f708a303f72aa51';

abstract class _$DistanceToFreelancer
    extends BuildlessAutoDisposeNotifier<double?> {
  late final double freelancerLat;
  late final double freelancerLng;

  double? build(
    double freelancerLat,
    double freelancerLng,
  );
}

/// See also [DistanceToFreelancer].
@ProviderFor(DistanceToFreelancer)
const distanceToFreelancerProvider = DistanceToFreelancerFamily();

/// See also [DistanceToFreelancer].
class DistanceToFreelancerFamily extends Family<double?> {
  /// See also [DistanceToFreelancer].
  const DistanceToFreelancerFamily();

  /// See also [DistanceToFreelancer].
  DistanceToFreelancerProvider call(
    double freelancerLat,
    double freelancerLng,
  ) {
    return DistanceToFreelancerProvider(
      freelancerLat,
      freelancerLng,
    );
  }

  @override
  DistanceToFreelancerProvider getProviderOverride(
    covariant DistanceToFreelancerProvider provider,
  ) {
    return call(
      provider.freelancerLat,
      provider.freelancerLng,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'distanceToFreelancerProvider';
}

/// See also [DistanceToFreelancer].
class DistanceToFreelancerProvider
    extends AutoDisposeNotifierProviderImpl<DistanceToFreelancer, double?> {
  /// See also [DistanceToFreelancer].
  DistanceToFreelancerProvider(
    double freelancerLat,
    double freelancerLng,
  ) : this._internal(
          () => DistanceToFreelancer()
            ..freelancerLat = freelancerLat
            ..freelancerLng = freelancerLng,
          from: distanceToFreelancerProvider,
          name: r'distanceToFreelancerProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$distanceToFreelancerHash,
          dependencies: DistanceToFreelancerFamily._dependencies,
          allTransitiveDependencies:
              DistanceToFreelancerFamily._allTransitiveDependencies,
          freelancerLat: freelancerLat,
          freelancerLng: freelancerLng,
        );

  DistanceToFreelancerProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.freelancerLat,
    required this.freelancerLng,
  }) : super.internal();

  final double freelancerLat;
  final double freelancerLng;

  @override
  double? runNotifierBuild(
    covariant DistanceToFreelancer notifier,
  ) {
    return notifier.build(
      freelancerLat,
      freelancerLng,
    );
  }

  @override
  Override overrideWith(DistanceToFreelancer Function() create) {
    return ProviderOverride(
      origin: this,
      override: DistanceToFreelancerProvider._internal(
        () => create()
          ..freelancerLat = freelancerLat
          ..freelancerLng = freelancerLng,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        freelancerLat: freelancerLat,
        freelancerLng: freelancerLng,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<DistanceToFreelancer, double?>
      createElement() {
    return _DistanceToFreelancerProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is DistanceToFreelancerProvider &&
        other.freelancerLat == freelancerLat &&
        other.freelancerLng == freelancerLng;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, freelancerLat.hashCode);
    hash = _SystemHash.combine(hash, freelancerLng.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin DistanceToFreelancerRef on AutoDisposeNotifierProviderRef<double?> {
  /// The parameter `freelancerLat` of this provider.
  double get freelancerLat;

  /// The parameter `freelancerLng` of this provider.
  double get freelancerLng;
}

class _DistanceToFreelancerProviderElement
    extends AutoDisposeNotifierProviderElement<DistanceToFreelancer, double?>
    with DistanceToFreelancerRef {
  _DistanceToFreelancerProviderElement(super.provider);

  @override
  double get freelancerLat =>
      (origin as DistanceToFreelancerProvider).freelancerLat;
  @override
  double get freelancerLng =>
      (origin as DistanceToFreelancerProvider).freelancerLng;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
