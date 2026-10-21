import 'dart:async';
import 'dart:io';

import 'package:attune/core/services/storage/backup_exclusion.dart';
import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'chat_cache_backend_base.dart';

class _ChatDriftDatabase extends GeneratedDatabase {
  _ChatDriftDatabase(super.executor);

  @override
  final List<TableInfo<Table, Object?>> allTables = const [];

  @override
  int get schemaVersion => 1;
}

class _DriftChatCacheBackend implements ChatCacheBackend {
  _DriftChatCacheBackend({Future<void> Function(File file)? deleteFile})
    : _deleteFile = deleteFile ?? _delete;

  static Future<void> _delete(File file) => file.delete();

  /// Test seam: how a store file is deleted (a test makes it fail).
  final Future<void> Function(File file) _deleteFile;
  _ChatDriftDatabase? _db;

  _ChatDriftDatabase get _database {
    final db = _db;
    if (db == null) throw StateError('Chat cache backend not initialized.');
    return db;
  }

  static const _fileName = 'attune_chat_cache.sqlite';

  @override
  Future<void> init() async {
    // A second init (the recovery retry, or a re-init) never leaks or
    // fights the previous connection.
    await _closeQuietly();
    try {
      await _open();
    } catch (error) {
      // A half-opened handle must not hold the file while reset() deletes
      // it, nor linger after the service falls back to memory.
      await _closeQuietly();
      throw ChatCacheOpenException(classifyChatCacheOpenFailure(error), error);
    }
  }

  Future<void> _closeQuietly() async {
    final db = _db;
    _db = null;
    if (db == null) return;
    try {
      await db.close();
    } catch (_) {
      // A handle that will not close is exactly the case being recovered
      // from; dropping the reference is all that is left to do.
    }
  }

  @override
  Future<void> reset() async {
    // The files go regardless of whether the handle closes.
    await _closeQuietly();
    final directory = await getApplicationSupportDirectory();
    await _deleteStoreFiles(directory.path);
  }

  @override
  Future<void> requestWipeOnNextOpen() async {
    final directory = await getApplicationSupportDirectory();
    await File(_markerPath(directory.path)).writeAsString('', flush: true);
  }

  String _markerPath(String directory) => p.join(directory, '$_fileName.wipe');

