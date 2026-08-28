import 'package:supabase_flutter/supabase_flutter.dart';

/// One segment of a streak, in playback order.
class StreakClip {
  const StreakClip({
    required this.index,
    required this.mediaUrl,
    required this.durationMs,
  });

  factory StreakClip.fromRow(Map<String, dynamic> row) => StreakClip(
        index: (row['clip_index'] as num).toInt(),
        mediaUrl: row['media_url'] as String,
        durationMs: (row['duration_ms'] as num).toInt(),
      );

  final int index;
  final String mediaUrl;
  final int durationMs;
}

class StreakRepository {
  StreakRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _safeClient => _client ?? Supabase.instance.client;

  /// Spends one view, returning what remains.
  ///
  /// Through the RPC, never a direct UPDATE: messages' RLS would let a
  /// client write any value to streak_views_remaining, including
  /// refilling its own budget. The RPC also owns destroying the clips at
  /// zero, which a client must never be able to trigger early or skip.
  Future<int> markViewed(String messageId) async {
    final result = await _safeClient.rpc(
      'mark_streak_viewed',
      params: {'p_message_id': messageId},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  /// The clips of one streak, in playback order.
  ///
  /// Named columns only. The caption is view-time state held by the
  /// viewer, and the budget is server-owned — selecting either here
  /// invites rendering it somewhere the spec forbids.
  Future<List<StreakClip>> fetchClips(String messageId) async {
    final rows = await _safeClient
        .from('streak_clips')
        .select('clip_index, media_url, duration_ms')
        .eq('message_id', messageId)
        .order('clip_index');

    return rows
        .map((row) => StreakClip.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }
}
