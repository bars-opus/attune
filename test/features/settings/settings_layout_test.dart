// Settings, grouped: profile, Chat feel (high up, a card like the rest),
// then notifications, safety, privacy, care, app settings, support, legal,
// the relationship and the account. Each category has its own icon colour;
// app settings, support and legal stay grey.
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/settings/data/settings_data.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:attune/features/settings/widgets/settings_item.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(List<SettingsSection>, AppLocalizations)> _sections(
  WidgetTester t,
) async {
  late List<SettingsSection> sections;
  late AppLocalizations loc;
  await t.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            loc = AppLocalizations.of(context)!;
            sections = SettingsDataSource.getSettingsSections(
              context,
              'me',
              quietStatesOn: true,
              outsidePerspectiveOn: true,
              chatFeel: const SettingsSection(
                id: 'chat_feel',
                title: 'Chat feel',
                items: [],
              ),
            );
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return (sections, loc);
}

List<String> _ids(SettingsSection s) => [for (final i in s.items) i.id];

void main() {
  testWidgets('the sections, in order', (t) async {
    final (sections, loc) = await _sections(t);
    expect(
      [for (final s in sections) s.id],
      [
        'account',
        'chat_feel',
        'notifications_location',
        'safety',
        'privacy',
        'care',
        'app',
        'support',
        'legal',
        'relationship',
        'danger',
      ],
    );
    expect(
      [for (final s in sections) s.title],
      [
        '',
        'Chat feel',
        'Notifications & location',
        'Safety',
        'Privacy & your data',
        'Care & wellbeing',
        loc.appSettingsSectionTitle,
        loc.supportSectionTitle,
        loc.legalSectionTitle,
        'Your relationship',
        loc.accountActionsSectionTitle,
      ],
    );
  });

  testWidgets('each setting sits with its kind', (t) async {
    final (sections, _) = await _sections(t);
    final by = {for (final s in sections) s.id: _ids(s)};
    expect(by['account'], ['profile', 'qr_code', 'share_profile']);
    expect(by['notifications_location'], ['notifications', 'location']);
    expect(by['safety'], [
      'safety_resources',
      'safety_pin',
      'blocked',
      'muted',
    ]);
    expect(by['privacy'], ['signed_in_devices', 'download_my_data']);
    expect(by['care'], [
      'quiet_states',
      'hidden_periods',
      'outside_perspective',
    ]);
    expect(by['app'], ['theme', 'language']);
    expect(by['support'], [
      'guide',
      'help',
      'feedback',
      'rate',
      'appInfoScreen',
    ]);
    expect(by['legal'], ['terms', 'licenses']);
    expect(by['relationship'], ['pause_relationship', 'endRelationship']);
    expect(by['danger'], ['logout', 'deactivate', 'deleteAccount']);
  });

  testWidgets(
    'a colour per setting: grey only for app settings, support and legal; red only for safety and what cannot be undone',
    (t) async {
      final (sections, _) = await _sections(t);
      const greyOnly = {'app', 'support', 'legal'};
      const redAllowed = {'safety', 'relationship', 'danger'};
      final reds = {
        Colors.red,
        Colors.redAccent,
        Theme.of(t.element(find.byType(SizedBox).first)).colorScheme.error,
      };
      for (final s in sections) {
        for (final i in s.items) {
          if (greyOnly.contains(s.id)) {
            expect(i.iconColor, Colors.grey, reason: '${s.id}/${i.id}');
          } else {
            expect(
              i.iconColor,
              isNot(Colors.grey),
              reason:
                  '${s.id}/${i.id}: grey is for app settings, support and legal',
            );
          }
          if (!redAllowed.contains(s.id)) {
            expect(
              reds.contains(i.iconColor),
              isFalse,
              reason: '${s.id}/${i.id}: red means safety or no undo',
            );
          }
        }
        // Neighbours differ, so each row is its own (the relationship's two
        // are both "careful", in red, on purpose).
        if (greyOnly.contains(s.id) || s.id == 'relationship') continue;
        for (var k = 1; k < s.items.length; k++) {
          expect(
            s.items[k].iconColor,
            isNot(s.items[k - 1].iconColor),
            reason:
                '${s.id}: ${s.items[k - 1].id} and ${s.items[k].id} share a colour',
          );
        }
      }
    },
  );

  testWidgets(
    'on screen, Chat feel is a settings card high up, its switches settings rows',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await t.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: ScreenUtilConfig.builder(
            builder:
                (_) => const MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: SettingsScreen(currentUserId: 'test-user'),
                ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.byType(SwitchListTile),
        findsNothing,
        reason: 'the same rows as every other setting',
      );
      final sounds = find.byKey(const ValueKey('message_sounds_switch'));
      expect(sounds, findsOneWidget, reason: 'near the top, no scrolling');
      expect(
        find.ancestor(of: sounds, matching: find.byType(SettingsItem)),
        findsOneWidget,
      );
      expect(
        t.getTopLeft(find.text('Chat feel')).dy,
        lessThan(t.getTopLeft(find.text('Notifications & location')).dy),
      );
    },
  );
}
