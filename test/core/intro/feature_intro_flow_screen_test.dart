import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';
import 'package:attune/core/intro/presentation/screens/feature_intro_flow_screen.dart';

class _FakeDocs implements DocumentationModule {
  @override
  String get id => 'fakeFeature';

  @override
  IconData get icon => Icons.star;

  @override
  int get order => 1;

  @override
  String getTitle(BuildContext context) => 'Fake Feature';

  @override
  String getSubtitle(BuildContext context) => 'A feature for testing';

  @override
  List<ManualSection> getSections(BuildContext context) => [
        ManualSection(
          id: 'fake_section',
          title: 'Fake Section',
          icon: Icons.info,
          category: 'Fake Feature',
          order: 1,
          contents: [
            ManualContent(
              id: 'fake_content',
              title: 'Fake content title',
              content: 'Fake content body',
              type: ManualContentType.text,
              order: 1,
            ),
          ],
        ),
      ];

  @override
  List<FAQModel> getFAQs(BuildContext context) => [
        const FAQModel(
          id: 'fake_faq',
          question: 'Is this a real FAQ?',
          answer: 'No, it is a fake one for testing.',
          category: 'Fake Feature',
          order: 1,
        ),
      ];
}

void main() {
  Widget buildTestable({required VoidCallback onComplete}) {
    return MaterialApp(
      home: ScreenUtilInit(
        designSize: const Size(800, 600),
        builder: (_, __) => FeatureIntroFlowScreen(
          module: _FakeDocs(),
          briefParagraph: 'This is the brief intro paragraph.',
          launchLabel: 'Get started',
          onComplete: onComplete,
        ),
      ),
    );
  }

  testWidgets('starts on page 1 with brief intro content, no Back control', (tester) async {
    await tester.pumpWidget(buildTestable(onComplete: () {}));
    await tester.pumpAndSettle();

    expect(find.text('Fake Feature'), findsOneWidget);
    expect(find.text('This is the brief intro paragraph.'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
  });

  testWidgets('Continue advances page 1 to page 2 (documentation)', (tester) async {
    await tester.pumpWidget(buildTestable(onComplete: () {}));
    // AppButton wraps its content in a 500ms AnimatedScaleFade entrance
    // animation; settle it before interacting, and again after each tap —
    // otherwise flutter_test's hit-test pre-check on the still-animating
    // button (and the PageView scroll animation) can misfire as a false
    // positive, or the tap can land before the button's final position.
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('Fake content title'), findsOneWidget);
  });

  testWidgets('Continue advances page 2 to page 3 (FAQ), Back returns to page 2', (tester) async {
    await tester.pumpWidget(buildTestable(onComplete: () {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('Is this a real FAQ?'), findsOneWidget);

    await tester.tap(find.text('Back'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('Fake content title'), findsOneWidget);
  });

  testWidgets('final CTA on page 3 calls onComplete', (tester) async {
    var completed = false;
    await tester.pumpWidget(buildTestable(onComplete: () => completed = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });

  testWidgets('Skip on page 1 calls onComplete immediately', (tester) async {
    var completed = false;
    await tester.pumpWidget(buildTestable(onComplete: () => completed = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });
}
