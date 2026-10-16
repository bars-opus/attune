// test/features/couple_map/widget/couple_widget_sync_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_widget_store.dart';

final now = DateTime(2026, 10, 16, 12);
final png = Uint8List.fromList([1, 2, 3]);
CoupleWidgetPayload distance() => CoupleWidgetPayload(
  caption: '5.1k km apart',
  validUntilMs: now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
  reunionDate: '2026-10-28',
);

void main() {
  late MemoryCoupleWidgetStore store;
  setUp(() {
    store = MemoryCoupleWidgetStore();
    CoupleWidgetSync.store = store;
  });

  Future<void> optIn(bool on) async =>
      SharedPreferences.setMockInitialValues({coupleWidgetEnabledKey: on});

  test('publishes only when opted in, read from storage', () async {
    await optIn(false);
    final g = CoupleWidgetSync.generation;
    expect(
      await CoupleWidgetSync.publish(
        distance(),
        map: ReplaceMap(png),
        generation: g,
      ),
      isFalse,
    );
    expect(store.payload, isNull);
    await optIn(true);
    expect(
      await CoupleWidgetSync.publish(
        distance(),
        map: ReplaceMap(png),
        generation: g,
      ),
      isTrue,
    );
    expect(CoupleWidgetPayload.decode(store.payload), distance());
    expect(store.map, png);
    expect(store.notified, 1);
  });

  test('a stale generation never writes', () async {
    await optIn(true);
    final g = CoupleWidgetSync.generation;
    await CoupleWidgetSync.hideDistanceNow();
    store.log.clear();
    expect(
      await CoupleWidgetSync.publish(
        distance(),
        map: ReplaceMap(png),
        generation: g,
      ),
      isFalse,
    );
    expect(store.log, isEmpty);
  });

  test('no distance part removes the map', () async {
    await optIn(true);
    store.map = png;
    await CoupleWidgetSync.publish(
      const CoupleWidgetPayload(reunionDate: '2026-10-28'),
      map: const KeepMap(),
      generation: CoupleWidgetSync.generation,
    );
    expect(store.map, isNull);
  });

  test(
    'hideDistanceNow keeps the reunion, drops distance and map, bumps the generation',
    () async {
      await optIn(true);
      store.payload = distance().encode();
      store.map = png;
      final g = CoupleWidgetSync.generation;
      await CoupleWidgetSync.hideDistanceNow();
      expect(CoupleWidgetSync.generation, g + 1);
      final p = CoupleWidgetPayload.decode(store.payload);
      expect(p.hasDistance, isFalse);
      expect(p.reunionDate, '2026-10-28');
      expect(store.map, isNull);
    },
  );

  test(
    'clear empties, broadcasts before deleting the map, and resets the opt-in',
    () async {
      await optIn(true);
      store.payload = distance().encode();
      store.map = png;
      await CoupleWidgetSync.clear();
      expect(
        CoupleWidgetPayload.decode(store.payload),
        CoupleWidgetPayload.empty,
      );
      expect(store.map, isNull);
      expect(
        store.log.indexOf('notify'),
        lessThan(store.log.indexOf('removeMap')),
      );
      expect(await CoupleWidgetSync.isEnabled(), isFalse);
    },
  );

  test('clear(resetOptIn: false) keeps the choice (flag off)', () async {
    await optIn(true);
    await CoupleWidgetSync.clear(resetOptIn: false);
    expect(await CoupleWidgetSync.isEnabled(), isTrue);
  });

  test(
    'dropExpired removes a passed distance and its map from storage (§4.2)',
    () async {
      await optIn(true);
      store.payload =
          CoupleWidgetPayload(
            caption: 'x',
            validUntilMs: now.millisecondsSinceEpoch - 1,
            reunionDate: '2026-10-28',
          ).encode();
      store.map = png;
      await CoupleWidgetSync.dropExpired(now);
      final p = CoupleWidgetPayload.decode(store.payload);
      expect(p.hasDistance, isFalse);
      expect(p.reunionDate, '2026-10-28');
      expect(store.map, isNull);
    },
  );

  test(
    'a failed widget refresh still counts as written (Android before W2)',
    () async {
      await optIn(true);
      final s = NotifyFailsStore();
      CoupleWidgetSync.store = s;
      s.map = png;
      expect(
        await CoupleWidgetSync.publish(
          distance(),
          map: ReplaceMap(png),
          generation: CoupleWidgetSync.generation,
        ),
        isTrue,
      );
      expect(CoupleWidgetPayload.decode(s.payload), distance());
      await CoupleWidgetSync.hideDistanceNow();
      expect(
        s.map,
        isNull,
        reason: 'a notify failure must not skip the delete',
      );
    },
  );

  test('never throws without the plugin', () async {
    await optIn(true);
    CoupleWidgetSync.store = ThrowingCoupleWidgetStore();
    await CoupleWidgetSync.clear();
    await CoupleWidgetSync.hideDistanceNow();
    await CoupleWidgetSync.dropExpired(now);
    expect(
      await CoupleWidgetSync.publish(
        distance(),
        map: const KeepMap(),
        generation: CoupleWidgetSync.generation,
      ),
      isFalse,
    );
  });

  test('Android backup never carries the widget storage (§4.4)', () {
    for (final path in [
      'android/app/src/main/res/xml/backup_rules.xml',
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ]) {
      final xml = File(path).readAsStringSync();
      expect(
        RegExp(
          'domain="sharedpref" path="HomeWidgetPreferences.xml"',
        ).allMatches(xml).length,
        path.contains('extraction') ? 2 : 1,
        reason: path,
      );
      expect(
        RegExp('domain="file" path="home_widget/"').allMatches(xml).length,
        path.contains('extraction') ? 2 : 1,
        reason: path,
      );
    }
  });
}
