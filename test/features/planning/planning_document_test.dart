import 'dart:convert';

import 'package:attune/features/planning/domain/delta_sanitizer.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/inline_text_block.dart';
import 'package:attune/features/planning/presentation/widgets/planning_ribbon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Map<String, dynamic> _textBlock({String id = 'b1', String text = 'Hello', int version = 1, String sortKey = 'V'}) =>
    fakeBlockJson(id: id, type: 'text', plainText: text, version: version, sortKey: sortKey, payload: {
      'delta': [{'insert': '$text\n'}]
    });

FakePlanningGateway _gateway({List<Map<String, dynamic>>? blocks}) =>
    FakePlanningGateway({'get_planning_entry': (_) => fakeEntryDetailJson(blocks: blocks ?? [_textBlock()])});

Future<void> _open(WidgetTester tester, FakePlanningGateway g, {Widget screen = _screen}) async {
  await tester.pumpWidget(planningTestApp(g, screen));
  await tester.pumpAndSettle();
}

QuillController _controller(WidgetTester tester, [int i = 0]) =>
    tester.state<InlineTextBlockState>(find.byType(InlineTextBlock).at(i)).controller;

/// Typing, then the pause after which text saves itself.
Future<void> _typeAndPause(WidgetTester tester, String text, {int at = 0}) async {
  _controller(tester).document.insert(at, text);
  await tester.pump();
  await tester.pump(InlineTextBlock.debounce);
  await tester.pumpAndSettle();
}

List<Map<String, dynamic>> _ops(Map<String, dynamic> call) =>
    [for (final o in (call['p_payload'] as Map)['delta'] as List) Map<String, dynamic>.from(o as Map)];

Finder _ribbon(String label) => find.descendant(of: find.byType(PlanningRibbon), matching: find.text(label));

