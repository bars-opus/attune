// Spec 2 W8b Task 8 (R-80, owner 2026-11-22): the plain app icon is for
// everyone, so Settings has its own App icon row (App settings, after
// Language, under flow_paths_v2 like Spec 1's other rows). It opens the
// same page and control as Dating settings, on a neutral route outside
// /dating/: not behind the Dating lock, and no name, path, file or word of
// it says Dating.
import 'dart:async';
import 'dart:io';

import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/data/safety_docs.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/device/app_icon.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/settings/app_icon_screen.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/settings/data/settings_data.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/features/settings/presentation/screens/app_icon_screen.dart';
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_app_icon.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/tap_in_reach.dart';
import '../dating/support/dating_shell.dart' show FakeLock;

final loc = AppLocalizationsEn();
final _dating = RegExp('dating', caseSensitive: false);

/// The app's own route for the page (from the real router).
GoRoute _appIconRoute() {
  final router = createAppRouter(RoutingNotifier());
  addTearDown(router.dispose);
  GoRoute? find(List<RouteBase> routes) {
    for (final r in routes) {
      if (r is GoRoute && r.name == 'appIcon') return r;
      final inner = find(r.routes);
      if (inner != null) return inner;
    }
    return null;
  }

  return find(router.configuration.routes)!;
}

