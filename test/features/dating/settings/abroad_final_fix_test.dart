// Spec 2 W5 final fix wave (final-client-review.md), Other countries: the
// cross-border card is a D8 sheet with a heading (M-4); the wait line goes
// once the read it waited for lands (M-8, T10 N-1); "Done." follows "Turn
// off every other country" only (M-9, T10 N-2); the where step's row is
// there, dimmed, while its read is under way (M-10, T10 N-3); and a person
// who isn't eligible (any more) reaches the page from settings, Widen and
// the where step, and can turn every country off without ever seeing the
// list (M-11).
import 'dart:async';

import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/abroad_screen.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// No longer eligible, with GB still on.
const _lapsed = DatingAbroadOptions(
  ok: true,
  countries: [('GB', true), ('NG', false)],
);

void main() {
  final loc = AppLocalizationsEn();

  Future<DatingShell> open(WidgetTester t, FakeAbroad fake) async {
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.abroad,
      overrides: [datingAbroadGatewayProvider.overrideWithValue(fake)],
    );
    expect(find.byType(DatingAbroadScreen), findsOneWidget);
    return shell;
  }

  void reread(DatingShell shell) {
    final c = shell.container;
    c.invalidate(datingAbroadProvider(c.read(datingAccountProvider)));
  }

  final turnOnGb = find.text(
    loc.dating_abroadTurnOn(datingCountryName(loc, 'GB')),
  );

  testWidgets('M-4: the card has a heading; on an account change it shows '
      'nothing of the country and closes, writing nothing', (t) async {
    final handle = t.ensureSemantics();
    final fake = _Reads(_opts(false, false));
    final shell = await open(t, fake);
    await tap(t, find.byType(Switch).first);
    final heading = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(loc.dating_abroadTitle),
    );
    expect(heading, findsOneWidget);
    expect(
      t
          .getSemantics(heading)
          .getSemanticsData()
          .hasFlag(SemanticsFlag.isHeader),
      isTrue,
    );
    expect(turnOnGb, findsOneWidget);
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    expect(turnOnGb, findsNothing);
    expect(find.text(loc.dating_abroadCard), findsNothing);
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(fake.sets, isEmpty);
    handle.dispose();
  });

  testWidgets('M-8: the wait line goes once the read lands', (t) async {
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
    fake.hold = null;
    await t.pumpAndSettle();
    expect(find.text(loc.dating_busy), findsNothing);
    final switches = t.widgetList<Switch>(find.byType(Switch));
    expect(switches.every((s) => s.onChanged != null), isTrue);
  });

  testWidgets('M-8: a busy write still says so after its re-read', (t) async {
    final fake = _Reads(_opts(true, false))
      ..answer = const DatingWrite(ok: false, reason: 'busy');
    await open(t, fake);
    await tap(t, find.byType(Switch).first);
    expect(fake.sets, [<String>[]]);
    expect(find.text(loc.dating_busy), findsOneWidget);
  });

  testWidgets('M-9: the last switch off, then a re-read on an untrusted '
      'phone: the action, never "Done."', (t) async {
    final fake = _Reads(_opts(true, false));
    await open(t, fake);
    // The save's re-read answers that this phone isn't trusted.
    fake.value = const DatingAbroadOptions(reason: 'reverify_device');
    await tap(t, find.byType(Switch).first);
    expect(fake.sets, [<String>[]]);
    expect(find.text(loc.dating_sectionReverify), findsOneWidget);
    expect(find.text(loc.dating_abroadAllOffDone), findsNothing);
    expect(find.text(loc.dating_abroadAllOff), findsOneWidget);
  });

  group('M-10, M-11: the where step as an editor', () {
    Future<_Reads> where(WidgetTester t, _Reads fake) async {
      await pumpDatingShell(
        t,
        initial: '/dating/setup/where?from=settings',
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
      return fake;
    }

    Finder row() => find.ancestor(
      of: find.text(loc.dating_abroadRow),
      matching: find.byType(ListTile),
    );

    testWidgets('M-10: while the read is out, the row is there, dimmed, '
        'saying so; then it becomes the link', (t) async {
      final fake = _Reads(_opts(false, false))
        ..hold = Completer<DatingAbroadOptions>();
      await where(t, fake);
      expect(row(), findsOneWidget);
      expect(t.widget<ListTile>(row()).enabled, isFalse);
      expect(find.text(loc.loadingDefaultMessage), findsOneWidget);
      expect(find.text(loc.dating_abroadDisabled), findsNothing);
      final top = t.getTopLeft(find.text(loc.dating_whereHelper)).dy;
      fake.hold!.complete(_opts(false, false));
      fake.hold = null;
      await t.pumpAndSettle();
      expect(t.widget<ListTile>(row()).enabled, isTrue);
      expect(find.text(loc.loadingDefaultMessage), findsNothing);
      // The helper below it doesn't jump by a whole row.
      expect(
        (t.getTopLeft(find.text(loc.dating_whereHelper)).dy - top).abs(),
        lessThan(30),
      );
    });

    testWidgets('M-11: not eligible, the row says when and still opens the '
        'page, which offers only the off-only path', (t) async {
      final fake = await where(t, _Reads(_lapsed));
      expect(find.text(loc.dating_abroadDisabled), findsOneWidget);
      await tap(t, find.text(loc.dating_abroadRow));
      expect(find.byType(DatingAbroadScreen), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.text(countryNameFor('GB')), findsNothing);
      await tap(t, find.text(loc.dating_abroadAllOff));
      await tap(t, find.text(loc.dating_abroadAllOffConfirm));
      expect(fake.sets, [<String>[]]);
    });
  });

  group('M-11: no longer eligible', () {
    testWidgets('settings: the row opens the page; no list, no country; '
        'the confirm says when, Keep sends nothing, Turn off sends []', (
      t,
    ) async {
      final fake = FakeAbroad(_lapsed);
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
          datingAbroadGatewayProvider.overrideWithValue(fake),
        ],
      );
      await tap(t, find.text(loc.dating_abroadTitle));
      expect(find.byType(DatingAbroadScreen), findsOneWidget);
      expect(find.text(loc.dating_abroadDisabled), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      for (final code in ['GB', 'NG']) {
        expect(find.text(countryNameFor(code)), findsNothing);
        expect(find.text(datingCountryName(loc, code)), findsNothing);
      }
      await tap(t, find.text(loc.dating_abroadAllOff));
      expect(find.text(loc.dating_abroadAllOffBodyNotYet), findsOneWidget);
      expect(find.text(loc.dating_abroadAllOffBody), findsNothing);
      await tap(t, find.text(loc.dating_abroadAllOffKeep));
      expect(fake.sets, isEmpty);
      await tap(t, find.text(loc.dating_abroadAllOff));
      await tap(t, find.text(loc.dating_abroadAllOffConfirm));
      expect(fake.sets, [<String>[]]);
      expect(find.text(loc.dating_abroadAllOffDone), findsOneWidget);
    });

    testWidgets('a refused read shows no row and no action', (t) async {
      await open(t, FakeAbroad(const DatingAbroadOptions(reason: 'busy')));
      expect(find.text(loc.dating_abroadAllOff), findsNothing);
      expect(find.text(loc.dating_busy), findsOneWidget);
    });
  });
}
