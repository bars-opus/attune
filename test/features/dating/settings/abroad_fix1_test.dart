// Spec 2 W5c Task 10 fix round 1 (task-10-review.md): the switches wait for
// the fresh read after a save, and a write is built from the read as it is
// when sent, so a turn-off is never undone by a later tap (I-1); on a phone
// Dating doesn't trust, no list, only the re-verify line and "Turn off every
// other country" behind a confirm whose default is Keep (M-1); the setup
// where step, opened as an editor, never tells an eligible person they
// aren't (M-2); offline nothing can be changed (M-5).
import 'dart:async';

import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/abroad_screen.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pumpAndSettle();
}

/// Reads answer [value] at once unless [hold] is set.
class _Reads extends FakeAbroad {
  _Reads(super.value);

  Completer<DatingAbroadOptions>? hold;
  int reads = 0;

  @override
  Future<DatingAbroadOptions> read() {
    reads++;
    return hold?.future ?? super.read();
  }
}

DatingAbroadOptions _opts(bool gb, bool ng) => DatingAbroadOptions(
  ok: true,
  eligible: true,
  countries: [('GB', gb), ('NG', ng)],
);

const _reverify = DatingAbroadOptions(reason: 'reverify_device');

void main() {
  final loc = AppLocalizationsEn();

  Future<DatingShell> open(
    WidgetTester t,
    FakeAbroad fake, {
    bool online = true,
  }) async {
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.abroad,
      online: online,
      overrides: [datingAbroadGatewayProvider.overrideWithValue(fake)],
    );
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
    return shell;
  }

  List<Switch> switches(WidgetTester t) =>
      t.widgetList<Switch>(find.byType(Switch)).toList();

  void reread(DatingShell shell) {
    final c = shell.container;
    c.invalidate(datingAbroadProvider(c.read(datingAccountProvider)));
  }

  final turnOnGb = find.text(
    loc.dating_abroadTurnOn(datingCountryName(loc, 'GB')),
  );

  group('I-1', () {
    testWidgets('the reviewer\'s GB/NG sequence: a turn-off is never undone '
        'by a tap made while the list is read again', (t) async {
      final fake = _Reads(_opts(true, true));
      await open(t, fake);
      expect(switches(t).map((s) => s.value), [true, true]);
      // The re-read after the save is held open (a slow network).
      fake.hold = Completer<DatingAbroadOptions>();
      await tapInReach(t, find.byType(Switch).at(1));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(fake.sets, [
        ['GB'],
      ]);
      expect(find.byType(DatingAbroadScreen), findsOneWidget);
      expect(switches(t).every((s) => s.onChanged == null), isTrue);
      await tapInReach(t, find.byType(Switch).first);
      await t.pump();
      expect(fake.sets, [
        ['GB'],
      ], reason: 'no second write while the list is read again');
      // The fresh list lands: NG off, and the switches come back.
      fake.value = _opts(true, false);
      fake.hold!.complete(_opts(true, false));
      fake.hold = null;
      await t.pumpAndSettle();
      expect(switches(t).map((s) => s.value), [true, false]);
      expect(switches(t).every((s) => s.onChanged != null), isTrue);
      await tap(t, find.byType(Switch).first);
      expect(fake.sets, [
        ['GB'],
        <String>[],
      ]);
    });

    testWidgets('the card answered after a re-read writes the list as it is '
        'now (NG, turned off meanwhile, stays off)', (t) async {
      final fake = _Reads(_opts(false, true));
      final shell = await open(t, fake);
      await tap(t, find.byType(Switch).first);
      expect(find.text(loc.dating_abroadCard), findsOneWidget);
      // NG is turned off meanwhile (another save's re-read lands).
      fake.value = _opts(false, false);
      reread(shell);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_abroadCard), findsOneWidget);
      await tap(t, turnOnGb);
      expect(fake.sets, [
        ['GB'],
      ]);
    });

    testWidgets('the card answered while a re-read is under way writes '
        'nothing and says so calmly', (t) async {
      final fake = _Reads(_opts(false, true));
      final shell = await open(t, fake);
      await tap(t, find.byType(Switch).first);
      fake.hold = Completer<DatingAbroadOptions>();
      reread(shell);
      await t.pump();
      await tapInReach(t, turnOnGb);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(fake.sets, isEmpty);
      expect(find.text(loc.dating_busy), findsOneWidget);
      fake.hold!.complete(_opts(false, true));
      await t.pumpAndSettle();
      expect(switches(t).every((s) => s.onChanged != null), isTrue);
    });
  });

  group('M-1: a phone Dating doesn\'t trust', () {
    testWidgets('no list; the action sends [] once, Keep sends nothing', (
      t,
    ) async {
      final fake = FakeAbroad(_reverify);
      await open(t, fake);
      expect(find.text(loc.dating_sectionReverify), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      for (final code in ['GB', 'NG', 'GH']) {
        expect(find.text(countryNameFor(code)), findsNothing);
        expect(find.text(datingCountryName(loc, code)), findsNothing);
      }
      await tap(t, find.text(loc.dating_abroadAllOff));
      expect(find.text(loc.dating_abroadAllOffTitle), findsOneWidget);
      expect(find.text(loc.dating_abroadAllOffBody), findsOneWidget);
      // Keep is first and the filled button.
      final keep = find.widgetWithText(
        FilledButton,
        loc.dating_abroadAllOffKeep,
      );
      expect(keep, findsOneWidget);
      expect(
        t.getTopLeft(keep).dy,
        lessThan(t.getTopLeft(find.text(loc.dating_abroadAllOffConfirm)).dy),
      );
      await tap(t, find.text(loc.dating_abroadAllOffKeep));
      expect(find.text(loc.dating_abroadAllOffTitle), findsNothing);
      expect(fake.sets, isEmpty);
      await tap(t, find.text(loc.dating_abroadAllOff));
      await tap(t, find.text(loc.dating_abroadAllOffConfirm));
      expect(fake.sets, [<String>[]]);
      expect(find.text(loc.dating_abroadAllOffDone), findsOneWidget);
      expect(find.text(loc.dating_abroadAllOff), findsNothing);
      expect(find.text(loc.dating_sectionReverify), findsOneWidget);
    });

    testWidgets('offline the action can\'t be used', (t) async {
      await open(t, FakeAbroad(_reverify), online: false);
      expect(find.text(loc.dating_offline), findsOneWidget);
      final button = find.ancestor(
        of: find.text(loc.dating_abroadAllOff),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(t.widget<ButtonStyleButton>(button).onPressed, isNull);
    });

    testWidgets('Dating settings offers the row there, and it opens the page', (
      t,
    ) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.settings,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.reverifyDevice),
        ),
        overrides: [
          datingAbroadGatewayProvider.overrideWithValue(FakeAbroad(_reverify)),
        ],
      );
      expect(find.text(loc.dating_settingsTitle), findsWidgets);
      await tap(t, find.text(loc.dating_abroadTitle));
      expect(find.byType(DatingAbroadScreen), findsOneWidget);
      expect(find.text(loc.dating_abroadAllOff), findsOneWidget);
    });

    testWidgets('a trusted, not-yet-set-up settings page has no row', (
      t,
    ) async {
      await pumpDatingShell(
        t,
        initial: DatingPaths.settings,
        overrides: [
          datingAbroadGatewayProvider.overrideWithValue(FakeAbroad(_reverify)),
        ],
      );
      expect(find.text(loc.dating_settingsTitle), findsWidgets);
      expect(find.text(loc.dating_abroadTitle), findsNothing);
    });

    testWidgets('goldens and guidelines: the page and the confirm', (t) async {
      final overrides = [
        ...datingShellOverrides(),
        datingAbroadGatewayProvider.overrideWithValue(FakeAbroad(_reverify)),
      ];
      await expectFlowGoldens(
        t,
        'abroad_reverify',
        () => const DatingAbroadScreen(),
        overrides: overrides,
      );
      await expectFlowGuidelines(t);
      await expectFlowGoldens(
        t,
        'abroad_all_off_confirm',
        () => const DatingAbroadScreen(),
        overrides: overrides,
        before: (t) async {
          await tapInReach(t, find.text(loc.dating_abroadAllOff));
          await t.pumpAndSettle();
          expect(find.text(loc.dating_abroadAllOffTitle), findsOneWidget);
        },
      );
      await expectFlowGuidelines(t);
    });
  });

  group('M-2: the where step as an editor', () {
    Future<_Reads> where(
      WidgetTester t,
      DatingAbroadOptions o, {
      String initial = '/dating/setup/where?from=today',
    }) async {
      final fake = _Reads(o);
      await pumpDatingShell(
        t,
        initial: initial,
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active),
        ),
        overrides: [
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(
              profile: const DatingMyProfile(
                countryCode: 'GH',
                regionCode: 'AA',
              ),
            ),
          ),
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(),
          ),
          datingAbroadGatewayProvider.overrideWithValue(fake),
        ],
      );
      expect(find.text(loc.dating_abroadRow), findsWidgets);
      return fake;
    }

    testWidgets('eligible: a link to Other countries, never "available once '
        'verified"', (t) async {
      await where(t, _opts(false, false));
      expect(find.text(loc.dating_abroadDisabled), findsNothing);
      await tap(t, find.text(loc.dating_abroadRow));
      expect(find.byType(DatingAbroadScreen), findsOneWidget);
    });

    testWidgets('not eligible: W3\'s line, which is true', (t) async {
      await where(t, const DatingAbroadOptions(ok: true));
      expect(find.text(loc.dating_abroadDisabled), findsOneWidget);
    });

    testWidgets('first-run setup: W3\'s row, and no read', (t) async {
      final fake = await where(
        t,
        _opts(false, false),
        initial: '/dating/setup/where',
      );
      expect(find.text(loc.dating_abroadDisabled), findsOneWidget);
      expect(fake.reads, 0);
    });
  });

  testWidgets('M-5: offline, no switch can be used', (t) async {
    await open(t, FakeAbroad(_opts(true, false)), online: false);
    expect(find.text(loc.dating_offline), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(switches(t).every((s) => s.onChanged == null), isTrue);
  });
}
