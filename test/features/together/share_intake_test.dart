import 'dart:async';

import 'package:attune/features/together/data/share_intake.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/domain/shared_capture.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/share_intake_listener.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline_providers;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FakeShareSource implements ShareSource {
  FakeShareSource({this.first = const []});
  final List<SharedItem> first;
  final controller = StreamController<List<SharedItem>>.broadcast();
  int resets = 0;
  @override
  Future<List<SharedItem>> initial() async => first;
  @override
  Stream<List<SharedItem>> stream() => controller.stream;
  @override
  Future<void> reset() async => resets++;
}

Future<(ProviderContainer, List<int>)> _pump(
  WidgetTester t,
  FakeShareSource source, {
  String? relationshipId = 'r1',
}) async {
  final opened = <int>[];
  final container = ProviderContainer(
    overrides: [
      shareSourceProvider.overrideWithValue(source),
      timeline_providers.currentRelationshipIdProvider.overrideWith(
        (ref) async => relationshipId,
      ),
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ShareIntakeListener(
          onShare: () => opened.add(1),
          child: const Text('app'),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (container, opened);
}

void main() {
  testWidgets('a share that opened the app waits as a pending note', (t) async {
    final source = FakeShareSource(
      first: const [SharedItem('text', 'Dinner Sat 7pm')],
    );
    final (c, opened) = await _pump(t, source);
    expect(c.read(pendingShareProvider)?.text, 'Dinner Sat 7pm');
    expect(opened, [1]);
    expect(source.resets, 1);
  });

  testWidgets('a newer share replaces the older one; images are ignored', (
    t,
  ) async {
    final source = FakeShareSource();
    final (c, opened) = await _pump(t, source);
    source.controller.add(const [SharedItem('text', 'First')]);
    await t.pumpAndSettle();
    source.controller.add(const [SharedItem('text', 'Second')]);
    await t.pumpAndSettle();
    source.controller.add(const [SharedItem('image', '/tmp/x.jpg')]);
    await t.pumpAndSettle();
    expect(c.read(pendingShareProvider)?.text, 'Second');
    expect(opened.length, 2);
  });

  test('a pending share goes stale after 10 minutes', () {
    final p = PendingShare('x', DateTime(2026, 11, 2, 9));
    expect(p.expiredAt(DateTime(2026, 11, 2, 9, 9)), isFalse);
    expect(p.expiredAt(DateTime(2026, 11, 2, 9, 11)), isTrue);
  });

  testWidgets(
    'signed out or unpaired: the share waits and nothing is brought forward',
    (t) async {
      final source = FakeShareSource(
        first: const [SharedItem('text', 'Dinner Sat 7pm')],
      );
      final (c, opened) = await _pump(t, source, relationshipId: null);
      expect(c.read(pendingShareProvider)?.text, 'Dinner Sat 7pm');
      expect(opened, isEmpty);
    },
  );

  testWidgets("a share never lifts quick exit's neutral screen", (t) async {
    final router = GoRouter(
      initialLocation: '/neutralScreen',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('home')),
        GoRoute(
          path: '/neutralScreen',
          builder: (_, __) => const Text('neutral'),
        ),
        GoRoute(path: '/together', builder: (_, __) => const Text('together')),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    showTogetherForShare(router);
    await t.pumpAndSettle();
    expect(find.text('neutral'), findsOneWidget);
    router.go('/');
    await t.pumpAndSettle();
    showTogetherForShare(router);
    await t.pumpAndSettle();
    expect(find.text('together'), findsOneWidget);
  });

  testWidgets(
    "handled shares leave no copy in the App Group (the extension's keys)",
    (t) async {
      final store = _RecordingStore();
      TogetherWidgetSync.store = store;
      addTearDown(() => TogetherWidgetSync.store = const HomeWidgetStore());
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('receive_sharing_intent/messages'),
        (_) async => null,
      );
      await const ReceiveSharingIntentSource().reset();
      expect(store.removed, ['ShareKey', 'ShareMessageKey']);
    },
  );
}

class _RecordingStore implements WidgetStore {
  final removed = <String>[];
  @override
  Future<void> save(String? payload) async {}
  @override
  Future<void> remove(String key) async => removed.add(key);
}
