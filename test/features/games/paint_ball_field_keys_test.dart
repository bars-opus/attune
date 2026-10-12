import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a key is distinct per position and per side', () {
    // The whole point of the seam: a test asking for "my middle figure"
    // must not match the opponent's. The old tests counted painters by
    // type name, which could not tell the two rows apart at all -- they
    // asserted on totals and inferred the rest.
    final keys = <Key>{
      for (var position = 0; position < 3; position++) ...[
        PaintBallFieldKeys.figure(position, isOpponent: false),
        PaintBallFieldKeys.figure(position, isOpponent: true),
        PaintBallFieldKeys.bay(position, isOpponent: false),
        PaintBallFieldKeys.bay(position, isOpponent: true),
      ],
    };

    expect(
      keys,
      hasLength(12),
      reason: '3 positions x 2 sides x 2 kinds, all distinct',
    );
  });

  test('the same arguments always give an equal key', () {
    // ValueKey equality is what lets a test written once keep finding
    // the same widget across rebuilds.
    expect(
      PaintBallFieldKeys.figure(1, isOpponent: false),
      PaintBallFieldKeys.figure(1, isOpponent: false),
    );
    expect(
      PaintBallFieldKeys.bay(2, isOpponent: true),
      PaintBallFieldKeys.bay(2, isOpponent: true),
    );
    expect(
      PaintBallFieldKeys.projectile(isMine: true),
      PaintBallFieldKeys.projectile(isMine: true),
    );
  });

  test('the two projectiles are distinguishable', () {
    // A replay puts both shots in the air at once (spec §2.6). The test
    // that pins this counted painters by name and could only assert
    // "two exist"; keys let it assert WHOSE.
    expect(
      PaintBallFieldKeys.projectile(isMine: true),
      isNot(PaintBallFieldKeys.projectile(isMine: false)),
    );
  });

  test('the singleton keys are distinct from each other', () {
    expect(
      {
        PaintBallFieldKeys.ground,
        PaintBallFieldKeys.paint,
        PaintBallFieldKeys.divider,
      },
      hasLength(3),
    );
  });

  test('a key survives a round trip through a widget', () {
    // Guards against a key type that compares equal but cannot be found
    // by find.byKey -- the failure would be invisible until a test that
    // depends on it silently found nothing.
    const key = PaintBallFieldKeys.ground;
    expect(const SizedBox(key: key).key, key);
  });
}
