import 'dart:convert';

import 'package:attune/features/chat/data/cache/chat_cache_backend.dart';
import 'package:attune/features/chat/data/cache/chat_cache_backend_base.dart'
    show ChatCacheFailureKind, ChatCacheOpenException;
import 'package:attune/features/chat/data/cache/chat_cache_backend_stub.dart'
    as memory;
import 'package:attune/features/chat/data/cache/chat_cache_cipher.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _maxMessagesPerRelationship = 200;
const _maxOutboxItems = 100;

/// Waits between open attempts on a busy/locked store: three tries, about
/// 0.75 s of waiting in all, so a lock held across a quick relaunch clears
/// without holding startup.
const _busyRetryDelays = [
  Duration(milliseconds: 250),
  Duration(milliseconds: 500),
];

final chatCacheServiceProvider = Provider<ChatCacheService>((ref) {
  throw UnimplementedError(
    'chatCacheServiceProvider must be overridden during startup.',
  );
});

class ChatCacheService {
  ChatCacheService._()
    : _backend = createChatCacheBackend(),
      _clearAllBound = _defaultClearAllBound;

  /// Test seam: inject an in-memory backend and a fixed-key cipher so cache
  /// behavior can be exercised without platform storage or the keystore.
  ///
  /// [withoutCipher] models a keystore that could not be read (or took
  /// longer than the 3 s bound): no key for the session. [clearAllBound]
  /// shortens how long a sign-out waits on the cache.
  @visibleForTesting
  ChatCacheService.forTesting({
    required ChatCacheBackend backend,
    ChatCacheCipher? cipher,
    bool withoutCipher = false,
    Duration clearAllBound = _defaultClearAllBound,
  }) : _backend = backend,
       _cipher = withoutCipher ? null : cipher ?? ChatCacheCipher.forTesting(),
       _clearAllBound = clearAllBound;

  static const _defaultClearAllBound = Duration(seconds: 3);

  /// How long [clearAll] may hold a sign-out.
  final Duration _clearAllBound;

  static final ChatCacheService _instance = ChatCacheService._();

  factory ChatCacheService() => _instance;

  ChatCacheBackend _backend;
  ChatCacheCipher? _cipher;
  bool _degraded = false;

  /// The on-disk backend this session fell back from ([isDegraded]): kept
  /// so a sign-out wipe or a purge still reaches the file it left behind.
  ChatCacheBackend? _diskBackend;

  /// True when this session runs on the in-memory fallback because the
  /// on-disk store could not be opened or rebuilt. Nothing persists across
  /// restarts until the next launch opens the disk store again.
  bool get isDegraded => _degraded;

  /// Never throws and never hangs the caller for long (Spec 16: "rebuild
  /// read cache from server; preserve recoverable queue").
  ///
  /// - Opens: nothing is lost.
  /// - Busy/locked: retried (three tries, ~0.75 s), then as "other".
  /// - Corrupt (SQLITE_CORRUPT/NOTADB): the file is deleted and recreated.
  ///   The read cache rebuilds from the server; its queue and drafts were
  ///   unreadable anyway. If the rebuild fails too, as "other".
  /// - Anything else (a schema/upgrade step, I/O, the platform directory):
  ///   this session runs on memory ([isDegraded]) and the file is left
  ///   untouched, so its queue and drafts are there on the next launch.
  ///   What this session writes is gone when the app closes.
  ///
  /// Single flight: a second call (or a [clearAll] while it runs) waits on
  /// the same open rather than starting another.
  Future<void> init() => _initFlight ??= _init();

  Future<void>? _initFlight;

  Future<void> _init() async {
    await _openBackendWithRecovery();
    // Fail-closed on privacy: if key setup fails we operate without a cache
    // rather than persisting plaintext content to disk (Spec 4.4). Bounded:
    // a hung keystore (seen on some Samsung phones) must not hold startup.
    try {
      _cipher ??= await ChatCacheCipher.create().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      _cipher = null;
    }
  }

  Future<void> _openBackendWithRecovery() async {
    var failure = await _tryOpen();
    for (final delay in _busyRetryDelays) {
      if (failure != ChatCacheFailureKind.busy) break;
      await Future<void>.delayed(delay);
      failure = await _tryOpen();
    }
    if (failure == null) return;
    if (failure == ChatCacheFailureKind.corrupt) {
      debugPrint('[chat-cache] store unreadable; rebuilding it');
      try {
        await _backend.reset();
        failure = await _tryOpen();
        if (failure == null) return;
      } catch (error) {
        debugPrint('[chat-cache] rebuild failed (${error.runtimeType})');
      }
    }
    // Not deleted: whatever the file still holds is there next launch.
    debugPrint(
      '[chat-cache] running on memory this session; the disk store is '
      'left as it is',
    );
    ChatLog.d('[CHAT] cache degraded kind=${failure?.name}');
    _degraded = true;
    _diskBackend = _backend;
    _backend = memory.createBackend();
    await _backend.init();
  }

