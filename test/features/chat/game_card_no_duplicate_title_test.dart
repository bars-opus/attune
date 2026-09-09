import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A game message carries the game's display name in `content` -- the
/// database trigger writes it there so the card has a title before the
/// session stream delivers its first row.
///
/// The bubble's generic text block runs after every media branch, so
/// without a guard it printed that name a SECOND time underneath the
/// card, which already shows it as the row's title. The same was true of
/// a trail, whose GameTrailLine draws `content` beside its icon.
///
/// Asserted against the source rather than by rendering: reproducing it
/// needs a live session stream, and what can actually regress is someone
/// simplifying the `hasText` condition back to a bare isNotEmpty.
void main() {
  test('the text block excludes game cards and trails', () {
    final source =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    final start = source.indexOf('final hasText =');
    expect(start, isNonNegative, reason: 'hasText was renamed');
    final condition = source.substring(start, source.indexOf(';', start));

    expect(
      condition.contains('!message.isGame'),
      isTrue,
      reason: 'a game card would print its own title twice',
    );
    expect(
      condition.contains('!message.isGameTrail'),
      isTrue,
      reason: 'a trail would print its own label twice',
    );
  });
}