  /// Tries every store file, then throws the first failure if any.
  Future<void> _deleteStoreFiles(String directory) async {
    Object? failure;
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File(p.join(directory, '$_fileName$suffix'));
      try {
        if (await file.exists()) await _deleteFile(file);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }

  // SQLite runs on a background isolate (createInBackground): a slow or
  // stuck statement never holds the UI isolate's event loop, so the
  // service's and main()'s timeouts really bound the open (final-review M8).
  // Errors cross back wrapped in DriftRemoteException, which
  // [classifyChatCacheOpenFailure] unwraps.
  Future<void> _open() async {
    final directory = await getApplicationSupportDirectory();
    await Directory(directory.path).create(recursive: true);
    // A sign-out wipe that could not run last session (I1): delete before
    // anything is read. If that fails, so does the open — the old store is
    // never used.
    final marker = File(_markerPath(directory.path));
    final owedWipe = await marker.exists();
    if (owedWipe) await _deleteStoreFiles(directory.path);
    final file = File(p.join(directory.path, _fileName));
    _db = _ChatDriftDatabase(NativeDatabase.createInBackground(file));
    await _database.customStatement('PRAGMA journal_mode = WAL');
    await _database.customStatement('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        user_id TEXT NOT NULL,
        relationship_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, relationship_id)
      )
    ''');
    await _database.customStatement('''
      CREATE TABLE IF NOT EXISTS chat_conversations (
        user_id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await _database.customStatement('''
      CREATE TABLE IF NOT EXISTS chat_outbox (
        user_id TEXT NOT NULL,
        relationship_id TEXT NOT NULL,
        client_message_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, relationship_id, client_message_id)
      )
    ''');
    await _database.customStatement('''
      CREATE TABLE IF NOT EXISTS chat_drafts (
        user_id TEXT NOT NULL,
        relationship_id TEXT NOT NULL,
        draft TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, relationship_id)
      )
    ''');
    // CREATE IF NOT EXISTS on every init, like the tables above: an existing
    // install gains the table without a schema-version bump.
    await _database.customStatement('''
      CREATE TABLE IF NOT EXISTS chat_sync_cursors (
        user_id TEXT NOT NULL,
        relationship_id TEXT NOT NULL,
        cursor_micros INTEGER NOT NULL,
        cursor_id TEXT,
        PRIMARY KEY (user_id, relationship_id)
      )
    ''');
    // A table created before cursor_id existed gains it; its rows read as
    // a timestamp-only cursor.
    final cursorColumns =
        await _database
            .customSelect('PRAGMA table_info(chat_sync_cursors)')
            .get();
    if (!cursorColumns.any((c) => c.read<String>('name') == 'cursor_id')) {
      await _database.customStatement(
        'ALTER TABLE chat_sync_cursors ADD COLUMN cursor_id TEXT',
      );
    }
    // A marker that cannot be removed fails the open: a store wiped on
    // every launch would silently drop the next account's queue each time.
    if (owedWipe) await _deleteFile(marker);
    // iOS backs up Application Support: keep the store out of device and
    // iCloud backups (Android: backup_rules.xml). Defence in depth — the
    // payloads are already encrypted. Best effort, never part of the open;
    // re-sent on every open because a reset recreates the files.
    for (final suffix in const ['', '-wal', '-shm']) {
      final path = p.join(directory.path, '$_fileName$suffix');
      if (File(path).existsSync()) {
        unawaited(BackupExclusion.exclude(path, once: false));
      }
    }
  }

  @override
  Future<String?> readMessages(String userId, String relationshipId) async {
    final row =
        await _database
            .customSelect(
              'SELECT payload FROM chat_messages WHERE user_id = ? AND relationship_id = ? LIMIT 1',
              variables: [Variable(userId), Variable(relationshipId)],
            )
            .getSingleOrNull();
    return row?.read<String>('payload');
  }

  @override
  Future<void> writeMessages(
    String userId,
    String relationshipId,
    String payload,
  ) => _database.customStatement(
    '''INSERT INTO chat_messages (user_id, relationship_id, payload, updated_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(user_id, relationship_id) DO UPDATE SET
         payload = excluded.payload, updated_at = excluded.updated_at''',
    [userId, relationshipId, payload, DateTime.now().millisecondsSinceEpoch],
  );

  @override
  Future<void> deleteMessages(String userId, String relationshipId) =>
      _database.customStatement(
        'DELETE FROM chat_messages WHERE user_id = ? AND relationship_id = ?',
        [userId, relationshipId],
      );

  @override
  Future<String?> readConversations(String userId) async {
    final row =
        await _database
            .customSelect(
              'SELECT payload FROM chat_conversations WHERE user_id = ? LIMIT 1',
              variables: [Variable(userId)],
            )
            .getSingleOrNull();
    return row?.read<String>('payload');
  }

  @override
  Future<void> writeConversations(String userId, String payload) =>
      _database.customStatement(
        '''INSERT INTO chat_conversations (user_id, payload, updated_at)
           VALUES (?, ?, ?)
           ON CONFLICT(user_id) DO UPDATE SET
             payload = excluded.payload, updated_at = excluded.updated_at''',
        [userId, payload, DateTime.now().millisecondsSinceEpoch],
      );

  @override
  Future<List<String>> readOutbox(
    String userId, {
    String? relationshipId,
  }) async {
    final query =
        relationshipId == null
            ? 'SELECT payload FROM chat_outbox WHERE user_id = ? ORDER BY created_at ASC'
            : 'SELECT payload FROM chat_outbox WHERE user_id = ? AND relationship_id = ? ORDER BY created_at ASC';
    final variables = <Variable<Object>>[
      Variable(userId),
      if (relationshipId != null) Variable(relationshipId),
    ];
    final rows =
        await _database.customSelect(query, variables: variables).get();
    return rows.map((row) => row.read<String>('payload')).toList();
  }

  @override
  Future<void> putOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
    String payload,
    int createdAtMillis,
  ) => _database.customStatement(
    '''INSERT INTO chat_outbox (
         user_id, relationship_id, client_message_id, payload, created_at
       ) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(user_id, relationship_id, client_message_id) DO UPDATE SET
         payload = excluded.payload, created_at = excluded.created_at''',
    [userId, relationshipId, clientMessageId, payload, createdAtMillis],
  );

