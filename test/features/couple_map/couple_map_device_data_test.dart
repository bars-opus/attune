// test/features/couple_map/couple_map_device_data_test.dart
import 'dart:io';

import 'package:attune/features/couple_map/data/couple_map_device_data.dart';
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'widget/support/memory_widget_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    CoupleWidgetSync.store = MemoryCoupleWidgetStore();
    SharedPreferences.setMockInitialValues({});
  });

  test('quick exit clears the home-screen widget first (widget spec §6.4)', () async {
    SharedPreferences.setMockInitialValues({'couple_widget_enabled': true});
    final widget =
        MemoryCoupleWidgetStore()
          ..payload = '{"v":1,"caption":"x","validUntilMs":9999999999999}';
    CoupleWidgetSync.store = widget;
    await clearCoupleMapDeviceData(
      clearMapCache: () async {},
      pins: FakePinImageRenderer(),
      store: MemoryCoupleMapLocalStore(),
    );
    expect(widget.payload, '{"v":1}');
    expect(widget.notified, 1);
    expect(await CoupleWidgetSync.isEnabled(), isFalse);
  });

  test('sign-out and the other Together exits clear the widget too', () {
    final source =
        File(
          'lib/features/together/data/together_device_surfaces.dart',
        ).readAsStringSync();
    // Started first, awaited last: never holds up Together's own clears.
    expect(
      source.indexOf('CoupleWidgetSync.clear()'),
      allOf(
        greaterThan(-1),
        lessThan(source.indexOf('TogetherWidgetSync.clear()')),
      ),
    );
    expect(source.contains('await distanceWidget;'), isTrue);
  });

  test('clears the Mapbox cache and the pin images', () async {
    var cleared = 0;
    final pins = FakePinImageRenderer();
    await pins.render(
      const PinSpec(
        initials: 'A',
        ring: Color(0xFFFFFFFF),
        fill: Color(0xFF000000),
        onFill: Color(0xFFFFFFFF),
        sizePx: 8,
      ),
    );
    expect(pins.length, 1);
    final store =
        MemoryCoupleMapLocalStore()
          ..values.addAll({for (final k in CoupleMapLocalKeys.all) k: 'x'});
    await clearCoupleMapDeviceData(
      clearMapCache: () async => cleared++,
      pins: pins,
      store: store,
    );
    expect(cleared, 1);
    expect(
      store.values,
      isEmpty,
      reason: 'pin choice, home area and hint go too (spec §3.6)',
    );
    expect(pins.length, 0);
  });

  test(
    'a failing map clear never throws (quick exit must not stall)',
    () async {
      await clearCoupleMapDeviceData(
        clearMapCache: () async => throw Exception('no map'),
        pins: FakePinImageRenderer(),
        store: MemoryCoupleMapLocalStore(),
      );
    },
  );

  test(
    'quick exit clears the map after the cover, and never touches server presence',
    () {
      final source =
          File(
            'lib/features/safety/domain/services/quick_exit_service.dart',
          ).readAsStringSync();
      final execute = source.substring(
        source.indexOf('static Future<void> execute'),
        source.indexOf('static Future<void> _markSafetyUnlockRequired'),
      );
      expect(
        execute.indexOf('_showNeutralCover(context)'),
        lessThan(execute.indexOf('clearCoupleMapDeviceData()')),
      );
      expect(execute.contains('unawaited(clearCoupleMapDeviceData())'), isTrue);
      for (final rpc in [
        'stop_presence',
        'set_presence_pause',
        'stopSharing',
      ]) {
        expect(
          source.contains(rpc),
          isFalse,
          reason: 'a sudden disappearance is itself a signal (spec §3.6)',
        );
      }
    },
  );
}
