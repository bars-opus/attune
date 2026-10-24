/// The last rings this phone saw (03 M3), so a cold start offline or a
/// failed first read paints them instead of "Add to your story". Holds ids,
/// counts, timestamps and storage keys only, never a URL. This device only
/// (Keychain `first_unlock_this_device`; Android encrypted prefs, already
/// excluded from backups). Cleared on sign-out, account switch, quick exit
/// and a relationship's pause, end or archive (story_device_wipe.dart).
library;

import 'dart:convert';

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoryRingSnapshot {
  const StoryRingSnapshot({
    required this.userId,
    required this.relationshipId,
    required this.savedAt,
    required this.rows,
  });

  final String userId;
  final String relationshipId;
  final DateTime savedAt;
  final List<StoryRingSummary> rows;

  Map<String, Object?> toJson() => {
    'v': 1,
    'user_id': userId,
    'relationship_id': relationshipId,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'rows': [for (final row in rows) row.toRow()],
  };

  static StoryRingSnapshot? fromJson(Object? json) {
    try {
      final map = Map<String, dynamic>.from(json! as Map);
      if (map['v'] != 1) return null;
      return StoryRingSnapshot(
        userId: '${map['user_id']}',
        relationshipId: '${map['relationship_id']}',
        savedAt: DateTime.parse('${map['saved_at']}'),
        rows: [
          for (final row in map['rows'] as List)
            StoryRingSummary.fromRow(Map<String, dynamic>.from(row as Map)),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// What may still be painted for [userId]'s [relationshipId] ring at
  /// [now]: rows whose newest story is under 24 h old. Null when the
  /// snapshot is someone else's, another relationship's, or over a day old.
  Map<String, StoryRingSummary>? usableFor({
    required String userId,
    required String relationshipId,
    required DateTime now,
  }) {
    if (userId != this.userId || relationshipId != this.relationshipId) {
      return null;
    }
    if (now.difference(savedAt) >= kStoryLifetime) return null;
    return {
      for (final row in rows)
        if (row.newestCreatedAt.add(kStoryLifetime).isAfter(now))
          row.authorId: row,
    };
  }
}

abstract class StoryRingLastKnownStore {
  /// Bumped by every [clear], synchronously, before the delete. A read
  /// that started under an older epoch must not write (review #1): a wipe
  /// during a ring fetch would otherwise be undone when the fetch lands.
  int get epoch;
  Future<StoryRingSnapshot?> read();
  Future<void> write(StoryRingSnapshot snapshot);
  Future<void> clear();

  /// Sign-out (batch-4 review #2): the wipe lands before the session ends,
  /// so no snapshot of [userId] is written until [allowWrites] (the next
  /// sign-in).
  void blockWritesFor(String userId);
  void allowWrites();
  bool acceptsWritesFor(String userId);
}

class SecureStoryRingLastKnownStore implements StoryRingLastKnownStore {
  static const String storageKey = 'story_ring_last_known_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<StoryRingSnapshot?> read() async {
    try {
      final raw = await _storage.read(key: storageKey);
      return raw == null ? null : StoryRingSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(StoryRingSnapshot snapshot) async {
    if (!acceptsWritesFor(snapshot.userId)) return;
    try {
      await _storage.write(
        key: storageKey,
        value: jsonEncode(snapshot.toJson()),
      );
    } catch (_) {}
  }

  /// Shared by every instance, like the keychain entry they all name:
  /// quick exit clears through a new one, and a read in flight on the
  /// provider's must still see that wipe.
  static int _epoch = 0;

  @override
  int get epoch => _epoch;

  /// Static for the same reason as [_epoch].
  static String? _blockedUserId;

  @override
  void blockWritesFor(String userId) => _blockedUserId = userId;

  @override
  void allowWrites() => _blockedUserId = null;

  @override
  bool acceptsWritesFor(String userId) => _blockedUserId != userId;

  @override
  Future<void> clear() async {
    _epoch++;
    try {
      await _storage.delete(key: storageKey);
    } catch (_) {}
  }
}

class MemoryStoryRingLastKnownStore implements StoryRingLastKnownStore {
  StoryRingSnapshot? value;
  int writes = 0;

  @override
  int epoch = 0;

  @override
  Future<StoryRingSnapshot?> read() async => value;

  String? blockedUserId;

  @override
  Future<void> write(StoryRingSnapshot snapshot) async {
    if (!acceptsWritesFor(snapshot.userId)) return;
    writes++;
    value = snapshot;
  }

  @override
  void blockWritesFor(String userId) => blockedUserId = userId;

  @override
  void allowWrites() => blockedUserId = null;

  @override
  bool acceptsWritesFor(String userId) => blockedUserId != userId;

  @override
  Future<void> clear() async {
    epoch++;
    value = null;
  }
}

final storyRingLastKnownStoreProvider = Provider<StoryRingLastKnownStore>(
  (_) => SecureStoryRingLastKnownStore(),
);
