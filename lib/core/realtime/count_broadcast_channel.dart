// lib/core/realtime/count_broadcast_channel.dart

import 'package:supabase_flutter/supabase_flutter.dart';

/// Subscribes to the 'counts' broadcast on a single entity's channel — see
/// 20260826120000_realtime_count_broadcasts.sql, which is the only thing
/// that ever sends on these channels (from inside the SECURITY DEFINER
/// increment/decrement RPCs, right after the row UPDATE, with only the
/// entity id and its count columns as payload).
///
/// Broadcast rather than postgres_changes: the base tables (opinions,
/// forum_topics, forum_posts) aren't SELECT-able by anon, and even
/// authenticated's raw-table SELECT carries user_id, which postgres_changes
/// would replay to every subscriber. Broadcast on a public (non-private)
/// channel has no RLS involved at all — the payload is exactly what the RPC
/// chose to send, nothing more — so it's safe for guests and signed-in
/// viewers alike, which is the whole point: every viewer sees the same
/// live count, not just the person who just tapped like.
///
/// One subscription per entity (one channel per card on screen) rather than
/// a single shared channel for a whole feed — simpler lifecycle (a card
/// subscribes in initState, unsubscribes in dispose, same as any other
/// per-widget resource) at the cost of one Realtime channel per visible
/// card. Fine at this app's scale; revisit if a feed screen ever needs
/// hundreds of simultaneously-live cards.
class CountBroadcastChannel {
  CountBroadcastChannel({
    required SupabaseClient supabase,
    required String topic,
    required void Function(Map<String, dynamic> payload) onCounts,
  }) {
    _channel = supabase
        .channel(topic)
        .onBroadcast(
          event: 'counts',
          callback: (payload) {
            // Supabase nests the sent payload under a `payload` key on the
            // receiving side — same defensive unwrap
            // supabase_chat_repository.dart's typing handler uses.
            final data =
                (payload['payload'] is Map)
                    ? Map<String, dynamic>.from(payload['payload'] as Map)
                    : payload;
            onCounts(data);
          },
        )
        .subscribe();
  }

  late final RealtimeChannel _channel;

  Future<void> dispose() => _channel.unsubscribe();
}
