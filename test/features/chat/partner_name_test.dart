import 'dart:io';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Conversation convo({String? partnerName}) => Conversation(
    id: 'r1',
    relationshipId: 'r1',
    partnerId: 'p1',
    name: 'Us Two',
    partnerName: partnerName,
    updatedAt: DateTime.now(),
    relationshipStatus: 'active',
    availability: ConversationAvailability.active,
  );

  test('the couple name and the partner name are separate', () {
    // conversation.name prefers the couple's shared chat_name. Using it
    // wherever ONE person is speaking -- a quoted reply, an insights
    // title -- credits an individual's words to the pair.
    final c = convo(partnerName: 'Ada');

    expect(c.name, 'Us Two');
    expect(c.partnerName, 'Ada');
  });

  test('partnerName falls back to the chat name when unknown', () {
    // A caller must always have something to render rather than a null.
    expect(convo().partnerName, 'Us Two');
  });

  test('partnerName survives a cache round-trip', () {
    // The conversation list is served from cache first; losing the field
    // there would put the couple name back in every reply preview until
    // the network fetch landed.
    final restored = Conversation.fromJson(convo(partnerName: 'Ada').toJson());

    expect(restored.partnerName, 'Ada');
    expect(restored.name, 'Us Two');
  });

  test('a quoted reply is labelled with the partner, not the couple', () {
    // The bug as reported: replying to a partner's message showed the
    // couple's chat name above the quote.
    final source =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    expect(
      source.contains("conversation?.name ?? 'Partner'"),
      isFalse,
      reason: 'the quote author label must not use the couple name',
    );
    expect(
      source.contains("conversation?.partnerName ?? 'Partner'"),
      isTrue,
    );
  });

  test('no screen passes the couple name as a partnerName', () {
    // Three call sites fed conversation.name into a parameter literally
    // called partnerName -- chat insights and the import mapping, both of
    // which name one person.
    for (final path in [
      'lib/features/chat/presentation/screens/chat_screen.dart',
      'lib/features/chat/presentation/screens/chat_import_screen.dart',
    ]) {
      expect(
        File(path).readAsStringSync().contains(
          'partnerName: widget.conversation.name',
        ),
        isFalse,
        reason: '$path passes the couple name where a person is meant',
      );
    }
  });
}
