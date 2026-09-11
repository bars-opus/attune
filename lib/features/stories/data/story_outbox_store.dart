/// The durable outbox for story captures (spec §6.1).
///
/// Calling a stories repository does not inherit the chat outbox's
/// retries, optimistic UI, or durable queueing — a story sent through
/// `StoryRepository` gets none of that for free. This store is what
/// closes that gap: it persists a [StoryOutboxRecord] to SQLite so a
/// captured-but-not-yet-posted story survives an app restart. "A story
/// is captured in the moment, often on poor connectivity, and a failed
/// upload that silently vanishes is worse here than in chat — there is
/// no bubble to show a retry affordance."
///
/// This is persistence only: write, read, update, delete. It does not
/// drive [StoryOutboxState] transitions or retry timing — that is
/// Task 6's state machine, built on top of this store.
///
/// **Encryption at rest.** Spec §6.1: the queue "reuses the encrypted
/// SQLite/cache patterns behind the chat outbox." This store's record
/// carries local file paths and a relationship id, so the payload column
/// is encrypted the same way `ChatCacheService` encrypts `chat_outbox`
/// (`chat_cache_service.dart:147-157`): [ChatCacheCipher] (AES-256-GCM,
/// keystore-backed) over the JSON payload before it reaches SQLite. The
/// cipher is reused directly rather than a separate `StoryOutboxCipher`
/// — see the class doc on [_cipher] for why. The indexing columns
/// (`user_id`, `client_story_id`, `created_at`) stay plaintext, same
/// rule chat follows (`chat_cache_cipher.dart:19`): they carry no story
/// content and the backend needs them to key and order rows.
library;

import 'dart:convert';

import 'package:attune/features/chat/data/cache/chat_cache_cipher.dart';
import 'package:flutter/foundation.dart';

import 'story_outbox_backend.dart';
import 'story_outbox_record.dart';

class StoryOutboxStore {
  StoryOutboxStore() : _backend = createDefaultStoryOutboxBackend();

  /// Test seam: inject a backend directly (an in-memory stub, or a
  /// `dart:io` backend pointed at a controlled temp file) so durability
  /// and restart behaviour can be exercised without the app-support
  /// directory or platform channels. [cipher] defaults to
  /// [ChatCacheCipher.forTesting] (a fixed in-memory key) so encryption
  /// round-trips are exercised without the platform keystore, matching
  /// `ChatCacheService.forTesting`.
  @visibleForTesting
  StoryOutboxStore.forTesting(StoryOutboxBackend backend, {ChatCacheCipher? cipher})
    : _backend = backend,
      _cipher = cipher ?? ChatCacheCipher.forTesting();

  final StoryOutboxBackend _backend;
  bool _initialized = false;

  /// Reused from chat rather than a new `StoryOutboxCipher`: the 256-bit
  /// data key is already provisioned in the platform keystore (iOS
  /// Keychain / Android Keystore) by the time either feature needs it,
  /// so a second cipher would mean a second keystore round-trip and a
  /// second independent fail-closed path for no isolation benefit that
  /// matters here — both stores already live in the same app-private
  /// sandbox, so a compromise able to read one key can read the other
  /// regardless of how many keys exist. The cost: [ChatCacheCipher]'s
  /// name and its storage key constant (`attune_chat_cache_key_v1`) both
  /// read as chat-only to a future reader who hasn't seen this comment —
  /// worth renaming to something feature-neutral (e.g.
  /// `AttuneLocalCacheCipher` / `attune_local_cache_key_v1`) the next
  /// time either file changes, rather than as a drive-by here.
  ChatCacheCipher? _cipher;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _backend.init();
    // Fail-closed on privacy, same as ChatCacheService.init(): if key
    // setup fails, this store operates without persistence rather than
    // writing plaintext story metadata to disk.
    try {
      _cipher ??= await ChatCacheCipher.create();
    } catch (_) {
      _cipher = null;
    }
    _initialized = true;
  }

  String? _encrypt(String plaintext) => _cipher?.encryptString(plaintext);

  String? _decrypt(String envelope) => _cipher?.decryptString(envelope);

  /// All records for [userId], oldest-first — the order a single-item
  /// queue should drain them in. Includes every state, `failedPermanent`
  /// included: spec §6.1, "it never silently disappears."
  Future<List<StoryOutboxRecord>> readAll(String userId) async {
    await _ensureInitialized();
    final rows = await _backend.readAll(userId);
    final records = <StoryOutboxRecord>[];
    for (final row in rows) {
      final raw = _decrypt(row);
      if (raw == null) continue; // no cipher, or an undecryptable row
      try {
        records.add(
          StoryOutboxRecord.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          ),
        );
      } catch (_) {
        // Skip a corrupt row rather than crash every caller of readAll.
      }
    }
    return records;
  }

  /// Insert-or-replace keyed on `(userId, clientStoryId)`. Enqueueing a
  /// new capture and updating an existing record's state/attempts both
  /// go through this — [StoryOutboxRecord.clientStoryId] is what makes
  /// the second case an update rather than a duplicate row.
  ///
  /// If the cipher is unavailable (keystore failure), the write is
  /// silently dropped rather than persisting plaintext — same
  /// fail-closed behaviour as `ChatCacheService.writeMessages` et al.
  Future<void> put(String userId, StoryOutboxRecord record) async {
    await _ensureInitialized();
    final payload = _encrypt(jsonEncode(record.toJson()));
    if (payload == null) return;
    await _backend.put(
      userId,
      record.clientStoryId,
      payload,
      // The record's own createdAt, not wall-clock write time — this is
      // the plaintext ordering column Task 6's FIFO drain relies on
      // (readAll's ORDER BY created_at ASC), so it must track the same
      // "created" concept as the encrypted payload's own createdAt field
      // rather than drift from it. Matches chat_cache_service.dart:154
      // (`send.createdAt.millisecondsSinceEpoch`, not `DateTime.now()`).
      record.createdAt.millisecondsSinceEpoch,
    );
  }

  /// Removes a record entirely — used on success (posted) or an explicit
  /// user Discard of a `failedPermanent` row. Never called just because a
  /// retry failed; a retryable or permanent failure is written back via
  /// [put], not removed, so it stays visible (spec §6.1).
  Future<void> remove(String userId, String clientStoryId) async {
    await _ensureInitialized();
    await _backend.remove(userId, clientStoryId);
  }

  Future<void> clearAll() async {
    await _ensureInitialized();
    await _backend.clearAll();
  }

  /// Closes the backend's connection. Production holds this store for
  /// the app's lifetime and never needs to call this; it exists for
  /// tests that must prove durability by closing a real connection and
  /// reopening a fresh [StoryOutboxStore] against the same file, rather
  /// than reading back through a connection that was simply held open.
  @visibleForTesting
  Future<void> disposeForTesting() => _backend.close();
}
