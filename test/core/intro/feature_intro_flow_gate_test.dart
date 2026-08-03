import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';
import 'package:attune/core/intro/data/seen_feature_intro_store.dart';
import 'package:attune/core/intro/presentation/widgets/feature_intro_flow_gate.dart';

/// Wraps a real store but makes markIntroSeen fail, to verify the gate
/// still advances the UI (setState still fires) even when the
/// fire-and-forget persistence write throws.
class _ThrowingMarkSeenStore implements SeenFeatureIntroStore {
  _ThrowingMarkSeenStore(this._delegate);

  final SeenFeatureIntroStore _delegate;

  @override
  bool hasSeenIntro(String featureId) => _delegate.hasSeenIntro(featureId);

  @override
  Future<void> markIntroSeen(String featureId) {
    return Future<void>.error(StateError('simulated persistence failure'));
  }
}

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
  List<ManualSection> getSections(BuildContext context) => [];

  @override
  List<FAQModel> getFAQs(BuildContext context) => [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestable(SeenFeatureIntroStore store) {
    return MaterialApp(
      home: ScreenUtilInit(
        designSize: const Size(800, 600),
        builder: (_, __) => FeatureIntroFlowGate(
          module: _FakeDocs(),
          briefParagraph: 'Brief.',
          launchLabel: 'Enter',
          storeOverride: store,
          buildFeature: () =>
              const Scaffold(body: Text('Real Feature Screen')),
        ),
      ),
    );
  }

  testWidgets('renders the real feature directly when intro already seen', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = SeenFeatureIntroStore(prefs);
    await store.markIntroSeen('fakeFeature');

    await tester.pumpWidget(buildTestable(store));
    await tester.pumpAndSettle();

    expect(find.text('Real Feature Screen'), findsOneWidget);
    expect(find.text('Fake Feature'), findsNothing);
  });

  testWidgets('renders the intro flow when unseen, then swaps to the real feature on completion', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final store = SeenFeatureIntroStore(prefs);

    await tester.pumpWidget(buildTestable(store));
    await tester.pumpAndSettle();

    expect(find.text('Fake Feature'), findsOneWidget);
    expect(find.text('Real Feature Screen'), findsNothing);

    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    expect(find.text('Real Feature Screen'), findsOneWidget);
    expect(store.hasSeenIntro('fakeFeature'), isTrue);
  });

  testWidgets(
    'still advances to the real feature when markIntroSeen fails',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = _ThrowingMarkSeenStore(SeenFeatureIntroStore(prefs));

      await tester.pumpWidget(buildTestable(store));
      await tester.pumpAndSettle();

      expect(find.text('Fake Feature'), findsOneWidget);

      // Should not throw up through the widget tree despite the
      // underlying store's markIntroSeen rejecting.
      await tester.tap(find.text('Skip intro'));
      await tester.pumpAndSettle();

      expect(find.text('Real Feature Screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
