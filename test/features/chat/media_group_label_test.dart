import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The media group carries ONE chip: the "1 / 5" counter.
///
/// A separate "5 images" label used to sit alongside it, but the counter
/// already says how many there are -- two chips at the top of the same
/// stack were saying the same thing twice.
///
/// The description survives for screen readers, where it is not
/// redundant: someone who cannot see the photos cannot scan them.
void main() {
  final source =
      File(
        'lib/features/chat/presentation/widgets/chat_media_group.dart',
      ).readAsStringSync();

  test('the album label chip is gone', () {
    expect(
      source.contains('_AlbumLabel'),
      isFalse,
      reason: 'the counter already conveys the count',
    );
  });

  test('the count is still described to screen readers', () {
    // _mediaLabel is what makes the announcement say "5 images" rather
    // than reading out a bare number, so removing the visual chip must
    // not take it with it.
    expect(source.contains('_mediaLabel('), isTrue);

    final semantics = source.substring(
      source.indexOf('return Semantics('),
      source.indexOf('child: SizedBox('),
    );
    expect(
      semantics.contains(r'$label'),
      isTrue,
      reason: 'a blind user cannot scan the stack; the label is their count',
    );
  });

  test('the remaining chips keep one fill and stay circular', () {
    // The counter and a video's duration draw on the same photos. Their
    // shared fill is what makes them read as one system.
    for (final widget in ['_CountBadge', '_DurationBadge']) {
      final start = source.indexOf('class $widget');
      expect(start, greaterThan(-1), reason: '$widget is missing');

      final next = source.indexOf('\nclass ', start + 1);
      final body =
          next == -1 ? source.substring(start) : source.substring(start, next);

      expect(
        body.contains('Colors.black.withValues(alpha: 0.62)'),
        isTrue,
        reason: '$widget drifted from the shared chip fill',
      );
      expect(
        body.contains('BorderRadius.circular(999)'),
        isTrue,
        reason: '$widget must stay circular',
      );
    }
  });
}
