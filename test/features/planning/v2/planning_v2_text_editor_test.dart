import 'dart:convert';

import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_text_editor_screen.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

Map<String, dynamic> _textBlock({String text = 'Hello', int version = 1}) => fakeBlockJson(
    id: 'b1', type: 'text', plainText: text, version: version, payload: {
      'delta': [{'insert': '$text\n'}]
    });

FakePlanningGateway _gateway() =>
    FakePlanningGateway({'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [_textBlock()])});

Future<void> _openEditor(WidgetTester tester, FakePlanningGateway g) async {
  await tester.pumpWidget(planningV2TestApp(g, const PlanningV2EntryScreen(relationshipId: 'r1', entryId: 'e1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Edit text'));
  await tester.pumpAndSettle();
}

QuillController _controller(WidgetTester tester) =>
    tester.state<PlanningV2TextEditorScreenState>(find.byType(PlanningV2TextEditorScreen)).controller;

void main() {
  testWidgets('read view renders the rich text; Edit opens the editor with it', (tester) async {
    await _openEditor(tester, _gateway());
    expect(find.byType(PlanningV2TextEditorScreen), findsOneWidget);
    expect(_controller(tester).document.toPlainText(), 'Hello\n');
  });

  testWidgets('save sends the version and a sanitized delta, then returns', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (p) => _textBlock(text: 'Hello there', version: 2);
    await _openEditor(tester, g);
    _controller(tester).document.insert(5, ' there');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final call = g.callsTo('update_planning_block').single;
    expect(call['p_version'], 1);
    expect((call['p_payload'] as Map)['delta'], [{'insert': 'Hello there\n'}]);
    expect(find.byType(PlanningV2TextEditorScreen), findsNothing);
  });

  testWidgets('pasted foreign attributes are stripped before save and the user is told (Review Focus 4)', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (p) => _textBlock(version: 2);
    await _openEditor(tester, g);
    _controller(tester).formatText(0, 5, Attribute.fromKeyValue('size', 'large'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    // findsWidgets: during the pop transition both scaffolds show the snackbar.
    expect(find.text('Some formatting is not supported here and was removed.'), findsWidgets);
    await tester.pumpAndSettle();
    final delta = jsonEncode((g.callsTo('update_planning_block').single['p_payload'] as Map)['delta']);
    expect(delta, isNot(contains('size')));
  });

  testWidgets('conflict: Use theirs loads their text; Keep mine re-saves on their version', (tester) async {
    final g = _gateway();
    var attempt = 0;
    g.handlers['update_planning_block'] = (p) {
      attempt++;
      if (attempt == 1) {
        throw PostgrestException(
            message: 'planning:stale_version', code: 'P0001',
            hint: jsonEncode({'current': _textBlock(text: 'Kofi wrote this', version: 4)}));
      }
      return _textBlock(text: 'Mine', version: 5);
    };
    await _openEditor(tester, g);
    _controller(tester).document.insert(0, 'Mine ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Your partner just changed this'), findsOneWidget);
    expect(find.text('Kofi wrote this'), findsOneWidget);
    await tester.tap(find.text('Keep mine'));
    await tester.pumpAndSettle();
    expect(g.callsTo('update_planning_block').last['p_version'], 4);
    expect(find.byType(PlanningV2TextEditorScreen), findsNothing);
  });

  testWidgets('conflict: Use theirs replaces the editor content and keeps the editor open', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (p) => throw PostgrestException(
        message: 'planning:stale_version', code: 'P0001',
        hint: jsonEncode({'current': _textBlock(text: 'Kofi wrote this', version: 4)}));
    await _openEditor(tester, g);
    _controller(tester).document.insert(0, 'Mine ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use theirs'));
    await tester.pumpAndSettle();
    expect(_controller(tester).document.toPlainText(), 'Kofi wrote this\n');
    expect(find.byType(PlanningV2TextEditorScreen), findsOneWidget);
  });

  testWidgets('save after the partner deleted the block closes with a message (Review Focus 2)', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] =
        (_) => throw const PostgrestException(message: 'planning:not_found', code: 'P0001');
    await _openEditor(tester, g);
    _controller(tester).document.insert(0, 'x');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Your partner removed this block.'), findsOneWidget);
    expect(find.byType(PlanningV2TextEditorScreen), findsNothing);
  });

  testWidgets('a network failure keeps the draft and the editor open', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (_) => throw Exception('offline');
    await _openEditor(tester, g);
    _controller(tester).document.insert(0, 'Draft ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanningV2TextEditorScreen), findsOneWidget);
    expect(_controller(tester).document.toPlainText(), startsWith('Draft '));
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await _openEditor(tester, _gateway());
    _controller(tester).document.insert(0, 'x');
    // Document.changes is a broadcast stream: the dirty flag's setState
    // lands a frame later, as it does for a real keystroke.
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanningV2TextEditorScreen), findsNothing);
  });

  test('highlight and text-colour tokens are the only colours the toolbar can apply', () {
    expect(PlanningV2TextEditorScreenState.tokens, ['yellow', 'green', 'blue', 'pink', 'purple']);
  });

  test('PlanningBlock import is used', () => expect(PlanningBlockType.text.name, 'text'));

  testWidgets('text over the 16 KB payload cap is refused in the editor with a specific message (final review I3)', (tester) async {
    final g = _gateway();
    await _openEditor(tester, g);
    _controller(tester).document.insert(0, 'ж' * 8200); // 2 bytes each: under 10k chars, over 16 KB
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('That text is too long to save. Split it into two blocks.'), findsOneWidget);
    expect(g.callsTo('update_planning_block'), isEmpty);
  });
}
