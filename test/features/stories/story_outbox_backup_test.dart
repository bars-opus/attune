import 'dart:io';

import 'package:attune/core/services/storage/backup_exclusion.dart';
import 'package:attune/features/stories/data/story_outbox_backend_io.dart'
    as io;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late List<String> excluded;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('story_outbox_backup');
    excluded = [];
    BackupExclusion.debugIsIOS = true;
    BackupExclusion.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, (call) async {
          excluded.add(call.arguments as String);
          return true;
        });
  });
  tearDown(() {
    BackupExclusion.debugIsIOS = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, null);
    dir.deleteSync(recursive: true);
  });

  test(
    'opening the outbox keeps its database files out of iOS backups',
    () async {
      final file = File('${dir.path}/attune_story_outbox.sqlite');
      final backend = io.createStoryOutboxBackend(file: file);
      await backend.init();
      await backend.put('u1', 'c1', 'payload', 1);
      await backend.close();
      final reopened = io.createStoryOutboxBackend(file: file);
      await reopened.init();
      await pumpEventQueue();
      expect(excluded, contains(file.path));
      expect(excluded, contains('${file.path}-wal'));
      await reopened.close();
    },
  );
}
