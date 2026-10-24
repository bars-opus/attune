import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/core/services/storage/backup_exclusion.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where a queued story's media waits (spec §6.1: "app-private storage
/// until success or explicit discard"): Application Support, never the
/// purgeable tmp/ the preparers write to (01 #10). Layout:
/// `story_outbox/<userId>/<clientStoryId>/{media.<ext>,thumb.jpg}`.
///
/// Records store paths RELATIVE to Application Support, because the iOS
/// container path changes on an app update. A legacy absolute path (queued
/// by an older build) resolves to itself.
class StoryMediaVault {
  StoryMediaVault({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static const String folderName = 'story_outbox';

  final Future<Directory> Function() _supportDirectory;
  String? _supportPath;

  Future<String> _support() async =>
      _supportPath ??= p.normalize((await _supportDirectory()).path);

  Future<Directory> _root({bool create = false}) async {
    final root = Directory(p.join(await _support(), folderName));
    if (create) {
      await root.create(recursive: true);
      // iOS: Application Support is backed up unless excluded (05 #2).
      // Sent on every adopt, not once per launch: a wipe deletes the
      // folder and its flag with it, and the next adopt recreates it.
      unawaited(BackupExclusion.exclude(root.path, once: false));
    }
    return root;
  }

  /// Stories adopted and not yet [release]d: their row may not be written
  /// yet, so [sweepOrphans] leaves their folders alone.
  final Set<String> _adopting = {};

  /// Moves both files into the story's folder. The caller [release]s
  /// [clientStoryId] once its row is written (or the folder deleted).
  Future<({String media, String thumbnail})> adopt({
    required String userId,
    required String clientStoryId,
    required String mediaPath,
    required String thumbnailPath,
  }) async {
    _checkSegment('userId', userId);
    _checkSegment('clientStoryId', clientStoryId);
    _adopting.add(clientStoryId);
    final root = await _root(create: true);
    final folder = Directory(p.join(root.path, userId, clientStoryId));
    await folder.create(recursive: true);
    final ext =
        p.extension(mediaPath).isEmpty ? '.bin' : p.extension(mediaPath);
    final media = p.join(folder.path, 'media$ext');
    final thumb = p.join(folder.path, 'thumb.jpg');
    await _move(mediaPath, media);
    await _move(thumbnailPath, thumb);
    final support = await _support();
    return (
      media: p.relative(media, from: support),
      thumbnail: p.relative(thumb, from: support),
    );
  }

  /// Each id becomes exactly one folder level under `story_outbox/`.
  static void _checkSegment(String name, String value) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('\\')) {
      throw ArgumentError.value(value, name, 'not a single path segment');
    }
  }

  /// Rename when on the same volume; copy then delete otherwise.
  static Future<void> _move(String from, String to) async {
    try {
      await File(from).rename(to);
    } on FileSystemException {
      await File(from).copy(to);
      try {
        await File(from).delete();
      } catch (_) {}
    }
  }

  /// An absolute (legacy) path passes through, and so does an empty one:
  /// "no file" must not resolve to the Application Support folder itself.
  static bool _passesThrough(String stored) =>
      stored.isEmpty || p.isAbsolute(stored);

  /// A stored relative path must stay inside `story_outbox/`; one that
  /// does not (`../x`, another folder) resolves to `''`, which reads as a
  /// missing file (`media_missing`), so nothing outside the vault is ever
  /// uploaded or deleted through a record.
  Future<String> resolve(String stored) async {
    if (_passesThrough(stored)) return stored;
    final support = await _support();
    final resolved = p.normalize(p.join(support, stored));
    return p.isWithin(p.join(support, folderName), resolved) ? resolved : '';
  }

  Future<StoryOutboxRecord> resolveRecord(StoryOutboxRecord record) async {
    if (_passesThrough(record.localMediaPath) &&
        _passesThrough(record.localThumbnailPath)) {
      return record;
    }
    return StoryRecordPaths.withPaths(
      record,
      await resolve(record.localMediaPath),
      await resolve(record.localThumbnailPath),
    );
  }

  /// The record's thumbnail bytes, for the ring's posted hold (03 M1), or
  /// null when missing, unreadable or over 512 KB. Never throws.
  Future<Uint8List?> readThumbnailBytes(StoryOutboxRecord record) async {
    try {
      final path = await resolve(record.localThumbnailPath);
      if (path.isEmpty) return null;
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.length > 512 * 1024 ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// The record's files and, for a vault record, its story folder. Never
  /// deletes anything outside `story_outbox/` other than the record's own
  /// two legacy files.
  Future<void> deleteFor(StoryOutboxRecord record) async {
    for (final stored in [record.localMediaPath, record.localThumbnailPath]) {
      try {
        final file = File(await resolve(stored));
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (!_passesThrough(record.localMediaPath)) {
      final media = await resolve(record.localMediaPath);
      if (media.isEmpty) return;
      final folder = Directory(p.dirname(media));
      final root = (await _root()).path;
      // Only a story folder: exactly `<userId>/<clientStoryId>` below the
      // root, never a user folder a malformed record points at.
      if (p.isWithin(root, folder.path) &&
          p.split(p.relative(folder.path, from: root)).length == 2) {
        try {
          if (await folder.exists()) await folder.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// The adopt of [clientStoryId] has settled: its row is written, or its
  /// folder was deleted.
  void release(String clientStoryId) => _adopting.remove(clientStoryId);

  /// Deletes [userId]'s story folders that have no row: a kill between
  /// [adopt] and the outbox write leaves plaintext media nothing else
  /// would remove short of a sign-out (final review #3c). [rowIds] answers
  /// null when the rows cannot all be read, and then nothing is deleted.
  /// Folders still being adopted are skipped; the snapshot is taken before
  /// the rows are read, so an adopt that settles in between has its row.
  Future<void> sweepOrphans(
    String userId,
    Future<Set<String>?> Function() rowIds,
  ) async {
    _checkSegment('userId', userId);
    final mine = Directory(p.join((await _root()).path, userId));
    if (!await mine.exists()) return;
    final folders = <Directory>[];
    await for (final entry in mine.list()) {
      if (entry is Directory) folders.add(entry);
    }
    if (folders.isEmpty) return;
    final adopting = {..._adopting};
    final keep = await rowIds();
    if (keep == null) return;
    for (final folder in folders) {
      final id = p.basename(folder.path);
      if (keep.contains(id) ||
          adopting.contains(id) ||
          _adopting.contains(id)) {
        continue;
      }
      try {
        await folder.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> wipeAll() async {
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<void> wipeExcept(String userId) async {
    final root = await _root();
    if (!await root.exists()) return;
    await for (final entry in root.list()) {
      if (entry is Directory && p.basename(entry.path) != userId) {
        try {
          await entry.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}

/// Paths are fixed for a record's life except when the vault resolves or
/// adopts them, so they are not part of `copyWith`.
extension StoryRecordPaths on StoryOutboxRecord {
  static StoryOutboxRecord withPaths(
    StoryOutboxRecord r,
    String media,
    String thumbnail,
  ) => StoryOutboxRecord.fromJson({
    ...r.toJson(),
    'localMediaPath': media,
    'localThumbnailPath': thumbnail,
  });
}

final storyMediaVaultProvider = Provider<StoryMediaVault>(
  (ref) => StoryMediaVault(),
);
