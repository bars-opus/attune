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

    // Every wallpaper layer must use the same width-fitted composition. If a
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
      expect(wallpaper.repeat, ImageRepeat.repeat);
      expect(wallpaper.alignment, Alignment.topCenter);
      expect(wallpaper.fit, BoxFit.none);
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

  testWidgets('dark mode restores background gradients without pattern glow', (tester) async {
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

    expect(wallpapers, hasLength(1));
    for (final wallpaper in wallpapers) {
      expect(wallpaper.repeat, ImageRepeat.repeat);
      expect(wallpaper.alignment, Alignment.topCenter);
      expect(wallpaper.fit, BoxFit.none);
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

    expect(canvas, hasLength(1), reason: 'one composite gradient, no Opacity');
    expect(canvas.single.colors.first, ChatColorScheme.dark.background);
    expect(
      canvas.single.colors.last,
      Color.lerp(
        ChatColorScheme.dark.background,
        ChatColorScheme.dark.backgroundAccent,
        0.28,
      ),
    );
    expect(
      find.descendant(of: wallpaperWidget, matching: find.byType(Opacity)),
      findsNothing,
      reason: 'a full-screen Opacity forces a saveLayer every frame',
    );
  });

  testWidgets('dark gradient follows scroll, saturates at 620px and stops rebuilding', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [ChatColorScheme.dark],
        ),
        home: Scaffold(
          body: AttuneChatWallpaper(
            scrollController: controller,
            child: ListView(
              controller: controller,
              children: const [SizedBox(height: 20000)],
            ),
          ),
        ),
      ),
    );
    Finder gradientBox() => find.descendant(
      of: find.byType(AttuneChatWallpaper),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient is LinearGradient,
      ),
    );
    LinearGradient gradient() =>
        ((tester.widget<DecoratedBox>(gradientBox()).decoration)
                as BoxDecoration)
            .gradient!
            as LinearGradient;

    final bg = ChatColorScheme.dark.background;
    final accent = Color.lerp(bg, ChatColorScheme.dark.backgroundAccent, 0.28)!;
    expect(gradient().colors.first, bg);

    controller.jumpTo(5000);
    await tester.pump();
    expect(gradient().colors.first, accent, reason: 'saturated: topLeft is accent');
    expect(gradient().colors.last, bg);

    expect(
      find.ancestor(
        of: gradientBox(),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
      reason: 'list repaints must not repaint the wallpaper gradient',
    );

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    controller.jumpTo(6000);
    await tester.pump();
    expect(
      rebuilt.whereType<AttuneChatWallpaper>(),
      isEmpty,
      reason: 'past saturation a scroll tick must not rebuild the wallpaper',
    );
    // The ListView child carries its own stretch AnimatedBuilder, so only the
    // wallpaper's own gradient path (ancestors of the gradient) is checked.
    expect(
      find.descendant(
        of: find.byType(AttuneChatWallpaper),
        matching: find.ancestor(
          of: gradientBox(),
          matching: find.byType(AnimatedBuilder),
        ),
      ),
      findsNothing,
    );
  });
}
