// test/features/chat/mp4_location_stripper_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/chat/domain/services/mp4_location_stripper.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

/// A box: 32-bit size + 4-byte type (a String, or raw bytes for '©xyz').
Uint8List box(Object type, List<int> payload) {
  final t = type is String ? ascii.encode(type) : type as List<int>;
  return Uint8List.fromList([..._u32(8 + payload.length), ...t, ...payload]);
}

const xyz = [0xA9, 0x78, 0x79, 0x7A]; // ©xyz
List<int> str(String s) => utf8.encode(s);

/// Apple's ©xyz payload: 2-byte length, 2-byte language, ISO 6709 text.
List<int> xyzPayload(String iso) => [0, iso.length, 0x15, 0xC7, ...str(iso)];

Uint8List mp4({
  required List<int> moovChildren,
  bool moovFirst = true,
  bool bigMdat = false,
}) {
  final ftyp = box('ftyp', [
    ...str('isom'),
    0,
    0,
    2,
    0,
    ...str('isomiso2mp41'),
  ]);
  final mdatPayload = List<int>.filled(64, 0x11);
  final Uint8List mdat =
      bigMdat
          ? Uint8List.fromList([
            0,
            0,
            0,
            1,
            ...ascii.encode('mdat'),
            ...(Uint8List(8)
              ..buffer.asByteData().setUint64(0, 16 + mdatPayload.length)),
            ...mdatPayload,
          ])
          : box('mdat', mdatPayload);
  final moov = box('moov', moovChildren);
  return Uint8List.fromList(
    moovFirst ? [...ftyp, ...moov, ...mdat] : [...ftyp, ...mdat, ...moov],
  );
}

Future<File> write(Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp('mp4');
  addTearDown(() => dir.delete(recursive: true));
  return File('${dir.path}/v.mp4')..writeAsBytesSync(bytes);
}

bool contains(Uint8List hay, String needle) =>
    latin1.decode(hay, allowInvalid: true).contains(needle);

void main() {
  test('moov/udta/©xyz (Android MediaMuxer) is neutralised in place', () async {
    final bytes = mp4(
      moovChildren: box('udta', box(xyz, xyzPayload('+05.5560-000.1970/'))),
    );
    final f = await write(bytes);
    expect(await Mp4LocationStripper.strip(f), 1);
    final out = f.readAsBytesSync();
    expect(
      out.length,
      bytes.length,
      reason: 'size (and so every offset) unchanged',
    );
    expect(contains(out, '+05.5560'), isFalse);
    expect(contains(out, 'free'), isTrue);
  });

  test(
    'QuickTime keys and moov after a 64-bit mdat (iPhone): location gone, make kept (Review Focus 1)',
    () async {
      final keys = box('keys', [
        0,
        0,
        0,
        0,
        ..._u32(2),
        ...box('mdta', str('com.apple.quicktime.location.ISO6709')),
        ...box('mdta', str('com.apple.quicktime.make')),
      ]);
      final ilst = box('ilst', [
        ...box(
          _u32(1),
          box('data', [
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            ...str('+05.5560-000.1970+012.000/'),
          ]),
        ),
        ...box(_u32(2), box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...str('Apple')])),
      ]);
      final meta = box('meta', [
        ...box('hdlr', [
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          ...str('mdta'),
          ...List.filled(12, 0),
        ]),
        ...keys,
        ...ilst,
      ]);
      final bytes = mp4(moovChildren: meta, moovFirst: false, bigMdat: true);
      final f = await write(bytes);
      expect(await Mp4LocationStripper.strip(f), 1);
      final out = f.readAsBytesSync();
      expect(out.length, bytes.length);
      expect(contains(out, '+05.5560'), isFalse);
      expect(
        contains(out, 'Apple'),
        isTrue,
        reason: 'non-location metadata is left alone',
      );
    },
  );

  test(
    'ISO meta (version + flags) under udta, and trak/udta, are both handled',
    () async {
      final isoMeta = box('meta', [
        0,
        0,
        0,
        0,
        ...box('hdlr', List.filled(24, 0)),
        ...box(
          'ilst',
          box(
            xyz,
            box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...str('+51.5050-000.1210/')]),
          ),
        ),
      ]);
      final trak = box(
        'trak',
        box('udta', box('loci', [0, 0, 0, 0, ...str('Somewhere'), 0])),
      );
      final bytes = mp4(moovChildren: [...box('udta', isoMeta), ...trak]);
      final f = await write(bytes);
      expect(await Mp4LocationStripper.strip(f), 2);
      final out = f.readAsBytesSync();
      expect(contains(out, '+51.5050'), isFalse);
      expect(contains(out, 'Somewhere'), isFalse);
    },
  );

  test('a clip with no location is left byte-for-byte alone', () async {
    final bytes = mp4(moovChildren: box('udta', box('name', str('holiday'))));
    final f = await write(bytes);
    expect(await Mp4LocationStripper.strip(f), 0);
    expect(f.readAsBytesSync(), bytes);
  });

  test(
    'not an MP4, truncated, or empty: nothing changes, nothing throws',
    () async {
      for (final junk in [
        Uint8List(0),
        Uint8List.fromList(str('hello world')),
        mp4(
          moovChildren: box('udta', box(xyz, xyzPayload('+0'))),
        ).sublist(0, 30),
      ]) {
        final f = await write(junk);
        expect(await Mp4LocationStripper.strip(f), 0);
        expect(f.readAsBytesSync(), junk);
      }
    },
  );

  test(
    'the video preparer strips the compressed output before measuring it',
    () {
      final src =
          File(
            'lib/features/chat/domain/services/chat_video_preparer.dart',
          ).readAsStringSync();
      final strip = src.indexOf('Mp4LocationStripper.strip(outFile)');
      expect(strip, isNonNegative);
      expect(strip, lessThan(src.indexOf('await outFile.length()')));
    },
  );
}
