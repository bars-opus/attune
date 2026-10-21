import 'package:attune/features/chat/domain/entities/message.dart';

/// Notices a game card that MOVED.
///
/// `move_game_card` keeps the card's id/client id/created_at and rewrites
/// only `sender_id` and `sort_at`, so the identity-based arrival tracker
/// never sees a move: the card teleported from mid-history to the bottom
/// with no motion. A move is a card whose presentationSortAt is later than
/// the last one this ledger saw for it. First sight is a baseline.
class GameMoveLedger {
  final Map<String, DateTime> _sortAt = {};
  final Map<String, int> _revision = {};

  /// Client ids of cards that moved since the previous [sync].
  Set<String> sync(Iterable<Message> messages) {
    final moved = <String>{};
    for (final message in messages) {
      if (!message.isGame) continue;
      final id = message.clientMessageId;
      final previous = _sortAt[id];
      _sortAt[id] = message.presentationSortAt;
      if (previous != null && message.presentationSortAt.isAfter(previous)) {
        _revision[id] = (_revision[id] ?? 0) + 1;
        moved.add(id);
      }
    }
    return moved;
  }

  /// How many times [clientMessageId] has moved. Part of the row's motion
  /// key, so each move gets a fresh SettleIn/MakeRoom (they decide once).
  int revisionOf(String clientMessageId) => _revision[clientMessageId] ?? 0;
}
