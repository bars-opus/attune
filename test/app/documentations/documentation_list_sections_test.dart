// The guides list's sections (2026-11-26): a closed section shows only its
// heading (nothing for a screen reader either), opens and closes on a tap,
// and a search opens every section with a match.
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/widgets/all_manual_widget.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [documentationFlagsProvider.overrideWith((ref) async => const <String>{})],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: DocumentationList()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every section starts closed; one opens and closes on a tap', (tester) async {
    await _pump(tester);
    expect(find.text('Start here'), findsOneWidget);
    expect(find.text('Your privacy and data'), findsNothing); // Start here, closed
    expect(find.text('Pausing, ending and your space'), findsNothing); // Your relationship, closed

    await tester.scrollUntilVisible(find.text('Your relationship'), 400,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Your relationship'));
    await tester.pumpAndSettle();
    expect(find.text('Pausing, ending and your space'), findsOneWidget);

    await tester.tap(find.text('Your relationship'));
    await tester.pumpAndSettle();
    expect(find.text('Pausing, ending and your space'), findsNothing);
  });

  testWidgets('a search opens the sections with a match and hides the rest', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'pausing');
    await tester.pumpAndSettle();
    expect(find.text('Pausing, ending and your space'), findsOneWidget);
    expect(find.text('Talking together'), findsNothing);
  });
}
