// Spec 1 W3b/W3c (§3.9, §3.10, §3.12): the Settings rows Spec 1 adds go in
// their sections, and only under flow_paths_v2.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/me/presentation/widgets/journal_reminder_row.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/settings/data/settings_data.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/features/settings/presentation/screens/how_you_use_attune_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_push_asker.dart';
import '../../helpers/fake_reminder_rpc.dart';

Future<List<SettingsConfig?>> _rows(
  WidgetTester tester, {
  required bool pathsV2,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  late List<SettingsConfig?> rows;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        flowPathsV2Provider.overrideWithValue(pathsV2),
        journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
        pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  rows = [
                    howYouUseSetting(context, ref),
                    journalReminderSetting(context, ref),
                  ];
                  return const SizedBox();
                },
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return rows;
}

void main() {
  testWidgets('flow_paths_v2 off: neither row', (tester) async {
    expect(await _rows(tester, pathsV2: false), [null, null]);
  });

  testWidgets('flow_paths_v2 on: both rows', (tester) async {
    final rows = await _rows(tester, pathsV2: true);
    expect(rows[0]!.title, 'How you use Attune');
    expect(rows[1]!.title, 'Remind me to write');
    expect(rows[1]!.subtitle, 'Off');
  });

  // B7 review M-7 (P-22): the Settings row opens the same sheet.
  testWidgets('"Remind me to write" in Settings opens the sheet', (
    tester,
  ) async {
    final rows = await _rows(tester, pathsV2: true);
    rows[1]!.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('When should we remind you?'), findsOneWidget);
  });

  testWidgets('each row sits in its section', (tester) async {
    late List<dynamic> sections;
    SettingsConfig row(String id) => SettingsConfig(
      id: id,
      title: id,
      subtitle: '',
      icon: Icons.circle,
      type: SettingsItemType.navigation,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            sections = SettingsDataSource.getSettingsSections(
              context,
              'u1',
              datingLock: row('dating_lock'),
              howYouUse: row('how_you_use_attune'),
              journalReminder: row('journal_reminder'),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    String sectionOf(String id) =>
        sections.firstWhere((s) => s.items.any((i) => i.id == id)).id as String;
    expect(sectionOf('dating_lock'), 'safety');
    expect(sectionOf('how_you_use_attune'), 'account');
    expect(sectionOf('journal_reminder'), 'notifications_location');
  });
}
