// Spec 2 W5c Task 10 rulings (§2.6, §3.4, §3.12, §3.15; D8): the card's
// button names the country as a sentence does (Ruling A); a card answered
// after another account signed in writes nothing, and the next account
// sees nothing of the last one's list or answer (Ruling B, D8); the wait
// is spoken (Ruling C); the settings row appears only once eligible and
// opens the page; Widen's Other countries row brings Today back read
// again; and the card and the dark page as goldens, with the guidelines.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/abroad_screen.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pumpAndSettle();
}

const _eligible = DatingAbroadOptions(
  ok: true,
  eligible: true,
  countries: [('GB', false)],
);

class _HeldAbroad extends FakeAbroad {
  _HeldAbroad() : super(_eligible);

  Completer<DatingAbroadOptions>? hold;

  @override
  Future<DatingAbroadOptions> read() => hold?.future ?? super.read();
}

void main() {
  final loc = AppLocalizationsEn();

  Future<(DatingShell, FakeAbroad)> open(
    WidgetTester t, [
    DatingAbroadOptions o = _eligible,
  ]) async {
    final fake = FakeAbroad(o);
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.abroad,
      overrides: [datingAbroadGatewayProvider.overrideWithValue(fake)],
    );
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
    return (shell, fake);
  }

  testWidgets('Ruling A: the row says the name, the button the sentence', (
    t,
  ) async {
    await open(t);
    expect(find.text('United Kingdom'), findsOneWidget);
    await tap(t, find.byType(Switch));
    expect(find.text('Turn on for the United Kingdom'), findsOneWidget);
    expect(
      find.text(loc.dating_abroadTurnOn(datingCountryName(loc, 'GB'))),
      findsOneWidget,
    );
  });

  group('Ruling B (D8)', () {
    testWidgets('a card answered as another account writes nothing', (t) async {
      final (shell, fake) = await open(t);
      await tap(t, find.byType(Switch));
      expect(find.text(loc.dating_abroadCard), findsOneWidget);
      shell.container.read(datingTestAccount.notifier).state = 'kwame';
      await t.pump();
      // W5 final fix (M-4): the card shows nothing of the last account's
      // country and closes, choosing nothing; nothing is written.
      expect(
        find.text(loc.dating_abroadTurnOn(datingCountryName(loc, 'GB'))),
        findsNothing,
      );
      await t.pumpAndSettle();
      expect(find.text(loc.dating_abroadCard), findsNothing);
      expect(fake.sets, isEmpty);
    });

    testWidgets('the next account sees nothing of the last one\'s', (t) async {
      final (shell, fake) = await open(t);
      fake.answer = const DatingWrite(ok: false, reason: 'not_available');
      await tap(t, find.byType(Switch));
      await tap(
        t,
        find.text(loc.dating_abroadTurnOn(datingCountryName(loc, 'GB'))),
      );
      expect(find.text(loc.dating_notAvailableHere), findsOneWidget);
      // (Eligible: W5 final fix M-11 shows a person who isn't no list.)
      fake.value = const DatingAbroadOptions(
        ok: true,
        eligible: true,
        countries: [('NG', false)],
      );
      shell.container.read(datingTestAccount.notifier).state = 'kwame';
      await t.pumpAndSettle();
      expect(find.byType(DatingAbroadScreen), findsOneWidget);
      expect(find.text(loc.dating_notAvailableHere), findsNothing);
      expect(find.text('United Kingdom'), findsNothing);
      expect(find.text('Nigeria'), findsOneWidget);
    });
  });

  testWidgets('D8 on the page alone: the next account reads no answer', (
    t,
  ) async {
    // Pumped without the shell's lock gate, which would rebuild the page:
    // the screen itself drops the last account's answer.
    final fake = FakeAbroad(_eligible)
      ..answer = const DatingWrite(ok: false, reason: 'not_available');
    await pumpFlowScreen(
      t,
      () => const DatingAbroadScreen(),
      overrides: [
        ...datingShellOverrides(),
        datingAbroadGatewayProvider.overrideWithValue(fake),
      ],
    );
    await t.pumpAndSettle();
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
    await tap(t, find.byType(Switch));
    await tap(
      t,
      find.text(loc.dating_abroadTurnOn(datingCountryName(loc, 'GB'))),
    );
    expect(find.text(loc.dating_notAvailableHere), findsOneWidget);
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)))
        .read(datingTestAccount.notifier)
        .state = 'kwame';
    await t.pumpAndSettle();
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
    expect(find.text('United Kingdom'), findsOneWidget);
    expect(find.text(loc.dating_notAvailableHere), findsNothing);
  });

  testWidgets('Ruling C: the wait is spoken', (t) async {
    // The next account's first read is held open (its list is unknown).
    final fake = _HeldAbroad();
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.abroad,
      overrides: [datingAbroadGatewayProvider.overrideWithValue(fake)],
    );
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
    fake.hold = Completer<DatingAbroadOptions>();
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
    expect(find.bySemanticsLabel(loc.loadingDefaultMessage), findsOneWidget);
    fake.hold!.complete(_eligible);
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('United Kingdom'), findsOneWidget);
  });

  // W5 final fix (M-11): eligible or not (a person no longer eligible can
  // still turn a country off); never on a refused read.
  testWidgets('the settings row once the read answers; it opens the page', (
    t,
  ) async {
    for (final (o, shown) in [
      (const DatingAbroadOptions(ok: true), findsOneWidget),
      (const DatingAbroadOptions(reason: 'reverify_device'), findsNothing),
      (_eligible, findsOneWidget),
    ]) {
      await pumpDatingShell(
        t,
        initial: DatingPaths.settings,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active),
        ),
        overrides: [
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(),
          ),
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(),
          ),
          datingAbroadGatewayProvider.overrideWithValue(FakeAbroad(o)),
        ],
      );
      expect(find.byType(DatingSettingsScreen), findsOneWidget);
      expect(find.text(loc.dating_settingsHowFar), findsOneWidget);
      expect(find.text(loc.dating_abroadTitle), shown);
    }
    await tap(t, find.text(loc.dating_abroadTitle));
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
  });

  testWidgets('Widen, Other countries, an edit, back: Today reads again', (
    t,
  ) async {
    final today = FakeDatingToday(
      today: datingTodayJson({'today_state': 'empty', 'cards': <Object?>[]}),
    );
    final abroad = FakeAbroad(_eligible);
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.today,
      overrides: [
        ...datingTodayOverrides(today),
        datingAbroadGatewayProvider.overrideWithValue(abroad),
      ],
    );
    expect(find.byType(DatingTodayScreen), findsOneWidget);
    expect(find.text(loc.dating_cardInterested), findsNothing);
    await tap(t, find.text(loc.dating_todayWiden));
    // The sheet is open, with all three rows.
    expect(find.text(loc.dating_widenAges(25, 40)), findsOneWidget);
    await tap(t, find.text(loc.dating_abroadTitle));
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
    await tap(t, find.byType(Switch));
    await tap(
      t,
      find.text(loc.dating_abroadTurnOn(datingCountryName(loc, 'GB'))),
    );
    expect(abroad.sets, [
      ['GB'],
    ]);
    final reads = today.reads;
    // The wider pool gives a card today.
    today.json = datingTodayJson();
    shell.router.pop();
    await t.pumpAndSettle();
    expect(find.byType(DatingAbroadScreen), findsNothing);
    expect(today.reads, reads + 1);
    expect(find.text(loc.dating_cardInterested), findsOneWidget);
  });

  testWidgets('the card: goldens and guidelines', (t) async {
    await expectFlowGoldens(
      t,
      'abroad_card',
      () => const DatingAbroadScreen(),
      overrides: [
        ...datingShellOverrides(),
        datingAbroadGatewayProvider.overrideWithValue(FakeAbroad(_eligible)),
      ],
      before: (t) async {
        await tapInReach(t, find.byType(Switch));
        await t.pumpAndSettle();
        expect(find.text(loc.dating_abroadCard), findsOneWidget);
      },
    );
    await expectFlowGuidelines(t);
  });

  testWidgets('dark: the page', (t) async {
    await pumpFlowScreen(
      t,
      () => Theme(data: AppTheme.darkTheme, child: const DatingAbroadScreen()),
      overrides: [
        ...datingShellOverrides(),
        datingAbroadGatewayProvider.overrideWithValue(
          FakeAbroad(
            const DatingAbroadOptions(
              ok: true,
              countries: [('GB', true), ('NG', false)],
            ),
          ),
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/abroad.dark.png'),
    );
    await expectFlowGuidelines(t);
  });
}
