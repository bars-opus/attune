import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
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
  _ChatDriftDatabase? _db;

  _ChatDriftDatabase get _database {
    final db = _db;
    if (db == null) throw StateError('Chat cache backend not initialized.');
    return db;
  }

  @override
  Future<void> init() async {
    final directory = await getApplicationSupportDirectory();
    await Directory(directory.path).create(recursive: true);
    final file = File(p.join(directory.path, 'attune_chat_cache.sqlite'));
    _db = _ChatDriftDatabase(NativeDatabase(file));
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
  Future<void> clearAll() async {
    await _database.transaction(() async {
      await _database.customStatement('DELETE FROM chat_messages');
      await _database.customStatement('DELETE FROM chat_conversations');
      await _database.customStatement('DELETE FROM chat_outbox');
      await _database.customStatement('DELETE FROM chat_drafts');
    });
  }
}

ChatCacheBackend createBackend() => _DriftChatCacheBackend();
