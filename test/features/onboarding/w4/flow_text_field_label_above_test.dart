// Batch-4 review #3: with labelAbove, tapping the label above the field
// focuses the field, as the label inside the border did; the field stays
// one labelled node.
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget field) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          field,
          FlowTextField(controller: TextEditingController(), label: 'Other'),
        ],
      ),
    ),
  ),
);

EditableText _editable(WidgetTester tester, int index) =>
    tester.widget<EditableText>(find.byType(EditableText).at(index));

void main() {
  testWidgets('tapping the label above focuses the field', (tester) async {
    await _pump(
      tester,
      FlowTextField(
        controller: TextEditingController(),
        label: "Your partner's first name",
        labelAbove: true,
      ),
    );
    expect(_editable(tester, 0).focusNode.hasFocus, isFalse);
    await tester.tap(find.text("Your partner's first name"));
    await tester.pump();
    expect(_editable(tester, 0).focusNode.hasFocus, isTrue);
    expect(_editable(tester, 1).focusNode.hasFocus, isFalse);
  });

  testWidgets('a focus node the screen gives is the one focused', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await _pump(
      tester,
      FlowTextField(
        controller: TextEditingController(),
        label: 'Name',
        labelAbove: true,
        focusNode: node,
      ),
    );
    await tester.tap(find.text('Name'));
    await tester.pump();
    expect(node.hasFocus, isTrue);
  });

  testWidgets('still one node named by the label', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      FlowTextField(
        controller: TextEditingController(),
        label: 'Name',
        labelAbove: true,
      ),
    );
    final node = tester.getSemantics(find.byType(TextField).first);
    expect(node.label, 'Name');
    expect(node.hasFlag(SemanticsFlag.isTextField), isTrue);
    expect(find.bySemanticsLabel('Name'), findsOneWidget);
    semantics.dispose();
  });
}
