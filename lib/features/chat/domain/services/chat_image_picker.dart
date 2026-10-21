import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/core/services/storage/backup_exclusion.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Writes a JPEG of the image at `sourcePath` to `jpegPath`; true on success.
typedef ChatPickToJpeg =
    Future<bool> Function(String sourcePath, String jpegPath);

/// Why a pick could not be staged. Content-free, for the composer's copy.
enum ChatImagePickFailure { accessDenied, unreadable }

/// The only error [ChatImagePicker.pickFromGallery] throws. Any file it had
/// staged is already deleted.
class ChatImagePickException implements Exception {
  const ChatImagePickException(this.failure);
  final ChatImagePickFailure failure;

  @override
  String toString() => 'ChatImagePickException(${failure.name})';
}

/// Picks a photo for chat at FULL resolution and stages it in a chat-owned
/// folder.
///
/// Deliberately not `ImagePickerService`: that picker re-encodes at
/// 1024 px / q85, crops, then compresses to a 500 px SHORT edge and copies
/// every pick into Documents/shop_images for good (chat review #20, #27).
/// Here the OS hands over the original bytes and `ChatImagePreparer` is the
/// single resize (1600 long edge) + EXIF strip + encode pass (a HEIC/HEIF
/// original is first converted to a full-size JPEG it can read).
///
/// The staged copy lives under Application Support/chat_picks — not the OS
/// temp or cache dir, which the system may empty while a send still waits
/// for preparation (a restart mid-prepare would then fail media_missing).
/// The controller deletes it once preparation has produced the upload file,
/// when a failed send is removed, and on a purge ([discard]); the caption
/// screen's back-out deletes it too. Anything older than [staleAfter] is
/// swept on the next pick: preparation needs no network and runs right
/// after send, so only an orphan (the app killed on the caption screen) or
/// a permanently failed row nobody removed lives that long.
class ChatImagePicker {
  ChatImagePicker({
    ImagePicker? picker,
    Future<Directory> Function()? stagingDirectory,
    bool? isIOS,
    ChatPickToJpeg? toJpeg,
    DateTime Function()? clock,
    Future<Set<String>?> Function()? referencedPaths,
    @visibleForTesting Duration? stagingWipeBound,
    @visibleForTesting Future<void> Function(Directory folder)? deleteFolder,
  }) : _referencedPaths = referencedPaths,
       _stagingWipeBound = stagingWipeBound ?? defaultStagingWipeBound,
       _deleteFolder = deleteFolder ?? _deleteFolderRecursively,
       _picker = picker ?? ImagePicker(),
       _stagingDirectory = stagingDirectory ?? getApplicationSupportDirectory,
       _isIOS = isIOS ?? Platform.isIOS,
       _toJpeg = toJpeg ?? nativeToJpeg,
       _clock = clock ?? DateTime.now;

  final ImagePicker _picker;
  final Future<Directory> Function() _stagingDirectory;
  final bool _isIOS;
  final ChatPickToJpeg _toJpeg;
  final DateTime Function() _clock;

  /// Every staged path a queue row still needs (source, upload, poster), or
  /// null when that cannot be known — then nothing is swept. Without it
  /// (a picker built outside the provider) the sweep never runs.
  final Future<Set<String>?> Function()? _referencedPaths;

  static const String folderName = 'chat_picks';

  /// Left in the staging root while a sign-out wipe ([wipeStaging]) runs:
  /// one cut off by its bound is finished by the next use
  /// ([finishOwedWipe]).
  static const String stagingWipeMarkerName = 'chat_staging.wipe';

  /// How long [wipeStaging] may hold a sign-out (like the chat cache's).
  static const Duration defaultStagingWipeBound = Duration(seconds: 3);

  final Duration _stagingWipeBound;
  final Future<void> Function(Directory folder) _deleteFolder;

