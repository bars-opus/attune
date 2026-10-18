import 'package:attune/features/planning/presentation/widgets/planning_ribbon.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/planning/domain/planning_outbox.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

FakePlanningGateway _gateway({bool template = false, String extraType = 'date'}) => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(isTemplate: template, blocks: [
            fakeBlockJson(id: 'b1', payload: {'title': 'Shopping list'}, items: [
              fakeItemJson(id: 'i1', text: 'Tomatoes', section: 'Produce', assignedTo: 'u-b'),
              fakeItemJson(id: 'i2', text: 'Milk', section: 'Dairy', checkedAt: '2026-10-12T09:00:00Z'),
            ]),
            fakeBlockJson(id: 'b2', type: extraType, sortKey: 'k', payload: {'title': 'Shop day'}, dateStart: '2026-10-17'),
          ]),
    });

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

/// The page's vertical list (the ribbon and tables scroll sideways).
final _page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

void main() {
  testWidgets('hero shows title and facts; blocks render in order; sections grouped', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
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
    await tester.pumpWidget(planningTestApp(g, _screen));
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
    await tester.pumpWidget(planningTestApp(g, _screen, store: store));
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
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Add item'), 'Eggs');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(g.callsTo('add_planning_block_item').single['p_text'], 'Eggs');
    expect(find.text('Eggs'), findsOneWidget);
  });

  testWidgets('swipe RIGHT deletes a block card with Undo that restores it', (tester) async {
    final g = _gateway();
    g.handlers['delete_planning_block'] = (_) => {'deleted': true};
    g.handlers['restore_planning_block'] = (_) => fakeBlockJson(id: 'b1', payload: {'title': 'Shopping list'});
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    // From the card's heading: its item rows have their own swipe.
    await tester.drag(find.text('Shopping list'), const Offset(600, 0)); // right = delete everywhere
    await tester.pumpAndSettle();
    expect(find.text('Shopping list'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(g.callsTo('restore_planning_block'), hasLength(1));
    expect(find.text('Shopping list'), findsOneWidget);
  });

  testWidgets('a dated Date block sits inline: deleted from its menu, not by swiping', (tester) async {
    final g = _gateway();
    g.handlers['delete_planning_block'] = (_) => {'deleted': true};
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.byKey(const ValueKey('block-b2')), matching: find.byType(Dismissible)), findsNothing);
    await tester.scrollUntilVisible(find.byTooltip('Options for Shop day'), 100, scrollable: _page);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Shop day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(g.callsTo('delete_planning_block').single, {'p_id': 'b2'});
  });

  testWidgets('Move down from the block menu (non-drag reorder for accessibility)', (tester) async {
    final g = _gateway();
    g.handlers['move_planning_block'] = (_) => fakeBlockJson(id: 'b1', sortKey: 'z');
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Shopping list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(g.callsTo('move_planning_block').single['p_after_id'], 'b2');
  });

  testWidgets('Insert adds a checklist block at the end when no block is selected', (tester) async {
    final g = _gateway();
    g.handlers['add_planning_block'] = (p) => fakeBlockJson(id: p['p_id'] as String, payload: {}, sortKey: 'z');
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(PlanningRibbon), matching: find.text('Checklist')));
    await tester.pumpAndSettle();
    final call = g.callsTo('add_planning_block').single;
    expect(call['p_block_type'], 'checklist');
    expect(call['p_after_id'], 'b2');
  });

  testWidgets('editing an item sets a due date (spec §6.2; Timeline reads it in P2)', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block_item'] = (p) =>
        {...fakeItemJson(id: 'i1', text: 'Tomatoes', section: 'Produce', version: 2), 'due_date': p['p_due_date']};
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomatoes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No due date'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20)); // close the wheel without turning it: today
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
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Tomatoes'), findsOneWidget);
  });

  testWidgets('uses the app design system: CardInkWell block cards, and a ribbon instead of a FAB', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(find.byType(PlanningRibbon), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(CardInkWell), findsOneWidget, reason: 'the checklist; a dated Date block sits inline');
  });

  testWidgets('templates show the template banner', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(template: true), _screen));
    await tester.pumpAndSettle();
    expect(find.text('Template. New plans start from this.'), findsOneWidget);
  });

  testWidgets('a block type from a newer server renders a placeholder', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(extraType: 'hologram'), _screen));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('This block needs a newer version of Attune.'), 100, scrollable: _page);
    expect(find.text('This block needs a newer version of Attune.'), findsOneWidget);
  });

  testWidgets('queued changes offer Retry; ops the server refuses are shown, not silently dropped (final review I2)', (tester) async {
    final g = _gateway();
    g.handlers['set_planning_block_item_checked'] =
        (_) => throw const PostgrestException(message: 'planning:not_found', code: 'P0001');
    final store = MemoryOutboxStore()
      ..raw = [
        {'kind': 'check', 'op_id': 'op-1', 'relationship_id': 'r1', 'entry_id': 'e1', 'item_id': 'i1', 'checked': true}
      ];
    await tester.pumpWidget(planningTestApp(g, _screen, store: store));
    await tester.pumpAndSettle();
    expect(find.text('1 change waiting to sync'), findsOneWidget);
    await tester.tap(find.text('Retry sync'));
    await tester.pumpAndSettle();
    expect(find.text("1 change couldn't be saved"), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text("1 change couldn't be saved"), findsNothing);
  });

  testWidgets('swipe RIGHT deletes a checklist item; a left swipe does nothing', (tester) async {
    final g = _gateway();
    g.handlers['delete_planning_block_item'] = (_) => {'deleted': true};
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('item-i1')), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(g.callsTo('delete_planning_block_item'), isEmpty);
    await tester.drag(find.byKey(const ValueKey('item-i1')), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(g.callsTo('delete_planning_block_item').single, {'p_id': 'i1'});
  });

  testWidgets('the checklist heading matches the Date block: small, not bold, a medium gap below', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    final heading = tester.widget<Text>(find.text('Shopping list'));
    final ctx = tester.element(find.text('Shopping list'));
    expect(heading.style?.fontSize, Theme.of(ctx).textTheme.titleSmall?.fontSize);
    expect(heading.style?.fontWeight, FontWeight.w400);
    final gap = tester.getTopLeft(find.text('Produce')).dy - tester.getBottomLeft(find.text('Shopping list')).dy;
    expect(gap, greaterThanOrEqualTo(Spacing.md));
  });

  // Spec 7 (research 06 B9 (c)): a plan can be put away without a sound —
  // archived, out of Recent and the calendar, its countdowns cancelled.
  testWidgets('Put away gently archives the plan quietly', (tester) async {
    final g = _gateway();
    g.handlers['put_planning_entry_away'] = (_) => null;
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plan options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Put away gently'));
    await tester.pumpAndSettle();
    expect(g.callsTo('put_planning_entry_away').single, {'p_entry_id': 'e1'});
    expect(find.text('Put away. It\'s in Done & archived.'), findsOneWidget);
  });
}
