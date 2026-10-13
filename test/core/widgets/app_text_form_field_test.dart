import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('passes capitalization, suffix text, helper text and a counter builder to the field', (tester) async {
    final c = TextEditingController(text: 'abc');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppTextFormField(
          controller: c,
          label: 'Amount',
          textCapitalization: TextCapitalization.sentences,
          suffixText: 'GHS',
          helperText: 'What the one who did not pay owes',
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text('$currentLength/9'),
        ),
      ),
    ));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textCapitalization, TextCapitalization.sentences);
    expect(field.decoration?.suffixText, 'GHS');
    expect(field.decoration?.helperText, 'What the one who did not pay owes');
    expect(find.text('3/9'), findsOneWidget);
    expect(find.text('GHS'), findsOneWidget);
    expect(find.text('What the one who did not pay owes'), findsOneWidget);
  });

  testWidgets('defaults stay as they were', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppTextFormField(label: 'Name'))));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textCapitalization, TextCapitalization.none);
    expect(field.decoration?.suffixText, isNull);
    expect(field.decoration?.helperText, isNull);
    expect(field.buildCounter, isNull);
  });

  testWidgets('labelPadding indents the label from the field edge; none by default', (tester) async {
    Future<double> indent(EdgeInsetsGeometry? p) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppTextFormField(label: 'Day', labelPadding: p))));
      return tester.getTopLeft(find.text('Day')).dx - tester.getTopLeft(find.byType(InputDecorator)).dx;
    }

    expect(await indent(null), 0);
    expect(await indent(const EdgeInsets.only(left: 24)), 24);
  });

  testWidgets('labelColor recolours the label; onSurface by default', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppTextFormField(label: 'Day'))));
    final scheme = Theme.of(tester.element(find.text('Day'))).colorScheme;
    expect(tester.widget<Text>(find.text('Day')).style?.color, scheme.onSurface);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AppTextFormField(label: 'Day', labelColor: scheme.onSurface.withValues(alpha: 0.6)))));
    expect(tester.widget<Text>(find.text('Day')).style?.color, scheme.onSurface.withValues(alpha: 0.6));
  });
}
