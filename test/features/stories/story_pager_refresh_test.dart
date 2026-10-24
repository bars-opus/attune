// R2 (07a group B): a refresh keeps what is on screen until the new page
// arrives, and a failed refresh keeps it too.
import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_repository.dart'
    show StoryApiError;
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

const _key = StoryReelKey(relationshipId: kitRel, authorId: kitPartner);

ProviderContainer _container(ScriptedReelGateway gateway) {
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(kitUser),
      storyReadGatewayProvider.overrideWithValue(gateway),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(
    storyReelPagesProvider(_key),
    (_, __) {},
    fireImmediately: true,
  );
  addTearDown(sub.close);
  return container;
}

List<String>? _ids(ProviderContainer c) =>
    c.read(storyReelPagesProvider(_key)).valueOrNull?.map((i) => i.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R2: refresh keeps data', () {
    test('a refresh keeps the loaded stories readable while it runs', () async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      final container = _container(gateway);
      await pumpEventQueue();
      expect(_ids(container), ['a', 'b']);

      final gate = Completer<void>();
      gateway.refreshGates.add(gate);
      gateway.active.add(kitItem('c', createdAt: DateTime.now().toUtc()));
      gateway.emitSignal();
      await pumpEventQueue();

      final during = container.read(storyReelPagesProvider(_key));
      expect(during.isRefreshing, isTrue);
      expect(_ids(container), ['a', 'b']);

      gate.complete();
      await pumpEventQueue();
      expect(_ids(container), ['a', 'b', 'c']);
    });

    test(
      'a refresh that fails keeps the stories and reports the error',
      () async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
        final container = _container(gateway);
        await pumpEventQueue();

        gateway.nextListError = StoryApiError.network('offline');
        gateway.emitSignal();
        await pumpEventQueue();

        final after = container.read(storyReelPagesProvider(_key));
        expect(after.hasError, isTrue);
        expect(_ids(container), ['a', 'b']);
      },
    );
  });

  group('loadMore shares one page', () {
    test('two callers share one fetch and both see the new page', () async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']))
        ..pageSize = 2;
      final container = _container(gateway);
      await pumpEventQueue();
      final notifier = container.read(storyReelPagesProvider(_key).notifier);
      final gate = Completer<void>();
      gateway.nextPageGate = gate;

      var firstDone = false;
      var secondDone = false;
      unawaited(notifier.loadMore().then((_) => firstDone = true));
      unawaited(notifier.loadMore().then((_) => secondDone = true));
      await pumpEventQueue();
      expect(
        secondDone,
        isFalse,
        reason: 'the second caller waits for the page',
      );

      gate.complete();
      await pumpEventQueue();
      expect(firstDone && secondDone, isTrue);
      expect(gateway.listCalls, 2);
      expect(_ids(container), ['a', 'b', 'c']);
    });

    test(
      'a loadMore during a refresh fetches nothing and never duplicates',
      () async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']))
          ..pageSize = 2;
        final container = _container(gateway);
        await pumpEventQueue();
        final notifier = container.read(storyReelPagesProvider(_key).notifier);

        final gate = Completer<void>();
        gateway.refreshGates.add(gate);
        gateway.emitSignal();
        await pumpEventQueue();
        final callsBefore = gateway.listCalls;

        final more = notifier.loadMore();
        await pumpEventQueue();
        expect(gateway.listCalls, callsBefore);
        expect(_ids(container), ['a', 'b']);

        gate.complete();
        await more;
        await pumpEventQueue();
        expect(_ids(container), ['a', 'b']);
      },
    );

    test('a loadMore overtaken by a refresh completes only after the refresh '
        'lands', () async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']))
        ..pageSize = 2;
      final container = _container(gateway);
      await pumpEventQueue();
      final notifier = container.read(storyReelPagesProvider(_key).notifier);

      final pageGate = Completer<void>();
      gateway.nextPageGate = pageGate;
      var moreDone = false;
      unawaited(notifier.loadMore().then((_) => moreDone = true));
      await pumpEventQueue();

      final refreshGate = Completer<void>();
      gateway.refreshGates.add(refreshGate);
      gateway.emitSignal();
      await pumpEventQueue();

      pageGate.complete();
      await pumpEventQueue();
      expect(moreDone, isFalse, reason: 'the stale page is dropped');

      refreshGate.complete();
      await pumpEventQueue();
      expect(moreDone, isTrue);
      expect(_ids(container), ['a', 'b']);
    });
  });
}
