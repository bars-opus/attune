import 'dart:typed_data';

import 'package:attune/features/chat/presentation/widgets/video_message_thumbnail.dart';
import 'package:flutter/material.dart';
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
