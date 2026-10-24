// R6 and the reel's chrome: whose story and when (06 #8), Seen for the
// poster (spec §5.2), the bars (06 #10), screen-reader pause (02 #18),
// gestures (05 #7, 02 #27) and where the reel opens (owner ruling 3).
import 'dart:async';

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:attune/features/stories/presentation/widgets/story_reel_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('storyPostedLabel', () {
    final now = DateTime.utc(2026, 10, 23, 12);

    test('the 24-hour reel says how long ago', () {
      expect(
        storyPostedLabel(
          now.subtract(const Duration(seconds: 20)),
          now: now,
          clockTime: false,
        ),
        'Just now',
      );
      expect(
        storyPostedLabel(
          now.subtract(const Duration(minutes: 12)),
          now: now,
          clockTime: false,
        ),
        '12m',
      );
      expect(
        storyPostedLabel(
          now.subtract(const Duration(hours: 3, minutes: 5)),
          now: now,
          clockTime: false,
        ),
        '3h',
      );
    });

    test('calendar and map stories show the clock time', () {
      final posted = DateTime.utc(2026, 10, 20, 9, 5);
      expect(
        storyPostedLabel(posted, now: now, clockTime: true),
        MyDateFormat.toTime(posted.toLocal()),
      );
    });
    test('map and quote stories show the date and the time', () {
      final posted = DateTime.utc(2026, 4, 12, 9, 5);
      final local = posted.toLocal();
      expect(
        storyPostedLabel(posted, now: now, clockTime: true, withDate: true),
        MyDateFormat.join([
          MyDateFormat.toDateShort(local),
          MyDateFormat.toTime(local),
        ]),
      );
      expect(
        storyPostedSpokenLabel(
          posted,
          now: now,
          clockTime: true,
          withDate: true,
        ),
        'posted ${MyDateFormat.toDateShort(local)} at '
        '${MyDateFormat.toTime(local)}',
      );
    });
  });

  group('R6: whose story, and when', () {
    final threeHoursAgo = DateTime.now().toUtc().subtract(
      const Duration(hours: 3, minutes: 5),
    );

    testWidgets("my partner's reel names them and says when", (tester) async {
      final gateway = ScriptedReelGateway(
        active: [kitItem('a', createdAt: threeHoursAgo)],
      );
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      expect(find.text('Kofi - 3h'), findsOneWidget);
    });

    testWidgets('my own reel says You', (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = ScriptedReelGateway(
        active: [kitItem('a', author: kitMe, createdAt: threeHoursAgo)],
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(find.text('You - 3h'), findsOneWidget);
      expect(find.bySemanticsLabel('You, 3 hours ago'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a day reel labels each partner with the time of day', (
      tester,
    ) async {
      final theirs = kitItem('t', createdAt: DateTime.utc(2026, 10, 20, 8));
      final mine = kitItem(
        'm',
        author: kitMe,
        createdAt: DateTime.utc(2026, 10, 20, 9),
      );
      final gateway = ScriptedReelGateway(day: [theirs, mine]);
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      expect(
        find.text('Kofi - ${MyDateFormat.toTime(theirs.createdAt.toLocal())}'),
        findsOneWidget,
      );
      await tapRight(tester);
      expect(
        find.text('You - ${MyDateFormat.toTime(mine.createdAt.toLocal())}'),
        findsOneWidget,
      );
    });

    // Final review #9: a map cluster mixes days, and a quoted story can be
    // from any day, so the clock time alone is ambiguous there.
    testWidgets('a map story says the date as well as the time', (
      tester,
    ) async {
      final theirs =
          StoryPlace.fromRow(_placeRow('p', author: kitPartner)).story;
      await pumpReel(
        tester,
        gateway: ScriptedReelGateway(),
        mode: KitMode.places,
        placeItems: [theirs],
        hold: const Duration(seconds: 30),
      );
      final local = theirs.createdAt.toLocal();
      expect(
        find.text(
          MyDateFormat.join([
            'Kofi',
            MyDateFormat.toDateShort(local),
            MyDateFormat.toTime(local),
          ]),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a story opened from a chat reply says its date too', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        day: [
          kitItem('x', createdAt: DateTime.utc(2026, 10, 20, 8)),
          kitItem('y', createdAt: DateTime.utc(2026, 10, 20, 9, 5)),
        ],
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        initialStoryItemId: 'y',
        hold: const Duration(seconds: 30),
      );
      final local = DateTime.utc(2026, 10, 20, 9, 5).toLocal();
      expect(
        find.text(
          MyDateFormat.join([
            'Kofi',
            MyDateFormat.toDateShort(local),
            MyDateFormat.toTime(local),
          ]),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a very long name fits on one line (Review Focus 5)', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: [kitItem('a', createdAt: threeHoursAgo)],
      );
      await pumpReel(
        tester,
        gateway: gateway,
        partnerName: 'A' * 120,
        hold: const Duration(seconds: 30),
      );
      expect(tester.takeException(), isNull);
      final byline = tester.widget<Text>(
        find.byKey(const ValueKey('story-reel-byline')),
      );
      expect(byline.maxLines, 1);
      expect(find.byTooltip('Close story'), findsOneWidget);
    });

    testWidgets('the buttons sit below the progress bars, not on them', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(day: kitItems(['a'], author: kitMe));
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      final barsBottom = tester.getRect(find.byType(StoryProgressBars)).bottom;
      expect(
        tester.getRect(find.byTooltip('Close story')).top,
        greaterThanOrEqualTo(barsBottom),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('story-reel-delete'))).top,
        greaterThanOrEqualTo(barsBottom),
      );
    });
  });

  group('Seen on my own story', () {
    testWidgets('my story my partner has seen says Seen', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a'], author: kitMe, viewed: {'a'}),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(find.byKey(const ValueKey('story-reel-seen')), findsOneWidget);
      expect(find.bySemanticsLabel('Seen by Kofi'), findsOneWidget);
    });

    testWidgets('my story not yet seen shows nothing', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a'], author: kitMe),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(find.byKey(const ValueKey('story-reel-seen')), findsNothing);
    });

    testWidgets("a partner's story I have seen never says Seen", (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a'], viewed: {'a'}),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      expect(find.byKey(const ValueKey('story-reel-seen')), findsNothing);
    });

    // Final review #1: list_story_places has no seen column, and
    // StoryPlace.fromRow fakes has_been_viewed = true for the pins.
    testWidgets('a map story my partner never watched shows no Seen', (
      tester,
    ) async {
      final mine = StoryPlace.fromRow(_placeRow('p', author: kitMe)).story;
      await pumpReel(
        tester,
        gateway: ScriptedReelGateway(),
        mode: KitMode.places,
        placeItems: [mine],
        hold: const Duration(seconds: 30),
      );
      expect(shownItemId(tester), 'p');
      expect(find.byKey(const ValueKey('story-reel-seen')), findsNothing);
    });

    testWidgets("the map reel never fades my partner's stories", (
      tester,
    ) async {
      final items = [
        for (final id in ['p', 'q'])
          StoryPlace.fromRow(_placeRow(id, author: kitPartner)).story,
      ];
      await pumpReel(
        tester,
        gateway: ScriptedReelGateway(),
        mode: KitMode.places,
        placeItems: items,
        hold: const Duration(seconds: 30),
      );
      final viewed =
          tester
              .widget<StoryProgressBars>(find.byType(StoryProgressBars))
              .viewed;
      expect(viewed, everyElement(isFalse));
    });

    testWidgets('Seen appears live when my partner watches', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a'], author: kitMe),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      gateway.active[0] = kitItem(
        'a',
        author: kitMe,
        createdAt: gateway.active[0].createdAt,
        viewed: true,
      );
      gateway.emitSignal();
      await settle(tester);
      expect(find.byKey(const ValueKey('story-reel-seen')), findsOneWidget);
    });
  });

  testWidgets("the reel fades my partner's stories I have already seen", (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(
      active: kitItems(['a', 'b', 'c'], viewed: {'c'}),
    );
    await pumpReel(tester, gateway: gateway, hold: const Duration(seconds: 30));
    final viewed =
        tester.widget<StoryProgressBars>(find.byType(StoryProgressBars)).viewed;
    expect(viewed![2], isTrue);
    expect(viewed[1], isFalse);
  });
  group('where the reel opens (owner ruling 3)', () {
    testWidgets("my partner's reel opens at the first story I have not seen", (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b', 'c'], viewed: {'a', 'b'}),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      expect(shownItemId(tester), 'c');
      expect(bars(tester), (index: 2, count: 3));
    });

    testWidgets('when everything is seen it starts again from the oldest '
        '(Review Focus 4)', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b'], viewed: {'a', 'b'}),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      expect(shownItemId(tester), 'a');
      expect(find.byType(StoryReelScreen), findsOneWidget);
    });

    testWidgets('the first unseen story can be on a later page', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b', 'c'], viewed: {'a', 'b'}),
      )..pageSize = 2;
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      expect(shownItemId(tester), 'c');
    });

    testWidgets('my own reel always opens at the oldest', (tester) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b'], author: kitMe, viewed: {'a'}),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(shownItemId(tester), 'a');
    });

    testWidgets('a day reel opened for one story starts at that story', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(day: kitItems(['x', 'y', 'z']));
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        initialStoryItemId: 'y',
        hold: const Duration(seconds: 30),
      );
      expect(shownItemId(tester), 'y');
    });

    // Final review #4: while the start search pages, nothing on screen
    // may act on (or name) items[0], a story the person never chose.
    testWidgets('while the quoted story is still being found, Delete and the '
        'byline wait for it', (tester) async {
      final gateway =
          ScriptedReelGateway(day: kitItems(['a', 'b', 'c'], author: kitMe))
            ..pageSize = 2
            ..nextPageGate = Completer<void>();
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        initialStoryItemId: 'c',
        hold: const Duration(seconds: 30),
      );
      expect(find.byKey(const ValueKey('story-reel-delete')), findsNothing);
      expect(find.byKey(const ValueKey('story-reel-byline')), findsNothing);
      expect(find.byKey(const ValueKey('story-reel-seen')), findsNothing);

      gateway.nextPageGate!.complete();
      await settle(tester);
      expect(shownItemId(tester), 'c');
      expect(find.byKey(const ValueKey('story-reel-delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-reel-byline')), findsOneWidget);
    });

    testWidgets('tapping a story reply in chat opens the story it quotes', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
          day: kitItems(['x', 'story-live', 'z'], author: kitMe),
        )
        ..replyTargets['story-live'] = StoryReplyTarget(
          relationshipId: kitRel,
          authorId: kitMe,
          occurredOn: kitDay,
        );
      final message = Message(
        id: 'srv-1',
        clientMessageId: 'client-srv-1',
        relationshipId: kitRel,
        senderId: kitMe,
        content: 'love this',
        createdAt: DateTime(2026, 10, 20, 10),
        status: MessageStatus.sent,
        isMine: true,
        quotedText: 'Photo story',
        storyItemId: 'story-live',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(kitUser),
            storyReadGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            home: Scaffold(body: MessageBubble(message: message)),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Photo story'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);

      final reel = tester.widget<StoryReelScreen>(find.byType(StoryReelScreen));
      expect(reel.initialStoryItemId, 'story-live');
      expect(kitIdFrom(gateway.signCalls.first), 'story-live');
    });
  });
  group('screen-reader pause (WCAG 2.2.2)', () {
    SemanticsNode viewer(WidgetTester tester) =>
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Story viewer')));

    void act(WidgetTester tester, SemanticsAction action) {
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        viewer(tester).id,
        action,
      );
    }

    testWidgets('the pause holds the story until it is played again', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 1),
      );

      act(tester, SemanticsAction.longPress);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(shownItemId(tester), 'a');

      act(tester, SemanticsAction.longPress);
      await tester.pump(const Duration(milliseconds: 1100));
      await settle(tester);
      expect(shownItemId(tester), 'b');
      handle.dispose();
    });

    testWidgets('the pause carries over to the next story', (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b', 'c']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 1),
      );
      act(tester, SemanticsAction.longPress);
      await settle(tester);
      act(tester, SemanticsAction.increase);
      await settle(tester);
      expect(shownItemId(tester), 'b');
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(shownItemId(tester), 'b');
      handle.dispose();
    });

    testWidgets('the pause is offered as a named action', (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      final ids = viewer(tester).getSemanticsData().customSemanticsActionIds!;
      final labels = [
        for (final id in ids) CustomSemanticsAction.getAction(id)!.label,
      ];
      expect(labels, contains('Pause story'));
      handle.dispose();
    });
  });
  group('gestures', () {
    testWidgets('a quick-exit triple tap at the top does not page the reel', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a', 'b', 'c', 'd']),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      final size = tester.getSize(find.byType(StoryReelScreen));
      for (var i = 0; i < 3; i++) {
        await tester.tapAt(Offset(size.width * 0.6, 20));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);
      expect(shownItemId(tester), 'a');
    });

    testWidgets('a tap lower down still pages (regression guard)', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      await tapRight(tester);
      expect(shownItemId(tester), 'b');
    });

    testWidgets('tapping back on the first story starts it again', (
      tester,
    ) async {
      // pumpReel leaves ~370 ms on the first story's clock; a 2 s hold makes
      // "no restart" cross the hold by the first check (1.57 s + 1.0 s).
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 2),
      );
      await tester.pump(const Duration(milliseconds: 1200));
      await tapLeft(tester);
      await tester.pump(const Duration(milliseconds: 1000));
      await settle(tester);
      expect(shownItemId(tester), 'a');

      await tester.pump(const Duration(milliseconds: 1100));
      await settle(tester);
      expect(shownItemId(tester), 'b');
    });
  });

  group('batch-6 review polish', () {
    final threeHoursAgo = DateTime.now().toUtc().subtract(
      const Duration(hours: 3, minutes: 5),
    );

    // Batch-4 review, Minor 3: VoiceOver read "Kofi dash 3 h".
    testWidgets('the byline is read as words, not "Kofi dash 3 h"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final gateway = ScriptedReelGateway(
        active: [kitItem('a', createdAt: threeHoursAgo)],
      );
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      expect(find.bySemanticsLabel('Kofi, 3 hours ago'), findsOneWidget);
      handle.dispose();
    });

    test('spoken posted labels', () {
      final now = DateTime.utc(2026, 10, 23, 12);
      String spoken(Duration ago) =>
          storyPostedSpokenLabel(now.subtract(ago), now: now, clockTime: false);
      expect(spoken(const Duration(seconds: 5)), 'just now');
      expect(spoken(const Duration(minutes: 1)), '1 minute ago');
      expect(spoken(const Duration(minutes: 12)), '12 minutes ago');
      expect(spoken(const Duration(hours: 1, minutes: 2)), '1 hour ago');
      expect(spoken(const Duration(hours: 3)), '3 hours ago');
      final posted = DateTime.utc(2026, 10, 20, 9, 5);
      expect(
        storyPostedSpokenLabel(posted, now: now, clockTime: true),
        'posted at ${MyDateFormat.toTime(posted.toLocal())}',
      );
    });

    // Batch-4 review, Minor 1: at large text the Seen chip squeezed the
    // byline to ~24 dp. It drops to its icon and keeps its label. On my own
    // active reel, where the server's seen flag is real (final review #1:
    // the map path has none and never shows Seen).
    testWidgets('at large text on a narrow phone Seen shrinks to its icon', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final mine = kitItem(
        'p',
        author: kitMe,
        createdAt: threeHoursAgo,
        viewed: true,
      );
      await pumpReel(
        tester,
        gateway: ScriptedReelGateway(active: [mine]),
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('story-reel-seen')), findsOneWidget);
      expect(find.text('Seen'), findsNothing);
      expect(find.bySemanticsLabel('Seen by Kofi'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('story-reel-byline'))).width,
        greaterThanOrEqualTo(80),
      );
      handle.dispose();
    });

    testWidgets('with room to spare Seen keeps its word (regression guard)', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(
        active: kitItems(['a'], author: kitMe, viewed: {'a'}),
      );
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.ownReel,
        hold: const Duration(seconds: 30),
      );
      expect(find.text('Seen'), findsOneWidget);
    });

    // Batch-4 review, Minor 2: white chrome over a bright photo.
    testWidgets('a dark scrim sits behind the bars and the header', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(day: kitItems(['a'], author: kitMe));
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        hold: const Duration(seconds: 30),
      );
      final scrim = find.byKey(const ValueKey('story-reel-top-scrim'));
      expect(scrim, findsOneWidget);
      final box = tester.widget<DecoratedBox>(scrim);
      final gradient =
          (box.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first, const Color(0x73000000));
      expect(gradient.colors.last, const Color(0x00000000));
      final area = tester.getRect(scrim);
      expect(area.top, 0);
      expect(
        area.bottom,
        greaterThanOrEqualTo(
          tester.getRect(find.byTooltip('Close story')).bottom,
        ),
      );
    });

    testWidgets('the scrim never swallows a tap (regression guard)', (
      tester,
    ) async {
      final gateway = ScriptedReelGateway(active: kitItems(['a', 'b']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      await tapRight(tester);
      expect(shownItemId(tester), 'b');
      final scrim = tester.getRect(
        find.byKey(const ValueKey('story-reel-top-scrim')),
      );
      final size = tester.getSize(find.byType(StoryReelScreen));
      // Below the quick-exit band (inset + 56) but still on the scrim.
      await tester.tapAt(Offset(size.width * 0.2, scrim.bottom - 4));
      await settle(tester);
      expect(shownItemId(tester), 'a');
    });

    // Batch-5 review, Minor 1: a stalled page must not hold the reel shut.
    testWidgets('a stalled search for the first unseen story gives up after '
        'a few seconds and opens at the oldest', (tester) async {
      final gateway =
          ScriptedReelGateway(
              active: kitItems(['a', 'b', 'c'], viewed: {'a', 'b'}),
            )
            ..pageSize = 2
            ..nextPageGate = Completer<void>();
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      expect(shownItemId(tester), isNull);
      await tester.pump(kStoryStartSearchBudget);
      await settle(tester);
      expect(shownItemId(tester), 'a');
    });

    // Batch-5 review, Nit 4: on iPhone, double-tap-and-hold is a real hold.
    testWidgets(
      'on iPhone the hint points at the Pause story action',
      (tester) async {
        final handle = tester.ensureSemantics();
        final gateway = ScriptedReelGateway(active: kitItems(['a']));
        await pumpReel(
          tester,
          gateway: gateway,
          hold: const Duration(seconds: 30),
        );
        final hint =
            tester
                .getSemantics(find.bySemanticsLabel(RegExp('^Story viewer')))
                .getSemanticsData()
                .hint;
        expect(hint, contains('Pause story action'));
        expect(hint, isNot(contains('Double-tap and hold')));
        handle.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets('on Android the hint keeps double-tap and hold', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final gateway = ScriptedReelGateway(active: kitItems(['a']));
      await pumpReel(
        tester,
        gateway: gateway,
        hold: const Duration(seconds: 30),
      );
      final hint =
          tester
              .getSemantics(find.bySemanticsLabel(RegExp('^Story viewer')))
              .getSemanticsData()
              .hint;
      expect(hint, contains('Double-tap and hold to pause or play'));
      handle.dispose();
    });
  });
}

/// A row shaped like `list_story_places` returns it (no seen column), with
/// this kit's storage keys so the readers can tell which story is shown.
Map<String, Object?> _placeRow(
  String id, {
  required String author,
  String created = '2026-04-12T09:05:00Z',
}) => {
  'story_item_id': id,
  'relationship_id': kitRel,
  'author_id': author,
  'lat': 5.556,
  'lng': -0.197,
  'label': 'Near Osu, Accra',
  'placed_at': created,
  'client_story_id': 'client-$id',
  'media_type': 'image',
  'media_key': 'story-media/$id.jpg',
  'thumbnail_key': 'story-media/$id-thumb.jpg',
  'media_width': 1080,
  'media_height': 1920,
  'duration_ms': null,
  'occurred_on': created.substring(0, 10),
  'created_at': created,
  'expires_at': '2026-04-13T09:05:00Z',
};
