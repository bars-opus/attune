// Spec 1 W10a (batch 3 fix round 1, I-2): above 1.0 an InfoRowWidget's
// custom trailing keeps its own width (up to 40% of the screen) and the
// title column gets the rest, instead of the two splitting the row.
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = Size(390, 844);
const _title = 'Trips we keep meaning to take, someday soon';
const _trailingKey = Key('trailing');

Future<void> _pump(WidgetTester t, double scale, Widget trailing) async {
  t.view.physicalSize = _phone;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
  await t.pumpWidget(
    ScreenUtilConfig.builder(
      builder:
          (_) => MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  InfoRowWidget(
                    title: _title,
                    subtitle: 'Four ideas, two saved for the spring',
                    icon: Icons.flight_takeoff,
                    trailing: KeyedSubtree(key: _trailingKey, child: trailing),
                  ),
                ],
              ),
            ),
          ),
    ),
  );
}

void main() {
  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('text $scale: a 24 px trailing leaves the title the row', (
      t,
    ) async {
      await _pump(t, scale, const Icon(Icons.chevron_right, size: 24));
      final row = t.getRect(find.byType(InfoRowWidget));
      final title = t.getRect(find.text(_title));
      final trailing = t.getRect(find.byKey(_trailingKey));
      expect(t.takeException(), isNull);
      expect(trailing.width, 24);
      expect(title.width, greaterThanOrEqualTo(0.7 * row.width));
      expect(trailing.right, closeTo(row.right, 1));
    });
  }

  testWidgets('text 2.0: a wide trailing stops at 40% of the screen', (
    t,
  ) async {
    await _pump(t, 2.0, const Text('Settled up with each other last week'));
    final trailing = t.getRect(find.byKey(_trailingKey));
    expect(t.takeException(), isNull);
    expect(trailing.width, lessThanOrEqualTo(0.4 * _phone.width + 0.01));
  });
}
