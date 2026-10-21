// Text sizes in notes: Small 14, Normal 16, Large 20, Huge 26 — and the
// size menu previews exactly those. Sizes are plain-text sizes: a heading
// has its own, so the size menu stays out of headings, and making a line a
// heading clears the sizes in it (a size on a heading shrank it: "Large"
// was 18 on a 30 Heading 2).
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/planning_quill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

Map<String, double?> _sizes(WidgetTester t) {
  final out = <String, double?>{};
  for (final e in find.byType(RichText).evaluate()) {
    void walk(InlineSpan s, TextStyle? inh) {
      if (s is TextSpan) {
        final st = inh?.merge(s.style) ?? s.style;
        if ((s.text ?? '').endsWith('Line')) out[s.text!] = st?.fontSize;
        for (final c in s.children ?? const <InlineSpan>[]) walk(c, st);
      }
    }

    walk((e.widget as RichText).text, null);
  }
  return out;
}

void main() {
  testWidgets('Small 14, Normal 16, Large 20, Huge 26', (t) async {
    await t.pumpWidget(
      planningTestApp(
        FakePlanningGateway({
          'get_planning_entry':
              (_) => fakeEntryDetailJson(
                blocks: [
                  fakeBlockJson(
                    id: 'tx',
                    type: 'text',
                    payload: {
                      'delta': [
                        {'insert': 'NormalLine\n'},
                        {
                          'insert': 'SmallLine',
                          'attributes': {'size': 'small'},
                        },
                        {'insert': '\n'},
                        {
                          'insert': 'LargeLine',
                          'attributes': {'size': 'large'},
                        },
                        {'insert': '\n'},
                        {
                          'insert': 'HugeLine',
                          'attributes': {'size': 'huge'},
                        },
                        {'insert': '\n'},
                      ],
                    },
                  ),
                ],
              ),
        }),
        const PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1'),
      ),
    );
    await t.pumpAndSettle();
    expect(_sizes(t), {
      'NormalLine': 16,
      'SmallLine': 14,
      'LargeLine': 20,
      'HugeLine': 26,
    });
  });

  test('the size menu previews the sizes notes use', () {
    expect(planningTextSizes, {
      'small': 14.0,
      'normal': 16.0,
      'large': 20.0,
      'huge': 26.0,
    });
  });

  group('headings keep their own size', () {
    QuillController controller(List<Map<String, dynamic>> ops, int at) =>
        QuillController(
          document: Document.fromJson(ops),
          selection: TextSelection.collapsed(offset: at),
        );

    test('no size menu in a heading line', () {
      final c = controller([
        {'insert': 'Title'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {'insert': 'Body\n'},
      ], 2);
      expect(planningSizeAllowed(c), isFalse);
      c.updateSelection(
        const TextSelection.collapsed(offset: 8),
        ChangeSource.local,
      );
      expect(planningSizeAllowed(c), isTrue);
    });

    test('making a line a heading clears the sizes in it, and only in it', () {
      final c = controller([
        {
          'insert': 'Big',
          'attributes': {'size': 'large'},
        },
        {'insert': ' words\n'},
        {
          'insert': 'Keep',
          'attributes': {'size': 'huge'},
        },
        {'insert': '\n'},
      ], 1);
      planningApplyHeading(c, Attribute.h2);
      final ops = c.document.toDelta().toJson();
      expect(ops, [
        {'insert': 'Big words'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {
          'insert': 'Keep',
          'attributes': {'size': 'huge'},
        },
        {'insert': '\n'},
      ]);
    });
  });
}
