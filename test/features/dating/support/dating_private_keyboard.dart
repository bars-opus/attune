// Spec 2 W3 final fix (client M-12): a Dating free-text field never lets
// the keyboard learn or suggest what is typed (a shared phone: the next
// person would see "genderqueer" or a pronoun set offered back).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every text field at or under [field] keeps the keyboard from learning,
/// suggesting and autocorrecting, down to the EditableText the platform
/// is given.
void expectPrivateKeyboard(WidgetTester t, Finder field) {
  final fields = find.descendant(
    of: field,
    matching: find.byType(TextField),
    matchRoot: true,
  );
  expect(fields, findsWidgets);
  for (final w in t.widgetList<TextField>(fields)) {
    expect(w.enableSuggestions, isFalse, reason: 'enableSuggestions');
    expect(w.autocorrect, isFalse, reason: 'autocorrect');
    expect(
      w.enableIMEPersonalizedLearning,
      isFalse,
      reason: 'enableIMEPersonalizedLearning',
    );
  }
  final editables = find.descendant(
    of: fields,
    matching: find.byType(EditableText),
  );
  for (final e in t.widgetList<EditableText>(editables)) {
    expect(e.enableSuggestions, isFalse);
    expect(e.autocorrect, isFalse);
    expect(e.enableIMEPersonalizedLearning, isFalse);
  }
}
