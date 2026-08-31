import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing sits between the wallpaper and the bottom of the screen', () {
    // The wallpaper was in an Expanded followed by Gap(Spacing.md), so a
    // strip of the scaffold's own background (colorScheme.neutral — light
    // in light mode) showed beneath it, under the floating composer.
    //
    // The composer is Positioned over this column and carries its own
    // SafeArea, so the gap was reserving space nothing needed.
    final src =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();

    final columnTail = src.substring(
      src.indexOf('child: AttuneChatWallpaper('),
      src.indexOf('Positioned(', src.indexOf('child: AttuneChatWallpaper(')),
    );

    expect(
      columnTail,
      isNot(contains('Gap(Spacing.md)')),
      reason:
          'a gap below the wallpaper exposes the scaffold background as a '
          'band above the composer',
    );
  });
}
