import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/game_move_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

Message _game(String id, DateTime sortAt, {bool isMine = true}) => Message(
  id: id,
  clientMessageId: 'c-$id',
  relationshipId: 'r1',
  senderId: isMine ? 'me' : 'partner',
  content: 'Snakes and Ladders',
  createdAt: DateTime(2026, 10, 19, 9),
  sortAt: sortAt,
  status: MessageStatus.delivered,
  isMine: isMine,
  mediaType: 'game',
  gameSessionId: 's-$id',
);

Message _text(String id, DateTime at) => Message(
  id: id,
  clientMessageId: 'c-$id',
  relationshipId: 'r1',
  senderId: 'partner',
  content: 'hi',
  createdAt: at,
  status: MessageStatus.delivered,
  isMine: false,
);

void main() {
  final t0 = DateTime(2026, 10, 19, 9);
  final t1 = DateTime(2026, 10, 19, 10);

  test('first sight of a card is a baseline, not a move', () {
    final ledger = GameMoveLedger();
    expect(ledger.sync([_game('g1', t0), _text('m1', t0)]), isEmpty);
    expect(ledger.revisionOf('c-g1'), 0);
  });

  test(
    'a card whose sortAt advanced is reported once, with a new revision',
    () {
      final ledger = GameMoveLedger();
      ledger.sync([_game('g1', t0)]);
      expect(ledger.sync([_game('g1', t1, isMine: false)]), {'c-g1'});
      expect(ledger.revisionOf('c-g1'), 1);
      // The same snapshot again is not a second move.
      expect(ledger.sync([_game('g1', t1, isMine: false)]), isEmpty);
      expect(ledger.revisionOf('c-g1'), 1);
    },
  );

  test('a card that only re-sorts in place still counts as a move', () {
    // Review Focus 5: move_game_card bumps sort_at even when the card is
    // already on the actor's side (a session game answered twice).
    final ledger = GameMoveLedger();
    ledger.sync([_game('g1', t0, isMine: false)]);
    expect(ledger.sync([_game('g1', t1, isMine: false)]), {'c-g1'});
  });

  test('non-game rows and an older sortAt are ignored', () {
    final ledger = GameMoveLedger();
    ledger.sync([_game('g1', t1), _text('m1', t0)]);
    expect(ledger.sync([_game('g1', t0), _text('m1', t1)]), isEmpty);
  });
}
