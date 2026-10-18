// The manual's bullet and text blocks render **bold** spans instead of
// showing the asterisks to the reader.
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';
import 'package:attune/app/documentations/user_manual/widgets/manual_widget.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

bool _hasBold(InlineSpan span, String text) {
  if (span is TextSpan) {
    if (span.text == text && span.style?.fontWeight == FontWeight.w700)
      return true;
    return (span.children ?? const []).any((c) => _hasBold(c, text));
  }
  return false;
}

void main() {
  testWidgets('**bold** renders bold, without asterisks', (tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: ManualWidget(
                  sections: const [
                    ManualSection(
                      id: 's',
                      title: 'Section',
                      icon: Icons.info_outline,
                      contents: [
                        ManualContent(
                          id: 'b',
                          title: '',
                          content: 'Read **this** first.',
                          type: ManualContentType.bulletList,
                          bulletPoints: ['**Active:** Full chat.'],
                        ),
                        ManualContent(
                          id: 't',
                          title: '',
                          content: 'Plain **text** too.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('**'), findsNothing);
    final rich = tester.widgetList<RichText>(find.byType(RichText)).toList();
    for (final word in ['Active:', 'this', 'text']) {
      expect(rich.any((r) => _hasBold(r.text, word)), isTrue, reason: word);
    }
    expect(
      find.textContaining('Full chat.', findRichText: true),
      findsOneWidget,
    );
  });
}
