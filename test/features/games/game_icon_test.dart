import 'dart:io';

import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a drawn game resolves to an asset that exists', () {
    // The resolver names a file; if the file is missing the card shows a
    // broken image rather than falling back, which is worse than having
    // no art at all.
    final asset = gameIconAsset('this_or_that');

    expect(asset, isNotNull);
    expect(
      File(asset!).existsSync(),
      isTrue,
      reason: '$asset is referenced but not on disk',
    );
  });

  test('an undrawn game returns null so the glyph fallback runs', () {
    // The set is filled in one game at a time. A game without art must
    // return null rather than a path to a file that does not exist.
    for (final gameType in [
      'truth_or_dare',
      '36_questions',
      'mirror',
      'sliding_scale',
      'scenario',
      'love_map',
      'paint_ball',
    ]) {
      expect(
        gameIconAsset(gameType),
        isNull,
        reason: '$gameType has no art yet and must fall back',
      );
    }
  });

  test('every declared asset is registered with the bundle', () {
    // An SVG on disk that pubspec does not list loads as a blank at
    // runtime, with no analyzer or test failure to catch it.
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      pubspec.contains('assets/images/game_icons/'),
      isTrue,
      reason:
          'Flutter asset directories are shallow, so the nested folder '
          'needs its own pubspec entry',
    );
  });
}
