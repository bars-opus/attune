import 'dart:convert';

import 'package:attune/features/chat/data/cache/chat_cache_backend.dart';
import 'package:attune/features/chat/data/cache/chat_cache_cipher.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _maxMessagesPerRelationship = 200;
const _maxOutboxItems = 100;

final chatCacheServiceProvider = Provider<ChatCacheService>((ref) {
  throw UnimplementedError(
    'chatCacheServiceProvider must be overridden during startup.',
  );
});

class ChatCacheService {
  ChatCacheService._() : _backend = createChatCacheBackend();

  /// Test seam: inject an in-memory backend and a fixed-key cipher so cache
  /// behavior can be exercised without platform storage or the keystore.
  @visibleForTesting
  ChatCacheService.forTesting({
    required ChatCacheBackend backend,
    ChatCacheCipher? cipher,
  }) : _backend = backend,
       _cipher = cipher ?? ChatCacheCipher.forTesting();

  static final ChatCacheService _instance = ChatCacheService._();

  factory ChatCacheService() => _instance;

  final ChatCacheBackend _backend;
  ChatCacheCipher? _cipher;

  Future<void> init() async {
    await _backend.init();
    // Fail-closed on privacy: if key setup fails we operate without a cache
    // rather than persisting plaintext content to disk (Spec 4.4).
    try {
      _cipher ??= await ChatCacheCipher.create();
    } catch (_) {
      _cipher = null;
    }
  }

  String? _encrypt(String plaintext) => _cipher?.encryptString(plaintext);

  String? _decrypt(String? envelope) {
    final cipher = _cipher;
    if (cipher == null || envelope == null) return null;
    return cipher.decryptString(envelope);
  }

  Future<List<Message>> readMessages(
    String userId,
    String relationshipId,
  ) async {
    final raw = _decrypt(await _backend.readMessages(userId, relationshipId));
    if (raw == null || raw.isEmpty) return [];

    try {
      return (jsonDecode(raw) as List)
          .map(
            (entry) =>
                Message.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeMessages(
    String userId,
    String relationshipId,
    List<Message> messages,
  ) async {
    final limited =
        messages.length > _maxMessagesPerRelationship
            ? messages.sublist(0, _maxMessagesPerRelationship)
            : messages;
    final payload = _encrypt(
      jsonEncode(limited.map((message) => message.toJson()).toList()),
    );
    if (payload == null) return;
    await _backend.writeMessages(userId, relationshipId, payload);
  }

  Future<List<Conversation>> readConversations(String userId) async {
    final raw = _decrypt(await _backend.readConversations(userId));
    if (raw == null || raw.isEmpty) return [];

    try {
      return (jsonDecode(raw) as List)
          .map(
            (entry) =>
                Conversation.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeConversations(
    String userId,
    List<Conversation> conversations,
  ) async {
    final payload = _encrypt(
      jsonEncode(
        conversations.map((conversation) => conversation.toJson()).toList(),
      ),
    );
    if (payload == null) return;
    await _backend.writeConversations(userId, payload);
  }

  Future<List<PendingSend>> readOutbox(
    String userId, {
    String? relationshipId,
  }) async {
    final rows = await _backend.readOutbox(
      userId,
      relationshipId: relationshipId,
    );
    final sends = <PendingSend>[];
    for (final row in rows) {
      final payload = _decrypt(row);
      if (payload == null) continue;
      try {
        sends.add(
          PendingSend.fromJson(
            Map<String, dynamic>.from(jsonDecode(payload) as Map),
          ),
        );
      } catch (_) {
        // Skip an undecryptable/corrupt queue row rather than crash the flush.
      }
    }
    return sends;
  }

  Future<void> putOutbox(String userId, PendingSend send) async {
    final payload = _encrypt(jsonEncode(send.toJson()));
    if (payload == null) return;
    await _backend.putOutbox(
      userId,
      send.relationshipId,
      send.clientMessageId,
      payload,
      send.createdAt.millisecondsSinceEpoch,
    );

    final overflow = (await readOutbox(userId)).length - _maxOutboxItems;
    if (overflow <= 0) return;

    final staleRows = await _backend.oldestOutbox(userId, overflow);
    for (final row in staleRows) {
      await _backend.removeOutbox(
        userId,
        row.relationshipId,
        row.clientMessageId,
      );
    }
  }

  Future<void> removeOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
  ) async {
    await _backend.removeOutbox(userId, relationshipId, clientMessageId);
  }

  Future<void> purgeRelationship(String userId, String relationshipId) async {
    await _backend.deleteMessages(userId, relationshipId);
    await _backend.purgeOutboxForRelationship(userId, relationshipId);
    await _backend.clearDraft(userId, relationshipId);
  }

  Future<String> readDraft(String userId, String relationshipId) async {
    return _decrypt(await _backend.readDraft(userId, relationshipId)) ?? '';
  }

  Future<void> writeDraft(
    String userId,
    String relationshipId,
    String draft,
  ) async {
    final normalized = draft.trimRight();
    if (normalized.isEmpty) {
      await _backend.clearDraft(userId, relationshipId);
      return;
    }
    final payload = _encrypt(normalized);
    if (payload == null) return;
    await _backend.writeDraft(userId, relationshipId, payload);
  }

  Future<void> clearDraft(String userId, String relationshipId) async {
    await _backend.clearDraft(userId, relationshipId);
  }

  Future<void> clearAll() async {
    await _backend.clearAll();
  }
}
