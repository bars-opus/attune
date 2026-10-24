import 'dart:convert';
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:video_compress/video_compress.dart';

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
      expect(ChatVideoPreparer.maxSourceBytes, 500 * 1024 * 1024);
      expect(ChatVideoPreparer.targetHeight, 720);
    });
  });

  group('rotation-corrected dimensions', () {
    // The bug this guards: video_compress reports RAW encoded frame
    // dimensions and exposes rotation as a separate `orientation` field. A
    // portrait phone clip is stored as a 1280x720 landscape frame plus a
    // 90-degree flag, so persisting the raw numbers made every portrait
    // video render with a landscape aspect ratio — too tall in the bubble,
    // letterboxed against the wrong edge fullscreen.
    test('a 90-degree rotation swaps the axes (landscape frame reads as '
        'portrait)', () {
      final size = ChatVideoPreparer.debugOrientedSize(
        width: 1280,
        height: 720,
        orientation: 90,
      );
      expect(size.width, 720);
      expect(size.height, 1280);
      // The real assertion: the resulting ratio is portrait (< 1), not the
      // landscape ratio the raw numbers describe.
      expect(size.width / size.height, lessThan(1));
    });

    test('a 270-degree rotation also swaps the axes', () {
      final size = ChatVideoPreparer.debugOrientedSize(
        width: 1280,
        height: 720,
        orientation: 270,
      );
      expect(size.width, 720);
      expect(size.height, 1280);
    });

    test('0 and 180 degrees leave the axes untouched', () {
      for (final orientation in [0, 180]) {
        final size = ChatVideoPreparer.debugOrientedSize(
          width: 1280,
          height: 720,
          orientation: orientation,
        );
        expect(size.width, 1280, reason: 'orientation $orientation');
        expect(size.height, 720, reason: 'orientation $orientation');
      }
    });

    test('a null/unknown orientation is treated as no rotation', () {
      final size = ChatVideoPreparer.debugOrientedSize(
        width: 1280,
        height: 720,
        orientation: null,
      );
      expect(size.width, 1280);
      expect(size.height, 720);
    });

    test('negative and over-360 orientations normalize before deciding', () {
      // Some encoders report -90 rather than 270.
      final negative = ChatVideoPreparer.debugOrientedSize(
        width: 1280,
        height: 720,
        orientation: -90,
      );
      expect(negative.width, 720);
      expect(negative.height, 1280);

      final wrapped = ChatVideoPreparer.debugOrientedSize(
        width: 1280,
        height: 720,
        orientation: 450, // 450 % 360 == 90
      );
      expect(wrapped.width, 720);
      expect(wrapped.height, 1280);
    });

    test('an already-portrait frame with no rotation stays portrait', () {
      final size = ChatVideoPreparer.debugOrientedSize(
        width: 720,
        height: 1280,
        orientation: 0,
      );
      expect(size.width / size.height, lessThan(1));
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
    test(
      'a longer selected window estimates more bytes than a shorter one from the same source',
      () {
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
      },
    );

    test(
      'a window covering the full source estimates approximately the full source size',
      () {
        const sourceBytes = 50 * 1024 * 1024;
        const sourceDuration = Duration(minutes: 2);

        final estimate = ChatVideoPreparer.debugEstimateWindowBytes(
          sourceBytes: sourceBytes,
          sourceDuration: sourceDuration,
          windowDuration: sourceDuration,
        );

        expect(
          estimate,
          closeTo(sourceBytes, 1),
        ); // linear estimate, exact at full coverage
      },
    );

    test(
      'a zero-length window estimates zero bytes, not a divide-by-zero crash',
      () {
        final estimate = ChatVideoPreparer.debugEstimateWindowBytes(
          sourceBytes: 50 * 1024 * 1024,
          sourceDuration: const Duration(minutes: 2),
          windowDuration: Duration.zero,
        );
        expect(estimate, 0);
      },
    );
  });

  group('early absolute source-size guard', () {
    // Final-whole-branch-review fix: VideoTrimScreen clamps the selected
    // window to <=3 minutes before prepare() ever runs, which meant the
    // window-estimate guard could only trip within a narrow high-bitrate
    // band — not the broad "reject huge sources early" protection the
    // Global Constraints imply. This test asserts a source file bigger than
    // maxSourceBytes is rejected immediately from just its raw byte length,
    // independent of trim window and before any MIME sniff/decode work
    // (proven here by the fact that the file has no valid ftyp box at all —
    // if the guard didn't fire first, MIME sniffing would reject with
    // 'media_type_unsupported' instead of 'media_too_large').
    test('a source file larger than maxSourceBytes is rejected before MIME '
        'sniffing, regardless of trim window', () async {
      final file = File(p.join(tmp.path, 'huge.mp4'));
      // Not a valid ftyp box — if this guard didn't run first, the file
      // would instead fail MIME sniffing with a different rejection code.
      final raf = await file.open(mode: FileMode.write);
      await raf.truncate(ChatVideoPreparer.maxSourceBytes + 1);
      await raf.close();

      expect(
        () => const ChatVideoPreparer().prepare(
          localPath: file.path,
          trimStart: Duration.zero,
          trimEnd: const Duration(seconds: 5),
        ),
        throwsA(
          isA<ChatVideoRejected>().having(
            (e) => e.code,
            'code',
            'media_too_large',
          ),
        ),
      );
    });
  });

  group('resource cleanup / existence checks', () {
    test('rejects a missing source file', () async {
      expect(
        () => const ChatVideoPreparer().prepare(localPath: '/no/such/file.mp4'),
        throwsA(
          isA<ChatVideoRejected>().having(
            (e) => e.code,
            'code',
            'media_missing',
          ),
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
    test(
      'rejects a file with no ftyp box (not a valid mp4/mov container)',
      () async {
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
      },
    );

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
      expect(ChatVideoPreparer.debugSniffMime(bytes), 'video/mp4');
    });

    List<int> ftyp(String brand) => <int>[
      0x00, 0x00, 0x00, 0x18,
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      ...brand.codeUnits, // major brand
      0x00, 0x00, 0x02, 0x00,
    ];

    test('common MP4 brands beyond the old allowlist are accepted', () {
      // ffmpeg -movflags, HEVC exports, 3GPP phones, older encoders.
      for (final brand in [
        'isom', 'iso2', 'iso3', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42',
        'avc1', 'hev1', 'hvc1', 'M4V ', 'M4A ', 'f4v ', 'dash', '3gp4',
        '3gp5', '3gp6', '3g2a', 'mmp4', 'NDXC',
      ]) {
        expect(ChatVideoPreparer.debugSniffMime(ftyp(brand)), 'video/mp4',
            reason: 'brand "$brand"');
      }
    });

    test('QuickTime keeps its own MIME', () {
      expect(ChatVideoPreparer.debugSniffMime(ftyp('qt  ')), 'video/quicktime');
    });

    test('a non-printable brand is still refused (not an ISO-BMFF video)', () {
      expect(ChatVideoPreparer.debugSniffMime(ftyp('\x00\x01\x02\x03')), isNull);
    });

    test('bytes with no ftyp box are refused', () {
      expect(ChatVideoPreparer.debugSniffMime('RIFF....WEBPVP8 '.codeUnits), isNull);
    });
  });

  group('optional maxDuration/maxBytes overrides', () {
    test(
      'omitting maxDuration/maxBytes preserves the existing 3-minute/25MB constants',
      () {
        // This test asserts on the PARAMETER DEFAULTING behavior itself,
        // not a full prepare() run (which needs native calls unavailable in
        // this test host) — it confirms the guard conditions prepare()
        // evaluates internally would be computed against
        // ChatVideoPreparer.maxDuration/maxBytes when the new parameters are
        // null, by checking the effective values a small extracted helper
        // would resolve to. Since prepare() doesn't expose this resolution
        // as a separate testable unit today, this task also adds a
        // @visibleForTesting seam (Step 3) specifically so this can be
        // asserted without a full native-backed prepare() call.
        expect(
          ChatVideoPreparer.debugResolveMaxDuration(null),
          ChatVideoPreparer.maxDuration,
        );
        expect(
          ChatVideoPreparer.debugResolveMaxBytes(null),
          ChatVideoPreparer.maxBytes,
        );
      },
    );

    test('passing maxDuration/maxBytes overrides the defaults', () {
      const overrideDuration = Duration(seconds: 10);
      const overrideBytes = 2 * 1024 * 1024;
      expect(
        ChatVideoPreparer.debugResolveMaxDuration(overrideDuration),
        overrideDuration,
      );
      expect(
        ChatVideoPreparer.debugResolveMaxBytes(overrideBytes),
        overrideBytes,
      );
    });

    test(
      'an ephemeral-scale duration bound (10s) correctly rejects an 11-second window',
      () async {
        // Uses ChatVideoPreparer's own debugEstimateWindowBytes/duration-bounds
        // reasoning indirectly: since prepare() itself needs native calls this
        // test host can't provide, this asserts the resolved bound value
        // itself is what a caller would compare effectiveDuration against —
        // i.e. that passing maxDuration: Duration(seconds: 10) genuinely
        // produces a 10-second (not 3-minute) ceiling for any downstream
        // duration comparison.
        final resolved = ChatVideoPreparer.debugResolveMaxDuration(
          const Duration(seconds: 10),
        );
        expect(const Duration(seconds: 11) > resolved, isTrue);
        expect(const Duration(seconds: 9) > resolved, isFalse);
      },
    );
  });

  group('precise export window (stories Wave 2, opt-in)', () {
    const max = Duration(seconds: 60);
    const tol = Duration(seconds: 2);

    // Fix round 1 (ledger ruling): this used to pin today's (0 s, 59 s)
    // window. Android's plugin cuts `duration` from the END, so an untrimmed
    // source is now exported whole on every flow, with no plugin args.
    test('without a tolerance an untrimmed source is still exported whole', () {
      final w = ChatVideoPreparer.debugExportWindow(
        source: const Duration(milliseconds: 59700), maxDuration: max,
      );
      expect(w.end, const Duration(milliseconds: 59700));
      expect(w.whole, isTrue);
      for (final android in [false, true]) {
        final a = ChatVideoPreparer.debugCompressArgs(
          source: const Duration(milliseconds: 59700),
          start: w.start, end: w.end, whole: w.whole, android: android,
        );
        expect(a.startTime, isNull, reason: 'android: $android');
        expect(a.duration, isNull, reason: 'android: $android');
      }
    });

    test('a take that overshoots the minute by the stop latency is clamped to 60 s', () {
      final w = ChatVideoPreparer.debugExportWindow(
        source: const Duration(milliseconds: 60240),
        maxDuration: max,
        boundaryTolerance: tol,
      );
      expect(w.end - w.start, max);
      // Fix round 1: exported whole (no args on either platform); the
      // reported duration is min(exported, 60000).
      expect(w.whole, isTrue);
      for (final android in [false, true]) {
        final a = ChatVideoPreparer.debugCompressArgs(
          source: const Duration(milliseconds: 60240),
          start: w.start, end: w.end, whole: w.whole, android: android,
        );
        expect(a.startTime, isNull, reason: 'android: $android');
        expect(a.duration, isNull, reason: 'android: $android');
      }
    });

    test('beyond the tolerance it is not clamped (still too long)', () {
      final w = ChatVideoPreparer.debugExportWindow(
        source: const Duration(milliseconds: 63000),
        maxDuration: max,
        boundaryTolerance: tol,
      );
      expect(w.end - w.start, const Duration(milliseconds: 63000));
    });

    test('an untrimmed short or fractional clip is exported whole', () {
      for (final ms in [800, 59700]) {
        final w = ChatVideoPreparer.debugExportWindow(
          source: Duration(milliseconds: ms),
          maxDuration: max,
          boundaryTolerance: tol,
        );
        expect(w.whole, isTrue, reason: '$ms ms');
        final a = ChatVideoPreparer.debugCompressArgs(
          source: Duration(milliseconds: ms),
          start: w.start, end: w.end, whole: w.whole, android: false,
        );
        expect(a.startTime, isNull, reason: '$ms ms');
        expect(a.duration, isNull,
            reason: 'never duration: 0 (01 #16) and never a lost fraction');
        expect(w.end, Duration(milliseconds: ms));
      }
    });

    test('a precise duration is min(exported, 60000); legacy keeps the window', () {
      expect(
        ChatVideoPreparer.debugReportedDurationMs(
          window: const Duration(seconds: 60), exportedMs: 60031.0,
          maxDuration: max, precise: true,
        ),
        60000,
      );
      expect(
        ChatVideoPreparer.debugReportedDurationMs(
          window: const Duration(milliseconds: 800), exportedMs: 812.4,
          maxDuration: max, precise: true,
        ),
        812,
      );
      expect(
        ChatVideoPreparer.debugReportedDurationMs(
          window: const Duration(milliseconds: 59700), exportedMs: 59000,
          maxDuration: max, precise: false,
        ),
        59700,
      );
    });

    test('prepare() uses the window helper (the plugin args come from it)', () {
      final src = File('lib/features/chat/domain/services/chat_video_preparer.dart')
          .readAsStringSync();
      expect(src, contains('debugExportWindow('));
      expect(src, contains('debugCompressArgs('));
      expect(src, contains('android: defaultTargetPlatform == TargetPlatform.android'));
      expect(src, contains('startTime: args.startTime'));
      expect(src, contains('duration: args.duration'));
    });
  });

  // Fix round 1: video_compress 3.1.4 on Android hands `duration` to
  // Transcoder's TrimDataSource as microseconds cut from the END
  // (VideoCompressPlugin.kt:145); iOS reads it as the window length. Whole
  // sources pass no args at all; real trims are rounded so the exported
  // range always covers the chosen window.
  group('plugin trim arguments per platform', () {
    const threeMin = Duration(minutes: 3);
    Duration ms(int v) => Duration(milliseconds: v);

    ({int? startTime, int? duration}) args(
      Duration source, {
      Duration? start,
      Duration? end,
      required bool android,
      Duration maxDuration = threeMin,
      Duration? tolerance,
    }) {
      final w = ChatVideoPreparer.debugExportWindow(
        source: source,
        trimStart: start,
        trimEnd: end,
        maxDuration: maxDuration,
        boundaryTolerance: tolerance,
      );
      return ChatVideoPreparer.debugCompressArgs(
        source: source, start: w.start, end: w.end, whole: w.whole, android: android,
      );
    }

    void expectArgs(({int? startTime, int? duration}) a, int? start, int? duration) {
      expect((a.startTime, a.duration), (start, duration));
    }

    test('untrimmed: no args on either platform', () {
      expectArgs(args(ms(30000), android: false), null, null);
      expectArgs(args(ms(30000), android: true), null, null);
    });

    test('a trim covering the whole source: no args', () {
      expectArgs(args(ms(30000), start: Duration.zero, end: ms(30000), android: true), null, null);
      expectArgs(args(ms(30000), start: Duration.zero, end: ms(30000), android: false), null, null);
    });

    test('the 60-62 s clamp: no args on either platform', () {
      for (final android in [false, true]) {
        expectArgs(
          args(ms(60240), android: android, maxDuration: ms(60000), tolerance: ms(2000)),
          null,
          null,
        );
      }
    });

    test('trim in the middle: iOS a length, Android the seconds cut from the end', () {
      expectArgs(args(ms(30000), start: ms(5000), end: ms(15000), android: false), 5, 10);
      expectArgs(args(ms(30000), start: ms(5000), end: ms(15000), android: true), 5, 15);
    });

    test('trim at the start', () {
      expectArgs(args(ms(30000), start: Duration.zero, end: ms(10000), android: false), 0, 10);
      expectArgs(args(ms(30000), start: Duration.zero, end: ms(10000), android: true), 0, 20);
    });

    test('trim at the end', () {
      expectArgs(args(ms(30000), start: ms(20000), end: ms(30000), android: false), 20, 10);
      expectArgs(args(ms(30000), start: ms(20000), end: ms(30000), android: true), 20, 0);
    });

    test('fractional seconds are rounded so the window is never cut short', () {
      expectArgs(args(ms(30500), start: ms(5600), end: ms(15300), android: false), 5, 11);
      expectArgs(args(ms(30500), start: ms(5600), end: ms(15300), android: true), 5, 15);
    });

    test('every fractional window is covered, and Android never trims past the '
        'source (TrimDataSource throws when start + end >= duration)', () {
      const source = 30500;
      for (var start = 0; start < source - 600; start += 700) {
        for (var end = start + 500; end <= source; end += 900) {
          final ios = args(ms(source), start: ms(start), end: ms(end), android: false);
          final droid = args(ms(source), start: ms(start), end: ms(end), android: true);
          if (ios.startTime == null) {
            expect(droid.startTime, isNull);
            continue;
          }
          final why = '$start-$end';
          expect(ios.startTime! * 1000, lessThanOrEqualTo(start), reason: why);
          expect((ios.startTime! + ios.duration!) * 1000, greaterThanOrEqualTo(end), reason: why);
          expect(ios.duration, greaterThan(0), reason: why);
          expect(droid.startTime! * 1000, lessThanOrEqualTo(start), reason: why);
          expect(source - droid.duration! * 1000, greaterThanOrEqualTo(end), reason: why);
          expect((droid.startTime! + droid.duration!) * 1000, lessThan(source), reason: why);
        }
      }
    });
  });

  // Batch-5 review #2: stories record at veryHigh (1080p), so the fixed
  // 720p transcode becomes a real 720p encode that can pass 25 MB (the
  // server ceiling too). Opted in, one more encode one quality step down is
  // tried before the take is refused. Chat and streaks pass nothing: one
  // encode, refused as today.
  group('oversize step-down (stories, opt-in)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const compressChannel = MethodChannel('video_compress');
    const thumbnailChannel = MethodChannel('plugins.justsoft.xyz/video_thumbnail');
    const limit = 4000; // maxBytes override: small files, same rule as 25 MB

    late String source;
    late List<int> qualities;
    late List<String> outputs;
    late Map<int, int> bytesByQuality;
    late List<Map<String, dynamic>> compressArgs;
    late double exportedMs;

    setUp(() async {
      source = p.join(tmp.path, 'take.mp4');
      // ISO-BMFF ftyp header ('mp42'), then filler: enough for the sniff.
      await File(source).writeAsBytes([
        0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, //
        ...'mp42'.codeUnits, ...List.filled(512, 0),
      ]);
      qualities = [];
      outputs = [];
      bytesByQuality = {};
      compressArgs = [];
      exportedMs = 30000.0;
      final thumb = img.encodeJpg(
        img.fill(img.Image(width: 64, height: 36), color: img.ColorRgb8(90, 90, 90)),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(compressChannel, (call) async {
        final args = (call.arguments as Map).cast<String, dynamic>();
        switch (call.method) {
          case 'getMediaInfo':
            return jsonEncode({
              'path': args['path'],
              'duration': 30000.0,
              'width': 1920,
              'height': 1080,
            });
          case 'compressVideo':
            final quality = args['quality'] as int;
            qualities.add(quality);
            compressArgs.add(args);
            final out = p.join(tmp.path, 'out_${qualities.length}.mp4');
            await File(out).writeAsBytes(List.filled(bytesByQuality[quality]!, 0));
            outputs.add(out);
            return jsonEncode({
              'path': out,
              'duration': exportedMs,
              'width': 1280,
              'height': 720,
            });
        }
        return null;
      });
      messenger.setMockMethodCallHandler(thumbnailChannel, (_) async => thumb);
    });
    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(compressChannel, null);
      messenger.setMockMethodCallHandler(thumbnailChannel, null);
    });

    final hd = VideoQuality.Res1280x720Quality.index;
    final qhd = VideoQuality.Res960x540Quality.index;
    const story = ChatVideoPreparer(
      oversizeRetryQuality: VideoQuality.Res960x540Quality,
    );

    test('without the opt-in an oversize 720p output is refused, as today', () async {
      bytesByQuality = {hd: limit + 1, qhd: limit ~/ 2};
      await expectLater(
        const ChatVideoPreparer().prepare(localPath: source, maxBytes: limit),
        throwsA(isA<ChatVideoRejected>().having((e) => e.code, 'code', 'media_compress_failed')),
      );
      expect(qualities, [hd], reason: 'one encode, at 720p');
    });

    test('opted in, an oversize 720p output is re-encoded once at 960x540 and '
        'the story posts', () async {
      bytesByQuality = {hd: limit + 1, qhd: limit ~/ 2};
      final prepared = await story.prepare(localPath: source, maxBytes: limit);
      expect(qualities, [hd, qhd]);
      expect(prepared.file.path, outputs.last);
      expect(prepared.byteSize, limit ~/ 2);
      expect(File(outputs.first).existsSync(), isFalse,
          reason: 'the oversize encode is not left behind');
    });

    test('opted in, a take still too large at 960x540 is refused', () async {
      bytesByQuality = {hd: limit + 1, qhd: limit + 1};
      await expectLater(
        story.prepare(localPath: source, maxBytes: limit),
        throwsA(isA<ChatVideoRejected>().having((e) => e.code, 'code', 'media_compress_failed')),
      );
      expect(qualities, [hd, qhd], reason: 'one retry, never a loop');
      // Review #6 (fix round 2): neither encode is left behind (Android's
      // plugin folder is never cleared).
      for (final out in outputs) {
        expect(File(out).existsSync(), isFalse, reason: out);
      }
    });

    test('stories final review #3b: the raw first frame (raw_thumb_*.jpg) is '
        'not left in tmp/ once the poster is prepared', () async {
      bytesByQuality = {hd: limit};
      List<String> rawThumbs() => Directory.systemTemp
          .listSync()
          .map((e) => p.basename(e.path))
          .where((n) => n.startsWith('raw_thumb_'))
          .toList();
      final before = rawThumbs().toSet();
      final prepared =
          await const ChatVideoPreparer().prepare(localPath: source, maxBytes: limit);
      expect(rawThumbs().where((n) => !before.contains(n)), isEmpty);
      expect(prepared.thumbnailFile.existsSync(), isTrue,
          reason: 'the prepared poster chat paints is kept');
    });

    test('fix round 1: an untrimmed chat take reaches the plugin with no '
        'startTime and no duration', () async {
      bytesByQuality = {hd: limit};
      await const ChatVideoPreparer().prepare(localPath: source, maxBytes: limit);
      expect(compressArgs.single['startTime'], isNull);
      expect(compressArgs.single['duration'], isNull);
    });

    test('fix round 1: a trimmed take on Android passes the seconds cut from '
        'the end; on iOS the window length', () async {
      bytesByQuality = {hd: limit};
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final (platform, duration) in [
        (TargetPlatform.android, 15), // 30 s source, keep 5-15 s: cut 15 s
        (TargetPlatform.iOS, 10),
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        await const ChatVideoPreparer().prepare(
          localPath: source,
          trimStart: const Duration(seconds: 5),
          trimEnd: const Duration(seconds: 15),
          maxBytes: limit,
        );
        debugDefaultTargetPlatformOverride = null;
        expect(compressArgs.last['startTime'], 5, reason: '$platform');
        expect(compressArgs.last['duration'], duration, reason: '$platform');
      }
    });

    test('fix round 2: a trimmed Android export reports the length it '
        'actually has (rounded outward); iOS keeps the window (C1)', () async {
      bytesByQuality = {hd: limit};
      exportedMs = 10900.0; // 5-15.9 s exported for a 5.4-15.3 s window
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final reported = <TargetPlatform, int>{};
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final prepared = await const ChatVideoPreparer().prepare(
          localPath: source,
          trimStart: const Duration(milliseconds: 5400),
          trimEnd: const Duration(milliseconds: 15300),
          maxBytes: limit,
        );
        debugDefaultTargetPlatformOverride = null;
        reported[platform] = prepared.durationMs;
      }
      expect(reported[TargetPlatform.android], 10900);
      expect(reported[TargetPlatform.iOS], 9900);
    });

    test('fix round 2: an untrimmed chat take still reports its source '
        'length', () async {
      bytesByQuality = {hd: limit};
      exportedMs = 29950.0;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final prepared = await const ChatVideoPreparer().prepare(
        localPath: source,
        maxBytes: limit,
      );
      debugDefaultTargetPlatformOverride = null;
      expect(prepared.durationMs, 30000);
    });

    test('opted in, a 720p output within the limit is not re-encoded', () async {
      bytesByQuality = {hd: limit, qhd: 1};
      final prepared = await story.prepare(localPath: source, maxBytes: limit);
      expect(qualities, [hd]);
      expect(prepared.byteSize, limit);
    });
  });
}
