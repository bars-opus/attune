import 'dart:io';

import 'package:attune/core/services/storage/backup_exclusion.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/outbox_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late Directory tmp;
  late List<String> excluded;
  late StoryMediaVault vault;

  setUp(() {
    support = Directory.systemTemp.createTempSync('vault_support');
    tmp = Directory.systemTemp.createTempSync('vault_tmp');
    excluded = [];
    BackupExclusion.debugIsIOS = true;
    BackupExclusion.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, (call) async {
          excluded.add(call.arguments as String);
          return true;
        });
    vault = StoryMediaVault(supportDirectory: () async => support);
  });
  tearDown(() {
    BackupExclusion.debugIsIOS = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, null);
    support.deleteSync(recursive: true);
    tmp.deleteSync(recursive: true);
  });

  File tmpFile(String name) =>
      File(p.join(tmp.path, name))..writeAsBytesSync([1, 2, 3]);

  test(
    'adopt moves both files out of tmp into a per-user, per-story folder',
    () async {
      final media = tmpFile('capture.mp4');
      final thumb = tmpFile('thumb.jpg');
      final stored = await vault.adopt(
        userId: 'u1',
        clientStoryId: 'cid-1',
        mediaPath: media.path,
        thumbnailPath: thumb.path,
      );
      expect(stored.media, 'story_outbox/u1/cid-1/media.mp4');
      expect(stored.thumbnail, 'story_outbox/u1/cid-1/thumb.jpg');
      expect(p.isRelative(stored.media), isTrue);
      expect(media.existsSync(), isFalse, reason: 'moved, not copied');
      expect(File(await vault.resolve(stored.media)).existsSync(), isTrue);
      await pumpEventQueue(); // the exclusion is sent unawaited
      expect(
        await vault.resolve(stored.media),
        p.join(support.path, 'story_outbox/u1/cid-1/media.mp4'),
      );
      expect(
        excluded,
        contains(p.join(support.path, 'story_outbox')),
        reason: 'the folder is kept out of iOS/iCloud backups',
      );
    },
  );

  test('an empty path (no file) stays empty and never asks the platform for '
      'a folder', () async {
    final noPlatform = StoryMediaVault(
      supportDirectory: () async => throw StateError('no path_provider'),
    );
    expect(await noPlatform.resolve(''), '');
    final record = StoryRecordPaths.withPaths(
      outboxRecord(tmp),
      '/tmp/legacy-media.jpg',
      '',
    );
    expect(await noPlatform.resolveRecord(record), same(record));
  });

  test('a legacy absolute path resolves to itself (Review Focus 3)', () async {
    final legacy = tmpFile('old.jpg').path;
    expect(await vault.resolve(legacy), legacy);
  });

  test(
    'deleteFor removes the files and the story folder, never outside it',
    () async {
      final stored = await vault.adopt(
        userId: 'u1',
        clientStoryId: 'cid-2',
        mediaPath: tmpFile('a.jpg').path,
        thumbnailPath: tmpFile('b.jpg').path,
      );
      final record = outboxRecord(tmp, id: 'cid-2');
      final adopted = StoryRecordPaths.withPaths(
        record,
        stored.media,
        stored.thumbnail,
      );
      await vault.deleteFor(adopted);
      expect(
        Directory(p.join(support.path, 'story_outbox/u1/cid-2')).existsSync(),
        isFalse,
      );

      // A legacy record: its absolute files go, nothing else is touched.
      final legacy = outboxRecord(tmp, id: 'cid-3');
      await vault.deleteFor(legacy);
      expect(File(legacy.localMediaPath).existsSync(), isFalse);
      expect(tmp.existsSync(), isTrue);
    },
  );

  test('wipeExcept keeps only the signed-in person\'s folder', () async {
    for (final user in ['u1', 'u2']) {
      await vault.adopt(
        userId: user,
        clientStoryId: 'c',
        mediaPath: tmpFile('$user-m.jpg').path,
        thumbnailPath: tmpFile('$user-t.jpg').path,
      );
    }
    await vault.wipeExcept('u2');
    expect(
      Directory(p.join(support.path, 'story_outbox/u1')).existsSync(),
      isFalse,
    );
    expect(
      Directory(p.join(support.path, 'story_outbox/u2')).existsSync(),
      isTrue,
    );
    await vault.wipeAll();
    expect(
      Directory(p.join(support.path, 'story_outbox')).existsSync(),
      isFalse,
    );
  });

  test('I2: the folder recreated after wipeAll is excluded from backup '
      'again (probe P2)', () async {
    await vault.adopt(
      userId: 'u1',
      clientStoryId: 'a',
      mediaPath: tmpFile('1.jpg').path,
      thumbnailPath: tmpFile('2.jpg').path,
    );
    await pumpEventQueue();
    await vault.wipeAll();
    excluded.clear();
    await vault.adopt(
      userId: 'u2',
      clientStoryId: 'b',
      mediaPath: tmpFile('3.jpg').path,
      thumbnailPath: tmpFile('4.jpg').path,
    );
    await pumpEventQueue();
    expect(excluded, contains(p.join(support.path, 'story_outbox')));
  });

  test('M2: a stored relative path that escapes story_outbox resolves to '
      'no file (probe P4)', () async {
    expect(await vault.resolve('../outside.jpg'), '');
    expect(await vault.resolve('story_outbox/../../outside.jpg'), '');
    expect(await vault.resolve('elsewhere/media.jpg'), '');
    expect(
      await vault.resolve('story_outbox/u1/c/media.jpg'),
      p.join(support.path, 'story_outbox/u1/c/media.jpg'),
    );
  });

  test('M2: deleteFor never deletes a folder above the story level, and '
      'never a file outside the vault', () async {
    final sibling = await vault.adopt(
      userId: 'u1',
      clientStoryId: 'keep',
      mediaPath: tmpFile('k1.jpg').path,
      thumbnailPath: tmpFile('k2.jpg').path,
    );
    final outside = File(p.join(support.path, 'outside.jpg'))
      ..writeAsBytesSync([1]);
    // Malformed: one level short, so its dirname is the user folder.
    final malformed = StoryRecordPaths.withPaths(
      outboxRecord(tmp, id: 'bad'),
      'story_outbox/u1/media.jpg',
      '../outside.jpg',
    );
    await vault.deleteFor(malformed);
    expect(File(await vault.resolve(sibling.media)).existsSync(), isTrue);
    expect(outside.existsSync(), isTrue);
  });

  test('M2: adopt refuses ids that are not single path segments', () async {
    for (final bad in ['', '.', '..', 'a/b', '../x']) {
      await expectLater(
        vault.adopt(
          userId: bad,
          clientStoryId: 'c',
          mediaPath: tmpFile('m.jpg').path,
          thumbnailPath: tmpFile('t.jpg').path,
        ),
        throwsArgumentError,
        reason: 'userId "$bad"',
      );
      await expectLater(
        vault.adopt(
          userId: 'u1',
          clientStoryId: bad,
          mediaPath: tmpFile('m.jpg').path,
          thumbnailPath: tmpFile('t.jpg').path,
        ),
        throwsArgumentError,
        reason: 'clientStoryId "$bad"',
      );
    }
  });

  test('final review #3c: sweepOrphans skips a story still being adopted '
      '(its row is not written yet), then removes it once released with no '
      'row; it never acts on an unreadable answer', () async {
    await vault.adopt(
      userId: 'u1',
      clientStoryId: 'new-1',
      mediaPath: tmpFile('m.jpg').path,
      thumbnailPath: tmpFile('t.jpg').path,
    );
    final folder = Directory(p.join(support.path, 'story_outbox/u1/new-1'));
    await vault.sweepOrphans('u1', () async => <String>{});
    expect(folder.existsSync(), isTrue, reason: 'adopt not yet settled');

    vault.release('new-1');
    await vault.sweepOrphans('u1', () async => null);
    expect(folder.existsSync(), isTrue, reason: 'rows unreadable: no sweep');

    await vault.sweepOrphans('u1', () async => {'new-1'});
    expect(folder.existsSync(), isTrue, reason: 'it has a row');

    await vault.sweepOrphans('u1', () async => <String>{});
    expect(folder.existsSync(), isFalse, reason: 'no row, not adopting');
  });
}
