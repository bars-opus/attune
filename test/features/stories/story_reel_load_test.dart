// R4 (07a group D): a story is "seen", and its clock starts, only once it
// is actually on screen; a failed load never counts.
import 'dart:async';

import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart'
    show kStorySignedUrlReuse;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R4: seen on first frame', () {
    testWidgets('a photo counts as seen only once its bytes have arrived', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      final images = KitImages()..gates['a'] = Completer<void>();
      await pumpReel(tester, gateway: gateway, images: images);
      await tester.pump(const Duration(seconds: 2));

      expect(gateway.marked, isEmpty);
      expect(
        find.byKey(const ValueKey('story-reel-item-loading')),
        findsOneWidget,
      );

      images.gates['a']!.complete();
      await settle(tester);
      expect(gateway.marked, ['a']);
    });

    testWidgets(
      'the clock starts when the photo appears, not when its link is signed',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
        final images = KitImages()..gates['a'] = Completer<void>();
        await pumpReel(
          tester,
          gateway: gateway,
          images: images,
          hold: const Duration(seconds: 1),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(shownItemId(tester), 'a');

        images.gates['a']!.complete();
        await settle(tester);
        await tester.pump(const Duration(milliseconds: 800));
        expect(shownItemId(tester), 'a');

        await tester.pump(const Duration(milliseconds: 300));
        await settle(tester);
        expect(shownItemId(tester), 'b');
      },
    );

    testWidgets('a photo that fails to decode is never marked seen', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      final images = KitImages()..failing.add('a');
      await pumpReel(tester, gateway: gateway, images: images);
      await tester.pump(const Duration(milliseconds: 500));
      expect(gateway.marked, isEmpty);
    });

    testWidgets('a video counts as seen once it is ready to play '
        '(regression guard)', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['v'], videos: {'v'}),
      );
      await pumpReel(tester, gateway: gateway);
      expect(gateway.marked, ['v']);
    });
  });

  group('R4: failed items recover', () {
    testWidgets(
      'a story that cannot load says so, offers Retry and Next, and retries '
      'itself at most three times with growing gaps',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']))
          ..signFailKeys.add('story-media/a.jpg');
        await pumpReel(tester, gateway: gateway);

        expect(find.text("Couldn't load this story."), findsOneWidget);
        expect(find.byKey(const ValueKey('story-reel-retry')), findsOneWidget);
        expect(find.byKey(const ValueKey('story-reel-next')), findsOneWidget);
        expect(gateway.signCallsFor('a'), 1);

        await tester.pump(const Duration(seconds: 1));
        await settle(tester);
        expect(gateway.signCallsFor('a'), 2);
        await tester.pump(const Duration(seconds: 2));
        await settle(tester);
        expect(gateway.signCallsFor('a'), 3);
        await tester.pump(const Duration(seconds: 4));
        await settle(tester);
        expect(gateway.signCallsFor('a'), 4);
        await tester.pump(const Duration(seconds: 30));
        await settle(tester);
        expect(gateway.signCallsFor('a'), 4);
        expect(gateway.marked, isEmpty);
      },
    );

    testWidgets('Next skips a story that will not load', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']))
        ..signFailKeys.add('story-media/a.jpg');
      await pumpReel(tester, gateway: gateway);
      await tester.tap(find.byKey(const ValueKey('story-reel-next')));
      await settle(tester);
      expect(shownItemId(tester), 'b');
    });

    testWidgets('Retry loads the story once its link works again', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']))
        ..signFailKeys.add('story-media/a.jpg');
      await pumpReel(tester, gateway: gateway);
      gateway.signFailKeys.clear();
      await tester.tap(find.byKey(const ValueKey('story-reel-retry')));
      await settle(tester);
      expect(shownItemId(tester), 'a');
      expect(gateway.marked, ['a']);
    });

    testWidgets(
      'a video that never gets ready gives up after 15 seconds and offers '
      'Retry',
      (tester) async {
        final gateway = ScriptedReelGateway(
          active: kitItems(['v'], videos: {'v'}),
        );
        final players = KitPlayers()..hangInitFor = (_) => true;
        await pumpReel(tester, gateway: gateway, players: players);
        expect(find.byKey(const ValueKey('story-reel-retry')), findsNothing);

        await tester.pump(const Duration(seconds: 15));
        await settle(tester);
        expect(find.byKey(const ValueKey('story-reel-retry')), findsOneWidget);
        expect(players.all.first.disposed, isTrue);
      },
    );

    // Final review #3: a stale init settling late cleared the screen-level
    // timer, so the next video lost its 15 s deadline.
    testWidgets(
      "a slow video settling late never cancels the next video's 15 s "
      'deadline',
      (tester) async {
        final gateway = ScriptedReelGateway(
          active: kitItems(['v1', 'v2'], videos: {'v1', 'v2'}),
        );
        final v1Init = Completer<void>();
        final players =
            KitPlayers()
              ..initGateFor = ((id) => id == 'v1' ? v1Init : null)
              ..hangInitFor = ((id) => id == 'v2');
        await pumpReel(tester, gateway: gateway, players: players);
        await tapRight(tester);
        expect(players.last.itemId, 'v2');

        v1Init.complete();
        await settle(tester);
        await tester.pump(const Duration(seconds: 15));
        await settle(tester);

        expect(find.byKey(const ValueKey('story-reel-retry')), findsOneWidget);
      },
    );

    testWidgets('a video that fails mid-play stops and offers Retry', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['v'], videos: {'v'}),
      );
      final rig = await pumpReel(tester, gateway: gateway);
      final player = rig.players.last;
      player.fail();
      await settle(tester);
      expect(find.byKey(const ValueKey('story-reel-retry')), findsOneWidget);
      expect(player.playing, isFalse);
    });

    testWidgets('a buffering video shows a small spinner', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['v'], videos: {'v'}),
      );
      final rig = await pumpReel(tester, gateway: gateway);
      rig.players.last.isBuffering = true;
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const ValueKey('story-reel-buffering')),
        findsOneWidget,
      );
    });

    testWidgets('with reduce motion on, a buffering video still shows the '
        'spinner, and it goes when buffering ends (batch-3 review #1)', (
      tester,
    ) async {
      tester.view.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.view.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final gateway = ScriptedReelGateway(
        active: kitItems(['v'], videos: {'v'}),
      );
      final rig = await pumpReel(tester, gateway: gateway);
      rig.players.last.isBuffering = true;
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const ValueKey('story-reel-buffering')),
        findsOneWidget,
      );

      rig.players.last.isBuffering = false;
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('story-reel-buffering')), findsNothing);
    });

    testWidgets('Retry after an archive swap signs the new storage key '
        '(Review Focus 1)', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']))
        ..signFailKeys.add('story-media/a.jpg');
      await pumpReel(tester, gateway: gateway);

      gateway.active[0] = kitItem(
        'a',
        createdAt: gateway.active[0].createdAt,
        mediaKey: 'story-media/a-archived.jpg',
      );
      gateway.emitSignal();
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('story-reel-retry')));
      await settle(tester);

      // The last signing of story a's media (once a shows, the preload
      // of b signs b.jpg after it).
      expect(
        gateway.signCalls.lastWhere((k) => k.startsWith('story-media/a')),
        'story-media/a-archived.jpg',
      );
    });
  });

  group('one signed link per story per visit', () {
    testWidgets('the preloaded next photo is not signed again when shown', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      await tapRight(tester);
      expect(shownItemId(tester), 'b');
      expect(gateway.signCallsFor('b'), 1);
    });

    testWidgets('going back to a story reuses its link', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      await tapRight(tester);
      await tapLeft(tester);
      expect(shownItemId(tester), 'a');
      expect(gateway.signCallsFor('a'), 1);
    });

    testWidgets(
      'going back to a story after its link turned 540 s old signs it afresh '
      '(batch-2 review #2: the reel ages links on the injected clock)',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
        await pumpReel(
          tester,
          gateway: gateway,
          hold: const Duration(minutes: 20),
        );
        await tapRight(tester);
        await tester.pump(kStorySignedUrlReuse);
        await tapLeft(tester);
        expect(shownItemId(tester), 'a');
        expect(gateway.signCallsFor('a'), 2);
      },
    );

    testWidgets('a photo that failed to decode is signed afresh on Retry', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      final images = KitImages()..failing.add('a');
      await pumpReel(tester, gateway: gateway, images: images);
      images.failing.clear();
      await tester.tap(find.byKey(const ValueKey('story-reel-retry')));
      await settle(tester);
      expect(gateway.signCallsFor('a'), 2);
      expect(gateway.marked, ['a']);
    });
  });
}
