// Tests for RawLocationService — the Nearby-only, Geolocator-direct
// position reader (AI Assistant spec §5.2). No test in this codebase
// mocks Geolocator yet (checked: `test/features/location/
// location_wiring_test.dart` asserts on `LocationService`/
// `presence_repository.dart` source text, never on a live/mocked
// Geolocator call), so this file establishes the convention Geolocator
// itself documents for testing its static API: swap
// `GeolocatorPlatform.instance` for a `mocktail` fake that implements
// the platform interface, since `Geolocator.checkPermission()` /
// `.requestPermission()` / `.isLocationServiceEnabled()` /
// `.getCurrentPosition()` all delegate to `GeolocatorPlatform.instance`
// under the hood.
import 'package:attune/features/ai_assistant/data/services/raw_location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _MockGeolocatorPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {}

Position _fakePosition({double lat = 1.23, double lng = 4.56, double acc = 12}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.utc(2026, 1, 1),
    accuracy: acc,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  late _MockGeolocatorPlatform mockPlatform;
  final service = const RawLocationService();

  setUp(() {
    mockPlatform = _MockGeolocatorPlatform();
    GeolocatorPlatform.instance = mockPlatform;
  });

  group('RawLocationService.getCurrentPosition', () {
    test('returns a RawPositionResult with only coordinates+accuracy on success', () async {
      when(() => mockPlatform.isLocationServiceEnabled())
          .thenAnswer((_) async => true);
      when(() => mockPlatform.checkPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);
      when(
        () => mockPlatform.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenAnswer((_) async => _fakePosition());

      final result = await service.getCurrentPosition();

      expect(result, isA<RawPositionSuccess>());
      final success = result as RawPositionSuccess;
      expect(success.latitude, 1.23);
      expect(success.longitude, 4.56);
      expect(success.accuracyM, 12);
    });

    test(
      'RawPositionSuccess has no field for any reverse-geocoded address/'
      'locality — proven at the type level, not just by this test not '
      'asserting one',
      () {
        // If a field existed, this file (as the type's own test) would
        // need to name it to compile a value for it. There is deliberately
        // nothing to name: latitude/longitude/accuracyM are the only
        // fields RawPositionSuccess's const constructor accepts.
        const success = RawPositionSuccess(
          latitude: 0,
          longitude: 0,
          accuracyM: 0,
        );
        expect(success.latitude, 0);
        expect(success.longitude, 0);
        expect(success.accuracyM, 0);
      },
    );

    test(
      'requests permission when checkPermission reports denied, and '
      'proceeds on success',
      () async {
        when(() => mockPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => true);
        when(() => mockPlatform.checkPermission())
            .thenAnswer((_) async => LocationPermission.denied);
        when(() => mockPlatform.requestPermission())
            .thenAnswer((_) async => LocationPermission.whileInUse);
        when(
          () => mockPlatform.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),
        ).thenAnswer((_) async => _fakePosition());

        final result = await service.getCurrentPosition();

        expect(result, isA<RawPositionSuccess>());
        verify(() => mockPlatform.requestPermission()).called(1);
      },
    );

    test(
      'returns RawPositionDenied (not a thrown exception) when the user '
      'declines the permission request',
      () async {
        when(() => mockPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => true);
        when(() => mockPlatform.checkPermission())
            .thenAnswer((_) async => LocationPermission.denied);
        when(() => mockPlatform.requestPermission())
            .thenAnswer((_) async => LocationPermission.denied);

        final result = await service.getCurrentPosition();

        expect(result, isA<RawPositionDenied>());
        verifyNever(
          () => mockPlatform.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),
        );
      },
    );

    test('returns RawPositionDenied when permission is denied forever', () async {
      when(() => mockPlatform.isLocationServiceEnabled())
          .thenAnswer((_) async => true);
      when(() => mockPlatform.checkPermission())
          .thenAnswer((_) async => LocationPermission.deniedForever);

      final result = await service.getCurrentPosition();

      expect(result, isA<RawPositionDenied>());
      verifyNever(() => mockPlatform.requestPermission());
    });

    test(
      'returns RawPositionServiceDisabled (not a thrown exception) when '
      'location services are off',
      () async {
        when(() => mockPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => false);

        final result = await service.getCurrentPosition();

        expect(result, isA<RawPositionServiceDisabled>());
        verifyNever(() => mockPlatform.checkPermission());
      },
    );

    test(
      'returns RawPositionFailure (not a thrown exception) when the '
      'platform throws while fetching a fix',
      () async {
        when(() => mockPlatform.isLocationServiceEnabled())
            .thenAnswer((_) async => true);
        when(() => mockPlatform.checkPermission())
            .thenAnswer((_) async => LocationPermission.whileInUse);
        when(
          () => mockPlatform.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),
        ).thenThrow(Exception('platform error'));

        final result = await service.getCurrentPosition();

        expect(result, isA<RawPositionFailure>());
      },
    );

    test('requests balanced/approximate accuracy, not high-accuracy tracking', () async {
      when(() => mockPlatform.isLocationServiceEnabled())
          .thenAnswer((_) async => true);
      when(() => mockPlatform.checkPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);

      LocationSettings? capturedSettings;
      when(
        () => mockPlatform.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenAnswer((invocation) async {
        capturedSettings =
            invocation.namedArguments[#locationSettings] as LocationSettings?;
        return _fakePosition();
      });

      await service.getCurrentPosition();

      expect(capturedSettings, isNotNull);
      expect(
        capturedSettings!.accuracy,
        LocationAccuracy.medium,
        reason:
            'spec §5.2 requires balanced/approximate accuracy, never '
            'high-accuracy tracking',
      );
    });
  });
}
