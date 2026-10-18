import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The trailing text of the one InfoRowWidget titled [title], or null if
/// there is no such row (e.g. an Expenses block's "Total" amount). A
/// trailing widget that draws its text (a rolling amount, settled) counts.
String? infoRowValue(WidgetTester tester, String title) {
  final text = infoRowTrailingText(tester, title);
  return text?.data ?? text?.textSpan?.toPlainText();
}

/// The Text the trailing of the one InfoRowWidget titled [title] shows, for
/// its style too; null if there is no such row or no text.
Text? infoRowTrailingText(WidgetTester tester, String title) {
  final rows = tester.widgetList<InfoRowWidget>(find.byType(InfoRowWidget)).where((r) => r.title == title).toList();
  if (rows.isEmpty) return null;
  final trailing = rows.single.trailing;
  if (trailing == null) return null;
  if (trailing is Text) return trailing;
  final inside = find.descendant(of: find.byWidget(trailing), matching: find.byType(Text));
  return inside.evaluate().isEmpty ? null : tester.widget<Text>(inside.first);
}

/// The subtitle of the one InfoRowWidget titled [title].
String? infoRowSubtitle(WidgetTester tester, String title) =>
    tester.widgetList<InfoRowWidget>(find.byType(InfoRowWidget)).where((r) => r.title == title).single.subtitle;
