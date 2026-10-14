import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart' show withScreenUtil;
import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

void main() {
  testWidgets('adding a link closes only its sheet: the note stays open, the screen under it untouched', (tester) async {
    final g = FakePlanningGateway({'get_planning_entry': (_) => fakeEntryDetailJson()});
    g.handlers['add_planning_block'] = (p) =>
        fakeBlockJson(id: p['p_id'] as String, type: 'link', payload: p['p_payload'] as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
      overrides: planningOverrides(g),
      child: withScreenUtil(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _screen)),
              child: const Text('Category'),
            ),
          ),
        ),
      )),
    ));
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Web address'), 'youtu.be/wmZtslmSqfk');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(g.callsTo('add_planning_block'), hasLength(1));
    expect(find.byType(PlanningEntryScreen), findsOneWidget, reason: 'the note must stay open');
  });

  Future<FakePlanningGateway> openLinkSheet(WidgetTester tester) async {
    final g = FakePlanningGateway({'get_planning_entry': (_) => fakeEntryDetailJson()});
    g.handlers['add_planning_block'] = (p) =>
        fakeBlockJson(id: p['p_id'] as String, type: 'link', payload: p['p_payload'] as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
      overrides: planningOverrides(g),
      child: withScreenUtil(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _screen)),
              child: const Text('Category'),
            ),
          ),
        ),
      )),
    ));
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Web address'), 'youtu.be/wmZtslmSqfk');
    return g;
  }

  testWidgets('Done tapped twice closes the sheet once; the note stays open', (tester) async {
    final g = await openLinkSheet(tester);
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Save'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PlanningEntryScreen), findsOneWidget);
    expect(g.callsTo('add_planning_block'), hasLength(1));
  });

  testWidgets("the keyboard's Done then the header's Done: the note stays open", (tester) async {
    final g = await openLinkSheet(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Save'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PlanningEntryScreen), findsOneWidget);
    expect(g.callsTo('add_planning_block'), hasLength(1));
  });

  testWidgets('the keyboard closing while the sheet animates away does not pop the note', (tester) async {
    addTearDown(tester.view.reset);
    final g = await openLinkSheet(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900); // keyboard up
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 40));
    tester.view.resetViewInsets(); // keyboard goes down mid-animation
    await tester.pumpAndSettle();
    expect(find.byType(PlanningEntryScreen), findsOneWidget);
    expect(g.callsTo('add_planning_block'), hasLength(1));
  });

  testWidgets('Done firing twice in one frame (double tap, or keyboard + header) still closes only the sheet',
      (tester) async {
    final g = await openLinkSheet(tester);
    final done = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save'));
    done.onPressed!();
    done.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(PlanningEntryScreen), findsOneWidget, reason: 'the second Done must not pop the note');
    expect(g.callsTo('add_planning_block'), hasLength(1));
  });
}
