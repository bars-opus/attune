import 'dart:async';

import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/planning_block_motion.dart';
import 'package:attune/features/planning/presentation/widgets/planning_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _gateway() {
  final g = FakePlanningGateway({
    // One short block, so an inserted one lands on screen.
    'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
          fakeBlockJson(id: 'b1', payload: {'title': 'Shopping list'}),
        ]),
  });
  g.handlers['add_planning_block'] = (p) => fakeBlockJson(
      id: p['p_id'] as String, type: p['p_block_type'] as String, sortKey: 'Z', payload: {'title': 'New list'});
  g.handlers['delete_planning_block'] = (_) => {'deleted': true};
  return g;
}

double _shown(WidgetTester tester, String text) => tester
    .widget<SizeTransition>(find.ancestor(of: find.text(text), matching: find.byType(SizeTransition)).first)
    .sizeFactor
    .value;

Widget _reducedMotion(Widget app) => Builder(
    builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: app));

void main() {
  testWidgets('blocks already in the plan appear without animating', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pump(); // first frame with data
    await tester.pump();
    expect(_shown(tester, 'Shopping list'), 1.0);
  });

  testWidgets('an inserted block grows in', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(PlanningRibbon), matching: find.text('Checklist')));
    await tester.pump();
    await tester.pump(PlanningBlockMotion.duration ~/ 3);
    final mid = _shown(tester, 'New list');
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0));
    await tester.pumpAndSettle();
    expect(_shown(tester, 'New list'), 1.0);
  });

  testWidgets('deleting from the menu collapses the block first, then removes it', (tester) async {
    final g = _gateway();
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Shopping list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(PlanningBlockMotion.duration ~/ 3);
    expect(g.callsTo('delete_planning_block'), isEmpty, reason: 'still animating out');
    expect(_shown(tester, 'Shopping list'), lessThan(1.0));
    await tester.pumpAndSettle();
    expect(g.callsTo('delete_planning_block'), hasLength(1));
    expect(find.text('Shopping list'), findsNothing);
  });

  testWidgets('with Reduce motion on, deleting is immediate', (tester) async {
    final g = _gateway();
    await tester.pumpWidget(_reducedMotion(planningTestApp(g, _screen)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Shopping list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(g.callsTo('delete_planning_block'), hasLength(1));
  });

  testWidgets('a menu delete offers Undo afterwards, with no error from the removed block', (tester) async {
    final g = _gateway();
    final server = Completer<void>();
    // A real network answer arrives frames later, after the block has left the page.
    g.handlers['delete_planning_block'] = (_) async {
      await server.future;
      return {'deleted': true};
    };
    g.handlers['restore_planning_block'] = (_) => fakeBlockJson(id: 'b1', payload: {'title': 'Shopping list'});
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Shopping list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(); // collapses; the block leaves the page; the server is still thinking
    server.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Block removed'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(g.callsTo('restore_planning_block'), hasLength(1));
    expect(find.text('Shopping list'), findsOneWidget);
  });

  testWidgets('an inserted block is brought into view, so its entrance is seen', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            for (var i = 0; i < 6; i++) fakeBlockJson(id: 'c$i', sortKey: 'K$i', payload: {'title': 'List $i'}),
          ]),
    });
    g.handlers['add_planning_block'] = (p) => fakeBlockJson(
        id: p['p_id'] as String, type: p['p_block_type'] as String, sortKey: 'Z', payload: {'title': 'New list'});
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(PlanningRibbon), matching: find.text('Checklist')));
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byType(ReorderableListView));
    final block = tester.getRect(find.text('New list'));
    expect(list.top <= block.top && block.bottom <= list.bottom, isTrue,
        reason: 'the new block is on screen: $block within $list');
  });
}
