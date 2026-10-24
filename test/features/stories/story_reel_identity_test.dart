// R1 (07a group A): the reel follows the story on screen by id while its
// list is refetched underneath it (review 02 #1, #4, #5, #16).
import 'dart:async';

import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart'
    show storyPlacesGatewayProvider;
import 'package:attune/features/stories/data/story_repository.dart'
    show StoryApiError;
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../couple_map/support/fakes.dart' show FakeStoryPlacesGateway;
import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R1: the reel follows the story on screen, not a position', () {
    testWidgets(
      'a reply after the partner deletes an earlier story quotes the story '
      'on screen',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
        final rig = await pumpReel(
          tester,
          gateway: gateway,
          hold: const Duration(seconds: 30),
        );
        await tapRight(tester);
        expect(shownItemId(tester), 'b');

        gateway.active.removeWhere((i) => i.id == 'a');
        gateway.emitSignal();
        await settle(tester);

        expect(shownItemId(tester), 'b');
        expect(bars(tester), (index: 0, count: 2));
        await typeReply(tester, 'where is this?');
        await sendReply(tester);
        expect(rig.chat.lastSendArgs!.storyItemId, 'b');
      },
    );

    testWidgets('when the story on screen is deleted, the next one plays', (
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

      gateway.active.removeWhere((i) => i.id == 'b');
      gateway.emitSignal();
      await settle(tester);

      expect(shownItemId(tester), 'c');
      expect(bars(tester), (index: 1, count: 2));
    });

    testWidgets(
      'the last story deleted under me stops its sound and closes the reel',
      (tester) async {
        final gateway = ScriptedReelGateway(
          active: kitItems(['v'], videos: {'v'}),
        );
        final rig = await pumpReel(
          tester,
          gateway: gateway,
          below: ['HOME', 'CHAT'],
        );
        final player = rig.players.last;
        expect(player.playing, isTrue);

        gateway.active.clear();
        gateway.emitSignal();
        await settle(tester);

        expect(player.playing, isFalse, reason: 'no audio under an empty reel');
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(StoryReelScreen), findsNothing);
        expect(find.text('CHAT'), findsOneWidget);
      },
    );

    testWidgets('auto-advance follows the live list, never a stale copy', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 1),
      );
      expect(shownItemId(tester), 'a');

      gateway.active.removeWhere((i) => i.id == 'b');
      gateway.emitSignal();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 1100));
      await settle(tester);

      expect(shownItemId(tester), 'c');
    });

    testWidgets(
      'a first story that fails to load is not re-requested every frame',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']))
          ..signFailKeys.add('story-media/a.jpg');
        await pumpReel(tester, gateway: gateway);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(gateway.signCallsFor('a'), 1);
      },
    );
  });

  group('R1: Delete acts on the story on screen and steps off it', () {
    testWidgets(
      'deleting in the day reel shows the next story, and a second Delete '
      'removes only the story then on screen',
      (tester) async {
        final gateway = ScriptedReelGateway(
          day: kitItems(['a', 'b', 'c', 'd'], author: kitMe),
        );
        await pumpReel(
          tester,
          gateway: gateway,
          mode: KitMode.day,
          hold: const Duration(seconds: 30),
        );
        await tapRight(tester);
        expect(shownItemId(tester), 'b');

        await confirmDelete(tester);
        expect(gateway.deleteCalls, ['b']);
        expect(shownItemId(tester), 'c');
        expect(bars(tester), (index: 1, count: 3));

        await confirmDelete(tester);
        expect(gateway.deleteCalls, ['b', 'c']);
        expect(shownItemId(tester), 'd');
      },
    );

    testWidgets('deleting the newest story steps back to the one before it '
        '(regression guard)', (tester) async {
      final gateway = ScriptedReelGateway(
        day: kitItems(['a', 'b'], author: kitMe),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      await tapRight(tester);
      await confirmDelete(tester);
      expect(shownItemId(tester), 'a');
      expect(bars(tester), (index: 0, count: 1));
    });

    testWidgets('Delete steps off the story before the refetch returns', (
      tester,
    ) async {
      // `b` is a video: until Task 4 the body is a spinner during a gated
      // refetch, so the player list is what shows the step-off.
      final gateway = ScriptedReelGateway(
        day: kitItems(['a', 'b', 'c'], author: kitMe, videos: {'b'}),
      );
      final rig = await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      final gate = Completer<void>();
      gateway.refreshGates.add(gate);

      await confirmDelete(tester);

      expect(gateway.deleteCalls, ['a']);
      expect(rig.players.all.map((p) => p.itemId), ['b']);
      expect(rig.players.last.playing, isTrue);

      gate.complete();
      await settle(tester);
      expect(bars(tester), (index: 0, count: 2));
    });

    testWidgets('Delete is disabled while a delete is in flight', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        day: kitItems(['a', 'b'], author: kitMe),
      )..deleteGate = Completer<void>();
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      await confirmDelete(tester);
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('story-reel-delete')),
      );
      expect(button.onPressed, isNull);

      gateway.deleteGate!.complete();
      await settle(tester);
      expect(gateway.deleteCalls, ['a']);
      expect(shownItemId(tester), 'b');
    });

    testWidgets('a failed delete keeps the story and lets the person try again '
        '(Review Focus 3, regression guard)', (tester) async {
      final gateway = ScriptedReelGateway(
        day: kitItems(['a', 'b'], author: kitMe),
      )..deleteError = StoryApiError.network('offline');
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      await confirmDelete(tester);
      expect(find.text('Could not delete this story.'), findsOneWidget);
      expect(shownItemId(tester), 'a');
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('story-reel-delete')))
            .onPressed,
        isNotNull,
      );
    });
  });

  // Final review #2: the clock ran while a delete was in flight, so a slow
  // failure closed the reel (or landed on another story) untold.
  group('a slow delete keeps the reel paused until it returns', () {
    testWidgets('a slow delete of my last story keeps the reel open and '
        'reports a failure', (tester) async {
      final gateway =
          ScriptedReelGateway(active: kitItems(['a'], author: kitMe))
            ..deleteGate = Completer<void>()
            ..deleteError = StoryApiError.network('offline');
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 2),
      );
      await confirmDelete(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      // Long enough for a close's exit transition to finish.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryReelScreen), findsOneWidget);

      gateway.deleteGate!.complete();
      await settle(tester);
      expect(find.text('Could not delete this story.'), findsOneWidget);
      expect(shownItemId(tester), 'a');
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('story-reel-delete')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a slow delete that succeeds steps off as before', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b', 'c'], author: kitMe),
      )..deleteGate = Completer<void>();
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 1),
      );
      await confirmDelete(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(shownItemId(tester), 'a');

      gateway.deleteGate!.complete();
      await settle(tester);
      expect(gateway.deleteCalls, ['a']);
      expect(shownItemId(tester), 'b');
    });

    testWidgets('a slow remove-from-map keeps the reel paused and reports a '
        'failure', (tester) async {
      final gate = Completer<void>();
      final places = FakeStoryPlacesGateway({
        'clear_story_place':
            (_) => gate.future.then((_) => throw StateError('offline')),
      });
      await pumpReel(
        tester,
        gateway: ScriptedReelGateway(),
        mode: KitMode.places,
        placeItems: kitItems(['a', 'b'], author: kitMe),
        hold: const Duration(seconds: 1),
        extraOverrides: [storyPlacesGatewayProvider.overrideWithValue(places)],
      );
      await tester.tap(find.byKey(const ValueKey('story-reel-remove-place')));
      await settle(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(shownItemId(tester), 'a');

      gate.complete();
      await settle(tester);
      expect(
        find.text("Couldn't remove the place. Try again."),
        findsOneWidget,
      );
      expect(shownItemId(tester), 'a');
    });
  });

  group('R1: typing a reply has its own pause', () {
    testWidgets('tapping the story while typing only closes the keyboard', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      await typeReply(tester, 'hi');
      expect(replyFocused(tester), isTrue);

      await tapRight(tester);

      expect(shownItemId(tester), 'a');
      expect(replyFocused(tester), isFalse);
    });

    testWidgets('a hold released while typing does not restart the clock', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 1),
      );
      await typeReply(tester, 'hi');

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(StoryReelScreen)),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(shownItemId(tester), 'a');
      expect(replyFocused(tester), isTrue);
    });

    testWidgets("a tap in the reply strip's padding never moves the reel", (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      final send = tester.getRect(
        find.byKey(const ValueKey('story-reel-reply-send')),
      );
      final size = tester.getSize(find.byType(StoryReelScreen));

      await tester.tapAt(Offset(size.width - 4, send.center.dy));
      await settle(tester);

      expect(shownItemId(tester), 'a');
    });
  });

  group('R5: delete from my own reel', () {
    testWidgets('my reel offers Delete, and deleting shows my next story', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b', 'c'], author: kitMe),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(find.byKey(const ValueKey('story-reel-delete')), findsOneWidget);

      await confirmDelete(tester);
      expect(gateway.deleteCalls, ['a']);
      expect(shownItemId(tester), 'b');
      expect(bars(tester), (index: 0, count: 2));
    });

    testWidgets("my partner's reel never offers Delete", (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      expect(find.byKey(const ValueKey('story-reel-delete')), findsNothing);
    });

    testWidgets('deleting my only story closes my reel', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a'], author: kitMe),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        below: ['HOME', 'CHATS'],
        hold: const Duration(seconds: 30),
      );
      await confirmDelete(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryReelScreen), findsNothing);
      expect(find.text('CHATS'), findsOneWidget);
    });

    // Batch-4 review, Minor 4: Home's ring must not wait on realtime.
    testWidgets('deleting refreshes the Home ring without a signal', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a'], author: kitMe),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      // Home's rings row keeps the autoDispose ring provider alive.
      final sub = ProviderScope.containerOf(
        tester.element(find.byType(StoryReelScreen)),
      ).listen(storyRingSummaryProvider(kitRel), (_, __) {});
      addTearDown(sub.close);
      await settle(tester);
      final before = gateway.ringSummaryCalls;

      await confirmDelete(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(gateway.ringSummaryCalls, before + 1);
    });
  });
}
