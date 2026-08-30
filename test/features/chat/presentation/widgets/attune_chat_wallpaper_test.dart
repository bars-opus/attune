import 'package:attune/features/chat/presentation/widgets/attune_chat_wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    final wallpaper = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))
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
  });
}
