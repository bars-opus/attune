import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:attune/features/chat/presentation/widgets/video_message_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1x1 transparent PNG, scaled by the test's own ImageProvider so the
/// decoded dimensions are whatever the test wants to assert on.
const _pngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

/// Finds the AspectRatio the thumbnail sizes itself with. Scoped under
/// VideoMessageThumbnail so it can't accidentally match one from the test
/// scaffold.
double aspectRatioOf(WidgetTester tester) {
  final widget = tester.widget<AspectRatio>(
    find
        .descendant(
          of: find.byType(VideoMessageThumbnail),
          matching: find.byType(AspectRatio),
        )
        .first,
  );
  return widget.aspectRatio;
}

void main() {
  testWidgets(
    'falls back to the persisted dimensions before the poster decodes',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoMessageThumbnail(
              // No poster at all, so the decoded-image path can never win
              // and the persisted-dimension fallback is what's under test.
              thumbnailUrl: null,
              durationMs: 5000,
              width: 720,
              height: 1280,
            ),
          ),
        ),
      );

      // Portrait, straight from the stored dimensions.
      expect(aspectRatioOf(tester), closeTo(720 / 1280, 0.0001));
    },
  );

  testWidgets('defaults to portrait when there are no usable dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoMessageThumbnail(
            thumbnailUrl: null,
            durationMs: 5000,
            // Older rows predate the media_width/media_height columns.
            width: 0,
            height: 0,
          ),
        ),
      ),
    );

    // Phone-shot video is overwhelmingly portrait, so a portrait default is
    // the less-wrong guess than the old 16/9 landscape one.
    expect(aspectRatioOf(tester), lessThan(1));
  });

  testWidgets('clamps an extreme stored ratio into the allowed range', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoMessageThumbnail(
            thumbnailUrl: null,
            durationMs: 5000,
            // A 1:6 sliver — without clamping this would render a bubble
            // tall enough to swallow the viewport.
            width: 200,
            height: 1200,
          ),
        ),
      ),
    );

    expect(aspectRatioOf(tester), greaterThanOrEqualTo(0.5));
  });

  group('busy overlay (WhatsApp-style send-in-progress)', () {
    testWidgets('shows a determinate ring over the poster while compressing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoMessageThumbnail(
              thumbnailUrl: null,
              durationMs: 5000,
              width: 720,
              height: 1280,
              showBusyOverlay: true,
              uploadProgress: 0.42,
            ),
          ),
        ),
      );

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      // Determinate: compression reports real percentages.
      expect(indicator.value, closeTo(0.42, 0.0001));
      // The play glyph is replaced while busy — tapping wouldn't play
      // anything yet.
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('falls back to an indeterminate ring when there is no '
        'progress signal (the upload phase)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoMessageThumbnail(
              thumbnailUrl: null,
              durationMs: 5000,
              width: 720,
              height: 1280,
              showBusyOverlay: true,
              uploadProgress: null,
            ),
          ),
        ),
      );

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.value, isNull);
    });

    testWidgets('restores the play glyph and drops the ring once sent', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoMessageThumbnail(
              thumbnailUrl: null,
              durationMs: 5000,
              width: 720,
              height: 1280,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('the tile keeps its shape across the busy -> sent transition', (
      tester,
    ) async {
      Widget build({required bool busy}) => MaterialApp(
        home: Scaffold(
          body: VideoMessageThumbnail(
            // Same key both times: this is the real transition, where the
            // element stays mounted rather than being swapped for a
            // different widget type mid-send.
            key: const ValueKey('same-message'),
            thumbnailUrl: null,
            durationMs: 5000,
            width: 720,
            height: 1280,
            showBusyOverlay: busy,
            uploadProgress: busy ? 0.8 : null,
          ),
        ),
      );

      await tester.pumpWidget(build(busy: true));
      final busyRatio = aspectRatioOf(tester);
      final elementWhileBusy = tester.element(
        find.byType(VideoMessageThumbnail),
      );

      await tester.pumpWidget(build(busy: false));
      await tester.pumpAndSettle();

      // No shape jump at the moment the user is watching the send finish...
      expect(aspectRatioOf(tester), busyRatio);
      // ...and no remount, which would re-run the poster measurement and
      // flicker.
      expect(
        tester.element(find.byType(VideoMessageThumbnail)),
        same(elementWhileBusy),
      );
    });
  });

  group('poster caching / no re-measure on re-sign', () {
    testWidgets('a remote poster uses a disk-backed provider keyed on the '
        'stable storage path, not the signed URL', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoMessageThumbnail(
              thumbnailUrl: 'https://example.com/poster.jpg?token=abc',
              cacheKey: 'chat-media/rel-1/poster.jpg',
              durationMs: 5000,
              width: 720,
              height: 1280,
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(
        find
            .descendant(
              of: find.byType(VideoMessageThumbnail),
              matching: find.byType(Image),
            )
            .first,
      );
      final provider = image.image as CachedNetworkImageProvider;
      // Keyed on the storage path so a re-signed URL still hits the same
      // disk entry — a URL-keyed cache would miss on every app open.
      expect(provider.cacheKey, 'chat-media/rel-1/poster.jpg');
      // Holds the previous frame while a new provider resolves, so the
      // optimistic-to-canonical swap doesn't flash a blank box.
      expect(image.gaplessPlayback, isTrue);
    });

    testWidgets('re-signing the URL does not discard the measured ratio', (
      tester,
    ) async {
      Widget build(String url) => MaterialApp(
        home: Scaffold(
          body: VideoMessageThumbnail(
            key: const ValueKey('same-message'),
            thumbnailUrl: url,
            // Same underlying image throughout — only the signature moves.
            cacheKey: 'chat-media/rel-1/poster.jpg',
            durationMs: 5000,
            width: 720,
            height: 1280,
          ),
        ),
      );

      await tester.pumpWidget(build('https://example.com/p.jpg?token=OLD'));
      final before = aspectRatioOf(tester);

      await tester.pumpWidget(build('https://example.com/p.jpg?token=NEW'));
      await tester.pump();

      // A re-sign is not a new poster: the tile must not fall back to the
      // placeholder ratio and visibly resize.
      expect(aspectRatioOf(tester), before);
    });
  });

  group('cold restart: poster paints from disk before any URL exists', () {
    // Temp dirs are reclaimed only after every test in the group has
    // finished, so no decode is still reading a file when it disappears.
    final tempDirs = <Directory>[];
    tearDownAll(() {
      for (final dir in tempDirs) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    File writePoster() {
      final dir = Directory.systemTemp.createTempSync('poster_cache');
      tempDirs.add(dir);
      return File('${dir.path}/poster.jpg')..writeAsBytesSync(_pngBytes);
    }

    /// Returns a previously-downloaded poster for one specific key, and a
    /// miss for anything else — the shape of a real cache after a restart.
    _FakeCacheManager fakeCacheWith(String key, File file) =>
        _FakeCacheManager({key: file});

    testWidgets('a cache hit paints the poster with no URL in hand', (
      tester,
    ) async {
      final posterFile = writePoster();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoMessageThumbnail(
              // Exactly the cold-restart state: the cached row carries the
              // stable storage key, but no signed URL (they expire, so none
              // is persisted) and no local file (client-only field).
              thumbnailUrl: null,
              cacheKey: 'chat-media/rel-1/poster.jpg',
              durationMs: 5000,
              width: 720,
              height: 1280,
              cacheManager: fakeCacheWith(
                'chat-media/rel-1/poster.jpg',
                posterFile,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The poster is painted straight off disk. Before this, the tile
      // rendered a grey placeholder for the length of a sign-then-download
      // round trip while these exact bytes sat in the cache, unreachable
      // because the provider needed a URL to find them.
      final image = tester.widget<Image>(
        find
            .descendant(
              of: find.byType(VideoMessageThumbnail),
              matching: find.byType(Image),
            )
            .first,
      );
      expect(image.image, isA<FileImage>());
      expect((image.image as FileImage).file.path, posterFile.path);
    });

    testWidgets('a cache miss leaves the placeholder, painting no image', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoMessageThumbnail(
              thumbnailUrl: null,
              cacheKey: 'chat-media/rel-1/never-fetched.jpg',
              durationMs: 5000,
              width: 720,
              height: 1280,
              cacheManager: const _FakeCacheManager({}),
            ),
          ),
        ),
      );
      await tester.pump();

      // A poster this device has never downloaded is an ordinary miss, not
      // an error: the tile keeps its placeholder and the normal
      // resolve-then-fetch path still supplies the poster.
      expect(
        find.descendant(
          of: find.byType(VideoMessageThumbnail),
          matching: find.byType(Image),
        ),
        findsNothing,
      );
    });

    testWidgets('an available URL wins over the disk lookup', (tester) async {
      final posterFile = writePoster();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoMessageThumbnail(
              thumbnailUrl: 'https://example.com/poster.jpg?token=abc',
              cacheKey: 'chat-media/rel-1/poster.jpg',
              durationMs: 5000,
              width: 720,
              height: 1280,
              cacheManager: fakeCacheWith(
                'chat-media/rel-1/poster.jpg',
                posterFile,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // With a URL in hand the normal provider handles it (and serves the
      // same disk entry itself) — the by-key lookup is a fallback for the
      // no-URL case only, not a second code path competing with it.
      final image = tester.widget<Image>(
        find
            .descendant(
              of: find.byType(VideoMessageThumbnail),
              matching: find.byType(Image),
            )
            .first,
      );
      expect(image.image, isA<CachedNetworkImageProvider>());
    });
  });

  testWidgets('renders the duration label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoMessageThumbnail(
            thumbnailUrl: null,
            durationMs: 95000,
            width: 720,
            height: 1280,
          ),
        ),
      ),
    );

    expect(find.text('1:35'), findsOneWidget);
  });

  testWidgets('tapping calls onTap — the bubble opens the viewer, never '
      'plays inline', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoMessageThumbnail(
            thumbnailUrl: null,
            durationMs: 5000,
            width: 720,
            height: 1280,
            onTap: () => taps++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(VideoMessageThumbnail));
    expect(taps, 1);
  });

  test('the poster bytes fixture is a valid PNG header', () {
    // Guards the fixture itself: a corrupted constant would make any
    // decode-based assertion above silently vacuous.
    expect(Uint8List.fromList(_pngBytes).sublist(1, 4), [0x50, 0x4E, 0x47]);
  });
}

/// A disk cache preloaded with a fixed key->file map, standing in for the
/// state of a real cache after an app restart. Only [getFileFromCache] is
/// exercised — the tile never downloads, writes, or evicts, so every other
/// member throwing keeps that guarantee honest rather than silently
/// tolerating a call the production path shouldn't make.
class _FakeCacheManager implements BaseCacheManager {
  const _FakeCacheManager(this._files);

  final Map<String, File> _files;

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    final file = _files[key];
    if (file == null) return null;
    return FileInfo(
      // FileInfo takes the `file` package's File, not dart:io's;
      // LocalFileSystem wraps the same on-disk path the tile ultimately
      // reads through FileImage.
      const LocalFileSystem().file(file.path),
      FileSource.Cache,
      DateTime.now().add(const Duration(days: 7)),
      key,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by the tile');
}
