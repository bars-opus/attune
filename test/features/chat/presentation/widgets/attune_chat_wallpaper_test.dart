import 'dart:io';

import 'package:attune/features/chat/presentation/widgets/attune_chat_wallpaper.dart';
import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('wallpaper artwork is a dense transparent portrait asset', () {
    final bytes =
        File(
          'assets/images/attune_chat_wallpaper_tile_refined.png',
        ).readAsBytesSync();
    final tile = img.decodePng(bytes);

    expect(tile, isNotNull);
    expect(tile!.width, 1024);
    expect(tile.height, 1536);
    expect(tile.numChannels, 4);

    var visiblePixels = 0;
    for (final pixel in tile) {
      if (pixel.a > 8) visiblePixels++;
    }
    final inkDensity = visiblePixels / (tile.width * tile.height);
    expect(inkDensity, inInclusiveRange(0.03, 0.35));
  });

  testWidgets('light mode renders flat portrait artwork without an accent', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttuneChatWallpaper(
            scrollController: scrollController,
            child: const Text('Conversation content'),
          ),
        ),
      ),
    );

    expect(find.text('Conversation content'), findsOneWidget);
    final wallpaperWidget = find.byType(AttuneChatWallpaper);
    expect(
      find.descendant(
        of: wallpaperWidget,
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );
    // Light mode has only a flat background and the portrait pattern. Both are
    // decorative and the pattern cannot intercept conversation gestures.
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

    // Every wallpaper layer must use the same single-cover composition. If a
    // dark-mode glow layer drifts from these settings it will visibly
    // misregister against the base pattern.
    final wallpapers =
        tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((widget) => widget.decoration)
            .whereType<BoxDecoration>()
            .map((decoration) => decoration.image)
            .whereType<DecorationImage>()
            .where(
              (image) =>
                  image.image ==
                  const AssetImage(
                    'assets/images/attune_chat_wallpaper_tile_refined.png',
                  ),
            )
            .toList();

    expect(
      wallpapers,
      hasLength(1),
      reason: 'the portrait artwork must be painted once',
    );
    for (final wallpaper in wallpapers) {
      expect(wallpaper.repeat, ImageRepeat.noRepeat);
      expect(wallpaper.alignment, Alignment.topCenter);
      expect(wallpaper.fit, BoxFit.cover);
      expect(wallpaper.filterQuality, FilterQuality.high);
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

    expect(canvas, isEmpty, reason: 'light mode must not paint a gradient');
    final background = find.descendant(
      of: wallpaperWidget,
      matching: find.byType(ColoredBox),
    );
    expect(background, findsOneWidget);
    expect(
      tester.widget<ColoredBox>(background).color,
      ChatColorScheme.light.background,
    );
  });

  testWidgets('dark mode keeps the opposed ambient gradients', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [ChatColorScheme.dark],
        ),
        home: const Scaffold(
          body: AttuneChatWallpaper(child: Text('Conversation content')),
        ),
      ),
    );

    final wallpaperWidget = find.byType(AttuneChatWallpaper);
    final wallpapers =
        tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: wallpaperWidget,
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((widget) => widget.decoration)
            .whereType<BoxDecoration>()
            .map((decoration) => decoration.image)
            .whereType<DecorationImage>()
            .where(
              (image) =>
                  image.image ==
                  const AssetImage(
                    'assets/images/attune_chat_wallpaper_tile_refined.png',
                  ),
            )
            .toList();

    expect(wallpapers, hasLength(4));
    for (final wallpaper in wallpapers) {
      expect(wallpaper.repeat, ImageRepeat.noRepeat);
      expect(wallpaper.alignment, Alignment.topCenter);
      expect(wallpaper.fit, BoxFit.cover);
      expect(wallpaper.filterQuality, FilterQuality.high);
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

    final base = canvas.firstWhere(
      (gradient) =>
          gradient.begin == Alignment.topLeft &&
          gradient.end == Alignment.bottomRight,
      orElse: () => throw StateError('no base topLeft -> bottomRight gradient'),
    );
    expect(base.colors, [
      ChatColorScheme.dark.background,
      ChatColorScheme.dark.background,
      Color.lerp(
        ChatColorScheme.dark.background,
        ChatColorScheme.dark.backgroundAccent,
        0.42,
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
