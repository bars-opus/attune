import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

Message _msg({
  required String id,
  required DateTime createdAt,
  DateTime? sortAt,
  String? mediaType,
}) => Message(
  id: id,
  clientMessageId: id,
  relationshipId: 'rel-1',
  senderId: 'me',
  content: id,
  createdAt: createdAt,
  sortAt: sortAt,
  mediaType: mediaType,
  isMine: true,
  status: MessageStatus.sent,
);

void main() {
  test('a resurfaced message sorts to the newest position', () {
    // The server pages on (sort_at, id), and a game card is moved to the
    // bottom by bumping sort_at when someone answers. The client re-sorted
    // every merge by createdAt, which put the card straight back where it
    // was first sent -- so it changed sides correctly and then rendered
    // ABOVE its own trail markers.
    final old = DateTime(2026, 9, 1, 10);
    final recent = DateTime(2026, 9, 2, 15);

    final messages = [
      _msg(id: 'card', createdAt: old, sortAt: recent, mediaType: 'game'),
      _msg(id: 'later-message', createdAt: DateTime(2026, 9, 1, 12)),
    ];

    // Newest-first, as the chat holds them.
    messages.sort((a, b) {
      final byTime = b.presentationSortAt.compareTo(a.presentationSortAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });

    expect(
      messages.first.id,
      'card',
      reason: 'the resurfaced card must be the newest entry',
    );
  });

  test('the chat sorts by presentationSortAt, not createdAt', () {
    // Pinned on the source: every ordinary message has sortAt ==
    // createdAt, so a comparator using the wrong field passes every test
    // that does not involve a resurfaced row.
    final source =
        File(
          'lib/features/chat/presentation/state/chat_state.dart',
        ).readAsStringSync();

    final comparator = source.substring(
      source.indexOf('static int _bySortThenId'),
      source.indexOf('static int _bySortThenId') + 300,
    );

    expect(
      comparator.contains(
        'b.presentationSortAt.compareTo(a.presentationSortAt)',
      ),
      isTrue,
      reason:
          'presentationSortAt defaults to authoritative sortAt, while also '
          'preventing acknowledged optimistic rows from jumping mid-session',
    );
    expect(comparator.contains('b.createdAt.compareTo'), isFalse);

    final merge = source.substring(
      source.indexOf('List<Message> _mergeMessages'),
      source.indexOf('List<Message> _mergeMessages') + 2600,
    );
    expect(
      merge.contains('!message.isGame'),
      isTrue,
      reason: 'game cards must continue following server sort_at resurfacing',
    );
  });
}
