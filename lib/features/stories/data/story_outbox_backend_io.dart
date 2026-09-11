import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'story_outbox_backend_base.dart';

/// Same shape as `_ChatDriftDatabase` in `chat_cache_backend_io.dart`: no
/// generated tables, every statement is `customStatement`/`customSelect`.
class _StoryOutboxDriftDatabase extends GeneratedDatabase {
  _StoryOutboxDriftDatabase(super.executor);

  @override
  final List<TableInfo<Table, Object?>> allTables = const [];

  @override
  int get schemaVersion => 1;
}

/// The `dart:io` backend: a Drift-backed SQLite file under the app's
/// support directory, same location and creation pattern as the chat
/// cache's `attune_chat_cache.sqlite` (`chat_cache_backend_io.dart`),
/// so this reuses that file's on-disk conventions (WAL journal mode,
/// `CREATE TABLE IF NOT EXISTS`) without coupling to chat's own
/// `ChatCacheBackend`/database instance — this store has its own
/// connection and its own lifecycle, so a restart test can close and
/// reopen it in isolation.
class _DriftStoryOutboxBackend implements StoryOutboxBackend {
  _DriftStoryOutboxBackend({File? file}) : _fileOverride = file;

  final File? _fileOverride;
  _StoryOutboxDriftDatabase? _db;

  _StoryOutboxDriftDatabase get _database {
    final db = _db;
    if (db == null) {
      throw StateError('Story outbox backend not initialized.');
    }
    return db;
  }

  @override
  Future<void> init() async {
    final file = _fileOverride ?? await _defaultFile();
    await file.parent.create(recursive: true);
    _db = _StoryOutboxDriftDatabase(NativeDatabase(file));
    await _database.customStatement('PRAGMA journal_mode = WAL');
    await _database.customStatement('''
      CREATE TABLE IF NOT EXISTS story_outbox (
        user_id TEXT NOT NULL,
        client_story_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, client_story_id)
      )
    ''');
  }

  static Future<File> _defaultFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'attune_story_outbox.sqlite'));
  }

  @override
  Future<List<String>> readAll(String userId) async {
    final rows =
        await _database
            .customSelect(
              '''SELECT payload FROM story_outbox
                 WHERE user_id = ? ORDER BY created_at ASC''',
              variables: [Variable(userId)],
            )
            .get();
    return rows.map((row) => row.read<String>('payload')).toList();
  }

  @override
  Future<void> put(String userId, String clientStoryId, String payload) =>
      _database.customStatement(
        '''INSERT INTO story_outbox (user_id, client_story_id, payload, created_at)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(user_id, client_story_id) DO UPDATE SET
             payload = excluded.payload''',
        [userId, clientStoryId, payload, DateTime.now().millisecondsSinceEpoch],
      );

  @override
  Future<void> remove(String userId, String clientStoryId) =>
      _database.customStatement(
        'DELETE FROM story_outbox WHERE user_id = ? AND client_story_id = ?',
        [userId, clientStoryId],
      );

  @override
  Future<void> clearAll() =>
      _database.customStatement('DELETE FROM story_outbox');

  @override
  Future<void> close() => _database.close();
}

/// [file] is a test seam: production always uses the default
/// app-support-directory location; a durability test points this at a
/// temp file it controls so it can close and reopen the same file.
StoryOutboxBackend createStoryOutboxBackend({File? file}) =>
    _DriftStoryOutboxBackend(file: file);
