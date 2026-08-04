import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/app/documentations/user_manual/data/games_docs.dart';
import 'package:attune/app/documentations/user_manual/data/truth_or_dare_docs.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/widgets/documentation_tab_view.dart';

void main() {
  setUp(() {
    DocumentationRegistry.initialize();
  });

  Widget buildTestable(module) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        home: Scaffold(body: DocumentationTabView(module: module)),
      ),
    );
  }

  testWidgets('shows a Related tab for a module with related ids', (tester) async {
    await tester.pumpWidget(buildTestable(GamesDocs()));
    await tester.pumpAndSettle();

    expect(find.text('Related'), findsOneWidget);
  });

  testWidgets('shows no Related tab for a module without related ids', (tester) async {
    await tester.pumpWidget(buildTestable(TruthOrDareDocs()));
    await tester.pumpAndSettle();

    expect(find.text('Related'), findsNothing);
  });

  testWidgets('tapping a related card drills into that module and shows a back row', (tester) async {
    await tester.pumpWidget(buildTestable(GamesDocs()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();

    expect(find.text('Truth or Dare'), findsWidgets);

    await tester.tap(find.text('Truth or Dare').first);
    await tester.pumpAndSettle();

    expect(find.text('Games'), findsOneWidget); // back row shows parent's title
    expect(find.text('Related'), findsNothing); // Truth or Dare has no related tab of its own
  });

  testWidgets('tapping the back row returns to the parent, whose Related tab reappears', (tester) async {
    await tester.pumpWidget(buildTestable(GamesDocs()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Truth or Dare').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();

    expect(find.text('Related'), findsOneWidget);
  });

  testWidgets('drilling into a related module always opens its Documentation tab, even from FAQs', (tester) async {
    await tester.pumpWidget(buildTestable(GamesDocs()));
    await tester.pumpAndSettle();

    // Select the FAQs tab first.
    await tester.tap(find.text('FAQs'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Related'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Truth or Dare').first);
    await tester.pumpAndSettle();

    // Truth or Dare's Documentation tab content should be visible, not its FAQ content.
    expect(find.text('How it works'), findsWidgets); // a real ManualSection title in TruthOrDareDocs
  });
}
