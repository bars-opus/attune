import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/together/data/together_live_activity.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/domain/together_live.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_widget_sync_test.dart' show FakeWidgetStore;

class FakeLiveStore implements LiveActivityStore {
  FakeLiveStore({this.supported = true});
  final bool supported;
  final shown = <LivePlan>[];
  int ends = 0;
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<void> show(LivePlan plan) async => shown.add(plan);
  @override
  Future<void> end() async => ends++;
}

class _BrokenStore implements LiveActivityStore {
  @override
  Future<bool> isSupported() async => throw Exception('no channel');
  @override
  Future<void> show(LivePlan plan) async => throw Exception('no channel');
  @override
  Future<void> end() async => throw Exception('no channel');
}

final _plan = LivePlan(
  title: 'Dinner',
  start: DateTime(2026, 11, 2, 19),
  end: DateTime(2026, 11, 2, 21),
);

void main() {
  late FakeLiveStore store;
  setUp(() {
    store = FakeLiveStore();
    TogetherLiveActivity.store = store;
    TogetherWidgetSync.store = FakeWidgetStore();
    SharedPreferences.setMockInitialValues({});
  });

  test('off by default; turning it off ends what is showing', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(togetherLiveEnabledProvider.future), isFalse);
    await c.read(togetherLiveEnabledProvider.notifier).set(true);
    expect(await c.read(togetherLiveEnabledProvider.future), isTrue);
    await c.read(togetherLiveEnabledProvider.notifier).set(false);
    expect(store.ends, 1);
    expect(
      (await SharedPreferences.getInstance()).getBool('together_live_enabled'),
      isFalse,
    );
  });

  test(
    'shows or ends only when this phone opted in (read from storage)',
    () async {
      await TogetherLiveActivity.showIfEnabled(_plan);
      expect(store.shown, isEmpty);
      SharedPreferences.setMockInitialValues({'together_live_enabled': true, 'together_live_titles': true});
      await TogetherLiveActivity.showIfEnabled(_plan);
      expect(store.shown, [_plan]);
      await TogetherLiveActivity.showIfEnabled(null);
      expect(store.ends, 1);
    },
  );

  test(
    'a phone without Live Activities: unsupported, and nothing throws',
    () async {
      TogetherLiveActivity.store = _BrokenStore();
      SharedPreferences.setMockInitialValues({'together_live_enabled': true});
      expect(await TogetherLiveActivity.isSupported(), isFalse);
      await TogetherLiveActivity.showIfEnabled(_plan);
      await TogetherLiveActivity.end();
    },
  );

  testWidgets('quick exit ends the lock-screen plan and empties the card', (
    t,
  ) async {
    final widgetStore = FakeWidgetStore();
    TogetherWidgetSync.store = widgetStore;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (c, _) => Scaffold(
                body: TextButton(
                  onPressed: () => QuickExitService.execute(c),
                  child: const Text('exit'),
                ),
              ),
        ),
        GoRoute(
          path: '/neutral',
          name: 'neutralScreen',
          builder: (_, __) => const Text('neutral'),
        ),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.tap(find.text('exit'));
    await t.pumpAndSettle();
    expect(find.text('neutral'), findsOneWidget);
    expect(store.ends, 1);
    expect(widgetStore.saved, [null]);
  });
}
