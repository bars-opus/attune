import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:attune/features/chat/presentation/widgets/streak_bubble.dart';
import 'package:attune/features/chat/presentation/widgets/streak_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('unwatched: a play button and "Play"', (tester) async {
    await tester.pumpWidget(_wrap(StreakBubble(
      viewsRemaining: 1,
      hasBeenPlayed: false,
      onTap: () {},
    )));

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('after the first play it reads "Tap to play"', (tester) async {
    await tester.pumpWidget(_wrap(StreakBubble(
      viewsRemaining: 2,
      hasBeenPlayed: true,
      onTap: () {},
    )));

    expect(find.text('Tap to play'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
  });

  testWidgets('a replay budget shows how many are left', (tester) async {
    await tester.pumpWidget(_wrap(StreakBubble(
      viewsRemaining: 3,
      hasBeenPlayed: true,
      onTap: () {},
    )));
    expect(find.textContaining('3'), findsOneWidget);
  });

  testWidgets('a spent streak is not tappable and says so', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(StreakBubble(
      viewsRemaining: 0,
      hasBeenPlayed: true,
      onTap: () => tapped = true,
    )));

    expect(find.text('Streak expired'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    expect(tapped, isFalse, reason: 'a spent streak must not reopen');
  });

  testWidgets('tapping an available streak fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(StreakBubble(
      viewsRemaining: 1,
      hasBeenPlayed: false,
      onTap: () => tapped = true,
    )));

    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('no thumbnail or caption is ever rendered', (tester) async {
    // The row must reveal nothing about the content before it is opened.
    await tester.pumpWidget(_wrap(StreakBubble(
      viewsRemaining: 1,
      hasBeenPlayed: false,
      onTap: () {},
    )));

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('the review sheet offers only send and cancel — no caption',
      (tester) async {
    var sent = false;
    var cancelled = false;

    await tester.pumpWidget(_wrap(StreakReviewSheet(
      segments: const [
        StreakSegment(path: '/tmp/a.mp4', duration: Duration(seconds: 60)),
      ],
      onSend: () => sent = true,
      onDiscard: () => cancelled = true,
    )));

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

    await tester.pumpWidget(_wrap(StreakReviewSheet(
      segments: const [
        StreakSegment(path: '/tmp/a.mp4', duration: Duration(seconds: 30)),
      ],
      onSend: () => sent = true,
      onDiscard: () => cancelled = true,
    )));

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancelled, isTrue);
    expect(sent, isFalse);
  });
}
