import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The album label ("5 images") rides ON the photo stack, opposite the
/// count badge, sharing its surface.
///
/// It used to sit above the carousel on the wallpaper, where it could not
/// carry the bubble's colour at all: a media group draws a TRANSPARENT
/// bubble so the images show through, and the sender's pale mint measures
/// 1.04:1 against the light wallpaper -- the same colour as the
/// background, not a faint version of it. Over the images it has a
/// surface of its own and reads at a glance.
void main() {
  final source =
      File(
        'lib/features/chat/presentation/widgets/chat_media_group.dart',
      ).readAsStringSync();

  test('the label and the count share one treatment', () {
    // They are a matched pair at the top of the same stack. Two different
    // treatments there would read as two unrelated things stuck on the
    // photos, which is what a bespoke label surface would produce.
    final labelSurface = source.substring(
      source.indexOf('class _AlbumLabel'),
      source.indexOf('class _CountBadge'),
    );
    final badgeSurface = source.substring(source.indexOf('class _CountBadge'));

    // Surface only. The RADIUS is deliberately not shared: the counter
    // is a short symmetric "1 / 5" that reads as a round chip, while the
    // album label's text is long enough that a pill's semicircular ends
    // look like a tag stuck on the photo.
    for (final property in [
      'Colors.black.withValues(alpha: 0.62)',
    ]) {
      expect(
        labelSurface.contains(property),
        isTrue,
        reason: 'the label must share the count badge surface: $property',
      );
      expect(badgeSurface.contains(property), isTrue);
    }
  });

  test('the label sits opposite the count, not on top of it', () {
    // Both are pinned to top: 12. If they took the same side they would
    // overlap, and the album name would be hidden behind the counter.
    final labelPosition = source.substring(
      source.indexOf('child: _AlbumLabel') - 400,
      source.indexOf('child: _AlbumLabel'),
    );
    final badgePosition = source.substring(
      source.indexOf('child: _CountBadge') - 900,
      source.indexOf('child: _CountBadge'),
    );

    expect(
      labelPosition.contains('start: widget.isMine ? null : 12'),
      isTrue,
      reason: 'the label takes the side the badge does not',
    );
    expect(
      badgePosition.contains('end: widget.isMine ? null : 12'),
      isTrue,
      reason: 'the badge keeps its original side, at the same inset',
    );
  });

  test('no colour is threaded in for the label any more', () {
    // labelColor came from the bubble, and every value it could carry was
    // invisible on the wallpaper. The parameter is gone rather than left
    // as an argument nothing reads.
    expect(source.contains('labelColor'), isFalse);

    final bubble =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();
    expect(bubble.contains('mediaLabelColor'), isFalse);
  });

  test('every chip drawn on the photos shares one fill', () {
    // Three chips sit on the same images: the album label, the count
    // badge and a video's duration. Their FILL is what makes them read as
    // one system.
    //
    // Their radius is intentionally not uniform -- the two badges stay
    // circular, and only the album label softens -- so this asserts the
    // fill alone rather than flattening a deliberate difference.
    for (final widget in ['_AlbumLabel', '_CountBadge', '_DurationBadge']) {
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
    }
  });

  test('only the album label softens its corners', () {
    // The badges are short and symmetric, so a pill suits them. The
    // label is not, so it takes a soft rectangle. Pinned because a
    // well-meaning "make these consistent" change would undo it.
    String bodyOf(String widget) {
      final start = source.indexOf('class $widget');
      final next = source.indexOf('\nclass ', start + 1);
      return next == -1
          ? source.substring(start)
          : source.substring(start, next);
    }

    expect(bodyOf('_AlbumLabel').contains('BorderRadius.circular(10)'), isTrue);
    expect(
      bodyOf('_CountBadge').contains('BorderRadius.circular(999)'),
      isTrue,
      reason: 'the counter stays circular',
    );
    expect(
      bodyOf('_DurationBadge').contains('BorderRadius.circular(999)'),
      isTrue,
      reason: 'the duration chip stays circular',
    );
  });
}
