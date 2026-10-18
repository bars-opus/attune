import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/conflict_toolkit/data/toolkit_texts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Spec 8 (B3 (a); plan review I4): "Take a pause" and its one fixed reply,
/// both made by the server. Whether the reply is offered is the server's
/// answer alone (`pause_reply_state`), never worked out here.
class PauseService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<String> send({
    required String relationshipId,
    required String clientMessageId,
    required int variant,
  }) async {
    final id = await _client.rpc(
      'send_pause',
      params: {
        'p_relationship_id': relationshipId,
        'p_client_message_id': clientMessageId,
        'p_variant': variant,
      },
    );
    return id as String;
  }

  Future<bool> replyAvailable(String pauseMessageId) async {
    final state = await _client.rpc(
      'pause_reply_state',
      params: {'p_pause_message_id': pauseMessageId},
    );
    return state == 'available';
  }

  Future<void> reply({
    required String pauseMessageId,
    required String clientMessageId,
  }) => _client.rpc(
    'send_pause_reply',
    params: {
      'p_pause_message_id': pauseMessageId,
      'p_client_message_id': clientMessageId,
    },
  );
}

/// Whether the chat should ask the server about a reply under [m]: a
/// received, live pause from the last hour. The server still decides.
bool mayOfferPauseReply(Message m, DateTime now) =>
    m.isPause &&
    !m.isMine &&
    m.deletedAt == null &&
    now.difference(m.createdAt) < const Duration(minutes: 60);

final pauseServiceProvider = Provider<PauseService>((ref) => PauseService());

/// Whether the reply chip shows under a received pause; false on any error.
final pauseReplyAvailableProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, pauseMessageId) async {
      try {
        return await ref
            .read(pauseServiceProvider)
            .replyAvailable(pauseMessageId);
      } catch (_) {
        return false;
      }
    });

/// `conflict_toolkit` and `private_safety_check`, both (plan review I5).
final conflictToolkitEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final client = Supabase.instance.client;
    final flags = await Future.wait([
      ChatFeatureFlags.isEnabled(client, ChatFeatureFlags.conflictToolkit),
      ChatFeatureFlags.isEnabled(client, ChatFeatureFlags.privateSafetyCheck),
    ]);
    return toolkitVisible(toolkit: flags[0], safetyCheck: flags[1]);
  } catch (_) {
    return false;
  }
});
