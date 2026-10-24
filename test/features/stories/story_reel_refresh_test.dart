// R2 in the reel: a change signal never blanks the reel or drops the
// keyboard; error and empty states can be retried and closed by name.
import 'dart:async';

import 'package:attune/features/stories/data/story_repository.dart'
    show StoryApiError;
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a change signal while typing keeps the reply field, the text and the '
    'keyboard',
    (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      await typeReply(tester, 'half a tho');

      final gate = Completer<void>();
      gateway.refreshGates.add(gate);
      gateway.emitSignal();
      await settle(tester);

      expect(
        find.byKey(const ValueKey('story-reel-reply-field')),
        findsOneWidget,
      );
      expect(replyFocused(tester), isTrue);
      expect(shownItemId(tester), 'a');

      gate.complete();
      await settle(tester);
      expect(replyFocused(tester), isTrue);
      expect(find.text('half a tho'), findsOneWidget);
    },
  );

  testWidgets('the first load still shows a spinner (regression guard)', (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(active: kitItems(['a']))
      ..firstLoadGate = Completer<void>();
    await pumpReel(tester, gateway: gateway);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gateway.firstLoadGate!.complete();
    await settle(tester);
    expect(shownItemId(tester), 'a');
  });

  testWidgets('a first load that fails offers Try again, which reloads', (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(active: kitItems(['a']))
      ..nextListError = StoryApiError.network('offline');
    await pumpReel(tester, gateway: gateway);
    expect(find.text("Couldn't load this story."), findsOneWidget);
    expect(find.byTooltip('Close story'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-reel-error-retry')));
    await settle(tester);
    expect(shownItemId(tester), 'a');
  });

  testWidgets('the empty state close button is labelled', (tester) async {
    await pumpReel(tester, gateway: ScriptedReelGateway());
    expect(find.text('No stories to show.'), findsOneWidget);
    expect(find.byTooltip('Close story'), findsOneWidget);
  });

  testWidgets('a delete whose refetch fails still steps off the story '
      '(Review Focus 3)', (tester) async {
    final gateway = ScriptedReelGateway(
      day: kitItems(['a', 'b', 'c'], author: kitMe),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      hold: const Duration(seconds: 30),
    );
    gateway.nextListError = StoryApiError.network('offline');
    await confirmDelete(tester);
    expect(gateway.deleteCalls, ['a']);
    expect(shownItemId(tester), 'b');
  });

  // Batch-1 review, Important 1: while a refetch is held, an item that
  // completes must advance to the next story, never close the reel (the
  // pager used to drop its value during a refresh, so the live list read
  // as empty and the end-of-page path closed).
  testWidgets(
    'a photo ending during a held refetch advances instead of closing',
    (tester) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 1),
      );

      final gate = Completer<void>();
      gateway.refreshGates.add(gate);
      gateway.emitSignal();
      await settle(tester);

      await tester.pump(const Duration(milliseconds: 1100));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryReelScreen), findsOneWidget);

      gate.complete();
      await settle(tester);
      expect(shownItemId(tester), 'b');
    },
  );

  testWidgets(
    'a video ending during a held refetch advances instead of closing',
    (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['v', 'b'], videos: {'v'}),
      );
      final rig = await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );

      final gate = Completer<void>();
      gateway.refreshGates.add(gate);
      gateway.emitSignal();
      await settle(tester);

      rig.players.last.complete();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryReelScreen), findsOneWidget);
      expect(shownItemId(tester), 'b');

      gate.complete();
      await settle(tester);
      expect(shownItemId(tester), 'b');
    },
  );
}