  /// One open attempt: null when it opened, else how it failed.
  Future<ChatCacheFailureKind?> _tryOpen() async {
    try {
      await _backend.init();
      return null;
    } catch (error) {
      final kind =
          error is ChatCacheOpenException
              ? error.kind
              : ChatCacheFailureKind.other;
      final cause = error is ChatCacheOpenException ? error.cause : error;
      debugPrint(
        '[chat-cache] open failed (${kind.name}, ${cause.runtimeType})',
      );
      return kind;
    }
  }

  /// A read-cache failure at runtime is a cache miss, never an exception
  /// into a controller: the server is the source of truth.
  ///
  /// Deliberately NOT guarded — these THROW on a backend error, because
  /// their callers act on the failure; swallowing it would lose or
  /// duplicate sends:
  /// - [readOutbox]: a flush that cannot read the queue arms its retry (M2).
  /// - [putOutbox] (the row write, and no key — see there): a send with no
  ///   queue row behind it goes direct once or turns failed and retryable
  ///   (M1), never "queued" with nothing queued.
  /// - [removeOutbox]: a dismissed bubble is never silently left queued to
  ///   be sent later.
  /// - [writeMessages]: the sync cursor is never persisted ahead of the
  ///   history it covers (rows first, cursor second), and settled media
  ///   keeps its staging file when its cache write failed.
  /// Everything else (history/conversation/draft reads, conversations,
  /// drafts, the sync cursor, purge, clear, the outbox trim) is guarded.
  Future<T> _guardRead<T>(
    String what,
    Future<T> Function() run,
    T fallback,
  ) async {
    try {
      return await run();
    } catch (error) {
      debugPrint('[chat-cache] $what read failed (${error.runtimeType})');
      return fallback;
    }
  }

