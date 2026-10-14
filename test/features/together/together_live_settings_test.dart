import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_live_activity.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_live_activity_test.dart' show FakeLiveStore;
import 'together_repository_test.dart' show FakeTogetherGateway;

const _title = "Tonight's plan on my lock screen";

Future<void> _open(WidgetTester t, {required bool supported}) async {
  t.view.physicalSize = const Size(1170, 5200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(
          TogetherRepository(
            FakeTogetherGateway({
              'get_together_prefs':
                  (_) => {'daily_summary': true, 'care_nudges': true},
            }),
          ),
        ),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        togetherLiveSupportedProvider.overrideWith((ref) async => supported),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (c) => TextButton(
                        onPressed: () => showTogetherSettingsSheet(c, 'r1'),
                        child: const Text('open'),
                      ),
                ),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TogetherLiveActivity.store = FakeLiveStore();
  });

  testWidgets(
    'the lock-screen plan is off until I turn it on, and says what it shows',
    (t) async {
      await _open(t, supported: true);
      expect(find.text(_title), findsOneWidget);
      expect(find.textContaining('countdown from 4 hours before'), findsOneWidget);
      final toggle = find.descendant(
        of: find.ancestor(
          of: find.text(_title),
          matching: find.byType(InfoRowWidget),
        ),
        matching: find.byType(AppToggleSwitch),
      );
      expect(t.widget<AppToggleSwitch>(toggle).toggleValue, isFalse);
      await t.tap(toggle);
      await t.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'together_live_enabled',
        ),
        isTrue,
      );
    },
  );

  testWidgets('where Live Activities aren’t available, there is no setting', (
    t,
  ) async {
    await _open(t, supported: false);
    expect(find.text(_title), findsNothing);
  });
}
