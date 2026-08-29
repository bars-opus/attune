import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

/// One clip's upload, resolved from a recorded segment.
class StreakClipUpload {
  const StreakClipUpload({
    required this.clipIndex,
    required this.localPath,
    required this.durationMs,
  });

  final int clipIndex;
  final String localPath;
  final int durationMs;
}

/// Turns recorded segments into ordered upload plans.
///
/// Each clip carries its OWN duration rather than assuming a full segment:
/// a partial final clip is kept deliberately, and the viewer's progress
/// would be wrong if its real length did not reach the row.
List<StreakClipUpload> streakClipUploads(List<StreakSegment> segments) => [
      for (var i = 0; i < segments.length; i++)
        StreakClipUpload(
          clipIndex: i,
          localPath: segments[i].path,
          durationMs: segments[i].duration.inMilliseconds,
        ),
    ];

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
  }) async {
    await _safeClient.from('streak_clips').insert({
      'message_id': messageId,
      // Single-clip streaks, so the index is always zero. Kept explicit
      // rather than defaulted: playback orders by it.
      'clip_index': 0,
      'media_url': mediaUrl,
      'duration_ms': durationMs,
    });
  }

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

  /// Sends a streak: one message row, then a clip row per segment.
  ///
  /// Not routed through PendingSend and the outbox like every other
  /// message type, deliberately. That model carries exactly one media
  /// path, and widening it for a five-clip payload would reshape the
  /// retry machinery every other message depends on. A streak is
  /// ephemeral and short-lived, so a failed send is better re-recorded
  /// than resurrected from an outbox days later.
  ///
  /// The message row's media_url is the FIRST clip's key: messages'
  /// payload-present constraint requires content or media_url, and the
  /// first clip is also what any poster would show.
  Future<String> sendStreak({
    required String relationshipId,
    required String senderId,
    required List<StreakClipUpload> clips,
    required int viewsRemaining,
    required Future<String> Function(String localPath) uploadClip,
  }) async {
    if (clips.isEmpty) {
      throw ArgumentError('a streak needs at least one clip');
    }

    final keys = <String>[];
    for (final clip in clips) {
      keys.add(await uploadClip(clip.localPath));
    }

    final message = await _safeClient
        .from('messages')
        .insert({
          'relationship_id': relationshipId,
          'sender_id': senderId,
          'client_message_id': const Uuid().v4(),
          'content': '',
          'media_type': 'streak',
          'media_url': keys.first,
          'streak_views_remaining': viewsRemaining,
        })
        .select('id')
        .single();

    final messageId = message['id'] as String;

    await _safeClient.from('streak_clips').insert([
      for (var i = 0; i < clips.length; i++)
        {
          'message_id': messageId,
          'clip_index': clips[i].clipIndex,
          'media_url': keys[i],
          'duration_ms': clips[i].durationMs,
        },
    ]);

    return messageId;
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
