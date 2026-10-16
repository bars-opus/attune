// test/features/couple_map/widget/couple_widget_publisher_test.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/data/world_outline.dart';
import 'package:attune/features/couple_map/widget/domain/couple_widget_payload.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_preview.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_publisher.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    show currentRelationshipIdProvider;
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    show remindersListProvider, RemindersListNotifier;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../location/presence_repository_test.dart'
    show FakePresenceGateway, FakeSampler;
import 'support/memory_widget_store.dart';

class _Reminders extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => <ReminderModel>[];

  /// A new list instance, so listeners are told.
  void touch() => state = AsyncData(<ReminderModel>[]);
}

const farRows = [
  {
    'who': 'self',
    'cell_lat': 5.565,
    'cell_lng': -0.208,
    'freshness': 'fresh',
    'utc_offset_minutes': 0,
  },
  {
    'who': 'partner',
    'cell_lat': 51.505,
    'cell_lng': -0.125,
    'freshness': 'fresh',
    'utc_offset_minutes': 60,
    'distance_km': 5100,
    'together': false,
  },
];

const storedDistance = '{"v":1,"caption":"x","validUntilMs":9999999999999}';

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

int reads(FakePresenceGateway g) =>
    g.calls.where((c) => c.$1 == 'couple_map_presence').length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryCoupleWidgetStore store;
  late FakeSampler sampler;
  late WorldOutline outline;

  setUpAll(() async {
    outline = WorldOutline.parse(await rootBundle.load(WorldOutline.asset));
  });

  setUp(() {
    store = MemoryCoupleWidgetStore();
    CoupleWidgetSync.store = store;
    sampler = FakeSampler();
    SharedPreferences.setMockInitialValues({coupleWidgetEnabledKey: true});
  });

  (ProviderContainer, CoupleWidgetPublisher) make(
    FakePresenceGateway g, {
    bool flag = true,
    DateTime Function()? clock,
    bool stubRender = false,
  }) {
    final c = ProviderContainer(
      overrides: [
        presenceGatewayProvider.overrideWithValue(g),
        presenceSamplerProvider.overrideWithValue(sampler),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        coupleMapEnabledProvider.overrideWith((ref) async => flag),
        currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
        remindersListProvider.overrideWith(_Reminders.new),
        worldOutlineProvider.overrideWith((ref) async => outline),
      ],
    );
    addTearDown(c.dispose);
    final p = c.read(coupleWidgetPublisherProvider);
    if (clock != null) p.clock = clock;
    if (stubRender) p.render = (_, __) async => Uint8List.fromList([1]);
    return (c, p);
  }

  FakePresenceGateway far() =>
      FakePresenceGateway({'couple_map_presence': (_) => farRows});

  test(
    'a resume read writes distance and map, and never records or samples',
    () async {
      final g = far();
      final (_, p) = make(g);
      await p.refreshFromServer(force: true);
      final payload = CoupleWidgetPayload.decode(store.payload);
      expect(payload.hasDistance, isTrue);
      expect(payload.caption, '5.1k km apart');
      expect(store.map, isNotNull);
      expect(g.calls.map((c) => c.$1), isNot(contains('record_presence')));
      expect(sampler.sampled, 0);
      expect(p.preview.value?.view.caption, '5.1k km apart');
    },
  );

  test('not opted in: no read, nothing written', () async {
    SharedPreferences.setMockInitialValues({});
    final g = far();
    final (_, p) = make(g);
    await p.refreshFromServer(force: true);
    expect(g.calls, isEmpty);
    expect(store.payload, isNull);
  });

  test('at most one read per 5 minutes', () async {
    var t = DateTime(2026, 10, 16, 12);
    final g = far();
    final (_, p) = make(g, clock: () => t, stubRender: true);
    await p.refreshFromServer();
    await p.refreshFromServer();
    expect(reads(g), 1);
    t = t.add(const Duration(minutes: 6));
    await p.refreshFromServer();
    expect(reads(g), 2);
  });

  test('a pause during an in-flight read drops the read (spec §4.1)', () async {
    final gate = Completer<List<Map<String, Object?>>>();
    final g = FakePresenceGateway({'couple_map_presence': (_) => gate.future});
    final (_, p) = make(g, stubRender: true);
    final pending = p.refreshFromServer(force: true);
    await Future<void>.delayed(Duration.zero);
    await CoupleWidgetSync.hideDistanceNow();
    gate.complete(farRows);
    await pending;
    expect(CoupleWidgetPayload.decode(store.payload).hasDistance, isFalse);
    expect(store.map, isNull);
  });

  test(
    'a clear during a slow render drops the render (Review Focus 5)',
    () async {
      final gate = Completer<Uint8List>();
      final (_, p) = make(far());
      p.render = (_, __) => gate.future;
      final pending = p.refreshFromServer(force: true);
      // Let the read land and the render start (it waits on [gate]).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await CoupleWidgetSync.clear();
      gate.complete(Uint8List.fromList([9]));
      await pending;
      expect(
        CoupleWidgetPayload.decode(store.payload),
        CoupleWidgetPayload.empty,
      );
      expect(store.map, isNull);
    },
  );

  test('a render over budget publishes the text layout', () async {
    final (_, p) = make(far());
    p.render = (_, __) => Completer<Uint8List>().future;
    p.renderBudget = const Duration(milliseconds: 10);
    await p.refreshFromServer(force: true);
    expect(CoupleWidgetPayload.decode(store.payload).hasDistance, isTrue);
    expect(store.map, isNull);
  });

  test(
    'flag off (after a good read) clears without forgetting the choice',
    () async {
      store.payload = storedDistance;
      final (_, p) = make(far(), flag: false);
      await p.refreshFromServer(force: true);
      expect(store.payload, '{"v":1}');
      expect(await CoupleWidgetSync.isEnabled(), isTrue);
    },
  );

  test(
    'offline at launch never clears, even with the flag reading false',
    () async {
      store.payload = storedDistance;
      final g = FakePresenceGateway({
        'couple_map_presence': (_) => throw Exception('offline'),
      });
      final (_, p) = make(g, flag: false);
      await p.refreshFromServer(force: true);
      expect(store.payload, storedDistance);
    },
  );

  test('a failing read leaves the stored payload (Review Focus 1)', () async {
    store.payload = storedDistance;
    final g = FakePresenceGateway({
      'couple_map_presence': (_) => throw Exception('offline'),
    });
    final (_, p) = make(g);
    await p.refreshFromServer(force: true);
    expect(store.payload, storedDistance);
  });

  test(
    'a read from the map tab (the hook) publishes — the only path that can here',
    () async {
      // The publisher's own reads fail, so only the hook can write a distance.
      final g = FakePresenceGateway({
        'couple_map_presence': (_) => throw Exception('offline'),
      });
      final (c, p) = make(g, stubRender: true);
      p.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.payload, isNull);
      c.read(presenceReadsProvider).add((
        'r1',
        CoupleMapPresence.fromRows(farRows),
      ));
      await until(() => store.payload != null);
      expect(CoupleWidgetPayload.decode(store.payload).hasDistance, isTrue);
    },
  );

  test(
    'a reminders change re-publishes from memory: no new read, same validity',
    () async {
      var t = DateTime(2026, 10, 16, 12);
      final g = far();
      final (c, p) = make(g, clock: () => t, stubRender: true);
      p.start();
      await until(() => store.payload != null);
      final readsBefore = reads(g);
      final writesBefore = store.log.where((e) => e == 'payload').length;
      final validBefore =
          CoupleWidgetPayload.decode(store.payload).validUntilMs;
      t = t.add(const Duration(minutes: 1));
      (c.read(remindersListProvider.notifier) as _Reminders).touch();
      await until(
        () => store.log.where((e) => e == 'payload').length > writesBefore,
      );
      expect(reads(g), readsBefore);
      expect(
        CoupleWidgetPayload.decode(store.payload).validUntilMs,
        validBefore,
      );
    },
  );

  test('never keeps the couple-map provider alive (spec §8)', () async {
    final g = far();
    final (c, p) = make(g, stubRender: true);
    p.start();
    await until(() => store.payload != null);
    final sub = c.listen(coupleMapPresenceProvider('r1'), (_, __) {});
    await c.read(coupleMapPresenceProvider('r1').future);
    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      c.getAllProviderElements().where(
        (e) => e.origin == coupleMapPresenceProvider('r1'),
      ),
      isEmpty,
    );
    final settled = reads(g);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(reads(g), settled);
  });

  test('disposing mid-render is safe (no late write, no error)', () async {
    final gate = Completer<Uint8List>();
    final c = ProviderContainer(
      overrides: [
        presenceGatewayProvider.overrideWithValue(far()),
        presenceSamplerProvider.overrideWithValue(sampler),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        coupleMapEnabledProvider.overrideWith((ref) async => true),
        currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
        remindersListProvider.overrideWith(_Reminders.new),
        worldOutlineProvider.overrideWith((ref) async => outline),
      ],
    );
    final p = c.read(coupleWidgetPublisherProvider)
      ..render = (_, __) => gate.future;
    p.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.dispose();
    gate.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(store.map, isNull);
  });

  test('the same snapped region is not re-rendered', () async {
    var renders = 0;
    final (_, p) = make(far());
    p.render = (f, o) {
      renders++;
      return Future.value(Uint8List.fromList([1]));
    };
    await p.refreshFromServer(force: true);
    await p.refreshFromServer(force: true);
    expect(renders, 1);
  });

  test(
    'a clear forgets the preview and the last read (final review C1)',
    () async {
      final (_, p) = make(far(), stubRender: true);
      await p.refreshFromServer(force: true);
      expect(p.preview.value, isNotNull);
      await CoupleWidgetSync.clear();
      expect(
        p.preview.value,
        isNull,
        reason: 'the next account must not see it',
      );
    },
  );

  test('the toggle re-reads storage after a clear (final review C1)', () async {
    final (c, _) = make(far(), stubRender: true);
    expect(await c.read(coupleWidgetEnabledProvider.future), isTrue);
    await CoupleWidgetSync.clear();
    await Future<void>.delayed(Duration.zero);
    expect(await c.read(coupleWidgetEnabledProvider.future), isFalse);
  });

  test(
    'a reminders change after a pause never brings the distance back (final review I1)',
    () async {
      final g = FakePresenceGateway({
        'couple_map_presence': (_) => throw Exception('offline'),
      });
      final (c, p) = make(g, stubRender: true);
      p.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      c.read(presenceReadsProvider).add((
        'r1',
        CoupleMapPresence.fromRows(farRows),
      ));
      await until(() => store.payload != null);
      expect(CoupleWidgetPayload.decode(store.payload).hasDistance, isTrue);
      await CoupleWidgetSync.hideDistanceNow();
      store.log.clear();
      (c.read(remindersListProvider.notifier) as _Reminders).touch();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(CoupleWidgetPayload.decode(store.payload).hasDistance, isFalse);
      expect(store.log, isNot(contains('map')));
    },
  );
}
