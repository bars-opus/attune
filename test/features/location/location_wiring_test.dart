import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Location attach entry shares a place, not a file', () {
    // The '+' sheet already listed "Location", wired to onAttachFile --
    // tapping it would have opened a file picker. A visible entry doing
    // the wrong thing is worse than no entry.
    final source =
        File(
          'lib/features/chat/presentation/widgets/chat_text_field.dart',
        ).readAsStringSync();

    final entry = source.substring(
      source.indexOf("title: 'Location'"),
      source.indexOf("title: 'Location'") + 300,
    );

    expect(
      entry.contains('onTap: widget.onSharePlace'),
      isTrue,
      reason: 'Location must open the share-a-place sheet',
    );
    expect(entry.contains('onTap: widget.onAttachFile'), isFalse);
  });

  test('the distance row renders nothing when there is no honest answer', () {
    // Either partner not sharing, a stale reading, or a failed fetch must
    // all produce an ABSENT row. A row saying "location unavailable"
    // invites the question "why", which is the pressure this whole design
    // exists to avoid.
    final source =
        File(
          'lib/features/location/presentation/widgets/partner_distance_row.dart',
        ).readAsStringSync();

    expect(
      source.contains('if (distance == null) return const SizedBox.shrink();'),
      isTrue,
      reason: 'an absent distance must render nothing, not a placeholder',
    );
  });

  test('stopping presence deletes the row rather than hiding it', () {
    // Presence that is merely flagged off is still presence. The
    // guarantee is that turning it off leaves nothing behind.
    final source =
        File(
          'lib/features/location/data/presence_repository.dart',
        ).readAsStringSync();

    final stop = source.substring(source.indexOf('Future<void> stopSharing'));
    expect(
      stop.contains(".delete()"),
      isTrue,
      reason: 'stopSharing must delete the stored position',
    );
  });

  test('the repository can read a distance but never a position', () {
    // The asymmetry the whole feature rests on. If a method ever returns
    // the partner's coordinates, the ambient row has become a location
    // channel.
    final source =
        File(
          'lib/features/location/data/presence_repository.dart',
        ).readAsStringSync();

    expect(source.contains('partner_distance'), isTrue);
    expect(
      source.contains("from('partner_presence').select"),
      isFalse,
      reason: 'a client must never select a partner presence row directly',
    );
  });
}
