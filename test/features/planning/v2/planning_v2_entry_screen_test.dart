import 'package:attune/core/widgets/buttons/app_fab.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/planning/v2/domain/planning_outbox.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

FakePlanningGateway _gateway({bool template = false, String extraType = 'date'}) => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(isTemplate: template, blocks: [
            fakeBlockJson(id: 'b1', payload: {'title': 'Shopping list'}, items: [
              fakeItemJson(id: 'i1', text: 'Tomatoes', section: 'Produce', assignedTo: 'u-b'),
              fakeItemJson(id: 'i2', text: 'Milk', section: 'Dairy', checkedAt: '2026-10-12T09:00:00Z'),
            ]),
            fakeBlockJson(id: 'b2', type: extraType, sortKey: 'k', payload: {'title': 'Shop day'}, dateStart: '2026-10-17'),
          ]),
    });

const _screen = PlanningV2EntryScreen(relationshipId: 'r1', entryId: 'e1');

void main() {
  testWidgets('hero shows title and facts; blocks render in order; sections grouped', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(planningV2TestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(find.text('Saturday shop'), findsOneWidget);
    expect(find.text('1 of 2 done'), findsOneWidget);
    expect(find.text('Oct 17, 2026'), findsWidgets);
    expect(find.text('Produce'), findsOneWidget);
    expect(find.text('Tomatoes'), findsOneWidget);
    expect(find.text('Milk'), findsNothing, reason: 'ticked items are folded');
    expect(find.text('1 done'), findsOneWidget);
    expect(find.bySemanticsLabel('Assigned to Kofi'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('ticking calls the RPC with an op id', (tester) async {
    final semantics = tester.ensureSemantics();
    final g = _gateway();
    g.handlers['set_planning_block_item_checked'] =
        (p) => fakeItemJson(id: 'i1', text: 'Tomatoes', section: 'Produce', checkedAt: '2026-10-12T10:00:00Z', version: 2);
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Tomatoes, not done'));
    await tester.pumpAndSettle();
    final call = g.callsTo('set_planning_block_item_checked').single;
    expect(call['p_checked'], isTrue);
    expect(call['p_op_id'], isA<String>());
    expect(find.text('2 done'), findsOneWidget);
    semantics.dispose(); // must be disposed inside the test body
  });

  testWidgets('an offline tick shows the waiting-to-sync chip', (tester) async {
    final semantics = tester.ensureSemantics();
    final g = _gateway();
    g.handlers['set_planning_block_item_checked'] = (_) => throw Exception('offline');
    final store = MemoryOutboxStore();
    await tester.pumpWidget(planningV2TestApp(g, _screen, store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Tomatoes, not done'));
    await tester.pumpAndSettle();
    expect(find.text('1 change waiting to sync'), findsOneWidget);
    expect(store.raw, hasLength(1));
    semantics.dispose(); // must be disposed inside the test body
  });

  testWidgets('adding an item from the field', (tester) async {
    final g = _gateway();
    g.handlers['add_planning_block_item'] = (p) => fakeItemJson(id: p['p_id'] as String, text: 'Eggs');
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Add item'), 'Eggs');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(g.callsTo('add_planning_block_item').single['p_text'], 'Eggs');
    expect(find.text('Eggs'), findsOneWidget);
  });

  testWidgets('swipe deletes a block with Undo that restores it', (tester) async {
    final g = _gateway();
    g.handlers['delete_planning_block'] = (_) => {'deleted': true};
    g.handlers['restore_planning_block'] = (_) => fakeBlockJson(id: 'b2', type: 'date', payload: {'title': 'Shop day'}, dateStart: '2026-10-17');
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('block-b2')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Shop day'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(g.callsTo('restore_planning_block'), hasLength(1));
    expect(find.text('Shop day'), findsOneWidget);
  });

  testWidgets('Move down from the block menu (non-drag reorder for accessibility)', (tester) async {
    final g = _gateway();
    g.handlers['move_planning_block'] = (_) => fakeBlockJson(id: 'b1', sortKey: 'z');
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Shopping list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(g.callsTo('move_planning_block').single['p_after_id'], 'b2');
  });

  testWidgets('tool tray adds a checklist block at the end', (tester) async {
    final g = _gateway();
    g.handlers['add_planning_block'] = (p) => fakeBlockJson(id: p['p_id'] as String, payload: {}, sortKey: 'z');
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add block'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist'));
    await tester.pumpAndSettle();
    final call = g.callsTo('add_planning_block').single;
    expect(call['p_block_type'], 'checklist');
    expect(call['p_after_id'], 'b2');
  });

  testWidgets('editing an item sets a due date (spec §6.2; Timeline reads it in P2)', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block_item'] = (p) =>
        {...fakeItemJson(id: 'i1', text: 'Tomatoes', section: 'Produce', version: 2), 'due_date': p['p_due_date']};
    await tester.pumpWidget(planningV2TestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomatoes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No due date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final ymd = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(g.callsTo('update_planning_block_item').single['p_due_date'], ymd);
    expect(find.textContaining('Due '), findsOneWidget);
  });

  testWidgets('text at 200% scale renders without overflow (spec §5)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(planningV2TestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Tomatoes'), findsOneWidget);
  });

  testWidgets('uses the app design system: AppFab and CardInkWell block cards', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(find.byType(AppFab), findsOneWidget);
    expect(find.byType(CardInkWell), findsNWidgets(2));
  });

  testWidgets('templates show the template banner', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(template: true), _screen));
    await tester.pumpAndSettle();
    expect(find.text('Template. New plans start from this.'), findsOneWidget);
  });

  testWidgets('a block type from a newer server renders a placeholder', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(extraType: 'budget'), _screen));
    await tester.pumpAndSettle();
    expect(find.text('This block needs a newer version of Attune.'), findsOneWidget);
  });
}