Future<SettingsConfig?> _row(
  WidgetTester t, {
  required bool pathsV2,
  FakeAppIcon? icon,
}) async {
  late SettingsConfig? row;
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        flowPathsV2Provider.overrideWithValue(pathsV2),
        appIconControlProvider.overrideWithValue(icon ?? FakeAppIcon()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            row = appIconSetting(context, ref);
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return row;
}

void main() {
  testWidgets('flow_paths_v2 off: no row; on: App icon and the icon now', (
    t,
  ) async {
    expect(await _row(t, pathsV2: false), isNull);
    final row = await _row(
      t,
      pathsV2: true,
      icon: FakeAppIcon(AppIconChoice.plain),
    );
    expect(row!.title, loc.appIcon_title);
    expect(row.subtitle, loc.appIcon_plain);
    expect(row.routeName, RouteNames.appIcon);
    expect(
      (await _row(t, pathsV2: true, icon: FakeAppIcon()))!.subtitle,
      loc.appIcon_attune,
    );
    // A phone that can't say: no value (the page says why).
    expect(
      (await _row(t, pathsV2: true, icon: FakeAppIcon(null)))!.subtitle,
      '',
    );
  });

  testWidgets('the row sits in App settings, after Language', (t) async {
    late List<SettingsSection> sections;
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            sections = SettingsDataSource.getSettingsSections(
              context,
              '',
              appIcon: SettingsConfig(
                id: 'app_icon',
                title: 'App icon',
                subtitle: '',
                icon: Icons.circle,
                type: SettingsItemType.navigation,
              ),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    final app = sections.singleWhere((s) => s.id == 'app');
    expect(app.items.map((i) => i.id), ['theme', 'language', 'app_icon']);
    expect(
      sections.where((s) => s.items.any((i) => i.id == 'app_icon')).length,
      1,
    );
  });

  test('the route: outside /dating/, no redirect, no Dating in its name', () {
    final route = _appIconRoute();
    expect(route.path, RouteNames.appIcon);
    expect(route.path, '/settings/app-icon');
    expect(route.redirect, isNull);
    expect(route.path, isNot(matches(_dating)));
    expect(route.name, isNot(matches(_dating)));
  });

  test('the page and the control are neutral: no Dating import, file or '
      'word', () {
    for (final path in [
      'lib/features/settings/presentation/screens/app_icon_screen.dart',
      'lib/core/device/app_icon.dart',
    ]) {
      // The code, not its comments (they may say where else it opens).
      final src = File(path)
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(src, isNot(contains('features/dating')), reason: path);
      expect(src, isNot(matches(RegExp(r'\bDating\w*\('))), reason: path);
      // No key, route or string literal the page writes says it.
      expect(
        src,
        isNot(matches(RegExp(r"'[^'\n]*dating", caseSensitive: false))),
        reason: path,
      );
    }
    for (final words in [
      loc.appIcon_title,
      loc.appIcon_intro,
      loc.appIcon_attune,
      loc.appIcon_plain,
      loc.appIcon_ios,
      loc.appIcon_android,
      loc.appIcon_failed,
      loc.appIcon_unsupported,
    ]) {
      expect(words, isNot(matches(_dating)), reason: words);
    }
  });

  testWidgets('Settings opens the page with the Dating lock on; a choice '
      'there is the same control and Settings says it', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final icon = FakeAppIcon();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const SettingsScreen(currentUserId: 'u1'),
        ),
        _appIconRoute(),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          flowPathsV2Provider.overrideWithValue(true),
          appIconControlProvider.overrideWithValue(icon),
          datingLockStoreProvider.overrideWithValue(FakeLock(true)),
        ],
        child: ScreenUtilConfig.builder(
          builder:
              (_) => MaterialApp.router(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final row = find.text(loc.appIcon_title);
    await t.scrollUntilVisible(
      row,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    await tapInReach(t, row);
    await t.pumpAndSettle();
    expect(find.byType(AppIconScreen), findsOneWidget);
    expect(find.byType(DatingAppIconScreen), findsNothing);
    expect(find.byType(DatingPageWatch), findsNothing);
    expect(find.textContaining(_dating), findsNothing);
    await tapInReach(t, find.text(loc.appIcon_plain));
    await t.pumpAndSettle();
    expect(icon.chosen, [AppIconChoice.plain]);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.byType(AppIconScreen), findsNothing);
    expect(find.text(loc.appIcon_plain), findsOneWidget); // the row's value
  });

  testWidgets('fix round 1 (M-4): a choice the phone answers after the page '
      'closed still shows in the row', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final icon = FakeAppIcon();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const SettingsScreen(currentUserId: 'u1'),
        ),
        _appIconRoute(),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          flowPathsV2Provider.overrideWithValue(true),
          appIconControlProvider.overrideWithValue(icon),
        ],
        child: ScreenUtilConfig.builder(
          builder:
              (_) => MaterialApp.router(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final row = find.text(loc.appIcon_title);
    await t.scrollUntilVisible(
      row,
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
    await tapInReach(t, row);
    await t.pumpAndSettle();
    icon.hold = Completer<void>();
    await tapInReach(t, find.text(loc.appIcon_plain));
    await t.pump();
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.byType(AppIconScreen), findsNothing);
    expect(find.text(loc.appIcon_attune), findsOneWidget); // not yet
    icon.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text(loc.appIcon_plain), findsOneWidget);
    expect(find.text(loc.appIcon_attune), findsNothing);
  });

  testWidgets('fix round 1 (M-6): the main manual explains App icon, without '
      'a Dating word, only while the row can show', (t) async {
    Future<ManualContent?> topic(Set<String> flags) async {
      late BuildContext context;
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            documentationFlagsProvider.overrideWith((ref) async => flags),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (c, ref, _) {
                ref.watch(documentationFlagsProvider);
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      return SafetyDocs()
          .getSections(context)
          .expand((s) => s.contents)
          .where((c) => c.id == 'safety_app_icon')
          .firstOrNull;
    }

    expect(await topic(const {}), isNull);
    expect(await topic(const {'flow_signin_v2'}), isNull);
    final on = (await topic(const {'flow_signin_v2', 'flow_paths_v2'}))!;
    expect(on.content, contains('Settings → App icon'));
    expect(on.content, contains('shows a message'));
    expect(on.content, contains('app list'));
    expect(on.content, contains('never change it back'));
    // Final client fix (M-5): iPads too.
    expect(on.content, contains('An iPhone or iPad shows a message'));
    expect(
      on.content.replaceAll('iPhone or iPad', ''),
      isNot(contains('iPhone')),
    );
    expect('${on.title} ${on.content}', isNot(matches(_dating)));
    expect(
      DocumentationRegistry.passageVisible('appIcon', const {
        'flow_signin_v2',
        'flow_paths_v2',
      }),
      isTrue,
    );
    expect(
      DocumentationRegistry.passageVisible('appIcon', const {'flow_paths_v2'}),
      isFalse,
    );
  });

  testWidgets('the neutral page meets the three guidelines', (t) async {
    await pumpFlowScreen(
      t,
      () => const AppIconScreen(),
      overrides: [appIconControlProvider.overrideWithValue(FakeAppIcon())],
    );
    expect(find.text(loc.appIcon_intro), findsOneWidget);
    await expectFlowGuidelines(t);
  });
}
