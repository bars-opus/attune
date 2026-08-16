import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chat_video_test');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('duration bounds', () {
    test('minDuration and maxDuration match the design spec values', () {
      expect(ChatVideoPreparer.minDuration, const Duration(milliseconds: 500));
      expect(ChatVideoPreparer.maxDuration, const Duration(minutes: 3));
    });
  });

  group('constants match the design spec', () {
    test('byte ceilings and target height are the confirmed values', () {
      expect(ChatVideoPreparer.maxBytes, 25 * 1024 * 1024);
      expect(ChatVideoPreparer.maxSourceBytes, 300 * 1024 * 1024);
      expect(ChatVideoPreparer.targetHeight, 720);
    });
  });

  group('trim-window byte-size-guard estimate', () {
    // This is the numeric-transform logic the plan's Global Constraints
    // section specifically calls out as needing a RELATIVE-correctness
    // test, not just a shape/range test — mirroring the exact class of bug
    // (inverted waveform normalization) that survived every per-task review
    // in the voice-messages build and was only caught by the final
    // whole-branch review. debugEstimateWindowBytes is a @visibleForTesting
    // seam exposing the same formula prepare() uses internally.
    test('a longer selected window estimates more bytes than a shorter one from the same source', () {
      const sourceBytes = 100 * 1024 * 1024; // 100MB source
      const sourceDuration = Duration(minutes: 10);

      final shortWindowEstimate = ChatVideoPreparer.debugEstimateWindowBytes(
        sourceBytes: sourceBytes,
        sourceDuration: sourceDuration,
        windowDuration: const Duration(seconds: 30),
      );
      final longWindowEstimate = ChatVideoPreparer.debugEstimateWindowBytes(
        sourceBytes: sourceBytes,
        sourceDuration: sourceDuration,
        windowDuration: const Duration(minutes: 3),
      );

      expect(longWindowEstimate, greaterThan(shortWindowEstimate));
    });

    test('a window covering the full source estimates approximately the full source size', () {
      const sourceBytes = 50 * 1024 * 1024;
      const sourceDuration = Duration(minutes: 2);

      final estimate = ChatVideoPreparer.debugEstimateWindowBytes(
        sourceBytes: sourceBytes,
        sourceDuration: sourceDuration,
        windowDuration: sourceDuration,
      );

      expect(estimate, closeTo(sourceBytes, 1)); // linear estimate, exact at full coverage
    });

    test('a zero-length window estimates zero bytes, not a divide-by-zero crash', () {
      final estimate = ChatVideoPreparer.debugEstimateWindowBytes(
        sourceBytes: 50 * 1024 * 1024,
        sourceDuration: const Duration(minutes: 2),
        windowDuration: Duration.zero,
      );
      expect(estimate, 0);
    });
  });

  group('resource cleanup / existence checks', () {
    test('rejects a missing source file', () async {
      expect(
        () => const ChatVideoPreparer().prepare(localPath: '/no/such/file.mp4'),
        throwsA(
          isA<ChatVideoRejected>().having((e) => e.code, 'code', 'media_missing'),
        ),
      );
    });

    test('rejects an empty source file', () async {
      final file = File(p.join(tmp.path, 'empty.mp4'));
      await file.writeAsBytes(const []);
      expect(
        () => const ChatVideoPreparer().prepare(localPath: file.path),
        throwsA(
          isA<ChatVideoRejected>().having((e) => e.code, 'code', 'media_empty'),
        ),
      );
    });
  });

  group('MIME sniffing', () {
    test('rejects a file with no ftyp box (not a valid mp4/mov container)', () async {
      final file = File(p.join(tmp.path, 'fake.mp4'));
      await file.writeAsString('this is not a video container');
      expect(
        () => const ChatVideoPreparer().prepare(localPath: file.path),
        throwsA(
          isA<ChatVideoRejected>().having(
            (e) => e.code,
            'code',
            'media_type_unsupported',
          ),
        ),
      );
    });

    test('accepts a minimal valid mp4 ftyp box signature', () {
      // ISO base media file format: a box is [4-byte size][4-byte type][data].
      // A minimal ftyp box with major brand 'isom' at the standard offset.
      final bytes = <int>[
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x69, 0x73, 0x6F, 0x6D, // major brand 'isom'
        0x00, 0x00, 0x02, 0x00, // minor version
        0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32, // compatible brands
      ];
      expect(
        ChatVideoPreparer.debugSniffMime(bytes),
        'video/mp4',
      );
    });

    test('unrecognized major brand returns null (caller rejects)', () {
      final bytes = <int>[
        0x00, 0x00, 0x00, 0x18,
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x78, 0x78, 0x78, 0x78, // unrecognized brand
        0x00, 0x00, 0x02, 0x00,
      ];
      expect(ChatVideoPreparer.debugSniffMime(bytes), isNull);
    });
  });
}
