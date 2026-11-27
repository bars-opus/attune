// The manual's topic list shows a topic for a switched-off feature only
// once its flags are on.
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/documentation_groups.dart';
import 'package:attune/app/documentations/user_manual/widgets/all_manual_widget.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Set<String> flags) async {
  tester.view.physicalSize = const Size(1200, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        documentationFlagsProvider.overrideWith((ref) async => flags),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              theme: AppTheme.lightTheme,
              // Every section open, so each topic can be looked for.
              home: Scaffold(
                body: DocumentationList(initiallyOpen: DocumentationGroup.values.toSet()),
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('flags off: gated topics are hidden, the rest show', (
    tester,
  ) async {
    await _pump(tester, const {});
    expect(find.text('Pausing, ending and your space'), findsOneWidget);
    expect(find.text('Your privacy and data'), findsOneWidget);
    expect(find.text('In a hard moment'), findsNothing);
    expect(find.text('Quiet for a while'), findsNothing);
    expect(find.text('Your map'), findsNothing);
  });

  testWidgets('flags on: they show', (tester) async {
    await _pump(tester, const {
      'conflict_toolkit',
      'private_safety_check',
      'quiet_states',
      'couple_map_enabled',
    });
    // The list is built lazily and grouped (2026-11-26): scroll to each.
    for (final title in const [
      'In a hard moment',
      'Private safety check-in',
      'Your map',
      'Quiet for a while',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(title), findsOneWidget);
    }
    // The toolkit needs both of its flags.
  });

  testWidgets('the toolkit needs both flags', (tester) async {
    await _pump(tester, const {'conflict_toolkit'});
    expect(find.text('In a hard moment'), findsNothing);
  });
}
