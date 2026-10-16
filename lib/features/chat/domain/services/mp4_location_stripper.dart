import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Removes where a video was recorded from an MP4/MOV, in place.
///
/// Phones write the capture location into the movie header: Android's
/// MediaMuxer as `moov/udta/©xyz`, iPhones as QuickTime metadata
/// (`moov/meta/keys` + `ilst`, key `com.apple.quicktime.location.*`), some
/// encoders as 3GPP `loci`. video_compress keeps them (iOS
/// AVAssetExportSession copies metadata by default).
///
/// Each location atom is renamed `free` and its payload zeroed. Nothing
/// moves, so the file size and every chunk offset (`stco`/`co64`) stay
/// valid. Anything unexpected leaves the file untouched; this never throws
/// and never fails a send.
abstract final class Mp4LocationStripper {
  static const _maxMoovBytes = 16 * 1024 * 1024;

  /// Returns how many location atoms were neutralised.
  static Future<int> strip(File file) async {
    RandomAccessFile? raf;
    try {
      // append mode opens read-write without truncating; writes below go
      // where setPosition puts them.
      raf = await file.open(mode: FileMode.append);
      final length = await raf.length();
      var at = 0;
      while (at + 8 <= length) {
        await raf.setPosition(at);
        final head = await raf.read(16);
        if (head.length < 8) return 0;
        final bd = ByteData.sublistView(Uint8List.fromList(head));
        var size = bd.getUint32(0);
        var header = 8;
        if (size == 1) {
          if (head.length < 16) return 0;
          size = bd.getUint64(8);
          header = 16;
        } else if (size == 0) {
          size = length - at;
        }
        if (size < header || at + size > length) return 0;
        if (_isType(head, 4, 'moov')) {
          if (size > _maxMoovBytes) return 0;
          await raf.setPosition(at);
          final moov = Uint8List.fromList(await raf.read(size));
          final n = _walk(moov, header, size);
          if (n > 0) {
            await raf.setPosition(at);
            await raf.writeFrom(moov);
            await raf.flush();
          }
          return n;
        }
        at += size;
      }
      return 0;
    } catch (_) {
      return 0;
    } finally {
      await raf?.close();
    }
  }

  /// Neutralises location atoms among the boxes in [b].
  static int stripBytes(Uint8List b) => _walk(b, 0, b.length);

  static int _walk(Uint8List b, int start, int end) {
    var n = 0;
    var i = start;
    while (i + 8 <= end) {
      final box = _box(b, i, end);
      if (box == null) break;
      final (size, header) = box;
      if (_isXyz(b, i + 4) || _isType(b, i + 4, 'loci')) {
        _neutralise(b, i, size, header);
        n++;
      } else if (_isType(b, i + 4, 'moov') ||
          _isType(b, i + 4, 'trak') ||
          _isType(b, i + 4, 'udta')) {
        n += _walk(b, i + header, i + size);
      } else if (_isType(b, i + 4, 'meta')) {
        var c = i + header;
        // ISO 'meta' is a full box (4 bytes version/flags); QuickTime's isn't.
        if (_box(b, c, i + size) == null || !_isPrintable(b, c + 4)) c += 4;
        n += _meta(b, c, i + size);
      }
      i += size;
    }
    return n;
  }

  /// Inside a meta box: QuickTime keys/ilst, and ©xyz items in an ilst.
  static int _meta(Uint8List b, int start, int end) {
    final locationKeys = <int>{};
    var n = 0;
    // First pass: which key indices name a location.
    var i = start;
    while (i + 8 <= end) {
      final box = _box(b, i, end);
      if (box == null) return n;
      final (size, header) = box;
      if (_isType(b, i + 4, 'keys')) {
        var k = i + header + 8; // version/flags, entry_count
        var index = 1;
        while (k + 8 <= i + size) {
          final ks = ByteData.sublistView(b, k, k + 4).getUint32(0);
          if (ks < 8 || k + ks > i + size) break;
          final name =
              latin1
                  .decode(b.sublist(k + 8, k + ks), allowInvalid: true)
                  .toLowerCase();
          if (name.contains('location')) locationKeys.add(index);
          index++;
          k += ks;
        }
      }
      i += size;
    }
    // Second pass: neutralise matching ilst items (and any ©xyz item).
    i = start;
    while (i + 8 <= end) {
      final box = _box(b, i, end);
      if (box == null) return n;
      final (size, header) = box;
      if (_isType(b, i + 4, 'ilst')) {
        var j = i + header;
        while (j + 8 <= i + size) {
          final item = _box(b, j, i + size);
          if (item == null) break;
          final (isize, iheader) = item;
          final key = ByteData.sublistView(b, j + 4, j + 8).getUint32(0);
          if (locationKeys.contains(key) || _isXyz(b, j + 4)) {
            _neutralise(b, j, isize, iheader);
            n++;
          }
          j += isize;
        }
      }
      i += size;
    }
    return n;
  }

  /// (size, headerLength) of the box at [i], or null when it doesn't fit.
  static (int, int)? _box(Uint8List b, int i, int end) {
    if (i + 8 > end) return null;
    final bd = ByteData.sublistView(b, i, end);
    var size = bd.getUint32(0);
    var header = 8;
    if (size == 1) {
      if (i + 16 > end) return null;
      size = bd.getUint64(8);
      header = 16;
    } else if (size == 0) {
      size = end - i;
    }
    if (size < header || i + size > end) return null;
    return (size, header);
  }

  static void _neutralise(Uint8List b, int i, int size, int header) {
    b.setRange(i + 4, i + 8, ascii.encode('free'));
    b.fillRange(i + header, i + size, 0);
  }

  static bool _isType(List<int> b, int at, String t) =>
      b.length >= at + 4 &&
      b[at] == t.codeUnitAt(0) &&
      b[at + 1] == t.codeUnitAt(1) &&
      b[at + 2] == t.codeUnitAt(2) &&
      b[at + 3] == t.codeUnitAt(3);

  static bool _isXyz(List<int> b, int at) =>
      b.length >= at + 4 &&
      b[at] == 0xA9 &&
      b[at + 1] == 0x78 &&
      b[at + 2] == 0x79 &&
      b[at + 3] == 0x7A;

  static bool _isPrintable(List<int> b, int at) =>
      b.length >= at + 4 &&
      [
        for (var k = 0; k < 4; k++) b[at + k],
      ].every((c) => c >= 0x20 && c < 0x7F);
}
