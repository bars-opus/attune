import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The trailing text of the one InfoRowWidget titled [title], or null if
/// there is no such row (e.g. an Expenses block's "Total" amount).
String? infoRowValue(WidgetTester tester, String title) {
  final rows = tester.widgetList<InfoRowWidget>(find.byType(InfoRowWidget)).where((r) => r.title == title).toList();
  if (rows.isEmpty) return null;
  final trailing = rows.single.trailing;
  return trailing is Text ? trailing.data : null;
}

/// The subtitle of the one InfoRowWidget titled [title].
String? infoRowSubtitle(WidgetTester tester, String title) =>
    tester.widgetList<InfoRowWidget>(find.byType(InfoRowWidget)).where((r) => r.title == title).single.subtitle;
