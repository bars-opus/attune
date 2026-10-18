// The manual's topic list shows a topic for a switched-off feature only
// once its flags are on.
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
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
              home: const Scaffold(body: DocumentationList()),
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
    expect(find.text('In a hard moment'), findsOneWidget);
    expect(find.text('Private safety check-in'), findsOneWidget);
    expect(find.text('Quiet for a while'), findsOneWidget);
    expect(find.text('Your map'), findsOneWidget);
    // The toolkit needs both of its flags.
  });

  testWidgets('the toolkit needs both flags', (tester) async {
    await _pump(tester, const {'conflict_toolkit'});
    expect(find.text('In a hard moment'), findsNothing);
  });
}
