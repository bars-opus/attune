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
    expect(
      find.descendant(
        of: wallpaperWidget,
        matching: find.byType(ExcludeSemantics),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: wallpaperWidget,
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );

    final wallpaper = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.image)
        .whereType<DecorationImage>()
        .singleWhere(
          (image) =>
              image.image ==
              const AssetImage('assets/images/attune_chat_wallpaper_tile.png'),
        );

    expect(wallpaper.repeat, ImageRepeat.repeat);
    expect(wallpaper.alignment, Alignment.topLeft);
    expect(wallpaper.filterQuality, FilterQuality.low);

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
            .single;
    expect(canvas.begin, Alignment.topLeft);
    expect(canvas.end, Alignment.bottomRight);
    expect(canvas.colors, [
      ChatColorScheme.light.background,
      ChatColorScheme.light.background,
      ChatColorScheme.light.backgroundAccent,
    ]);
  });
}
