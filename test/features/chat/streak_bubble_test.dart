import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:attune/features/chat/presentation/widgets/streak_bubble.dart';
import 'package:attune/features/chat/presentation/widgets/streak_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('a spent streak reads "Opened" for BOTH parties', (tester) async {
    // The sender saw "Opened" with a check while the recipient saw
    // "Streak expired" with a videocam-off icon — two different words for
    // the same event, and "expired" wrongly suggests time ran out rather
    // than that it was watched.
    for (final isMine in [true, false]) {
      await tester.pumpWidget(
        _wrap(
          StreakBubble(
            key: ValueKey(isMine),
            viewsRemaining: 0,
            hasBeenPlayed: true,
            isMine: isMine,
            openedByRecipient: true,
            onTap: () {},
          ),
        ),
      );

      expect(
        find.text('Opened'),
        findsOneWidget,
        reason: 'isMine=$isMine should read "Opened"',
      );
      expect(find.text('Streak expired'), findsNothing);
      expect(
        find.byIcon(Icons.check_box_outline_blank_rounded),
        findsOneWidget,
        reason:
            'a rounded outline container, not a check or a struck-out camera',
      );
    }
  });

  testWidgets('a spent streak is not tappable by either party', (tester) async {
    for (final isMine in [true, false]) {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          StreakBubble(
            key: ValueKey('tap-$isMine'),
            viewsRemaining: 0,
            hasBeenPlayed: true,
            isMine: isMine,
            openedByRecipient: true,
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.text('Opened'));
      await tester.pump();
      expect(tapped, isFalse, reason: 'isMine=$isMine must not reopen it');
    }
  });

  testWidgets('a single-view streak just says "Play"', (tester) async {
    await tester.pumpWidget(
      _wrap(
        StreakBubble(viewsRemaining: 1, hasBeenPlayed: false, onTap: () {}),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(
      find.textContaining('x'),
      findsNothing,
      reason: 'one view is the default — a count would be noise',
    );
  });

  testWidgets('a replay budget counts down in the label itself', (
    tester,
  ) async {
    // "Play 3x" then "Play 2x" then "Play": the remaining count belongs in
    // the label, not a separate chip beside it, so one glance answers both
    // "can I play this" and "how many times".
    for (final entry in {3: 'Play 3x', 2: 'Play 2x', 1: 'Play'}.entries) {
      await tester.pumpWidget(
        _wrap(
          StreakBubble(
            key: ValueKey(entry.key),
            viewsRemaining: entry.key,
            hasBeenPlayed: false,
            onTap: () {},
          ),
        ),
      );
      expect(
        find.text(entry.value),
        findsOneWidget,
        reason: '${entry.key} views remaining should read "${entry.value}"',
      );
    }
  });

  testWidgets('the countdown survives having been played', (tester) async {
    // hasBeenPlayed only says the recipient has opened it once; the budget
    // is what decides whether it can be opened again.
    await tester.pumpWidget(
      _wrap(StreakBubble(viewsRemaining: 2, hasBeenPlayed: true, onTap: () {})),
    );
    expect(find.text('Play 2x'), findsOneWidget);
  });

  testWidgets('a spent streak is not tappable and says so', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        StreakBubble(
          viewsRemaining: 0,
          hasBeenPlayed: true,
          onTap: () => tapped = true,
        ),
      ),
    );

    // Both parties now read "Opened" rather than the recipient seeing
    // "Streak expired", which described time running out.
    expect(find.text('Opened'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    expect(tapped, isFalse, reason: 'a spent streak must not reopen');
  });

  testWidgets('tapping an available streak fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        StreakBubble(
          viewsRemaining: 1,
          hasBeenPlayed: false,
          onTap: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('no thumbnail or caption is ever rendered', (tester) async {
    // The row must reveal nothing about the content before it is opened.
    await tester.pumpWidget(
      _wrap(
        StreakBubble(viewsRemaining: 1, hasBeenPlayed: false, onTap: () {}),
      ),
    );

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the review sheet offers only send and cancel — no caption', (
    tester,
  ) async {
    var sent = false;
    var cancelled = false;

    await tester.pumpWidget(
      _wrap(
        StreakReviewSheet(
          segments: const [
            StreakSegment(path: '/tmp/a.mp4', duration: Duration(seconds: 60)),
          ],
          onSend: () => sent = true,
          onDiscard: () => cancelled = true,
        ),
      ),
    );

    // No caption field and no replay toggle: replays are a persistent
    // chat setting, and the capture flow stays record -> send or cancel.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(sent, isTrue);
    expect(cancelled, isFalse);
  });

  testWidgets('cancel discards without sending', (tester) async {
    var sent = false;
    var cancelled = false;

    await tester.pumpWidget(
      _wrap(
        StreakReviewSheet(
          segments: const [
            StreakSegment(path: '/tmp/a.mp4', duration: Duration(seconds: 30)),
          ],
          onSend: () => sent = true,
          onDiscard: () => cancelled = true,
        ),
      ),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancelled, isTrue);
    expect(sent, isFalse);
  });

  testWidgets('the sender can replay until it is opened', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        StreakBubble(
          // Zero, deliberately: the budget belongs to the RECIPIENT, so it
          // must not gate the sender. With viewsRemaining: 1 this test passes
          // even when the sender is wrongly subject to that budget.
          viewsRemaining: 0,
          hasBeenPlayed: false,
          isMine: true,
          openedByRecipient: false,
          onTap: () => tapped = true,
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('once opened, the sender sees "Opened" and cannot replay', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        StreakBubble(
          viewsRemaining: 1,
          hasBeenPlayed: false,
          isMine: true,
          openedByRecipient: true,
          onTap: () => tapped = true,
        ),
      ),
    );

    // Doubles as the sender's read receipt.
    expect(find.text('Opened'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    expect(tapped, isFalse);
  });

  testWidgets('the recipient is unaffected by openedByRecipient', (
    tester,
  ) async {
    // Their own budget governs them, not the flag that locks the sender.
    await tester.pumpWidget(
      _wrap(
        StreakBubble(
          viewsRemaining: 2,
          hasBeenPlayed: true,
          isMine: false,
          openedByRecipient: true,
          onTap: () {},
        ),
      ),
    );

    // The count now lives in the label rather than a separate "N left"
    // chip beside it.
    expect(find.text('Play 2x'), findsOneWidget);
    expect(find.text('2 left'), findsNothing);
  });

  testWidgets('an in-flight streak says Sending, not Play', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        StreakBubble(
          viewsRemaining: 1,
          hasBeenPlayed: false,
          isMine: true,
          isSending: true,
          onTap: () => tapped = true,
        ),
      ),
    );

    expect(find.text('Sending…'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    expect(
      tapped,
      isFalse,
      reason: 'there is nothing to play until the upload lands',
    );
  });

  testWidgets('once sent it becomes playable', (tester) async {
    await tester.pumpWidget(
      _wrap(
        StreakBubble(
          viewsRemaining: 1,
          hasBeenPlayed: false,
          isMine: true,
          onTap: () {},
        ),
      ),
    );

    expect(find.text('Sending…'), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