  @override
  Future<void> removeOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
  ) => _database.customStatement(
    '''DELETE FROM chat_outbox
       WHERE user_id = ? AND relationship_id = ? AND client_message_id = ?''',
    [userId, relationshipId, clientMessageId],
  );

  @override
  Future<List<({String relationshipId, String clientMessageId})>> oldestOutbox(
    String userId,
    int limit,
  ) async {
    final rows =
        await _database
            .customSelect(
              '''SELECT relationship_id, client_message_id FROM chat_outbox
         WHERE user_id = ? ORDER BY created_at ASC LIMIT ?''',
              variables: [Variable(userId), Variable(limit)],
            )
            .get();
    return rows
        .map(
          (row) => (
            relationshipId: row.read<String>('relationship_id'),
            clientMessageId: row.read<String>('client_message_id'),
          ),
        )
        .toList();
  }

  @override
  Future<void> purgeOutboxForRelationship(
    String userId,
    String relationshipId,
  ) => _database.customStatement(
    'DELETE FROM chat_outbox WHERE user_id = ? AND relationship_id = ?',
    [userId, relationshipId],
  );

  @override
  Future<String?> readDraft(String userId, String relationshipId) async {
    final row =
        await _database
            .customSelect(
              'SELECT draft FROM chat_drafts WHERE user_id = ? AND relationship_id = ? LIMIT 1',
              variables: [Variable(userId), Variable(relationshipId)],
            )
            .getSingleOrNull();
    return row?.read<String>('draft');
  }

  @override
  Future<void> writeDraft(String userId, String relationshipId, String draft) =>
      _database.customStatement(
        '''INSERT INTO chat_drafts (user_id, relationship_id, draft, updated_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(user_id, relationship_id) DO UPDATE SET
         draft = excluded.draft, updated_at = excluded.updated_at''',
        [userId, relationshipId, draft, DateTime.now().millisecondsSinceEpoch],
      );

  @override
  Future<void> clearDraft(String userId, String relationshipId) =>
      _database.customStatement(
        'DELETE FROM chat_drafts WHERE user_id = ? AND relationship_id = ?',
        [userId, relationshipId],
      );

  @override
  Future<({int micros, String? id})?> readSyncCursor(
    String userId,
    String relationshipId,
  ) async {
    final row =
        await _database
            .customSelect(
              'SELECT cursor_micros, cursor_id FROM chat_sync_cursors WHERE user_id = ? AND relationship_id = ? LIMIT 1',
              variables: [Variable(userId), Variable(relationshipId)],
            )
            .getSingleOrNull();
    if (row == null) return null;
    return (
      micros: row.read<int>('cursor_micros'),
      id: row.readNullable<String>('cursor_id'),
    );
  }

  @override
  Future<void> writeSyncCursor(
    String userId,
    String relationshipId,
    int micros,
    String? id,
  ) => _database.customStatement(
    '''INSERT INTO chat_sync_cursors (
         user_id, relationship_id, cursor_micros, cursor_id
       ) VALUES (?, ?, ?, ?)
       ON CONFLICT(user_id, relationship_id) DO UPDATE SET
         cursor_micros = excluded.cursor_micros,
         cursor_id = excluded.cursor_id''',
    [userId, relationshipId, micros, id],
  );

  @override
  Future<void> clearSyncCursor(String userId, String relationshipId) =>
      _database.customStatement(
        'DELETE FROM chat_sync_cursors WHERE user_id = ? AND relationship_id = ?',
        [userId, relationshipId],
      );

  @override
  Future<void> clearAll() async {
    await _database.transaction(() async {
      await _database.customStatement('DELETE FROM chat_messages');
      await _database.customStatement('DELETE FROM chat_conversations');
      await _database.customStatement('DELETE FROM chat_outbox');
      await _database.customStatement('DELETE FROM chat_drafts');
      await _database.customStatement('DELETE FROM chat_sync_cursors');
    });
  }
}

/// Maps an open/first-query failure to what recovery may do with the file,
/// by SQLite primary result code (the low byte, so extended codes such as
/// SQLITE_CORRUPT_VTAB or SQLITE_BUSY_RECOVERY classify with their family).
@visibleForTesting
ChatCacheFailureKind classifyChatCacheOpenFailure(Object error) {
  // A statement on the background isolate fails as a DriftRemoteException
  // around the SqliteException; drift may also wrap it locally.
  var cause = error;
  for (var depth = 0; depth < 4; depth++) {
    if (cause is DriftRemoteException) {
      cause = cause.remoteCause;
    } else if (cause is DriftWrappedException && cause.cause != null) {
      cause = cause.cause!;
    } else {
      break;
    }
  }
  if (cause is! SqliteException) return ChatCacheFailureKind.other;
  switch (cause.extendedResultCode & 0xFF) {
    case 11: // SQLITE_CORRUPT
    case 26: // SQLITE_NOTADB
      return ChatCacheFailureKind.corrupt;
    case 5: // SQLITE_BUSY
    case 6: // SQLITE_LOCKED
      return ChatCacheFailureKind.busy;
    default:
      return ChatCacheFailureKind.other;
  }
}

ChatCacheBackend createBackend() => _DriftChatCacheBackend();

@visibleForTesting
ChatCacheBackend createBackendForTesting({
  Future<void> Function(File file)? deleteFile,
}) => _DriftChatCacheBackend(deleteFile: deleteFile);
