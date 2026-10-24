import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Spec 7 (research 06 B1): "I noticed…" notes. The server stores one of two
/// fixed forms (send_appreciation); the jar keeps received notes the person
/// chose to keep, for them alone.
const int maxAppreciationMiddle = 280;

/// The fixed form for [middle], or null when it is empty or too long. A
/// full stop or exclamation the person typed at the end is dropped, so the
/// form never doubles it.
String? composeAppreciation(String middle, {required bool thankful}) {
  final m = middle.trim().replaceFirst(RegExp(r'[.!?\s]+$'), '').trim();
  // Code points, as the server counts them (final review M-8).
  if (m.isEmpty || m.contains('\n') || m.runes.length > maxAppreciationMiddle) {
    return null;
  }
  return thankful
      ? 'Thankful for you because $m.'
      : 'I noticed you $m. Thank you.';
}

class JarNote {
  const JarNote({
    required this.messageId,
    required this.relationshipId,
    required this.content,
    required this.sentAt,
  });

  final String messageId;
  final String relationshipId;
  final String content;
  final DateTime sentAt;

  static JarNote fromRow(Map<String, dynamic> row) => JarNote(
    messageId: row['message_id'] as String,
    relationshipId: row['relationship_id'] as String,
    content: row['content'] as String? ?? '',
    sentAt: DateTime.parse(row['sent_at'] as String),
  );
}

class AppreciationService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<String> send({
    required String relationshipId,
    required String clientMessageId,
    required String text,
  }) async {
    final id = await _client.rpc(
      'send_appreciation',
      params: {
        'p_relationship_id': relationshipId,
        'p_client_message_id': clientMessageId,
        'p_text': text,
      },
    );
    return id as String;
  }

  Future<void> save(String messageId) =>
      _client.rpc('save_to_my_jar', params: {'p_message_id': messageId});

  Future<void> remove(String messageId) =>
      _client.rpc('remove_from_my_jar', params: {'p_message_id': messageId});

  /// Which received notes I kept (ids only), for the chat's actions.
  Future<Set<String>> jarIds() async {
    final rows = await _client.rpc('list_my_jar_ids') as List<dynamic>?;
    return {for (final r in rows ?? const []) r as String};
  }

  Future<List<JarNote>> jar() async {
    final rows = await _client.rpc('list_my_jar') as List<dynamic>?;
    return [
      for (final r in rows ?? const [])
        JarNote.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }
}

final appreciationServiceProvider = Provider<AppreciationService>(
  (_) => AppreciationService(),
);

final appreciationEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    return await ChatFeatureFlags.isEnabled(
      Supabase.instance.client,
      ChatFeatureFlags.appreciationNotes,
    );
  } catch (_) {
    return false;
  }
});

/// The notes this person kept, newest first.
final appreciationJarProvider = FutureProvider.autoDispose<List<JarNote>>((
  ref,
) {
  // Kept mounted behind the privacy cover: read again on each return.
  refreshWhenVisibleAgain(ref);
  return ref.read(appreciationServiceProvider).jar();
});

/// Which received notes this person kept (final review M-7: ids only).
final appreciationJarIdsProvider = FutureProvider.autoDispose<Set<String>>(
  (ref) => ref.read(appreciationServiceProvider).jarIds(),
);
