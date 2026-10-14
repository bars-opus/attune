import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_calendar_mirror.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'busy_sync_test.dart' show FakeBusySource;
import 'together_calendar_mirror_test.dart' show FakeMirrorCalendar;
import 'together_repository_test.dart' show FakeTogetherGateway;

const _title = "Copy our plans to my phone's calendar";

Future<void> _open(WidgetTester t) async {
  t.view.physicalSize = const Size(1170, 5600);
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
              'get_together_overlay': (_) => {'level': 'off'},
            }),
          ),
        ),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        deviceBusySourceProvider.overrideWithValue(FakeBusySource()),
        togetherLiveSupportedProvider.overrideWith((ref) async => false),
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

Finder _toggle() => find.descendant(
  of: find.ancestor(
    of: find.text(_title),
    matching: find.byType(InfoRowWidget),
  ),
  matching: find.byType(AppToggleSwitch),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'the calendar copy is off until I turn it on, and says what it adds',
    (t) async {
      TogetherMirror.calendar = FakeMirrorCalendar();
      await _open(t);
      expect(find.text(_title), findsOneWidget);
      expect(find.textContaining('“Plans”'), findsOneWidget);
      expect(t.widget<AppToggleSwitch>(_toggle()).toggleValue, isFalse);
      await t.tap(_toggle());
      await t.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'together_mirror_enabled',
        ),
        isTrue,
      );
    },
  );

  testWidgets('without calendar access it stays off and says how to allow it', (
    t,
  ) async {
    TogetherMirror.calendar = FakeMirrorCalendar(access: false);
    await _open(t);
    await t.tap(_toggle());
    await t.pumpAndSettle();
    expect(t.widget<AppToggleSwitch>(_toggle()).toggleValue, isFalse);
    expect(
      find.text('Calendar access is off. You can allow it in Settings.'),
      findsOneWidget,
    );
  });
}
