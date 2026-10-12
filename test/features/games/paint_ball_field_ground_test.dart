import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_ground.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the far row’s words', () {
    test('a known partner is named rather than called an opponent', () {
      // "THEIR COVER" turns the person you are playing into an
      // opponent. This app is about that specific person, so the board
      // says who.
      expect(
        fieldRowLabelText(
          partnerName: 'Ama',
          isReplaying: false,
          theirStreak: 1,
        ),
        'AMA',
      );
    });

    test('an unknown partner falls back rather than showing a gap', () {
      // The name loads asynchronously. Until it arrives the board must
      // still read as a board.
      expect(
        fieldRowLabelText(
          partnerName: null,
          isReplaying: false,
          theirStreak: 1,
        ),
        'THEIR COVER',
      );
    });

    test('a streak is called out, but only while the replay is on screen', () {
      expect(
        fieldRowLabelText(
          partnerName: 'Ama',
          isReplaying: true,
          theirStreak: 3,
        ),
        'SAME SPOT x3',
      );
    });

    test('a streak is not kept on the board between rounds', () {
      // It is a remark on what you just watched, not a readout. Left
      // up, it would be the same free clue as a paint trail.
      expect(
        fieldRowLabelText(
          partnerName: 'Ama',
          isReplaying: false,
          theirStreak: 3,
        ),
        'AMA',
      );
    });

    test('a streak of one or zero is never announced', () {
      // Review Focus #4. The label shows only from two upward: every
      // round is trivially a streak of one, and "SAME SPOT x1" would
      // call out holding a position the player only just took.
      for (final streak in [0, 1]) {
        expect(
          fieldRowLabelText(
            partnerName: 'Ama',
            isReplaying: true,
            theirStreak: streak,
          ),
          'AMA',
          reason: 'a streak of $streak is not a streak',
        );
      }
    });
  });

  testWidgets('the ground paints itself and carries its key', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FieldGround(child: Text('on the field'))),
      ),
    );
    await tester.pump();

    expect(find.byKey(PaintBallFieldKeys.ground), findsOneWidget);
    expect(find.text('on the field'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the divider is drawn and keyed', (tester) async {
    // The centre line is what makes the field two halves facing each
    // other rather than one strip of six covers.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FieldGround(child: SizedBox())),
      ),
    );
    await tester.pump();

    expect(find.byKey(PaintBallFieldKeys.divider), findsOneWidget);
  });
}
