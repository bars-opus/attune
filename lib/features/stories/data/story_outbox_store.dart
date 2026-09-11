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
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'story_outbox_backend.dart';
import 'story_outbox_record.dart';

class StoryOutboxStore {
  StoryOutboxStore() : _backend = createDefaultStoryOutboxBackend();

  /// Test seam: inject a backend directly (an in-memory stub, or a
  /// `dart:io` backend pointed at a controlled temp file) so durability
  /// and restart behaviour can be exercised without the app-support
  /// directory or platform channels.
  @visibleForTesting
  StoryOutboxStore.forTesting(StoryOutboxBackend backend) : _backend = backend;

  final StoryOutboxBackend _backend;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _backend.init();
    _initialized = true;
  }

  /// All records for [userId], oldest-first — the order a single-item
  /// queue should drain them in. Includes every state, `failedPermanent`
  /// included: spec §6.1, "it never silently disappears."
  Future<List<StoryOutboxRecord>> readAll(String userId) async {
    await _ensureInitialized();
    final rows = await _backend.readAll(userId);
    final records = <StoryOutboxRecord>[];
    for (final row in rows) {
      try {
        records.add(
          StoryOutboxRecord.fromJson(
            Map<String, dynamic>.from(jsonDecode(row) as Map),
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
  Future<void> put(String userId, StoryOutboxRecord record) async {
    await _ensureInitialized();
    await _backend.put(
      userId,
      record.clientStoryId,
      jsonEncode(record.toJson()),
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
