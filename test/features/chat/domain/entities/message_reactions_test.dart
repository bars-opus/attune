import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Message baseMessage() => Message(
    id: 'm1',
    clientMessageId: 'c1',
    relationshipId: 'r1',
    senderId: 'u1',
    content: 'hello',
    createdAt: DateTime(2026, 1, 1),
    status: MessageStatus.sent,
    isMine: true,
  );

  test('reactions defaults to empty', () {
    expect(baseMessage().reactions, isEmpty);
  });

  test('copyWith replaces reactions wholesale', () {
    final withReaction = baseMessage().copyWith(
      reactions: {
        '❤️': {'u1', 'u2'},
      },
    );
    expect(withReaction.reactions['❤️'], {'u1', 'u2'});
  });

  test('toJson/fromJson round-trips reactions', () {
    final withReaction = baseMessage().copyWith(
      reactions: {
        '❤️': {'u1', 'u2'},
        '👍': {'u1'},
      },
    );
    final restored = Message.fromJson(withReaction.toJson());
    expect(restored.reactions['❤️'], {'u1', 'u2'});
    expect(restored.reactions['👍'], {'u1'});
  });

  test('fromJson defaults reactions to empty when the key is absent', () {
    final json = baseMessage().toJson()..remove('reactions');
    final restored = Message.fromJson(json);
    expect(restored.reactions, isEmpty);
  });
}
