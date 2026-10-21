import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/features/chat/presentation/widgets/attune_chat_wallpaper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Final wave M-8: the wallpaper follows the list's scroll only where it
/// paints it (the dark gradient), and picks up the list's current place
/// when it is attached rather than waiting for the next scroll.
void main() {
  Widget app(
    Brightness brightness,
    ScrollController controller, {
    required bool attached,
  }) {
    final base =
        brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    return MaterialApp(
      theme: base.copyWith(
        extensions: [
          brightness == Brightness.dark
              ? ChatColorScheme.dark
              : ChatColorScheme.light,
        ],
      ),
      home: AttuneChatWallpaper(
        scrollController: attached ? controller : null,
        child: ListView(
          controller: controller,
          children: const [SizedBox(height: 5000)],
        ),
      ),
    );
  }

  List<Color> gradientColors(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(AttuneChatWallpaper),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).gradient is LinearGradient,
            ),
          )
          .first,
    );
    return ((box.decoration as BoxDecoration).gradient! as LinearGradient)
        .colors;
  }

  testWidgets('dark: attaching to a scrolled list shows its place at once', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(Brightness.dark, controller, attached: false));
    final atTop = gradientColors(tester);
    controller.jumpTo(620);
    await tester.pump();

    await tester.pumpWidget(app(Brightness.dark, controller, attached: true));
    final attached = gradientColors(tester);
    expect(attached.first, isNot(atTop.first), reason: 'no scroll needed');
    expect(attached.first, atTop.last, reason: 'fully scrolled: reversed');
  });

  testWidgets('light: scrolling never rebuilds the wallpaper', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(Brightness.light, controller, attached: true));
    final stack = tester.widget<Stack>(
      find
          .descendant(
            of: find.byType(AttuneChatWallpaper),
            matching: find.byType(Stack),
          )
          .first,
    );
    for (var offset = 0.0; offset <= 620; offset += 31) {
      controller.jumpTo(offset);
      await tester.pump();
    }
    expect(
      identical(
        tester.widget<Stack>(
          find
              .descendant(
                of: find.byType(AttuneChatWallpaper),
                matching: find.byType(Stack),
              )
              .first,
        ),
        stack,
      ),
      isTrue,
    );
  });

  testWidgets('dark: scrolling still moves the gradient', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(Brightness.dark, controller, attached: true));
    final atTop = gradientColors(tester);
    controller.jumpTo(620);
    await tester.pump();
    expect(gradientColors(tester).first, atTop.last);
  });
}
