import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/documentations/user_manual/data/healing_docs.dart';
import 'package:attune/core/intro/presentation/widgets/feature_intro_flow_gate.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Dating Mode intro gate shows DatingModeDocs content on first entry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(800, 600),
          builder: (_, __) => FeatureIntroFlowGate(
            module: DatingModeDocs(),
            briefParagraph: 'Test paragraph.',
            launchLabel: 'Continue to Dating Mode',
            buildFeature: () => const Scaffold(body: Text('Dating Dashboard Stub')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dating Mode'), findsOneWidget);
    expect(find.text('Dating Dashboard Stub'), findsNothing);
  });

  testWidgets('Healing Mode intro gate shows HealingDocs content on first entry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(800, 600),
          builder: (_, __) => FeatureIntroFlowGate(
            module: HealingDocs(),
            briefParagraph: 'Test paragraph.',
            launchLabel: 'Enter Healing Mode',
            buildFeature: () => const Scaffold(body: Text('Healing Journey Stub')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Healing Mode'), findsOneWidget);
    expect(find.text('Healing Journey Stub'), findsNothing);
  });
}
