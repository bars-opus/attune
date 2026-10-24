import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/domain/together_widget.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeWidgetStore implements WidgetStore {
  final saved = <String?>[];
  final removed = <String>[];
  @override
  Future<void> save(String? payload) async => saved.add(payload);
  @override
  Future<void> remove(String key) async => removed.add(key);
}

void main() {
  late FakeWidgetStore store;
  setUp(() {
    store = FakeWidgetStore();
    TogetherWidgetSync.store = store;
    SharedPreferences.setMockInitialValues({});
    // The story wipe's real image cache arms a 3 s bound under fake time
    // (stories Wave 4 Task 9); this suite tests Together's part.
    QuickExitService.clearStories = () async {};
    addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
  });

  test('off by default; turning it off clears what the widget shows', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(togetherWidgetEnabledProvider.future), isFalse);
    await c.read(togetherWidgetEnabledProvider.notifier).set(true);
    expect(await c.read(togetherWidgetEnabledProvider.future), isTrue);
    await c.read(togetherWidgetEnabledProvider.notifier).set(false);
    expect(store.saved.last, isNull);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'together_widget_enabled',
      ),
      isFalse,
    );
  });

  test('publish writes the payload; a broken store never throws', () async {
    await TogetherWidgetSync.publish([
      const WidgetLine(
        title: 'Dinner',
        label: 'Sat 7:00 PM',
        startMs: 1,
        endMs: 2,
      ),
    ]);
    expect(store.saved.single, contains('"Dinner"'));
    TogetherWidgetSync.store = _ThrowingStore();
    await TogetherWidgetSync.publish(const []);
    await TogetherWidgetSync.clear();
  });

  test(
    'publishing checks the stored opt-in itself (a stale one after sign-out never publishes)',
    () async {
      const line = WidgetLine(
        title: 'Dinner',
        label: 'Sat 7:00 PM',
        startMs: 1,
        endMs: 2,
      );
      SharedPreferences.setMockInitialValues({'together_widget_enabled': true, 'together_widget_titles': true});
      await TogetherWidgetSync.publishIfEnabled([line]);
      expect(store.saved.single, contains('Dinner'));
      // Sign-out's clearUserData() removes the key.
      SharedPreferences.setMockInitialValues({});
      await TogetherWidgetSync.publishIfEnabled([line]);
      expect(store.saved.length, 1);
    },
  );

  testWidgets(
    'quick exit shows the neutral screen first, then clears the widget',
    (t) async {
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
      await t.pumpAndSettle(); // the route change, then the 300 ms exit timer
      expect(find.text('neutral'), findsOneWidget);
      expect(store.saved, [null]);
      // and any shared text the share extension left in the App Group
      expect(store.removed, ['ShareKey', 'ShareMessageKey']);
    },
  );
}

class _ThrowingStore implements WidgetStore {
  @override
  Future<void> save(String? payload) async => throw Exception('no widget');
  @override
  Future<void> remove(String key) async => throw Exception('no widget');
}
