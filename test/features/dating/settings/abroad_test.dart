// Spec 2 W5c (§2.6, §3.12, §3.15; carry 17; D8): Other countries. Turning
// a country on shows the cross-border card and writes only on "Turn on";
// "Not now" writes nothing; turning off writes at once, even before the
// person is eligible; not eligible says when; refusals in their own words;
// the settings row and the Widen row appear only once eligible. W5 final
// fix (M-11): not eligible, the page shows no list, only the off-only
// path, and the Widen row shows whenever the read answers.
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/abroad_screen.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
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

void main() {
  final loc = AppLocalizationsEn();

  Future<FakeAbroad> open(WidgetTester t, DatingAbroadOptions o) async {
    final fake = FakeAbroad(o);
    await pumpDatingShell(
      t,
      initial: DatingPaths.abroad,
      overrides: [datingAbroadGatewayProvider.overrideWithValue(fake)],
    );
    return fake;
  }

  testWidgets(
    'on: the cross-border card first; "Turn on" writes, "Not now" nothing',
    (t) async {
      final fake = await open(t, _eligible);
      expect(find.text(countryNameFor('GB')), findsOneWidget);
      await tap(t, find.byType(Switch));
      expect(find.text(loc.dating_abroadCard), findsOneWidget);
      await tap(t, find.text(loc.dating_abroadNotNow));
      expect(fake.sets, isEmpty);
      await tap(t, find.byType(Switch));
      await tap(
        t,
        find.text(loc.dating_abroadTurnOn(datingCountryName(loc, 'GB'))),
      );
      expect(fake.sets, [
        ['GB'],
      ]);
    },
  );

  testWidgets(
    'off at once, even before eligible; on waits; not eligible says when',
    (t) async {
      final fake = await open(
        t,
        const DatingAbroadOptions(
          ok: true,
          countries: [('GB', true), ('NG', false)],
        ),
      );
      expect(find.text(loc.dating_abroadDisabled), findsOneWidget);
      // W5 final fix (M-11): no list and no country; off is one action.
      expect(find.byType(Switch), findsNothing);
      expect(find.text(countryNameFor('GB')), findsNothing);
      expect(find.text(countryNameFor('NG')), findsNothing);
      await tap(t, find.text(loc.dating_abroadAllOff));
      expect(find.text(loc.dating_abroadAllOffBodyNotYet), findsOneWidget);
      await tap(t, find.text(loc.dating_abroadAllOffConfirm));
      expect(find.text(loc.dating_abroadCard), findsNothing);
      expect(fake.sets, [<String>[]]);
      expect(find.text(loc.dating_abroadAllOffDone), findsOneWidget);
    },
  );

  // W5 final fix (M-11): the turn-off that no longer happens on a
  // not-eligible list, on the eligible one: at once, with no card.
  testWidgets('off at once on the list, with no card', (t) async {
    final fake = await open(
      t,
      const DatingAbroadOptions(
        ok: true,
        eligible: true,
        countries: [('GB', true), ('NG', false)],
      ),
    );
    await tap(t, find.byType(Switch).first);
    expect(find.text(loc.dating_abroadCard), findsNothing);
    expect(fake.sets, [<String>[]]);
  });

  testWidgets('refusals in their own words', (t) async {
    for (final (reason, line) in [
      ('not_yet', loc.dating_abroadDisabled),
      ('not_available', loc.dating_notAvailableHere),
      ('busy', loc.dating_busy),
      ('failed', loc.dating_errorGeneric),
      // Task 10 fix round 1 (M-5): the write's own refusals.
      ('not_eligible', loc.dating_sectionUnavailable),
      ('reverify_device', loc.dating_sectionReverify),
    ]) {
      final fake = FakeAbroad(_eligible)
        ..answer = DatingWrite(ok: false, reason: reason);
      await pumpDatingShell(
        t,
        initial: DatingPaths.abroad,
        overrides: [datingAbroadGatewayProvider.overrideWithValue(fake)],
      );
      await tap(t, find.byType(Switch));
      await tap(
        t,
        find.text(loc.dating_abroadTurnOn(datingCountryName(loc, 'GB'))),
      );
      expect(find.text(line), findsWidgets, reason: reason);
    }
    await open(t, const DatingAbroadOptions(reason: 'reverify_device'));
    expect(find.text(loc.dating_sectionReverify), findsOneWidget);
  });

  testWidgets('Widen shows Other countries once the read answers', (t) async {
    for (final (o, shown) in [
      (_eligible, findsOneWidget),
      // W5 final fix (M-11): not eligible too (the off-only path).
      (const DatingAbroadOptions(ok: true), findsOneWidget),
      (const DatingAbroadOptions(reason: 'reverify_device'), findsNothing),
    ]) {
      final today = FakeDatingToday(
        today: datingTodayJson({'today_state': 'empty', 'cards': <Object?>[]}),
      );
      await pumpDatingShell(
        t,
        initial: DatingPaths.today,
        overrides: [
          ...datingTodayOverrides(today),
          datingAbroadGatewayProvider.overrideWithValue(FakeAbroad(o)),
        ],
      );
      await tap(t, find.text(loc.dating_todayWiden));
      expect(find.text(loc.dating_abroadTitle), shown);
      expect(find.byType(DatingTodayScreen), findsOneWidget);
    }
  });

  testWidgets('goldens and guidelines', (t) async {
    await expectFlowGoldens(
      t,
      'abroad',
      () => const DatingAbroadScreen(),
      overrides: [
        ...datingShellOverrides(),
        datingAbroadGatewayProvider.overrideWithValue(FakeAbroad(_eligible)),
      ],
    );
    await expectFlowGuidelines(t);
  });
}
