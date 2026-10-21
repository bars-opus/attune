import 'dart:math' as math;

import 'package:attune/core/ui/layout/measure_size.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/games/invites/presentation/game_composer_bar.dart';
import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// #33: the list reserved a fixed 120/64px above the composer, so anything
/// stacked on top of the composer (typing indicator, reply strip, staged
/// game bar, a multi-line draft) painted over the newest bubble. The
/// reserve is now the measured height of that overlay.
void main() {
  // A phone with a home indicator: the overlay's SafeArea adds 34px under
  // the composer, which is what the old guessed reserve under-counted.
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(
            // reduceMotionOf reads MediaQuery; the platform accessibility
            // flag would also zero every AnimationController.
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduceMotion),
                  child: child!,
                ),
            home: ChatScreen(conversation: convo),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  // Enough frames for: the strip to build, its measurement to land, and
  // the 220ms at-bottom glide to start and finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  final messageList = find.byWidgetPredicate((w) => w is ListView && w.reverse);
  double listBottomPadding(WidgetTester tester) =>
      (tester.widget<ListView>(messageList).padding! as EdgeInsets).bottom;

  /// What the screen hands the list: the measured overlay height (null
  /// until measured). Each change is one measurement-driven screen rebuild.
  double? measuredOverlay(WidgetTester tester) =>
      (tester.widget(
                    find.byWidgetPredicate(
                      (w) => w.runtimeType.toString() == '_MessageList',
                    ),
                  )
                  as dynamic)
              .bottomOverlayHeight
          as double?;

  /// The whole newest row: bubble plus its timestamp/receipt footer.
  double newestRowBottom(WidgetTester tester) =>
      tester
          .getRect(
            find
                .ancestor(
                  of: find.text('newest message'),
                  matching: find.byType(MessageBubble),
                )
                .first,
          )
          .bottom;

  void seedOne(FakeChatRepository repo) {
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'newest message',
      createdAt: DateTime.now(),
    );
  }

  testWidgets('the typing indicator never covers the newest message', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo);

    final composerTop = tester.getTopLeft(find.byType(ChatTextField)).dy;
    expect(
      tester.getBottomLeft(find.text('newest message')).dy,
      lessThan(composerTop),
    );
    expect(newestRowBottom(tester), lessThanOrEqualTo(composerTop));

    repo.emitPartnerTyping('partner', true);
    await settle(tester);

    final indicator = find.byKey(const ValueKey('typing_indicator'));
    expect(indicator, findsOneWidget);
    final indicatorTop = tester.getTopLeft(indicator).dy;
    expect(
      tester.getBottomLeft(find.text('newest message')).dy,
      lessThan(indicatorTop),
      reason: 'the list must grow its bottom reserve by the indicator height',
    );
    expect(
      newestRowBottom(tester),
      lessThanOrEqualTo(indicatorTop),
      reason: 'the indicator painted over the newest row\'s footer',
    );

    repo.emitPartnerTyping('partner', false);
    await settle(tester);
    expect(
      newestRowBottom(tester),
      lessThanOrEqualTo(tester.getTopLeft(find.byType(ChatTextField)).dy),
    );
    await tearDownChat(tester, container);
  });

  testWidgets('a staged game bar never covers the newest message', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo);

    container
        .read(gameComposerProvider('rel-1').notifier)
        .stage('this_or_that');
    await settle(tester);

    expect(find.byType(GameComposerBar), findsOneWidget);
    expect(
      newestRowBottom(tester),
      lessThanOrEqualTo(tester.getTopLeft(find.byType(GameComposerBar)).dy),
      reason: 'the staged bar sits above the composer, inside the overlay',
    );

    container.read(gameComposerProvider('rel-1').notifier).cancel();
    await settle(tester);
    await tearDownChat(tester, container);
  });

  testWidgets('a multi-line draft never covers the newest message', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo);

    await tester.enterText(
      find.descendant(
        of: find.byType(ChatTextField),
        matching: find.byType(TextField),
      ),
      'one\ntwo\nthree\nfour',
    );
    await settle(tester);

    expect(
      newestRowBottom(tester),
      lessThanOrEqualTo(tester.getTopLeft(find.byType(ChatTextField)).dy),
    );

    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tearDownChat(tester, container);
  });

  testWidgets('the list pads by exactly the measured overlay plus a gap', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo);

    final overlay = tester.getSize(find.byType(MeasureSize)).height;
    expect(listBottomPadding(tester), overlay.ceilToDouble() + 12);

    await tearDownChat(tester, container);
  });

  testWidgets('with the keyboard up the reserve is not double-counted', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo);

    // A 320px keyboard. iOS reports the home-indicator padding as 0 while
    // it is up. The Scaffold resizes its body, so the overlay already rides
    // above the keyboard and the list must not add the inset again.
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    tester.view.padding = FakeViewPadding.zero;
    await tester.tap(find.byType(ChatTextField));
    await settle(tester);

    final overlayTop = tester.getTopLeft(find.byType(MeasureSize)).dy;
    expect(
      tester.getBottomLeft(find.byType(MeasureSize)).dy,
      1400 - 320,
      reason: 'the overlay sits directly on the keyboard',
    );
    final rowBottom = newestRowBottom(tester);
    expect(rowBottom, lessThanOrEqualTo(overlayTop));
    expect(
      overlayTop - rowBottom,
      lessThan(40),
      reason: 'the newest row stays close to the composer, not 320px off',
    );
    final overlay = tester.getSize(find.byType(MeasureSize)).height;
    expect(listBottomPadding(tester), overlay.ceilToDouble() + 12);

    FocusManager.instance.primaryFocus?.unfocus();
    tester.view.resetViewInsets();
    await settle(tester);
    await tearDownChat(tester, container);
  });

  testWidgets('one toggle re-measures the list at most twice', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo);

    // Counts measurements handed to the list, not padding frames: the
    // padding itself glides at the bottom (I1), the reports must not.
    Future<List<double?>> track(void Function() toggle) async {
      final seen = <double?>[measuredOverlay(tester)];
      toggle();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final measured = measuredOverlay(tester);
        if (measured != seen.last) seen.add(measured);
      }
      return seen;
    }

    final on = await track(() => repo.emitPartnerTyping('partner', true));
    expect(on.length - 1, inInclusiveRange(1, 2), reason: '$on');
    final off = await track(() => repo.emitPartnerTyping('partner', false));
    expect(off.length - 1, inInclusiveRange(1, 2), reason: '$off');
    expect(off.last, on.first, reason: 'back to the composer-only reserve');

    await tearDownChat(tester, container);
  });

  testWidgets('at the bottom the list glides to the new reserve', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo);

    final before = newestRowBottom(tester);
    final measuredBefore = measuredOverlay(tester);
    repo.emitPartnerTyping('partner', true);
    // Until the indicator's measurement reaches the list.
    for (var i = 0; i < 10 && measuredOverlay(tester) == measuredBefore; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(measuredOverlay(tester), isNot(measuredBefore));
    await tester.pump(const Duration(milliseconds: 16));
    final mid = newestRowBottom(tester);
    await settle(tester);
    final after = newestRowBottom(tester);

    expect(after, lessThan(before - 20), reason: 'the reserve grew');
    expect(mid, lessThan(before), reason: 'one frame in: already moving');
    expect(mid, greaterThan(after), reason: 'one frame in: not there yet');
    expect(
      after,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const ValueKey('typing_indicator'))).dy,
      ),
    );

    repo.emitPartnerTyping('partner', false);
    await settle(tester);
    expect(newestRowBottom(tester), closeTo(before, 0.5));
    await tearDownChat(tester, container);
  });

  testWidgets('a new measurement mid-glide retargets without a jump', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo);

    final measuredBefore = measuredOverlay(tester);
    repo.emitPartnerTyping('partner', true);
    for (var i = 0; i < 10 && measuredOverlay(tester) == measuredBefore; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    container
        .read(gameComposerProvider('rel-1').notifier)
        .stage('this_or_that');
    final paddings = <double>[listBottomPadding(tester)];
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      paddings.add(listBottomPadding(tester));
    }
    // easeOutCubic's steepest 16ms step is ~22% of the distance; a snap,
    // or a retarget from a stale start, is a much bigger single step.
    final distance = (paddings.last - paddings.first).abs();
    expect(distance, greaterThan(60));
    for (var i = 1; i < paddings.length; i++) {
      expect(
        (paddings[i] - paddings[i - 1]).abs(),
        lessThan(distance * 0.25),
        reason: 'no single-frame jump: $paddings',
      );
    }
    expect(
      paddings.last,
      tester.getSize(find.byType(MeasureSize)).height.ceilToDouble() + 12,
    );

    container.read(gameComposerProvider('rel-1').notifier).cancel();
    repo.emitPartnerTyping('partner', false);
    await settle(tester);
    await tearDownChat(tester, container);
  });

  testWidgets('a strip that leaves mid-glide reverses from where it is', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo);
    final restPadding = listBottomPadding(tester);

    final measuredBefore = measuredOverlay(tester);
    container
        .read(gameComposerProvider('rel-1').notifier)
        .stage('this_or_that');
    for (var i = 0; i < 10 && measuredOverlay(tester) == measuredBefore; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final atCancel = listBottomPadding(tester);
    final stagedReserve = measuredOverlay(tester)! + 12;
    expect(atCancel, greaterThan(restPadding), reason: 'mid-glide up');
    expect(atCancel, lessThan(stagedReserve - 20), reason: 'mid-glide up');

    container.read(gameComposerProvider('rel-1').notifier).cancel();
    final paddings = <double>[atCancel];
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      paddings.add(listBottomPadding(tester));
    }
    // The glide carries on up for the frames the removal takes to be
    // measured, then turns round. Retargeting from a stale start would
    // first leap to the bar's full reserve, then glide down.
    expect(
      paddings.reduce(math.max),
      lessThan(stagedReserve - 10),
      reason: 'leapt to the stale target: $paddings',
    );
    final turn = paddings.indexOf(paddings.reduce(math.max));
    for (var i = turn + 1; i < paddings.length; i++) {
      expect(
        paddings[i],
        lessThanOrEqualTo(paddings[i - 1] + 0.5),
        reason: 'once reversing, never moves away from the target: $paddings',
      );
    }
    expect(paddings.last, restPadding);
    await tearDownChat(tester, container);
  });

  testWidgets('with reduce motion the reserve lands in one frame', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedOne(repo);
    final container = await pumpChat(tester, repo, reduceMotion: true);

    final measuredBefore = measuredOverlay(tester);
    repo.emitPartnerTyping('partner', true);
    for (var i = 0; i < 10 && measuredOverlay(tester) == measuredBefore; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final measured = measuredOverlay(tester);
    expect(measured, isNot(measuredBefore));
    await tester.pump(const Duration(milliseconds: 16));
    expect(listBottomPadding(tester), measured! + 12);

    repo.emitPartnerTyping('partner', false);
    await settle(tester);
    await tearDownChat(tester, container);
  });

  testWidgets('scrolled up, a growing overlay does not move the messages', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final now = DateTime.now();
    for (var i = 0; i < 40; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'message number $i',
        createdAt: now.subtract(Duration(minutes: 40 - i)),
      );
    }
    final container = await pumpChat(tester, repo);

    await tester.drag(messageList, const Offset(0, 400));
    await settle(tester);
    final anchor = find.text('message number 30');
    expect(anchor, findsOneWidget);
    final before = tester.getTopLeft(anchor).dy;

    repo.emitPartnerTyping('partner', true);
    await settle(tester);
    expect(find.byKey(const ValueKey('typing_indicator')), findsOneWidget);
    expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));

    repo.emitPartnerTyping('partner', false);
    await settle(tester);
    expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
    await tearDownChat(tester, container);
  });
  testWidgets(
    'scrolled up, a typing toggle during animateTo(0) does not hop the list (I-2)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final now = DateTime.now();
      for (var i = 0; i < 60; i++) {
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'message number $i',
          createdAt: now.subtract(Duration(minutes: 60 - i)),
        );
      }
      final container = await pumpChat(tester, repo);
      final position =
          tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: messageList,
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
      position.jumpTo(1500);
      await settle(tester);

      Map<int, double> rowTops() => {
        for (var i = 0; i < 60; i++)
          if (find.text('message number $i').evaluate().isNotEmpty)
            i: tester.getTopLeft(find.text('message number $i')).dy,
      };

      position.animateTo(
        0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOut,
      );
      // Per-frame content motion: the median move of the rows seen in two
      // consecutive frames (as in chat_screen_list_anchor_test).
      final motion = <double>[];
      var previous = rowTops();
      for (var f = 0; f < 60; f++) {
        if (f == 6) repo.emitPartnerTyping('partner', true);
        await tester.pump(const Duration(milliseconds: 16));
        final current = rowTops();
        final deltas = [
          for (final i in current.keys)
            if (previous.containsKey(i)) current[i]! - previous[i]!,
        ]..sort();
        if (deltas.isNotEmpty) motion.add(deltas[deltas.length ~/ 2]);
        previous = current;
      }
      expect(find.byKey(const ValueKey('typing_indicator')), findsOneWidget);
      final endPixels = position.pixels;
      repo.emitPartnerTyping('partner', false);
      await settle(tester);
      await tearDownChat(tester, container);

      final active = [
        for (final m in motion)
          if (m.abs() > 0.5) m,
      ];
      expect(active.length, greaterThan(5), reason: '$motion');
      // Toward the newest end the content only moves up the screen.
      expect(active.every((m) => m < 0), isTrue, reason: '$motion');
      // No hop: wherever both neighbours move (>= 10 px), a frame stays
      // within 15 % of them.
      for (var i = 1; i < active.length - 1; i++) {
        final here = active[i].abs();
        final lo = math.min(active[i - 1].abs(), active[i + 1].abs());
        final hi = math.max(active[i - 1].abs(), active[i + 1].abs());
        if (lo < 10) continue;
        expect(
          here,
          greaterThanOrEqualTo(0.85 * lo),
          reason: 'frame $i stalls: $active',
        );
        expect(
          here,
          lessThanOrEqualTo(1.15 * hi),
          reason: 'frame $i hops: $active',
        );
      }
      expect(endPixels, 0);
    },
  );
}
