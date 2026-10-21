import 'dart:math' as math;

import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// RC-13 (jump half): a reverse ListView matched rows by INDEX, so a new
/// message at index 0 handed every row the next message's content while
/// keeping that index's layout offset — the text under the reader's finger
/// hopped by one bubble per arrival (measured before the fix: 59 px, one
/// text bubble, at 800x1400).
///
/// Keying the rows (findChildIndexCallback) alone did NOT hold it (still
/// 59 px). In Flutter 3.29.1, when index 0 is not built, the vacated first
/// built index is re-inflated with its OLD (non-null) layout offset, so
/// everything from there shifts by the newly built row's height, not the
/// arrival's. The list's ChatListScrollController cancels that shift in the
/// same layout pass, so no frame paints the list moved; the leftover
/// origin drift (that row's height minus the arrival's) is repaired by
/// Flutter's own correctBy once index 0 is near, and a running animateTo
/// is carried across that repair (the "returning to the newest end"
/// tests below).
void main() {
  ScrollPosition listPosition(WidgetTester tester) =>
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;

  /// Scrolls into history and returns a message fully on screen.
  Future<String> scrollUpToAnchor(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 49; i >= 0; i--) {
      final f = find.text('message $i');
      if (f.evaluate().isEmpty) continue;
      final rect = tester.getRect(f);
      if (rect.top > 200 && rect.bottom < 1000) return 'message $i';
    }
    fail('test needs a fully visible row');
  }

  /// Pumps ~1 s frame by frame; the largest drift of [text] from [before].
  Future<double> maxDriftOver(
    WidgetTester tester,
    String text,
    Offset before,
  ) async {
    var worst = 0.0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final dy = tester.getTopLeft(find.text(text)).dy;
      if ((dy - before.dy).abs() > worst) worst = (dy - before.dy).abs();
    }
    return worst;
  }

  void seedHistory(FakeChatRepository repo) {
    final base = DateTime.now().subtract(const Duration(hours: 1));
    for (var i = 0; i < 50; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: i.isEven ? 'partner' : 'user-a',
        content: 'message $i',
        createdAt: base.add(Duration(minutes: i)),
      );
    }
  }

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
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

  testWidgets('an arrival while scrolled up does not move visible rows', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now().subtract(const Duration(hours: 1));
    for (var i = 0; i < 50; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: i.isEven ? 'partner' : 'user-a',
        content: 'message $i',
        createdAt: base.add(Duration(minutes: i)),
      );
    }
    final container = await pumpChat(tester, repo);

    // Scroll toward older history (reverse list: drag down).
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Pick a row that is fully on screen now.
    String? anchor;
    for (var i = 49; i >= 0; i--) {
      final f = find.text('message $i');
      if (f.evaluate().isEmpty) continue;
      final rect = tester.getRect(f);
      if (rect.top > 200 && rect.bottom < 1000) {
        anchor = 'message $i';
        break;
      }
    }
    expect(anchor, isNotNull, reason: 'test needs a fully visible row');
    final before = tester.getTopLeft(find.text(anchor!));

    repo.seedIncoming(
      id: 'm-new',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'just arrived',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final after = tester.getTopLeft(find.text(anchor));
    expect(
      (after.dy - before.dy).abs(),
      lessThan(1),
      reason: 'the viewport must stay anchored on the row being read',
    );
    await tearDownChat(tester, container);
  });

  testWidgets('no frame paints the list moved, with several arrivals', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo);
    final container = await pumpChat(tester, repo);
    final anchor = await scrollUpToAnchor(tester);
    final before = tester.getTopLeft(find.text(anchor));
    final pixelsBefore = listPosition(tester).pixels;

    for (var i = 1; i <= 3; i++) {
      repo.seedIncoming(
        id: 'm-new-$i',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'arrival $i\nwith\nseveral\nlines',
        createdAt: DateTime.now(),
      );
    }
    repo.emitRealtime();

    expect(await maxDriftOver(tester, anchor, before), lessThan(1));
    // The list really did grow under the reader: the hold is an offset
    // correction, not a frozen list.
    expect(listPosition(tester).pixels, greaterThan(pixelsBefore + 100));
    await tearDownChat(tester, container);
  });

  testWidgets('an arrival and a padding change in the same frame compose', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo);
    final container = await pumpChat(tester, repo);
    repo.emitPartnerTyping('partner', true);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('typing_indicator')), findsOneWidget);

    final anchor = await scrollUpToAnchor(tester);
    final before = tester.getTopLeft(find.text(anchor));

    // The reply lands as the indicator goes away: the list gains a row and
    // loses the indicator's reserve together.
    repo.seedIncoming(
      id: 'm-new',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'just arrived',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    repo.emitPartnerTyping('partner', false);

    expect(await maxDriftOver(tester, anchor, before), lessThan(1));
    expect(find.byKey(const ValueKey('typing_indicator')), findsNothing);
    await tearDownChat(tester, container);
  });

  testWidgets('the ordering snap while scrolled up does not move the row '
      'being read', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo);
    final container = await pumpChat(tester, repo);
    final convo = activeConversation('rel-1');

    // My clock runs 5 min ahead of the server.
    repo.sendCreatedAtOffset = const Duration(minutes: -5);
    await tester.runAsync(
      () => container
          .read(chatControllerProvider(convo).notifier)
          .sendMessage('mine'),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    List<String> newest() =>
        container
            .read(chatControllerProvider(convo))
            .messages
            .take(2)
            .map((m) => m.content)
            .toList();
    expect(newest().first, 'mine');

    final anchor = await scrollUpToAnchor(tester);
    final before = tester.getTopLeft(find.text(anchor));

    // Sent after mine on the server, before my device's `now`.
    repo.seedIncoming(
      id: 'reply',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'reply',
      createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
    );
    repo.emitRealtime();

    final drift = await maxDriftOver(tester, anchor, before);
    final order = newest();
    await tearDownChat(tester, container);
    expect(drift, lessThan(1));
    expect(order, ['reply', 'mine'], reason: 'server order won');
  });

  testWidgets('a row keeps its sliver child across an arrival (matched by '
      'message, not by index)', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo);
    final container = await pumpChat(tester, repo);
    final anchor = await scrollUpToAnchor(tester);
    RenderObject slot() {
      RenderObject? node = tester.renderObject(find.text(anchor));
      while (node!.parent is! RenderSliverMultiBoxAdaptor) {
        node = node.parent;
      }
      return node;
    }

    final before = slot();
    repo.seedIncoming(
      id: 'm-new',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'just arrived',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final kept = identical(before, slot());
    await tearDownChat(tester, container);
    // By index, the slot that held this row is handed the next message
    // and the row is rebuilt into its neighbour's slot.
    expect(kept, isTrue);
  });

  testWidgets('scrolled up only a little, the arrival does not grow in under '
      'the reader', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo);
    final container = await pumpChat(tester, repo);
    // ~130 px up: the new row lands just below the viewport, inside the
    // list's cache extent, where a grow-in animation is laid out every
    // frame and would lift the visible rows after the hold.
    await tester.drag(find.byType(ListView), const Offset(0, 150));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(listPosition(tester).pixels, inInclusiveRange(60, 250));
    String? anchor;
    for (var i = 49; i >= 0; i--) {
      final f = find.text('message $i');
      if (f.evaluate().isEmpty) continue;
      final rect = tester.getRect(f);
      if (rect.top > 200 && rect.bottom < 1000) {
        anchor = 'message $i';
        break;
      }
    }
    final before = tester.getTopLeft(find.text(anchor!));

    repo.seedIncoming(
      id: 'm-new',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'just arrived',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();

    final drift = await maxDriftOver(tester, anchor, before);
    await tearDownChat(tester, container);
    expect(drift, lessThan(1));
  });

  testWidgets('an arrival first built as the reader scrolls back does not '
      'grow in under them', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo);
    final container = await pumpChat(tester, repo);
    await scrollUpToAnchor(tester);
    // Far enough up that the arrival is not built when it lands.
    repo.seedIncoming(
      id: 'm-new',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'just arrived',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('just arrived'), findsNothing);

    // Back to ~130 px from the newest end: the row is now built, just
    // below the viewport, inside the cache extent.
    final position = listPosition(tester);
    position.jumpTo(130);
    await tester.pump();
    String? anchor;
    for (var i = 49; i >= 0; i--) {
      final f = find.text('message $i');
      if (f.evaluate().isEmpty) continue;
      final rect = tester.getRect(f);
      if (rect.top > 200 && rect.bottom < 1000) {
        anchor = 'message $i';
        break;
      }
    }
    final before = tester.getTopLeft(find.text(anchor!));
    final drift = await maxDriftOver(tester, anchor, before);
    await tearDownChat(tester, container);
    expect(drift, lessThan(1));
  });

  testWidgets('at the bottom a new arrival still scrolls into view', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedHistory(repo);
    final container = await pumpChat(tester, repo);
    expect(listPosition(tester).pixels, 0);
    final newestBefore = tester.getTopLeft(find.text('message 49'));

    repo.seedIncoming(
      id: 'm-new',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'just arrived',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(listPosition(tester).pixels, 0);
    expect(find.text('just arrived'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('message 49')).dy,
      lessThan(newestBefore.dy - 20),
      reason: 'the older rows make room for the new one',
    );
    await tearDownChat(tester, container);
  });

  group('returning to the newest end after a hold is smooth', () {
    // Non-uniform heights make the origin drift D = height(row just past
    // the cache band) - height(arrival) non-zero, and Flutter repairs it
    // mid-animation (through correctBy, or silently once the cache-adjusted
    // scroll offset is 0). Its repair moves the content by more than the
    // offset, so without the per-layout pin that frame stalls (D > 0) or
    // jumps (D < 0); and an animateTo that does not follow a correction
    // writes the old offset back on its next tick. Own group ends carry a
    // delivery tick (Task 11), which makes those rows taller still.
    //
    // The bounds below (the 15 % neighbour band, jerk <= 25) are tuned to
    // these fixtures' row heights. When row heights change (fonts, footers)
    // re-tune them against a known-good build; never widen them to pass.
    String historyText(int i, int lines) =>
        ['message $i', for (var l = 2; l <= lines; l++) 'line $l'].join('\n');

    for (final (name, historyLines, arrivalLines) in [
      ('D > 0: one-line arrival into five-line history', 5, 1),
      ('D < 0: tall arrival into one-line history', 1, 8),
    ]) {
      for (final (senders, senderOf) in <(String, String Function(int))>[
        ('alternating senders', (i) => i.isEven ? 'partner' : 'user-a'),
        // Only the newest of each own run is a group end with a tick.
        ('own runs of three', (i) => (i ~/ 3).isEven ? 'user-a' : 'partner'),
      ]) {
        for (final viaSend in [true, false]) {
          testWidgets(
            '$name, $senders, '
            '${viaSend ? 'send (_scrollToLatest)' : 'pill-style animateTo(0)'}',
            (tester) async {
              final repo = FakeChatRepository(currentUserId: 'user-a');
              final base = DateTime.now().subtract(const Duration(hours: 1));
              for (var i = 0; i < 50; i++) {
                repo.seedIncoming(
                  id: 'm$i',
                  relationshipId: 'rel-1',
                  senderId: senderOf(i),
                  content: historyText(i, historyLines),
                  createdAt: base.add(Duration(minutes: i)),
                );
              }
              final container = await pumpChat(tester, repo);
              final position = listPosition(tester);
              position.jumpTo(1180);
              for (var i = 0; i < 6; i++) {
                await tester.pump(const Duration(milliseconds: 50));
              }

              repo.seedIncoming(
                id: 'm-new',
                relationshipId: 'rel-1',
                senderId: 'partner',
                content: [
                  'arrival',
                  for (var l = 2; l <= arrivalLines; l++) 'arrival line $l',
                ].join('\n'),
                createdAt: DateTime.now(),
              );
              repo.emitRealtime();
              for (var i = 0; i < 20; i++) {
                await tester.pump(const Duration(milliseconds: 50));
              }
              expect(position.pixels, greaterThan(1000));

              Map<int, double> rowTops() => {
                for (var i = 0; i < 50; i++)
                  if (find
                      .text(historyText(i, historyLines))
                      .evaluate()
                      .isNotEmpty)
                    i:
                        tester
                            .getTopLeft(find.text(historyText(i, historyLines)))
                            .dy,
              };

              if (viaSend) {
                await tester.enterText(find.byType(TextField), 'hi');
                await tester.pump();
                await tester.tap(find.byIcon(Icons.send_rounded));
              } else {
                position.animateTo(
                  0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              }

              // Per-frame content motion: the median move of the rows seen in
              // two consecutive frames.
              final motion = <double>[];
              var previous = rowTops();
              for (var f = 0; f < 30; f++) {
                await tester.pump(const Duration(milliseconds: 16));
                final now = rowTops();
                final deltas = [
                  for (final i in now.keys)
                    if (previous.containsKey(i)) now[i]! - previous[i]!,
                ]..sort();
                if (deltas.isNotEmpty) motion.add(deltas[deltas.length ~/ 2]);
                previous = now;
              }
              final endPixels = position.pixels;
              await tearDownChat(tester, container);

              final active = [
                for (final m in motion)
                  if (m.abs() > 0.5) m,
              ];
              expect(active.length, greaterThan(5), reason: '$motion');
              // Toward the newest end the content only moves up the screen.
              expect(active.every((m) => m < 0), isTrue, reason: '$motion');
              // No stall frame and no jump frame at all: wherever both
              // neighbours move (≥ 10 px; the last frames of an ease-out are
              // quantised), a frame stays within 15 % of them.
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
                  reason: 'frame $i jumps: $active',
                );
              }
              // And the speed changes gradually: a correction is blended into
              // the rest of the path, not taken as a step. A step shows as a
              // kink — a sudden change in per-frame acceleration (jerk); an
              // ease-out alone stays near 10, a step reaches ~30.
              for (var i = 2; i < active.length; i++) {
                final a = active[i - 2].abs();
                final b = active[i - 1].abs();
                final c = active[i].abs();
                if (math.min(a, math.min(b, c)) < 10) continue;
                expect(
                  ((c - b) - (b - a)).abs(),
                  lessThanOrEqualTo(25),
                  reason: 'speed kinks at frame $i: $active',
                );
              }
              expect(endPixels, 0);
            },
          );
        }
      }
    }
  });
}