  static Future<void> _deleteFolderRecursively(Directory folder) async {
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  /// Sign-out (I1): every staged pick and prepared upload goes, wholesale.
  /// The queue rows are wiped in the same step, so nothing references them
  /// — and a photo waiting offline on its retry timer has no live
  /// controller to purge it. Never throws; holds the caller at most
  /// [defaultStagingWipeBound]. The marker is written first: a wipe cut off
  /// by the bound (or by the process dying) is finished by the next use.
  Future<void> wipeStaging() async {
    try {
      await _singleFlight(_wipeStaging).timeout(_stagingWipeBound);
    } catch (error) {
      ChatLog.diagnostic(
        'staging wipe unfinished on sign-out; owed to the next use',
        error,
      );
    }
  }

  /// The one wipe pass in flight (N1). [wipeStaging] and [finishOwedWipe]
  /// share it: a pass cut off by its bound keeps running, and a second one
  /// beside it could delete what the next person has just staged.
  static Future<void>? _wiping;

  /// A fresh process has no wipe in flight (tests model the next launch).
  @visibleForTesting
  static void debugForgetInFlightWipe() => _wiping = null;

  /// [pass] through the shared slot; never throws.
  static Future<void> _singleFlight(Future<void> Function() pass) {
    final running = _wiping;
    if (running != null) return running;
    late final Future<void> started;
    started = pass()
        .catchError((Object error) {
          ChatLog.diagnostic('staging wipe pass failed (non-fatal)', error);
        })
        .whenComplete(() {
          if (identical(_wiping, started)) _wiping = null;
        });
    return _wiping = started;
  }

  Future<void> _wipeStaging() async {
    final root = await _stagingRoot();
    final marker = File(p.join(root, stagingWipeMarkerName));
    await marker.create(recursive: true);
    await _deleteStagingFolders(root);
    await marker.delete();
  }

  /// Finishes a sign-out wipe that was cut off ([wipeStaging]); no-op when
  /// none is owed. Runs before anything new is staged ([_ownedFolder]) and
  /// when a chat opens. Waits for a wipe still in flight first. Never throws.
  Future<void> finishOwedWipe() async {
    try {
      // Joins a pass already in flight (no timer of its own: the pass is
      // the bounded thing), then checks the marker through the same slot.
      final running = _wiping;
      if (running != null) await running;
      await _singleFlight(_finishOwed);
    } catch (error) {
      ChatLog.diagnostic('owed staging wipe failed (non-fatal)', error);
    }
  }

  Future<void> _finishOwed() async {
    final root = await _stagingRoot();
    final marker = File(p.join(root, stagingWipeMarkerName));
    if (!await marker.exists()) return;
    await _deleteStagingFolders(root);
    await marker.delete();
  }

  Future<String> _stagingRoot() async {
    final root = p.normalize((await _stagingDirectory()).path);
    _stagingRoots.add(root);
    return root;
  }

  Future<void> _deleteStagingFolders(String root) async {
    for (final name in const [folderName, preparedFolderName]) {
      await _deleteFolder(Directory(p.join(root, name)));
    }
  }

  /// Sibling of [folderName]: ChatImagePreparer's upload files for chat
  /// sends ([preparedDirectory]). Same ownership, cleanup and sweep rules.
  static const String preparedFolderName = 'chat_prepared';
  static const Duration staleAfter = Duration(days: 7);

  /// Null when the person backed out of the OS picker (or it was already
  /// open). Throws only [ChatImagePickException], with nothing left staged.
  Future<String?> pickFromGallery() async {
    final XFile? picked;
    try {
      picked = await _pickOriginal();
    } on PlatformException catch (error) {
      // A second tap while the system picker is still coming up: the
      // first call is showing it, so there is nothing to tell the person.
      if (error.code == 'already_active') return null;
      throw ChatImagePickException(
        error.code.contains('access_denied')
            ? ChatImagePickFailure.accessDenied
            : ChatImagePickFailure.unreadable,
      );
    } catch (_) {
      throw const ChatImagePickException(ChatImagePickFailure.unreadable);
    }
    if (picked == null) return null;

    String? target;
    try {
      final dir = await _ownedFolder(folderName);
      // The uploads folder is swept where it is, never created by a pick.
      await _sweepStale([
        dir,
        Directory(p.join(p.dirname(dir.path), preparedFolderName)),
      ]);
      final extension = p.extension(picked.path);
      target = p.join(
        dir.path,
        'pick_${_clock().microsecondsSinceEpoch}'
        '${extension.isEmpty ? '.jpg' : extension}',
      );
      await picked.saveTo(target);
      // A copy may carry the source's timestamp; the sweep ages from now.
      await File(target).setLastModified(_clock());
      if (await File(target).length() <= 0) {
        throw const FileSystemException('empty pick');
      }
      await _dropPluginCopy(picked.path, target);
      return await _asPreparable(target);
    } catch (_) {
      if (target != null) await _deleteQuietly(target);
      await _dropPluginCopy(picked.path, target);
      throw const ChatImagePickException(ChatImagePickFailure.unreadable);
    }
  }

  Future<XFile?> _pickOriginal() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      // No maxWidth / maxHeight: either makes the plugin scale before the
      // preparer sees the bytes. Android then hands over the untouched
      // original (image_picker_android skips its ImageResizer entirely
      // when nothing is set; the preparer bakes the EXIF orientation).
      // iOS ALWAYS re-encodes through UIImage — HEIC and all become JPEG
      // — at quality 1.0 when none is given, where a 24 MP shot lands
      // near the preparer's 25 MB source cap; 92 is visually lossless at
      // the 1600 px output and a third of the bytes. Not on Android: a
      // quality there switches the resizer on.
      imageQuality: _isIOS ? 92 : null,
      requestFullMetadata: false,
    );
  }

  /// The plugin's own temp copy is ours to drop once staged (or failed).
  static Future<void> _dropPluginCopy(String pluginPath, String? target) async {
    if (pluginPath == target) return;
    await _deleteQuietly(pluginPath);
  }

  Future<void> _sweepStale(List<Directory> dirs) async {
    final Set<String> keep;
    try {
      final referenced = await _referencedPaths?.call();
      if (referenced == null) return; // unknown: keep everything
      keep = {for (final path in referenced) p.normalize(path)};
    } catch (_) {
      return;
    }
    final cutoff = _clock().subtract(staleAfter);
    for (final dir in dirs) {
      try {
        if (!await dir.exists()) continue;
        await for (final entry in dir.list()) {
          if (entry is! File || keep.contains(p.normalize(entry.path))) {
            continue;
          }
          try {
            if ((await entry.lastModified()).isBefore(cutoff)) {
              await entry.delete();
            }
          } catch (_) {
            // One unreadable entry never blocks a pick.
          }
        }
      } catch (_) {
        // Best effort: the sweep is housekeeping, not part of the pick.
      }
    }
  }

  /// JPEG, PNG and WebP go to the preparer untouched (its pass is the one
  /// encode). Anything else — an Android HEIC/HEIF original, which the
  /// plugin hands over as-is when no size or quality is set; a GIF — is
  /// converted to a full-size JPEG first, as WhatsApp does. The preparer
  /// still strips EXIF/GPS afterwards. If the platform cannot decode it,
  /// the original goes on and the preparer rejects it as unsupported.
  Future<String> _asPreparable(String staged) async {
    if (ChatImagePreparer.acceptsHeader(await _header(staged))) return staged;
    final jpegPath = p.join(
      p.dirname(staged),
      '${p.basenameWithoutExtension(staged)}_converted.jpg',
    );
    var converted = false;
    try {
      converted =
          await _toJpeg(staged, jpegPath) &&
          await File(jpegPath).exists() &&
          await File(jpegPath).length() > 0;
    } catch (_) {
      converted = false;
    }
    if (!converted) {
      await _deleteQuietly(jpegPath);
      return staged;
    }
    await _deleteQuietly(staged);
    return jpegPath;
  }

  static Future<Uint8List> _header(String path) async {
    final file = await File(path).open();
    try {
      return await file.read(16);
    } finally {
      await file.close();
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort; the next pick's stale sweep retries it.
    }
  }

  /// Decodes [sourcePath] natively (Android BitmapFactory, HEIF from
  /// API 28; iOS UIImage) and writes a full-size JPEG to [jpegPath], with
  /// the EXIF orientation baked in and no EXIF kept. flutter_image_compress
  /// never upscales (Android scale = max(1, min(w/minW, h/minH)); iOS
  /// fminf(1, …)), so a bound no photo reaches keeps every pixel — its
  /// 1920x1080 default would cut a 12 MP shot down before the preparer
  /// (#20). False when the platform cannot decode the source.
  static Future<bool> nativeToJpeg(String sourcePath, String jpegPath) async {
    final out = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      jpegPath,
      minWidth: _noDownscale,
      minHeight: _noDownscale,
      quality: 92,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    return out != null;
  }

  static const int _noDownscale = 1 << 16;

  /// True only for files this picker staged. A path handed to
  /// `sendImageMessage` by another feature (a place photo, a share) is never
  /// deleted by chat.
  ///
  /// Rooted: [path] must be absolute, must not climb (`..`), and its parent
  /// must be exactly `chat_picks` or `chat_prepared` under a staging root
  /// this process resolved (Application Support in production). A matching
  /// folder name anywhere else is not enough.
  static bool ownsPath(String? path) {
    if (path == null || path.isEmpty || !p.isAbsolute(path)) return false;
    if (p.split(path).contains('..')) return false;
    final parent = p.dirname(p.normalize(path));
    for (final root in _stagingRoots) {
      if (parent == p.join(root, folderName) ||
          parent == p.join(root, preparedFolderName)) {
        return true;
      }
    }
    return false;
  }

  /// Staging roots resolved this process: production's Application Support
  /// (learned by any pick, [preparedDirectory] or [discard]) and a test's
  /// injected one.
  static final Set<String> _stagingRoots = {};

  static Future<void> _learnDefaultRoot() async {
    try {
      _stagingRoots.add(
        p.normalize((await getApplicationSupportDirectory()).path),
      );
    } catch (_) {
      // No path_provider (a bare test host): only injected roots count.
    }
  }

  /// [name] under the staging root, created, remembered as owned, and kept
  /// out of the iOS backup (best effort, never awaited by a pick).
  Future<Directory> _ownedFolder(String name) async {
    // A sign-out wipe still owed goes first: nothing new is ever staged
    // beside the previous person's files, or deleted with them.
    await finishOwedWipe();
    final root = await _stagingRoot();
    final dir = Directory(p.join(root, name));
    await dir.create(recursive: true);
    unawaited(BackupExclusion.exclude(dir.path));
    return dir;
  }

  /// Where ChatImagePreparer writes a chat send's upload file: durable like
  /// the picks, so a photo queued offline for days still uploads after the
  /// OS empties its temp dir. Deleted on acknowledgement (once promoted to
  /// the media cache), with a removed failed message, on a purge, or by the
  /// stale sweep.
  Future<Directory> preparedDirectory() => _ownedFolder(preparedFolderName);

  /// Deletes a staged pick. No-op for paths chat does not own.
  static Future<void> discard(String? path) async {
    if (path == null) return;
    await _learnDefaultRoot();
    if (!ownsPath(path)) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort; the next pick's stale sweep retries it.
    }
  }
}

final chatImagePickerProvider = Provider<ChatImagePicker>(
  (ref) => ChatImagePicker(
    referencedPaths: () async {
      // No account: whose queue would it be? Skip rather than guess.
      final user = ref.read(currentUserProvider);
      if (user == null) return null;
      final rows = await ref
          .read(chatCacheServiceProvider)
          .readOutboxStrict(user.id);
      if (rows == null) return null;
      return {
        for (final row in rows) ...[
          if (row.localMediaPath != null) row.localMediaPath!,
          if (row.localThumbnailPath != null) row.localThumbnailPath!,
        ],
      };
    },
  ),
);
