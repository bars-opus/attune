// Runs the real Drift/SQLite backend (chat_cache_backend_io.dart) against a
// real sqlite file in a temp directory — the schema, the in-place upgrade
// steps and the corruption recovery are exercised by SQLite itself, not a
// fake.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:attune/features/chat/data/cache/chat_cache_backend_io.dart'
    as io;
import 'package:attune/features/chat/data/cache/chat_cache_backend_base.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:drift/drift.dart'
    show DriftWrappedException, driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const _fileName = 'attune_chat_cache.sqlite';

class _SupportDirectory extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _SupportDirectory(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// The schema shipped before the sync cursor existed (HEAD before Task 4).
const _preCursorSchema = [
  '''CREATE TABLE chat_messages (
    user_id TEXT NOT NULL, relationship_id TEXT NOT NULL,
    payload TEXT NOT NULL, updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, relationship_id))''',
  '''CREATE TABLE chat_conversations (
    user_id TEXT PRIMARY KEY, payload TEXT NOT NULL,
    updated_at INTEGER NOT NULL)''',
  '''CREATE TABLE chat_outbox (
    user_id TEXT NOT NULL, relationship_id TEXT NOT NULL,
    client_message_id TEXT NOT NULL, payload TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, relationship_id, client_message_id))''',
  '''CREATE TABLE chat_drafts (
    user_id TEXT NOT NULL, relationship_id TEXT NOT NULL,
    draft TEXT NOT NULL, updated_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, relationship_id))''',
];

void main() {
  late Directory dir;
  late String dbPath;

  setUpAll(() {
    // Each test opens the same file from a second backend to model a
    // restart inside one process; production opens one per launch.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    // Failure paths log by design; keep the test output to results.
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = previousDebugPrint);
    dir = await Directory.systemTemp.createTemp('chat_cache_io_test');
    dbPath = p.join(dir.path, _fileName);
    PathProviderPlatform.instance = _SupportDirectory(dir.path);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Opens the file with the sqlite3 package directly — independent of the
  /// backend under test.
  T inspect<T>(T Function(sql.Database db) run) {
    final db = sql.sqlite3.open(dbPath);
    try {
      return run(db);
    } finally {
      db.dispose();
    }
  }

  Set<String> tables() => inspect(
    (db) =>
        db
            .select("SELECT name FROM sqlite_master WHERE type = 'table'")
            .map((r) => r['name'] as String)
            .toSet(),
  );

  List<String> cursorColumns() => inspect(
    (db) =>
        db
            .select('PRAGMA table_info(chat_sync_cursors)')
            .map((r) => r['name'] as String)
            .toList(),
  );

  void createOldDatabase({required bool withCursorTableWithoutId}) {
    inspect((db) {
      for (final statement in _preCursorSchema) {
        db.execute(statement);
      }
      if (withCursorTableWithoutId) {
        db.execute('''CREATE TABLE chat_sync_cursors (
          user_id TEXT NOT NULL, relationship_id TEXT NOT NULL,
          cursor_micros INTEGER NOT NULL,
          PRIMARY KEY (user_id, relationship_id))''');
        db.execute(
          "INSERT INTO chat_sync_cursors VALUES ('user-a', 'rel-1', 1234567)",
        );
      }
      db.execute(
        "INSERT INTO chat_outbox VALUES ('user-a', 'rel-1', 'q-old', 'old-payload', 5)",
      );
      db.execute(
        "INSERT INTO chat_messages VALUES ('user-a', 'rel-1', 'old-history', 5)",
      );
    });
  }

  PendingSend pending(String id) => PendingSend(
    clientMessageId: id,
    relationshipId: 'rel-1',
    senderId: 'user-a',
    text: 'queued',
    createdAt: DateTime(2026, 10, 19, 12),
  );

  test('fresh install: creates every table, WAL, and round-trips', () async {
    expect(File(dbPath).existsSync(), isFalse);
    final backend = io.createBackend();
    await backend.init();

    expect(
      tables(),
      containsAll(<String>[
        'chat_messages',
        'chat_conversations',
        'chat_outbox',
        'chat_drafts',
        'chat_sync_cursors',
      ]),
    );
    expect(cursorColumns(), [
      'user_id',
      'relationship_id',
      'cursor_micros',
      'cursor_id',
    ]);
    expect(
      inspect((db) => db.select('PRAGMA journal_mode').single.values.single),
      'wal',
    );

    await backend.writeMessages('user-a', 'rel-1', 'history');
    await backend.putOutbox('user-a', 'rel-1', 'q2', 'second', 20);
    await backend.putOutbox('user-a', 'rel-1', 'q1', 'first', 10);
    await backend.writeDraft('user-a', 'rel-1', 'draft');
    expect(await backend.readMessages('user-a', 'rel-1'), 'history');
    expect(await backend.readOutbox('user-a'), ['first', 'second']);
    expect(await backend.readDraft('user-a', 'rel-1'), 'draft');
  });

  test('the sync cursor round-trips (with and without an id)', () async {
    final backend = io.createBackend();
    await backend.init();

    expect(await backend.readSyncCursor('user-a', 'rel-1'), isNull);
    await backend.writeSyncCursor('user-a', 'rel-1', 1760000000123456, null);
    expect(await backend.readSyncCursor('user-a', 'rel-1'), (
      micros: 1760000000123456,
      id: null,
    ));
    await backend.writeSyncCursor('user-a', 'rel-1', 1760000000999999, 'm-9');
    expect(await backend.readSyncCursor('user-a', 'rel-1'), (
      micros: 1760000000999999,
      id: 'm-9',
    ));
    expect(
      await backend.readSyncCursor('user-a', 'rel-2'),
      isNull,
      reason: 'cursors are per relationship',
    );

    // Through the service: microsecond precision survives.
    final cache = ChatCacheService.forTesting(backend: backend);
    final at = DateTime.fromMicrosecondsSinceEpoch(1760000001000001);
    await cache.writeSyncCursor('user-a', 'rel-1', at, id: 'm-10');
    final read = await cache.readSyncCursor('user-a', 'rel-1');
    expect(read!.at, at);
    expect(read.id, 'm-10');

    await backend.clearSyncCursor('user-a', 'rel-1');
    expect(await backend.readSyncCursor('user-a', 'rel-1'), isNull);
  });

  test(
    'the queue and cursor survive a restart (a second open of the file)',
    () async {
      final first = ChatCacheService.forTesting(backend: io.createBackend());
      await first.init();
      await first.putOutbox('user-a', pending('q1'));
      await first.writeSyncCursor(
        'user-a',
        'rel-1',
        DateTime.fromMicrosecondsSinceEpoch(42),
        id: 'm-1',
      );

      final second = ChatCacheService.forTesting(backend: io.createBackend());
      await second.init();
      expect(second.isDegraded, isFalse);
      expect((await second.readOutbox('user-a')).single.clientMessageId, 'q1');
      expect((await second.readSyncCursor('user-a', 'rel-1'))!.id, 'm-1');
    },
  );

  test(
    'init twice on one backend closes the stale handle and still works',
    () async {
      final backend = io.createBackend();
      await backend.init();
      await backend.putOutbox('user-a', 'rel-1', 'q1', 'payload', 1);
      await backend.init();
      expect(await backend.readOutbox('user-a'), ['payload']);
    },
  );

  test(
    'upgrade from before the cursor table: gains it, keeps the queue and history',
    () async {
      createOldDatabase(withCursorTableWithoutId: false);
      expect(tables(), isNot(contains('chat_sync_cursors')));

      final backend = io.createBackend();
      await backend.init();

      expect(tables(), contains('chat_sync_cursors'));
      expect(cursorColumns(), contains('cursor_id'));
      expect(await backend.readOutbox('user-a'), ['old-payload']);
      expect(await backend.readMessages('user-a', 'rel-1'), 'old-history');
      expect(await backend.readSyncCursor('user-a', 'rel-1'), isNull);
      await backend.writeSyncCursor('user-a', 'rel-1', 99, 'm-1');
      expect(await backend.readSyncCursor('user-a', 'rel-1'), (
        micros: 99,
        id: 'm-1',
      ));
    },
  );

  test(
    'upgrade from a cursor table without cursor_id: gains the column, old row reads id-less',
    () async {
      createOldDatabase(withCursorTableWithoutId: true);
      expect(cursorColumns(), isNot(contains('cursor_id')));

      final backend = io.createBackend();
      await backend.init();

      expect(cursorColumns(), contains('cursor_id'));
      expect(await backend.readSyncCursor('user-a', 'rel-1'), (
        micros: 1234567,
        id: null,
      ));
      expect(await backend.readOutbox('user-a'), ['old-payload']);
      await backend.writeSyncCursor('user-a', 'rel-1', 7654321, 'm-2');
      expect(await backend.readSyncCursor('user-a', 'rel-1'), (
        micros: 7654321,
        id: 'm-2',
      ));

      // The upgrade step is idempotent: a second launch does not re-ALTER.
      final again = io.createBackend();
      await again.init();
      expect(await again.readSyncCursor('user-a', 'rel-1'), (
        micros: 7654321,
        id: 'm-2',
      ));
    },
  );

  test(
    'a corrupt file (garbage bytes) fails to open, then the service deletes and recreates it',
    () async {
      final random = Random(7);
      File(
        dbPath,
      ).writeAsBytesSync(List<int>.generate(8192, (_) => random.nextInt(256)));
      File('$dbPath-wal').writeAsBytesSync(List<int>.filled(64, 0xAB));

      // The raw backend really fails on this file (this is SQLite's own
      // verdict, not a scripted one).
      await expectLater(io.createBackend().init(), throwsA(anything));

      final cache = ChatCacheService.forTesting(backend: io.createBackend());
      await cache.init(); // must not throw

      expect(cache.isDegraded, isFalse, reason: 'rebuilt on disk, not memory');
      final header = File(dbPath).readAsBytesSync().sublist(0, 15);
      expect(String.fromCharCodes(header), 'SQLite format 3');
      await cache.putOutbox('user-a', pending('q1'));
      expect((await cache.readOutbox('user-a')).single.clientMessageId, 'q1');

      // And the rebuilt file is durable: a restart reads it back.
      final reopened = ChatCacheService.forTesting(backend: io.createBackend());
      await reopened.init();
      expect(
        (await reopened.readOutbox('user-a')).single.clientMessageId,
        'q1',
      );
    },
  );

  group('open-failure classification (SQLite result codes)', () {
    ChatCacheFailureKind kindOf(Object error) =>
        io.classifyChatCacheOpenFailure(error);

    test(
      'corruption: SQLITE_CORRUPT 11, SQLITE_NOTADB 26 and extended codes',
      () {
        expect(
          kindOf(sql.SqliteException(11, 'malformed')),
          ChatCacheFailureKind.corrupt,
        );
        expect(
          kindOf(sql.SqliteException(26, 'not a db')),
          ChatCacheFailureKind.corrupt,
        );
        expect(
          kindOf(sql.SqliteException(267, 'corrupt vtab')),
          ChatCacheFailureKind.corrupt,
        );
        expect(
          kindOf(sql.SqliteException(523, 'corrupt sequence')),
          ChatCacheFailureKind.corrupt,
        );
        expect(
          kindOf(
            DriftWrappedException(
              message: 'wrapped',
              cause: sql.SqliteException(26, 'x'),
            ),
          ),
          ChatCacheFailureKind.corrupt,
        );
      },
    );

    test('busy/locked: SQLITE_BUSY 5, SQLITE_LOCKED 6 and extended codes', () {
      expect(kindOf(sql.SqliteException(5, 'busy')), ChatCacheFailureKind.busy);
      expect(
        kindOf(sql.SqliteException(261, 'busy recovery')),
        ChatCacheFailureKind.busy,
      );
      expect(
        kindOf(sql.SqliteException(517, 'busy snapshot')),
        ChatCacheFailureKind.busy,
      );
      expect(
        kindOf(sql.SqliteException(6, 'locked')),
        ChatCacheFailureKind.busy,
      );
      expect(
        kindOf(sql.SqliteException(262, 'locked sharedcache')),
        ChatCacheFailureKind.busy,
      );
    });

    test('everything else is "other" (never deleted)', () {
      expect(
        kindOf(sql.SqliteException(1, 'schema')),
        ChatCacheFailureKind.other,
      );
      expect(
        kindOf(sql.SqliteException(10, 'ioerr')),
        ChatCacheFailureKind.other,
      );
      expect(
        kindOf(sql.SqliteException(13, 'full')),
        ChatCacheFailureKind.other,
      );
      expect(
        kindOf(sql.SqliteException(14, 'cantopen')),
        ChatCacheFailureKind.other,
      );
      expect(
        kindOf(const FileSystemException('nope')),
        ChatCacheFailureKind.other,
      );
      expect(kindOf(StateError('?')), ChatCacheFailureKind.other);
    });
  });

  test(
    'a store locked by another connection is retried, not deleted: the queue survives',
    () async {
      createOldDatabase(withCursorTableWithoutId: false);
      final holder = sql.sqlite3.open(dbPath)..execute('BEGIN EXCLUSIVE');
      // Released while the service is between retries.
      final release = Timer(const Duration(milliseconds: 150), () {
        holder.execute('COMMIT');
        holder.dispose();
      });
      addTearDown(release.cancel);
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = previousDebugPrint);

      final backend = io.createBackend();
      final cache = ChatCacheService.forTesting(backend: backend);
      await cache.init();
      debugPrint = previousDebugPrint;

      expect(
        logs.where((l) => l.contains('open failed (busy')),
        isNotEmpty,
        reason: 'the first open really hit SQLITE_BUSY: $logs',
      );
      expect(cache.isDegraded, isFalse);
      expect(await backend.readOutbox('user-a'), ['old-payload']);
      expect(await backend.readMessages('user-a', 'rel-1'), 'old-history');
    },
  );

  test(
    'a schema/upgrade failure on a readable file runs on memory and leaves the file and its queue untouched',
    () async {
      createOldDatabase(withCursorTableWithoutId: false);
      // A view where the cursor table should be: CREATE TABLE IF NOT
      // EXISTS sees the name taken and the ALTER step then fails
      // (SQLITE_ERROR) — a readable store whose upgrade cannot run.
      inspect(
        (db) => db.execute(
          'CREATE VIEW chat_sync_cursors AS '
          'SELECT user_id, relationship_id, 0 AS cursor_micros FROM chat_messages',
        ),
      );
      List<String> schema() => inspect(
        (db) =>
            db
                .select(
                  'SELECT type, name, sql FROM sqlite_master ORDER BY name',
                )
                .map((r) => '${r['type']} ${r['name']} ${r['sql']}')
                .toList(),
      );
      final before = schema();

      final cache = ChatCacheService.forTesting(backend: io.createBackend());
      await cache.init(); // must not throw

      expect(cache.isDegraded, isTrue);
      await cache.putOutbox('user-a', pending('session-only'));
      expect(
        (await cache.readOutbox('user-a')).single.clientMessageId,
        'session-only',
      );

      // Reopen the file itself: still there, same schema, queued row
      // intact for the next launch. (The bytes are not identical: the open
      // got as far as switching the journal to WAL before the step failed.)
      expect(File(dbPath).existsSync(), isTrue);
      expect(schema(), before);
      final rows = inspect(
        (db) =>
            db
                .select('SELECT client_message_id, payload FROM chat_outbox')
                .map((r) => '${r['client_message_id']}=${r['payload']}')
                .toList(),
      );
      expect(rows, ['q-old=old-payload']);
    },
  );

  group('sign-out in a degraded session reaches the disk file (I1)', () {
    /// A populated store whose upgrade step fails (see the view test): the
    /// session runs on memory and the file is kept.
    void createUnupgradableDatabase() {
      createOldDatabase(withCursorTableWithoutId: false);
      inspect(
        (db) => db.execute(
          'CREATE VIEW chat_sync_cursors AS '
          'SELECT user_id, relationship_id, 0 AS cursor_micros FROM chat_messages',
        ),
      );
    }

    File marker() => File('$dbPath.wipe');

    test('clearAll deletes the kept file: a reopen has no rows', () async {
      createUnupgradableDatabase();
      final cache = ChatCacheService.forTesting(backend: io.createBackend());
      await cache.init();
      expect(cache.isDegraded, isTrue);

      await cache.clearAll();

      expect(File(dbPath).existsSync(), isFalse);
      final next = io.createBackend();
      await next.init();
      expect(await next.readOutbox('user-a'), isEmpty);
      expect(await next.readMessages('user-a', 'rel-1'), isNull);
    });

    test(
      'a file that cannot be deleted now is wiped by the next open before use',
      () async {
        createUnupgradableDatabase();
        final cache = ChatCacheService.forTesting(
          backend: io.createBackendForTesting(
            deleteFile:
                (file) async =>
                    throw FileSystemException('scripted: locked', file.path),
          ),
        );
        await cache.init();
        expect(cache.isDegraded, isTrue);

        await cache.clearAll(); // must not throw

        expect(File(dbPath).existsSync(), isTrue, reason: 'delete failed');
        expect(marker().existsSync(), isTrue, reason: 'tombstone written');

        // Next launch: the marker is honoured before anything is read.
        final next = ChatCacheService.forTesting(backend: io.createBackend());
        await next.init();
        expect(next.isDegraded, isFalse);
        expect(marker().existsSync(), isFalse);
        expect(await next.readOutbox('user-a'), isEmpty);
        expect(
          inspect(
            (db) =>
                db.select('SELECT COUNT(*) AS n FROM chat_outbox').single['n'],
          ),
          0,
        );
      },
    );

    test(
      'a marker that cannot be removed after the wipe fails the open (no wipe every launch)',
      () async {
        createOldDatabase(withCursorTableWithoutId: false);
        marker().writeAsStringSync('');

        final cache = ChatCacheService.forTesting(
          backend: io.createBackendForTesting(
            deleteFile: (file) async {
              if (file.path.endsWith('.wipe')) {
                throw FileSystemException('scripted: stuck', file.path);
              }
              await file.delete();
            },
          ),
        );
        await cache.init();

        expect(
          cache.isDegraded,
          isTrue,
          reason: 'this session never writes to a store it would wipe again',
        );
        expect(marker().existsSync(), isTrue);
        expect(
          inspect(
            (db) =>
                db.select('SELECT COUNT(*) AS n FROM chat_outbox').single['n'],
          ),
          0,
          reason: 'the owed wipe itself did happen',
        );

        // Once the marker can go, the next launch opens normally.
        final next = ChatCacheService.forTesting(backend: io.createBackend());
        await next.init();
        expect(next.isDegraded, isFalse);
        expect(marker().existsSync(), isFalse);
      },
    );

    test(
      'a marked file that still cannot be deleted is never opened',
      () async {
        createUnupgradableDatabase();
        // The view would fail the upgrade anyway; replace it with a healthy
        // store so "not opened" is what keeps the rows unread.
        inspect((db) => db.execute('DROP VIEW chat_sync_cursors'));
        marker().writeAsStringSync('');

        final cache = ChatCacheService.forTesting(
          backend: io.createBackendForTesting(
            deleteFile:
                (file) async =>
                    throw FileSystemException('scripted: locked', file.path),
          ),
        );
        await cache.init();

        expect(cache.isDegraded, isTrue);
        expect(await cache.readMessages('user-a', 'rel-1'), isEmpty);
        expect(marker().existsSync(), isTrue, reason: 'still owed a wipe');
      },
    );
  });

  test(
    'SQLite runs off the main isolate: a slow statement does not hold the '
    'event loop (final-review M8)',
    () async {
      final backend = io.createBackend();
      await backend.init();
      // A queue big enough that reading it takes SQLite a while.
      inspect((db) {
        db.execute('BEGIN');
        final insert = db.prepare(
          'INSERT INTO chat_outbox VALUES (?, ?, ?, ?, ?)',
        );
        final payload = 'x' * 200;
        for (var i = 0; i < 200000; i++) {
          insert.execute(['user-a', 'rel-1', 'q$i', payload, 200000 - i]);
        }
        insert.dispose();
        db.execute('COMMIT');
      });

      final order = <String>[];
      final read = backend
          .readOutbox('user-a')
          .then((rows) => order.add('query:${rows.length}'));
      Timer(Duration.zero, () => order.add('timer'));
      await read;

      expect(
        order,
        ['timer', 'query:200000'],
        reason:
            'on the main isolate the whole statement runs before any timer '
            'can fire, so no timeout can bound it',
      );
    },
  );

  test(
    'an unusable support directory runs the session on memory, never throws',
    () async {
      // A regular file where the directory should be: create/open fail on
      // both attempts, so the service must fall back.
      final blocker = File(p.join(dir.path, 'not-a-directory'))
        ..writeAsStringSync('x');
      PathProviderPlatform.instance = _SupportDirectory(blocker.path);

      final cache = ChatCacheService.forTesting(backend: io.createBackend());
      await cache.init(); // must not throw

      expect(cache.isDegraded, isTrue);
      await cache.putOutbox('user-a', pending('q1'));
      expect((await cache.readOutbox('user-a')).single.clientMessageId, 'q1');
      expect(blocker.readAsStringSync(), 'x', reason: 'nothing else deleted');
    },
  );
}
