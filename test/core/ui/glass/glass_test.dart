import 'dart:ui' show SemanticsAction;

import 'package:attune/core/ui/glass/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool highContrast = false, bool reduceMotion = false}) {
  return MaterialApp(
    // Above the Navigator, so menu routes see the same settings.
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        highContrast: highContrast,
        disableAnimations: reduceMotion,
      ),
      child: app!,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('glass shows its child, padded, without errors where the shader is unavailable', (tester) async {
    await tester.pumpWidget(_app(const LiquidGlass(padding: EdgeInsets.all(10), child: Text('inside'))));
    expect(find.text('inside'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final glass = tester.getRect(find.byType(LiquidGlass));
    final text = tester.getRect(find.text('inside'));
    expect(text.left - glass.left, closeTo(10, 0.01));
  });

  testWidgets('high contrast: an opaque bordered surface, nothing shows through', (tester) async {
    await tester.pumpWidget(_app(const LiquidGlass(child: Text('inside')), highContrast: true));
    final box = tester.widget<DecoratedBox>(
      find.ancestor(of: find.text('inside'), matching: find.byType(DecoratedBox)).first,
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(decoration.color!.a, 1.0);
  });

  testWidgets('glass icon button: a labelled button that taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(GlassIconButton(icon: Icons.add, onPressed: () => taps++, tooltip: 'Add')));
    expect(find.bySemanticsLabel('Add'), findsOneWidget);
    // One node, named once, that a screen reader can activate.
    final node = tester.getSemantics(find.bySemanticsLabel('Add'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(tester.getSize(find.byType(GlassIconButton)).width, greaterThanOrEqualTo(44));
    await tester.tap(find.byType(GlassIconButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('glass menu: opens from its button, a row returns its value', (tester) async {
    String? chosen;
    await tester.pumpWidget(_app(
      GlassMenuButton<String>(
        tooltip: 'More',
        itemBuilder: (_) => const [
          GlassMenuItem(value: 'edit', label: 'Edit', icon: Icons.edit),
          GlassMenuItem(value: 'delete', label: 'Delete', destructive: true),
        ],
        onSelected: (v) => chosen = v,
      ),
    ));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(chosen, 'delete');
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('glass menu: a tap outside closes it and chooses nothing', (tester) async {
    String? chosen;
    await tester.pumpWidget(_app(
      GlassMenuButton<String>(
        tooltip: 'More',
        itemBuilder: (_) => const [GlassMenuItem(value: 'edit', label: 'Edit')],
        onSelected: (v) => chosen = v,
      ),
    ));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    expect(chosen, isNull);
  });

  testWidgets('glass menu: with no rows the button opens nothing', (tester) async {
    await tester.pumpWidget(_app(
      GlassMenuButton<String>(
        tooltip: 'More',
        itemBuilder: (_) => const [],
        onSelected: (_) {},
      ),
    ));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('glass menu: a disabled row does nothing', (tester) async {
    String? chosen;
    await tester.pumpWidget(_app(
      GlassMenuButton<String>(
        tooltip: 'More',
        itemBuilder: (_) => const [GlassMenuItem(value: 'edit', label: 'Edit', enabled: false)],
        onSelected: (v) => chosen = v,
      ),
    ));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('glass menu: with reduce motion it opens fully at once', (tester) async {
    await tester.pumpWidget(_app(
      GlassMenuButton<String>(
        tooltip: 'More',
        itemBuilder: (_) => const [GlassMenuItem(value: 'edit', label: 'Edit')],
        onSelected: (_) {},
      ),
      reduceMotion: true,
    ));
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    // Full size from the first frame: no growth out of the button.
    final menuGlass = find.ancestor(of: find.text('Edit'), matching: find.byType(LiquidGlass));
    expect(tester.getSize(menuGlass.first).width, greaterThan(200));
    await tester.pumpAndSettle();
  });

  testWidgets('glass menu stays on screen at large text', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      // Above the Navigator, so the menu's route sees the large text too.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: GlassMenuButton<int>(
            tooltip: 'More',
            itemBuilder: (_) => [
              for (var i = 0; i < 6; i++) GlassMenuItem(value: i, label: 'A longer row label $i'),
            ],
            onSelected: (_) {},
          ),
        ),
      ),
    ));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final menuGlass = find.ancestor(of: find.text('A longer row label 0'), matching: find.byType(LiquidGlass)).first;
    final menu = tester.getRect(menuGlass);
    const screen = Rect.fromLTWH(0, 0, 390, 844);
    expect(screen.contains(menu.topLeft) && screen.contains(menu.bottomRight - const Offset(1, 1)), isTrue);
    final first = tester.getRect(find.text('A longer row label 0'));
    expect(first.left, greaterThanOrEqualTo(menu.left));
    expect(first.right, lessThanOrEqualTo(menu.right));
  });

  testWidgets('liquid lens sits behind the selected item and follows it', (tester) async {
    final keys = List.generate(3, (_) => GlobalKey());
    Widget bar(int selected) => _app(
          SizedBox(
            width: 300,
            height: 60,
            child: LiquidLensRow(
              selectedIndex: selected,
              itemKeys: keys,
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(child: Center(child: SizedBox(key: keys[i], width: 40, height: 40))),
                ],
              ),
            ),
          ),
        );
    Rect lens() => tester.getRect(
          find.descendant(of: find.byType(LiquidLensRow), matching: find.byType(LiquidGlass)),
        );

    await tester.pumpWidget(bar(0));
    await tester.pumpAndSettle();
    expect(lens().center.dx, closeTo(tester.getCenter(find.byKey(keys[0])).dx, 0.5));
    // A capsule, never a circle.
    expect(lens().width, greaterThan(lens().height));

    await tester.pumpWidget(bar(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Mid-move it stretches wider than it is at rest.
    expect(lens().width, greaterThan(lens().height * 1.6 + 1));
    await tester.pumpAndSettle();
    expect(lens().center.dx, closeTo(tester.getCenter(find.byKey(keys[2])).dx, 0.5));
  });

  testWidgets('pressable: reduce motion taps without any scaling', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(
      GlassPressable(onTap: () => taps++, child: const SizedBox(width: 50, height: 50)),
      reduceMotion: true,
    ));
    await tester.tap(find.byType(GlassPressable));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.descendant(of: find.byType(GlassPressable), matching: find.byType(Transform)), findsNothing);
  });
}
