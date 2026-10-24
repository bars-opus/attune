// R3 (07a group C): an item completes once, and the reel closes once,
// popping only itself.
import 'dart:async';

import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R3: one-shot completion and close', () {
    testWidgets('the last photo ending closes only the reel', (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      await pumpReel(
        tester,
        gateway: gateway,
        below: ['HOME', 'CHAT'],
        hold: const Duration(seconds: 1),
      );
      await tester.pump(const Duration(milliseconds: 1200));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(find.byType(StoryReelScreen), findsNothing);
      expect(find.text('CHAT'), findsOneWidget);
    });

    testWidgets('closing a video stops its sound at once', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['v'], videos: {'v'}),
      );
      final rig = await pumpReel(tester, gateway: gateway);
      final player = rig.players.last;
      expect(player.playing, isTrue);

      await tester.tap(find.byTooltip('Close story'));
      await tester.pump();

      expect(player.playing, isFalse);
    });
  });

  group('R3: dialogs pause the reel', () {
    testWidgets(
      'the Delete dialog pauses the reel; the story resumes after Cancel',
      (tester) async {
        final gateway = ScriptedReelGateway(
          day: kitItems(['a', 'b'], author: kitMe),
        );
        await pumpReel(
          tester,
          gateway: gateway,
          mode: KitMode.day,
          hold: const Duration(seconds: 1),
        );
        await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
        await settle(tester);
        await tester.pump(const Duration(seconds: 3));

        expect(find.text('Delete this story?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(shownItemId(tester), 'a');

        await tester.pump(const Duration(milliseconds: 1100));
        await settle(tester);
        expect(shownItemId(tester), 'b');
      },
    );

    testWidgets(
      'coming back to the app with the dialog open keeps the reel paused '
      '(Review Focus 2)',
      (tester) async {
        final gateway = ScriptedReelGateway(
          day: kitItems(['a', 'b'], author: kitMe),
        );
        await pumpReel(
          tester,
          gateway: gateway,
          mode: KitMode.day,
          hold: const Duration(seconds: 1),
        );
        await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
        await settle(tester);
        await backgroundAndResume(tester);
        await tester.pump(const Duration(seconds: 3));

        expect(find.text('Delete this story?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(shownItemId(tester), 'a');
      },
    );

    // Final review #10: the keyboard half of Review Focus 2 (regression
    // guard; the behaviour was already correct).
    testWidgets(
      'coming back to the app while typing a reply keeps the reel paused '
      '(Review Focus 2)',
      (tester) async {
        final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
        await pumpReel(
          tester,
          gateway: gateway,
          hold: const Duration(seconds: 1),
        );
        await typeReply(tester, 'hi');
        expect(replyFocused(tester), isTrue);

        await backgroundAndResume(tester);
        await tester.pump(const Duration(seconds: 3));
        await settle(tester);

        expect(shownItemId(tester), 'a');
        expect(replyFocused(tester), isTrue);
      },
    );

    // Batch-1 review, Minor 5: a signal that empties the reel while one of
    // its dialogs is open dismisses that dialog and closes the reel. It
    // never pops only the dialog (leaving the reel on its empty state),
    // never leaves the dialog orphaned, and never pops the screen below.
    testWidgets(
      'a signal that empties the reel under its dialog closes both, and '
      'only them',
      (tester) async {
        final gateway = ScriptedReelGateway(
          day: kitItems(['a'], author: kitMe),
        );
        await pumpReel(
          tester,
          gateway: gateway,
          mode: KitMode.day,
          below: ['HOME', 'CHAT'],
          hold: const Duration(seconds: 30),
        );
        await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
        await settle(tester);
        expect(find.text('Delete this story?'), findsOneWidget);

        gateway.day.clear();
        gateway.emitSignal();
        await settle(tester);
        await tester.pumpAndSettle();

        expect(find.text('Delete this story?'), findsNothing);
        expect(find.byType(StoryReelScreen), findsNothing);
        expect(find.text('CHAT'), findsOneWidget);
        expect(gateway.deleteCalls, isEmpty);
      },
    );
  });

  testWidgets(
    'a tap while the next page loads waits for it instead of closing the reel',
    (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['p1', 'p2', 'p3']))
        ..pageSize = 2;
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 1),
      );
      await tapRight(tester);
      expect(shownItemId(tester), 'p2');

      final gate = Completer<void>();
      gateway.nextPageGate = gate;
      await tester.pump(const Duration(milliseconds: 1100));
      await tapRight(tester);
      expect(find.byType(StoryReelScreen), findsOneWidget);

      gate.complete();
      await settle(tester);
      expect(shownItemId(tester), 'p3');
    },
  );

  // Batch-2 review, Important 1: a page fetch overtaken by a refresh must
  // not spend the reel's page passes and close it while more pages exist.
  testWidgets(
    'a page load overtaken by a refresh still reaches the next page',
    (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['p1', 'p2', 'p3']))
        ..pageSize = 2;
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      await tapRight(tester);
      expect(shownItemId(tester), 'p2');

      final pageGate = Completer<void>();
      gateway.nextPageGate = pageGate;
      await tapRight(tester);

      final refreshGate = Completer<void>();
      gateway.refreshGates.add(refreshGate);
      gateway.emitSignal();
      await settle(tester);

      pageGate.complete();
      await settle(tester);
      refreshGate.complete();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(StoryReelScreen), findsOneWidget);
      expect(shownItemId(tester), 'p3');
    },
  );

  // Batch-2 review, Minor 2: the dialog counts as open from the moment it
  // is pushed, not from its first build a frame later.
  testWidgets(
    'a signal that empties the reel in the frame the dialog opens closes '
    'both',
    (tester) async {
      final gateway = ScriptedReelGateway(day: kitItems(['a'], author: kitMe));
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        below: ['HOME', 'CHAT'],
        hold: const Duration(seconds: 30),
      );
      gateway.day.clear();
      await tester.tap(find.byKey(const ValueKey('story-reel-delete')));
      gateway.emitSignal();
      await settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('Delete this story?'), findsNothing);
      expect(find.byType(StoryReelScreen), findsNothing);
      expect(find.text('CHAT'), findsOneWidget);
      expect(gateway.deleteCalls, isEmpty);
    },
  );
}