  Future<void> _guardWrite(String what, Future<void> Function() run) async {
    try {
      await run();
    } catch (error) {
      debugPrint('[chat-cache] $what write failed (${error.runtimeType})');
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
    final raw = _decrypt(
      await _guardRead(
        'messages',
        () => _backend.readMessages(userId, relationshipId),
        null,
      ),
    );
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
    final raw = _decrypt(
      await _guardRead(
        'conversations',
        () => _backend.readConversations(userId),
        null,
      ),
    );
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
    await _guardWrite(
      'conversations',
      () => _backend.writeConversations(userId, payload),
    );
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

  /// Every queue row of [userId] across relationships, or null when that
  /// cannot be known for certain: no cache key this session, the in-memory
  /// fallback ([isDegraded]: the disk store's rows are out of sight), an
  /// unreadable store, or any row that does not decrypt or parse. For a
  /// caller that deletes files nothing else references (ChatImagePicker's
  /// stale sweep), where "unknown" must mean "keep everything".
  Future<List<PendingSend>?> readOutboxStrict(String userId) async {
    if (_cipher == null || _degraded) return null;
    try {
      final rows = await _backend.readOutbox(userId);
      final sends = <PendingSend>[];
      for (final row in rows) {
        final payload = _decrypt(row);
        if (payload == null) return null;
        sends.add(
          PendingSend.fromJson(
            Map<String, dynamic>.from(jsonDecode(payload) as Map),
          ),
        );
      }
      return sends;
    } catch (_) {
      return null;
    }
  }

  /// Throws when the row cannot be written — including when there is no
  /// key this session — so the caller's dead-cache path runs.
  Future<void> putOutbox(String userId, PendingSend send) async {
    final payload = _encrypt(jsonEncode(send.toJson()));
    if (payload == null) {
      throw StateError('chat cache has no key this session; outbox unavailable');
    }
    await _backend.putOutbox(
      userId,
      send.relationshipId,
      send.clientMessageId,
      payload,
      send.createdAt.millisecondsSinceEpoch,
    );

    // The row has landed; a failed trim behind it must not read as a failed
    // put (the caller would send the message directly as well).
    await _guardWrite('outbox trim', () async {
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
    });
  }

  Future<void> removeOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
  ) async {
    await _backend.removeOutbox(userId, relationshipId, clientMessageId);
  }

  /// Best-effort per step: one failed delete never leaves the others
  /// undone (a purge is a privacy action — archive, account switch).
  ///
  /// In a degraded session the disk store is purged too if it opens now. If
  /// it still will not open, its rows for this relationship stay on disk
  /// (encrypted) until a later purge — the controller purges again whenever
  /// it next sees the relationship archived — or a sign-out wipe
  /// ([clearAll]) reaches them.
  Future<void> purgeRelationship(String userId, String relationshipId) async {
    await _purgeOn(_backend, userId, relationshipId);
    final disk = _diskBackend;
    if (disk == null) return;
    try {
      await disk.init();
    } catch (error) {
      debugPrint(
        '[chat-cache] disk store still unopenable; purge left for later '
        '(${error.runtimeType})',
      );
      return;
    }
    await _purgeOn(disk, userId, relationshipId);
  }

  Future<void> _purgeOn(
    ChatCacheBackend backend,
    String userId,
    String relationshipId,
  ) async {
    await _guardWrite(
      'purge messages',
      () => backend.deleteMessages(userId, relationshipId),
    );
    await _guardWrite(
      'purge outbox',
      () => backend.purgeOutboxForRelationship(userId, relationshipId),
    );
    await _guardWrite(
      'purge draft',
      () => backend.clearDraft(userId, relationshipId),
    );
    await _guardWrite(
      'purge cursor',
      () => backend.clearSyncCursor(userId, relationshipId),
    );
  }

  /// The server-only changes-since cursor for this (user, relationship): the
  /// (server `updated_at`, id) of the newest change a changes-since read has
  /// applied. Persisted so a cold start resumes from it instead of
  /// re-seeding. Stored plain: a timestamp and a row id, not content. [id]
  /// is null for a seeded cursor and for rows written before it existed.
  Future<({DateTime at, String? id})?> readSyncCursor(
    String userId,
    String relationshipId,
  ) async {
    // Unreadable reads as "no cursor", like a cache from before the cursor
    // existed: the controller re-seeds from its first page.
    final stored = await _guardRead(
      'sync cursor',
      () => _backend.readSyncCursor(userId, relationshipId),
      null,
    );
    if (stored == null) return null;
    return (
      at: DateTime.fromMicrosecondsSinceEpoch(stored.micros),
      id: stored.id,
    );
  }

  /// A failed write leaves the persisted cursor behind, never ahead: the
  /// next cold start over-reads. With no key nothing is written: the rows
  /// it would cover are not being persisted either.
  Future<void> writeSyncCursor(
    String userId,
    String relationshipId,
    DateTime at, {
    String? id,
  }) async {
    if (_cipher == null) return;
    await _guardWrite(
      'sync cursor',
      () => _backend.writeSyncCursor(
        userId,
        relationshipId,
        at.microsecondsSinceEpoch,
        id,
      ),
    );
  }

  Future<String> readDraft(String userId, String relationshipId) async {
    return _decrypt(
          await _guardRead(
            'draft',
            () => _backend.readDraft(userId, relationshipId),
            null,
          ),
        ) ??
        '';
  }

  Future<void> writeDraft(
    String userId,
    String relationshipId,
    String draft,
  ) async {
    final normalized = draft.trimRight();
    if (normalized.isEmpty) {
      await _guardWrite(
        'draft',
        () => _backend.clearDraft(userId, relationshipId),
      );
      return;
    }
    final payload = _encrypt(normalized);
    if (payload == null) return;
    await _guardWrite(
      'draft',
      () => _backend.writeDraft(userId, relationshipId, payload),
    );
  }

  Future<void> clearDraft(String userId, String relationshipId) async {
    await _guardWrite(
      'draft',
      () => _backend.clearDraft(userId, relationshipId),
    );
  }

  /// Sign-out: nothing of this account may stay on disk to be read or
  /// flushed after a later sign-in. Never throws.
  ///
  /// - Healthy: the rows are deleted. If that fails, the store itself is
  ///   deleted (or marked for wipe on the next open) and a fresh one is
  ///   opened for the rest of the session.
  /// - Degraded: the memory session is cleared and the disk file this
  ///   session fell back from is deleted, or marked for wipe on the next
  ///   open when it cannot be deleted now.
  Future<void> clearAll() async {
    // Bounded: sign-out runs inside the auth lock and must never hang on a
    // slow or still-opening cache. One clear at a time; a later call joins
    // the one in flight instead of starting a second recovery.
    final clearing = _clearFlight ??= _clearAll().whenComplete(
      () => _clearFlight = null,
    );
    try {
      await clearing.timeout(_clearAllBound);
    } catch (error) {
      debugPrint(
        '[chat-cache] sign-out wipe unfinished (${error.runtimeType}); '
        'owed to the next open',
      );
      await _markForWipe(_diskBackend ?? _backend);
    }
  }

  Future<void>? _clearFlight;

  Future<void> _clearAll() async {
    // An init still running (main()'s bound fired) finishes first, so the
    // wipe below never races it into a second recovery.
    final opening = _initFlight;
    if (opening != null) await opening;
    final disk = _diskBackend;
    if (disk != null) {
      await _guardWrite('clear', _backend.clearAll);
      await _wipeDiskStore(disk);
      return;
    }
    try {
      await _backend.clearAll();
      return;
    } catch (error) {
      debugPrint('[chat-cache] clear write failed (${error.runtimeType})');
    }
    await _wipeDiskStore(_backend);
    await _openBackendWithRecovery();
  }

  Future<void> _wipeDiskStore(ChatCacheBackend disk) async {
    try {
      await disk.reset();
      return;
    } catch (error) {
      debugPrint(
        '[chat-cache] disk store could not be deleted '
        '(${error.runtimeType}); marking it for wipe on next open',
      );
    }
    await _markForWipe(disk);
  }

  /// Bounded too: the marker write waits on the platform directory call.
  Future<void> _markForWipe(ChatCacheBackend disk) async {
    try {
      await disk.requestWipeOnNextOpen().timeout(_clearAllBound);
    } catch (error) {
      ChatLog.d(
        '[CHAT] cache wipe could not be scheduled '
        '(${error.runtimeType})',
      );
    }
  }
}
