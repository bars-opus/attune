// Spec 2 W6a (D8, D20): the chat's reads, one entry per account (the next
// account's entry starts as a plain loading value, never holding the last
// one's conversations), memory only, disposed when nothing shows them.
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show DatingSessionMemory;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final datingChatGatewayProvider = Provider<DatingChatGateway>(
  (ref) => DatingChatRepository(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider),
  ),
);

/// The conversations list (with the ended ones) for [account].
final datingConversationsProvider = FutureProvider.autoDispose
    .family<DatingConversations, String?>((ref, account) async {
      if (account == null) return DatingConversations.failed;
      return ref.read(datingChatGatewayProvider).conversations(ended: true);
    });

/// Spec 2 W6b Task 7 fix round 1 (M-1): [account]'s card dismissals the
/// server has not confirmed yet. Their cards stay hidden and they are sent
/// again on the next good read. Memory only (D20): opaque ids, kept for
/// the app's life, one set per account, never shown to another. Final
/// client fix (M-3, §7.4): emptied by quick exit and sign-out (Dating's
/// session entry in the device wipe registry).
final datingPendingCardDismissalsProvider =
    Provider.family<Set<String>, String>(_wipedSet);

/// Spec 2 W6c Task 9 fix round 1 (M-3): [account]'s timebox dismissals
/// the server has not confirmed yet, as `matchId|card`. Their cards stay
/// hidden and they are sent again on the next good read (as the card
/// dismissals above). Memory only (D20), one set per account; emptied as
/// the card dismissals are (M-3).
final datingPendingTimeboxDismissalsProvider =
    Provider.family<Set<String>, String>(_wipedSet);

/// M-3: a set the session wipe empties (it stays the same set, so a
/// sender holding it sees it emptied).
Set<String> _wipedSet(Ref ref, String account) {
  final set = <String>{};
  DatingSessionMemory.track(set, ref, set.clear);
  return set;
}

/// A count of [account]'s chat signals while something listens: each new
/// value means "read again". Never an error (a dropped connection is
/// silence; the screens read again when they open and on resume).
final datingChatSignalsProvider = StreamProvider.autoDispose
    .family<int, String?>((ref, account) async* {
      if (account == null) return;
      var n = 0;
      try {
        await for (final _ in ref
            .read(datingChatGatewayProvider)
            .signals(account)) {
          yield ++n;
        }
      } catch (_) {
        // silence
      }
    });
