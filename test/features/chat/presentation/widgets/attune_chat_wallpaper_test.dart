import 'dart:io';

import 'package:attune/features/chat/presentation/widgets/attune_chat_wallpaper.dart';
import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('wallpaper tile is a dense transparent seamless asset', () {
    final bytes =
        File('assets/images/attune_chat_wallpaper_tile.png').readAsBytesSync();
    final tile = img.decodePng(bytes);

    expect(tile, isNotNull);
    expect(tile!.width, 512);
    expect(tile.height, 512);
    expect(tile.numChannels, 4);

    var visiblePixels = 0;
    for (final pixel in tile) {
      if (pixel.a > 8) visiblePixels++;
    }
    final inkDensity = visiblePixels / (tile.width * tile.height);
    expect(inkDensity, inInclusiveRange(0.03, 0.35));

    for (var x = 0; x < tile.width; x++) {
      expect(tile.getPixel(x, 0).a, 0);
      expect(tile.getPixel(x, tile.height - 1).a, 0);
    }
    for (var y = 0; y < tile.height; y++) {
      expect(tile.getPixel(0, y).a, 0);
      expect(tile.getPixel(tile.width - 1, y).a, 0);
    }
  });

  testWidgets('renders the static tiled wallpaper behind chat content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AttuneChatWallpaper(child: Text('Conversation content')),
        ),
      ),
    );

    expect(find.text('Conversation content'), findsOneWidget);
    final wallpaperWidget = find.byType(AttuneChatWallpaper);
    // Six decorative layers, none of them readable by a screen reader:
    // two _WallpaperGradientLayer (the base gradient plus the
    // scroll-driven accent that cross-fades over it) carry one each, and
    // the Stack adds four more directly. The count was 2 before the
    // wallpaper gained its gradient and pattern layers.
    //
    // The number itself is not the point — that EVERY layer stays
    // excluded is. If this fails after a wallpaper change, check that the
    // new layer excludes semantics rather than just re-counting to match.
    expect(
      find.descendant(
        of: wallpaperWidget,
        matching: find.byType(ExcludeSemantics),
      ),
      findsNWidgets(6),
    );
    // Likewise: every decorative layer that can swallow a touch wraps
    // itself in IgnorePointer, so taps reach the conversation beneath.
    // What matters is that none of them is interactive, not the count.
    expect(
      find.descendant(
        of: wallpaperWidget,
        matching: find.byType(IgnorePointer),
      ),
      findsNWidgets(4),
    );

    // The tile is painted by several layers now (pattern, glow, canvas),
    // so this asserts EVERY one of them tiles identically rather than
    // singling one out — a layer that drifted to a different repeat or
    // alignment would visibly misregister against the others.
    final wallpapers = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.image)
        .whereType<DecorationImage>()
        .where(
          (image) =>
              image.image ==
              const AssetImage('assets/images/attune_chat_wallpaper_tile.png'),
        )
        .toList();

    expect(wallpapers, isNotEmpty, reason: 'the tile must be painted');
    for (final wallpaper in wallpapers) {
      expect(wallpaper.repeat, ImageRepeat.repeat);
      expect(wallpaper.alignment, Alignment.topLeft);
      expect(wallpaper.filterQuality, FilterQuality.low);
    }

    final canvas =
        tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: wallpaperWidget,
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((widget) => widget.decoration)
            .whereType<BoxDecoration>()
            .map((decoration) => decoration.gradient)
            .whereType<LinearGradient>()
            .toList();

    // Two gradient layers now, deliberately opposed: the base runs
    // topLeft -> bottomRight and the scroll-driven accent runs back the
    // other way, cross-fading as the conversation scrolls. So this picks
    // out the BASE layer by its direction rather than assuming one
    // gradient exists, and asserts the other is its mirror.
    final base = canvas.firstWhere(
      (g) => g.begin == Alignment.topLeft && g.end == Alignment.bottomRight,
      orElse: () => throw StateError('no base topLeft -> bottomRight gradient'),
    );
    // The accent end-stop is a BLEND toward backgroundAccent, not the raw
    // token: 0.60 in light, 0.42 in dark (attune_chat_wallpaper.dart's
    // _buildWallpaper). Derived here rather than hardcoded so retuning
    // the blend in one place does not silently drift from the test.
    expect(base.colors, [
      ChatColorScheme.light.background,
      ChatColorScheme.light.background,
      Color.lerp(
        ChatColorScheme.light.background,
        ChatColorScheme.light.backgroundAccent,
        0.60,
      ),
    ]);
    expect(
      canvas.any(
        (g) => g.begin == Alignment.bottomRight && g.end == Alignment.topLeft,
      ),
      isTrue,
      reason: 'the scroll accent mirrors the base gradient',
    );
  });
}
