// Spec 1 W10a (batch 3 fix round 1, M-1 to M-3): Planning's rows at large
// text give their label the row's free space (no Spacer splitting it), the
// split card's "Mark settled" keeps to the end, and an empty category's
// empty state stays centred while it fits.
import 'package:attune/features/planning/presentation/screens/planning_category_screen.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/link_block_view.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _phone = Size(390, 844);
const _tablet = Size(820, 1180);
const _entryScreen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

void _setPhone(WidgetTester t, double scale, [Size size = _phone]) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearAllTestValues);
}

/// How many lines [finder]'s Text takes.
double _lines(WidgetTester t, Finder finder) {
  final element = finder.evaluate().single;
  final text = element.widget as Text;
  final oneLine = TextPainter(
    text: TextSpan(
      text: 'x',
      style: DefaultTextStyle.of(element).style.merge(text.style),
    ),
    textScaler: MediaQuery.textScalerOf(element),
    textDirection: TextDirection.ltr,
  )..layout();
  return t.getSize(finder).height / oneLine.height;
}

Finder _menuIn(Finder block) => find.descendant(
  of: block,
  matching: find.byWidgetPredicate(
    (w) => w is PopupMenuButton && (w.tooltip ?? '').startsWith('Options for'),
  ),
);

FakePlanningGateway _entryWith(Map<String, dynamic> block) =>
    FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [block]),
    });

/// When the label wraps, its button reaches the menu: no blank space left
/// between them that the label could have used.
void _expectLabelUsesTheRow(
  WidgetTester t,
  String label,
  bool Function(Widget) isButton,
) {
  final text = find.text(label);
  final buttonRect = t.getRect(
    find.ancestor(of: text, matching: find.byWidgetPredicate(isButton)).first,
  );
  final menu = t.getRect(_menuIn(find.byType(LinkBlockView)));
  if (_lines(t, text) > 1.5) {
    expect(menu.left - buttonRect.right, lessThan(1), reason: '$label wraps');
  }
  expect(t.takeException(), isNull);
}

void main() {
  for (final scale in [1.0, 1.3, 1.6, 2.0]) {
    testWidgets('text $scale: "Add link" has the row up to the menu', (
      t,
    ) async {
      _setPhone(t, scale);
      await t.pumpWidget(
        planningTestApp(
          _entryWith(
            fakeBlockJson(
              id: 'ln',
              type: 'link',
              payload: {'label': 'Places to stay'},
            ),
          ),
          _entryScreen,
        ),
      );
      await t.pumpAndSettle();
      _expectLabelUsesTheRow(t, 'Add link', (w) => w is TextButton);
    });

    testWidgets('text $scale: "Open in YouTube" has the row up to the menu', (
      t,
    ) async {
      _setPhone(t, scale);
      await t.pumpWidget(
        planningTestApp(
          _entryWith(
            fakeBlockJson(
              id: 'ln',
              type: 'link',
              payload: {'url': 'https://youtu.be/wmZtslmSqfk'},
            ),
          ),
          _entryScreen,
          overrides: [
            planningYouTubePlayerProvider.overrideWithValue(
              (id) => Text('player $id'),
            ),
          ],
        ),
      );
      await t.pumpAndSettle();
      _expectLabelUsesTheRow(t, 'Open in YouTube', (w) => w is InkWell);
    });

    // A tablet's width: there "Mark settled" is narrower than half the
    // card's free space, so a split would leave blank space after it.
    testWidgets('text $scale: "Mark settled" sits at the end of the card', (
      t,
    ) async {
      _setPhone(t, scale, _tablet);
      final base = fakeEntryDetailJson(blocks: []);
      final entry = Map<String, dynamic>.from(base['entry'] as Map)
        ..['split'] = {
          'settled_at': null,
          'balances': [
            {
              'currency': 'GHS',
              'minor': 500,
              'owed_to': 'u-a',
              'owed_by': 'u-b',
            },
          ],
        };
      await t.pumpWidget(
        planningTestApp(
          FakePlanningGateway({
            'get_planning_entry': (_) => {...base, 'entry': entry},
          }),
          _entryScreen,
        ),
      );
      await t.pumpAndSettle();
      final row = t.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.balance_rounded),
              matching: find.byType(Row),
            )
            .first,
      );
      final button = t.getRect(
        find
            .ancestor(
              of: find.text('Mark settled'),
              matching: find.byType(TextButton),
            )
            .first,
      );
      expect(row.right - button.right, lessThan(1));
      if (scale > 1.0) {
        // Above 1.0 the button keeps to 40% and the balances get the rest.
        expect(button.width, lessThanOrEqualTo(0.4 * _tablet.width + 0.01));
      }
      expect(t.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('text $scale: an empty category centres its empty state', (
      t,
    ) async {
      _setPhone(t, scale);
      await t.pumpWidget(
        planningTestApp(
          FakePlanningGateway({
            'mark_planning_category_seen':
                (_) => {'seen_at': '2026-10-12T09:00:00Z'},
            'list_planning_entries':
                (_) => {'entries': <dynamic>[], 'next_cursor': null},
          }),
          PlanningCategoryScreen(
            relationshipId: 'r1',
            category: PlanningCategory.fromJson(
              fakeCategoryJson(id: 'c1', seedKey: 'trips', name: 'Trips'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final list = t.getRect(find.byType(ListView).first);
      final empty = t.getRect(find.byType(PlanningEmptyState));
      expect(
        empty.center.dy,
        moreOrLessEquals(list.top + 0.3 * _phone.height, epsilon: 1),
      );
      expect(t.takeException(), isNull);
    });
  }
}
