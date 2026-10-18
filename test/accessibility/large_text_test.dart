// Spec 5 (R5-13, F16): at large text sizes Together rows wrap instead of
// truncating to one line, and game tiles grow instead of clipping; targets
// stay labelled and at least 44 dp. Reduced motion is honoured (I7).
import 'dart:io';

import 'package:attune/core/ui/motion/stagger.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/games/presentation/widgets/game_grid_tile.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/widgets/together_item_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _long = 'Dinner at the place by the water we keep meaning to try again';

TogetherItem _item() => TogetherItem(
  kind: TogetherItemKind.event,
  id: 'e1',
  date: DateTime(2026, 11, 2),
  startsAt: DateTime(2026, 11, 2, 19),
  endsAt: DateTime(2026, 11, 2, 21),
  allDay: false,
  title: _long,
  participantIds: const ['ama', 'kofi'],
  createdBy: 'ama',
);

Future<void> _pump(WidgetTester t, Widget w, {double scale = 2.0}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, __) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: w)),
      ),
    ),
  ));
  await t.pump();
}

int? _lines(WidgetTester t, String text) =>
    t.widget<Text>(find.textContaining(text, findRichText: false).first).maxLines;

void main() {
  testWidgets('an agenda row wraps at 2x text and stays a labelled 44 dp target', (t) async {
    await _pump(t, TogetherItemRow(item: _item(), me: 'ama', partnerName: 'Kofi', onTap: () {}));
    expect(t.takeException(), isNull);
    final row = t.widget<InfoRowWidget>(find.byType(InfoRowWidget));
    expect(row.titleMaxLines, 2);
    expect(row.subTitleMaxLines, 3);
    await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('at normal size the agenda row keeps its one-line look', (t) async {
    await _pump(t, TogetherItemRow(item: _item(), me: 'ama', partnerName: 'Kofi'), scale: 1.0);
    final row = t.widget<InfoRowWidget>(find.byType(InfoRowWidget));
    expect(row.titleMaxLines, 1);
    expect(row.subTitleMaxLines, 1);
  });

  test('ritual rows use the same large-text lines', () {
    final src = File('lib/features/together/presentation/screens/together_screen.dart').readAsStringSync();
    final at = src.indexOf('Widget _ritualRow(');
    final body = src.substring(at, src.indexOf('String _dayLabel', at));
    expect(body, contains('togetherRowLines(context)'));
  });

  testWidgets('a game tile grows at 2x text instead of clipping', (t) async {
    await _pump(t, SizedBox(
      width: 170,
      child: GameGridTile(gameType: 'prototype', title: 'This or That', subtitle: _long, onTap: () {}),
    ));
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(GameGridTile)).height, greaterThanOrEqualTo(170 / 0.86));
    expect(_lines(t, 'This or That'), 2);
    await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('a game tile keeps its shape at normal size', (t) async {
    await _pump(t, SizedBox(
      width: 170,
      child: GameGridTile(gameType: 'prototype', title: 'This or That', subtitle: 'Quick picks', onTap: () {}),
    ), scale: 1.0);
    expect(t.getSize(find.byType(GameGridTile)).height, closeTo(170 / 0.86, 0.5));
  });

  testWidgets('Stagger renders at rest under reduced motion (I7)', (t) async {
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Stagger(children: const [Text('a', key: ValueKey('a')), Text('b', key: ValueKey('b'))])),
      ),
    ));
    await t.pump();
    for (final f in t.widgetList<FadeTransition>(find.byType(FadeTransition))) {
      expect(f.opacity.value, 1.0);
    }
    expect(t.binding.hasScheduledFrame, isFalse);
  });
}
