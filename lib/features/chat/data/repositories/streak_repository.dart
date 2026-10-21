import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a streak clip actually is. Explicit rather than inferred from
/// `durationMs == 0`: a photo stores that honestly (it has no length), so
/// an inferred discriminator would render a genuinely zero-length or
/// corrupt VIDEO as a broken image (spec §6.3 step 3).
enum StreakClipKind { photo, video }

/// One segment of a streak, in playback order.
class StreakClip {
  const StreakClip({
    required this.index,
    required this.mediaUrl,
    required this.durationMs,
    required this.mediaKind,
  });

  factory StreakClip.fromRow(Map<String, dynamic> row) => StreakClip(
    index: (row['clip_index'] as num).toInt(),
    mediaUrl: row['media_url'] as String,
    durationMs: (row['duration_ms'] as num).toInt(),
    // Every row written before this column existed reads back 'video'
    // (the column's own server-side DEFAULT), so a defensive fallback
    // here is belt-and-braces, not load-bearing.
    mediaKind:
        (row['media_kind'] as String?) == 'photo'
            ? StreakClipKind.photo
            : StreakClipKind.video,
  );

  final int index;
  final String mediaUrl;
  final int durationMs;
  final StreakClipKind mediaKind;
}

final streakRepositoryProvider = Provider<StreakRepository>(
  (ref) => StreakRepository(),
);

class StreakRepository {
  StreakRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _safeClient => _client ?? Supabase.instance.client;

  /// Attaches the clip row to a streak message that has just been
  /// inserted.
  ///
  /// Separate from the message insert because the outbox owns that write:
  /// _attemptSend inserts the message, reconciles duplicates and retries,
  /// and a streak only needs its clip hung off whatever row that produced.
  Future<void> attachClip({
    required String messageId,
    required String mediaUrl,
    required int durationMs,
    StreakClipKind mediaKind = StreakClipKind.video,
  }) async {
    await _safeClient
        .from('streak_clips')
        .upsert(
          {
            'message_id': messageId,
            // Single-clip streaks, so the index is always zero. Kept explicit
            // rather than defaulted: playback orders by it.
            'clip_index': 0,
            'media_url': mediaUrl,
            'duration_ms': durationMs,
            'media_kind': mediaKind == StreakClipKind.photo ? 'photo' : 'video',
          },
          onConflict: 'message_id,clip_index',
          ignoreDuplicates: true,
        );
  }

  /// Spends one view, returning what remains.
  ///
  /// Through the RPC, never a direct UPDATE: messages' RLS would let a
  /// client write any value to streak_views_remaining, including
  /// refilling its own budget. The RPC also owns destroying the clips at
  /// zero, which a client must never be able to trigger early or skip.
  ///
  /// [openId] names ONE opening of the viewer. The server charges each
  /// (message, viewer, open) once and answers a repeat with the count it
  /// stored, so a lost response can be retried with the same id without
  /// spending a second view.
  Future<int> markViewed(String messageId, {required String openId}) async {
    final result = await _safeClient.rpc(
      'mark_streak_viewed',
      params: {'p_message_id': messageId, 'p_open_id': openId},
    );
    // Logged with the RAW shape: the difference between "the RPC said 2
    // views remain" and "the RPC returned null and this defaulted to 0"
    // is invisible downstream, and both look like the bubble simply not
    // updating.
    ChatLog.diagnostic(
      'mark_streak_viewed returned',
      '${result.runtimeType}: $result',
    );
    return (result as num?)?.toInt() ?? 0;
  }

  /// The clips of one streak, in playback order — through the gated RPC.
  ///
  /// `streak_clips_for_viewing` returns rows only while the streak is
  /// viewable for THIS caller (recipient: budget left and inside the
  /// 30-minute replay window; sender: not yet opened) and destroys an
  /// expired one before answering. A direct table read handed out an
  /// expired replay and only the finish-time RPC said no — after it had
  /// played. The RPC returns named columns only: the caption is view-time
  /// state held by the viewer, and the budget is server-owned.
  Future<List<StreakClip>> fetchClips(String messageId) async {
    final result = await _safeClient.rpc(
      'streak_clips_for_viewing',
      params: {'p_message_id': messageId},
    );
    final rows = (result as List?) ?? const [];
    return rows
        .map(
          (row) => StreakClip.fromRow(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }
}
