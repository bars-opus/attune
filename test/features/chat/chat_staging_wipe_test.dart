// I1: sign-out deletes every staged pick (chat_picks/) and prepared upload
// (chat_prepared/) wholesale — the queue rows are gone, so nothing references
// them — bounded, and owed to the next use when cut off.
import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory support;
  late Directory picks;
  late Directory prepared;

  File seed(Directory dir, String name) =>
      File(p.join(dir.path, name))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);

  File marker() =>
      File(p.join(support.path, ChatImagePicker.stagingWipeMarkerName));

  setUp(() async {
    support = await Directory.systemTemp.createTemp('staging_wipe');
    picks = Directory(p.join(support.path, ChatImagePicker.folderName));
    prepared = Directory(
      p.join(support.path, ChatImagePicker.preparedFolderName),
    );
  });

  tearDown(() async {
    if (await support.exists()) await support.delete(recursive: true);
  });

  List<FileSystemEntity> contents(Directory dir) =>
      dir.existsSync() ? dir.listSync() : const [];

  test('wipes both folders wholesale, fresh files included', () async {
    seed(picks, 'pick_1.jpg');
    seed(picks, 'pick_2_converted.jpg');
    seed(prepared, 'upload_1.jpg');
    final unrelated = seed(support, 'attune_chat_cache.sqlite');

    await ChatImagePicker(stagingDirectory: () async => support).wipeStaging();

    expect(contents(picks), isEmpty);
    expect(contents(prepared), isEmpty);
    expect(marker().existsSync(), isFalse, reason: 'nothing left owed');
    expect(unrelated.existsSync(), isTrue, reason: 'only chat staging goes');
  });

  test('a staging root that never answers does not hold the caller', () async {
    final never = Completer<Directory>();
    final picker = ChatImagePicker(
      stagingDirectory: () => never.future,
      stagingWipeBound: const Duration(milliseconds: 100),
    );
    // The abandoned pass holds the shared slot; let it finish afterwards.
    addTearDown(() async {
      if (!never.isCompleted) never.complete(support);
      await picker.finishOwedWipe(); // joins the abandoned pass
    });
    await picker.wipeStaging().timeout(
      const Duration(seconds: 2),
      onTimeout: () => fail('wipeStaging() held sign-out past its bound'),
    );
  });

  test('a wipe cut off by its bound is finished by the next use, before '
      'anything new is staged', () async {
    final old = seed(prepared, 'upload_old.jpg');
    final oldPick = seed(picks, 'pick_old.jpg');
    final stuck = Completer<void>();
    addTearDown(() {
      if (!stuck.isCompleted) stuck.complete();
    });
    final cutOff = ChatImagePicker(
      stagingDirectory: () async => support,
      stagingWipeBound: const Duration(milliseconds: 100),
      deleteFolder: (_) => stuck.future,
    );
    await cutOff.wipeStaging();
    expect(old.existsSync(), isTrue, reason: 'the delete never ran');
    expect(marker().existsSync(), isTrue, reason: 'the wipe is owed');

    // The next launch's first chat use: preparing a send's upload folder.
    ChatImagePicker.debugForgetInFlightWipe();
    final next = ChatImagePicker(stagingDirectory: () async => support);
    final dir = await next.preparedDirectory();
    expect(old.existsSync(), isFalse);
    expect(oldPick.existsSync(), isFalse);
    expect(marker().existsSync(), isFalse);
    expect(dir.existsSync(), isTrue, reason: 'ready for the new send');
    final fresh = seed(dir, 'upload_new.jpg');
    await next.finishOwedWipe();
    expect(fresh.existsSync(), isTrue, reason: 'paid once, never again');
  });

  test('finishOwedWipe on its own (chat open) pays an owed wipe', () async {
    final old = seed(picks, 'pick_old.jpg');
    marker().writeAsStringSync('');
    await ChatImagePicker(
      stagingDirectory: () async => support,
    ).finishOwedWipe();
    expect(old.existsSync(), isFalse);
    expect(marker().existsSync(), isFalse);
  });

  test('with nothing owed, finishOwedWipe touches nothing', () async {
    final kept = seed(prepared, 'upload_queued.jpg');
    await ChatImagePicker(
      stagingDirectory: () async => support,
    ).finishOwedWipe();
    expect(kept.existsSync(), isTrue);
  });

  test('N1: a slow wipe cut off by its bound never deletes the next '
      "account's first pick", () async {
    seed(picks, 'pick_old.jpg');
    seed(prepared, 'upload_old.jpg');
    final slow = Completer<void>();
    var firstCall = true;
    final cutOff = ChatImagePicker(
      stagingDirectory: () async => support,
      stagingWipeBound: const Duration(milliseconds: 50),
      deleteFolder: (folder) async {
        if (firstCall) {
          firstCall = false;
          await slow.future;
        }
        if (await folder.exists()) await folder.delete(recursive: true);
      },
    );
    await cutOff.wipeStaging();
    // The slow delete finishes well after the next account's first pick.
    Timer(const Duration(milliseconds: 250), slow.complete);

    final next = ChatImagePicker(stagingDirectory: () async => support);
    final dir = await next.preparedDirectory();
    final fresh = seed(dir, 'upload_new.jpg');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(fresh.existsSync(), isTrue, reason: 'the wipe ended before reuse');
    expect(marker().existsSync(), isFalse);
  });

  test('N1: two uses during one wipe run it once', () async {
    seed(picks, 'pick_old.jpg');
    marker().writeAsStringSync('');
    var calls = 0;
    final gate = Completer<void>();
    final picker = ChatImagePicker(
      stagingDirectory: () async => support,
      deleteFolder: (folder) async {
        calls++;
        await gate.future;
        if (await folder.exists()) await folder.delete(recursive: true);
      },
    );
    final a = picker.finishOwedWipe();
    final b = picker.finishOwedWipe();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    gate.complete();
    await Future.wait([a, b]);
    expect(calls, 2, reason: 'one pass = two folders, not four');
  });
}
