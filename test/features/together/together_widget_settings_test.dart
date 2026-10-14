import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;
import 'together_widget_sync_test.dart' show FakeWidgetStore;

void main() {
  testWidgets(
    'the home-screen card is off until I turn it on, and says what it shows',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeWidgetStore();
      TogetherWidgetSync.store = store;
      t.view.physicalSize = const Size(1170, 4400);
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
      expect(find.text('Next plans on my home screen'), findsOneWidget);
      expect(find.textContaining('no names'), findsOneWidget);
      final toggle = find.descendant(
        of: find.ancestor(
          of: find.text('Next plans on my home screen'),
          matching: find.byType(InfoRowWidget),
        ),
        matching: find.byType(AppToggleSwitch),
      );
      await t.tap(toggle);
      await t.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'together_widget_enabled',
        ),
        isTrue,
      );
      await t.tap(toggle);
      await t.pumpAndSettle();
      expect(store.saved.last, isNull);
    },
  );
}