void main() {
  group('text is edited in place on the plan', () {
    testWidgets('no separate editor: the text is on the page, editable', (tester) async {
      await _open(tester, _gateway());
      expect(find.byType(InlineTextBlock), findsOneWidget);
      expect(_controller(tester).document.toPlainText(), 'Hello\n');
      expect(_controller(tester).readOnly, isFalse);
    });

    testWidgets('typing saves itself a second after you stop, with the version and a sanitized delta', (tester) async {
      final g = _gateway();
      g.handlers['update_planning_block'] = (p) => _textBlock(text: 'Hello there', version: 2);
      await _open(tester, g);
      await _typeAndPause(tester, ' there', at: 5);
      final call = g.callsTo('update_planning_block').single;
      expect(call['p_version'], 1);
      expect((call['p_payload'] as Map)['delta'], [{'insert': 'Hello there\n'}]);
    });

    testWidgets('leaving the plan saves what was typed', (tester) async {
      final g = _gateway();
      g.handlers['update_planning_block'] = (p) => _textBlock(text: 'xHello', version: 2);
      await tester.pumpWidget(planningTestApp(
          g,
          Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => _screen)),
              child: const Text('open'),
            ),
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      _controller(tester).document.insert(0, 'x');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(g.callsTo('update_planning_block'), hasLength(1));
    });

    testWidgets('pasted foreign attributes are stripped before save and the user is told (Review Focus 4)', (tester) async {
      final g = _gateway();
      g.handlers['update_planning_block'] = (p) => _textBlock(version: 2);
      await _open(tester, g);
      _controller(tester).formatText(0, 5, Attribute.fromKeyValue('font', 'serif'));
      await tester.pump();
      await tester.pump(InlineTextBlock.debounce);
      await tester.pump();
      expect(find.text('Some formatting is not supported here and was removed.'), findsOneWidget);
      await tester.pumpAndSettle();
      final delta = jsonEncode((g.callsTo('update_planning_block').single['p_payload'] as Map)['delta']);
      expect(delta, isNot(contains('serif')));
    });

    testWidgets('conflict: Keep mine re-saves on their version', (tester) async {
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
      await _open(tester, g);
      await _typeAndPause(tester, 'Mine ');
      expect(find.text('Your partner just changed this'), findsOneWidget);
      expect(find.text('Kofi wrote this'), findsOneWidget);
      await tester.tap(find.text('Keep mine'));
      await tester.pumpAndSettle();
      expect(g.callsTo('update_planning_block').last['p_version'], 4);
    });

    testWidgets('conflict: Use theirs replaces the text on the page', (tester) async {
      final g = _gateway();
      g.handlers['update_planning_block'] = (p) => throw PostgrestException(
          message: 'planning:stale_version', code: 'P0001',
          hint: jsonEncode({'current': _textBlock(text: 'Kofi wrote this', version: 4)}));
      await _open(tester, g);
      await _typeAndPause(tester, 'Mine ');
      await tester.tap(find.text('Use theirs'));
      await tester.pumpAndSettle();
      expect(_controller(tester).document.toPlainText(), 'Kofi wrote this\n');
    });

    testWidgets('a save after the partner deleted the block says so (Review Focus 2)', (tester) async {
      final g = _gateway();
      g.handlers['update_planning_block'] =
          (_) => throw const PostgrestException(message: 'planning:not_found', code: 'P0001');
      await _open(tester, g);
      await _typeAndPause(tester, 'x');
      expect(find.text('Your partner removed this block.'), findsOneWidget);
    });

    testWidgets('a network failure keeps the draft on the page and saves it on the next pause', (tester) async {
      final g = _gateway();
      var fail = true;
      g.handlers['update_planning_block'] = (_) {
        if (fail) throw Exception('offline');
        return _textBlock(text: 'Draft Hello', version: 2);
      };
      await _open(tester, g);
      await _typeAndPause(tester, 'Draft ');
      expect(_controller(tester).document.toPlainText(), startsWith('Draft '));
      fail = false;
      await _typeAndPause(tester, '');
      _controller(tester).document.insert(0, ' ');
      await tester.pump(InlineTextBlock.debounce);
      await tester.pumpAndSettle();
      expect(g.callsTo('update_planning_block').length, greaterThanOrEqualTo(2));
    });

    testWidgets('text over the 16 KB payload cap is refused with a specific message (final review I3)', (tester) async {
      final g = _gateway();
      await _open(tester, g);
      _controller(tester).document.insert(0, 'ж' * 8200); // 2 bytes each: under 10k chars, over 16 KB
      await tester.pump();
      await tester.pump(InlineTextBlock.debounce);
      await tester.pump();
      expect(find.text('That text is too long to save. Split it into two blocks.'), findsOneWidget);
      expect(g.callsTo('update_planning_block'), isEmpty);
    });

    testWidgets('a new note opens with the cursor in its text, and takes its title from the first line', (tester) async {
      final g = FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(
            title: 'New note', seedKey: 'notes', categoryName: 'Notes', blocks: [_textBlock(text: '')]),
        'update_planning_block': (_) => _textBlock(text: 'Groceries for Sunday\nmilk', version: 2),
        'update_planning_entry': (p) => {
              'entry': {...fakeEntryDetailJson(seedKey: 'notes')['entry'] as Map, 'title': p['p_title']}
            },
      });
      await _open(tester, g, screen: const PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1', openEditor: true));
      final editable = tester.widget<QuillEditor>(find.byType(QuillEditor));
      expect(editable.focusNode.hasFocus, isTrue, reason: 'writing starts at once');
      await _typeAndPause(tester, 'Groceries for Sunday\nmilk');
      expect(g.callsTo('update_planning_entry').single['p_title'], 'Groceries for Sunday');
    });

    testWidgets('a note the user already titled keeps its title', (tester) async {
      final g = FakePlanningGateway({
        'get_planning_entry': (_) =>
            fakeEntryDetailJson(title: 'Our list', seedKey: 'notes', blocks: [_textBlock(text: '')]),
        'update_planning_block': (_) => _textBlock(text: 'Groceries', version: 2),
      });
      await _open(tester, g);
      await _typeAndPause(tester, 'Groceries');
      expect(g.callsTo('update_planning_entry'), isEmpty);
    });

    testWidgets('the title is edited in place', (tester) async {
      final g = _gateway();
      g.handlers['update_planning_entry'] = (p) => {
            'entry': {...fakeEntryDetailJson()['entry'] as Map, 'title': p['p_title']}
          };
      await _open(tester, g);
      await tester.enterText(find.widgetWithText(TextField, 'Saturday shop'), 'Sunday shop');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(g.callsTo('update_planning_entry').single['p_title'], 'Sunday shop');
    });
  });

  testWidgets('deleting a text block that has the cursor raises no error', (tester) async {
    final g = _gateway(blocks: [_textBlock(), fakeBlockJson(id: 'c1', type: 'checklist', sortKey: 'W')]);
    g.handlers['delete_planning_block'] = (_) => {'deleted': true};
    await _open(tester, g);
    await tester.tap(find.byType(QuillEditor)); // the ribbon now follows this block
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options for Text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(InlineTextBlock), findsNothing);
    expect(find.text('Tap into text to format it'), findsOneWidget, reason: 'the ribbon let go of it');
  });

  group('the ribbon', () {
    test('highlight and text-colour tokens are the only colours it applies', () {
      expect(PlanningRibbon.tokens, ['yellow', 'green', 'blue', 'pink', 'purple']);
    });

    testWidgets('Home formats the text the cursor is in', (tester) async {
      await _open(tester, _gateway());
      expect(find.text('Tap into text to format it'), findsOneWidget);
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      expect(find.byType(QuillSimpleToolbar), findsOneWidget);
      _controller(tester).updateSelection(const TextSelection(baseOffset: 0, extentOffset: 5), ChangeSource.local);
      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(_controller(tester).document.toDelta().toJson().first['attributes'], {'bold': true});
    });

    testWidgets('colour sheets: swatches only, a no-colour swatch clears, full width', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200); // wide enough that a sheet could stop short
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final g = _gateway();
      g.handlers['update_planning_block'] = (p) => _textBlock(version: 2); // formatting autosaves
      await _open(tester, g);
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      _controller(tester).updateSelection(const TextSelection(baseOffset: 0, extentOffset: 5), ChangeSource.local);
      await tester.tap(find.byTooltip('Highlight'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextButton)), findsNothing);
      expect(tester.getSize(find.byType(BottomSheet)).width, 1600);
      await tester.tap(find.byTooltip('Highlight yellow'));
      await tester.pumpAndSettle();
      expect(_controller(tester).document.toDelta().toJson().first['attributes'], {'background': 'yellow'});
      await tester.tap(find.byTooltip('Highlight'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('No highlight'));
      await tester.pumpAndSettle();
      expect(_controller(tester).document.toDelta().toJson().first['attributes'], isNull);
      await tester.tap(find.byTooltip('Text size'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(BottomSheet)).width, 1600, reason: 'every ribbon sheet spans the screen');
    });

    testWidgets('Quill dialogs opened from the ribbon (link) have their translations', (tester) async {
      await _open(tester, _gateway());
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      _controller(tester).updateSelection(const TextSelection(baseOffset: 0, extentOffset: 5), ChangeSource.local);
      await tester.tap(find.byIcon(Icons.link));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('choices open in a sheet above the keyboard, not a dropdown under it: text size', (tester) async {
      await _open(tester, _gateway());
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      _controller(tester).updateSelection(const TextSelection(baseOffset: 0, extentOffset: 5), ChangeSource.local);
      await tester.tap(find.byTooltip('Text size'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      for (final label in ['Small', 'Normal', 'Large', 'Huge']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Large'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(_controller(tester).document.toDelta().toJson().first['attributes'], {'size': 'large'});
    });

    testWidgets('choices open in a sheet above the keyboard, not a dropdown under it: headings', (tester) async {
      await _open(tester, _gateway());
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(MenuAnchor), findsNothing, reason: 'no dropdowns left in Home');
      await tester.tap(find.byTooltip('Heading'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heading 2'));
      await tester.pumpAndSettle();
      expect(_controller(tester).document.toDelta().toJson().last['attributes'], {'header': 2});
      await tester.tap(find.byTooltip('Heading'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Normal text'));
      await tester.pumpAndSettle();
      expect(_controller(tester).document.toDelta().toJson().last['attributes'], isNull);
    });

    testWidgets('Insert mid-paragraph splits it around the new block, as a word processor does', (tester) async {
      final g = _gateway(blocks: [_textBlock(text: 'Hello world')]);
      var n = 0;
      g.handlers['update_planning_block'] = (p) => _textBlock(text: 'Hello', version: 2);
      g.handlers['add_planning_block'] = (p) => fakeBlockJson(
          id: p['p_id'] as String, type: p['p_block_type'] as String, sortKey: 'W${n++}',
          payload: p['p_payload'] as Map<String, dynamic>);
      await _open(tester, g);
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      _controller(tester).updateSelection(const TextSelection.collapsed(offset: 5), ChangeSource.local);
      await tester.tap(find.text('Insert'));
      await tester.pumpAndSettle();
      await tester.tap(_ribbon('Checklist'));
      await tester.pumpAndSettle();

      expect(deltaPlainText(_ops(g.callsTo('update_planning_block').single)).trim(), 'Hello');
      final adds = g.callsTo('add_planning_block');
      expect([for (final a in adds) a['p_block_type']], ['checklist', 'text']);
      expect(adds[0]['p_after_id'], 'b1');
      expect(adds[1]['p_after_id'], adds[0]['p_id']);
      expect(deltaPlainText(_ops(adds[1])).trim(), 'world');
    });

    testWidgets('Insert with no cursor in text adds after the block last tapped, else at the end', (tester) async {
      final g = _gateway(blocks: [
        fakeBlockJson(id: 'd1', type: 'date', payload: {'title': 'When'}),
        fakeBlockJson(id: 'd2', type: 'date', sortKey: 'X', payload: {'title': 'Flight'}),
      ]);
      g.handlers['add_planning_block'] = (p) => fakeBlockJson(
          id: p['p_id'] as String, type: p['p_block_type'] as String, sortKey: 'Z', payload: {});
      await _open(tester, g);
      await tester.tap(find.text('Insert'));
      await tester.pumpAndSettle();
      await tester.tap(_ribbon('Checklist'));
      await tester.pumpAndSettle();
      expect(g.callsTo('add_planning_block').last['p_after_id'], 'd2', reason: 'at the end');
      await tester.ensureVisible(find.text('When')); // the page followed the new block down
      await tester.pumpAndSettle();
      await tester.tap(find.text('When'));
      await tester.pumpAndSettle();
      await tester.tap(_ribbon('Checklist'));
      await tester.pumpAndSettle();
      expect(g.callsTo('add_planning_block').last['p_after_id'], 'd1', reason: 'after the tapped block');
    });
  });
}
