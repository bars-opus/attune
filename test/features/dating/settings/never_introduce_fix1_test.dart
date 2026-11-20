// Spec 2 W5c Task 9 fix round 1: the number as the real number (C-1); the
// fields hold still while an add is out and "Added." never sits beside a
// new number (I-1); Remove asks first (I-2); rows spoken with a comma
// (M-3); a quiet wait and a removed row gone at once (M-4); Dating's own
// country sheet, whose search never lets the keyboard learn (M-5); the
// dial code and number left to right (M-6); quick exit leaves nothing.
import 'dart:async';

import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/never_introduce_phone.dart';
import 'package:attune/features/dating/settings/never_introduce_screen.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_private_keyboard.dart';
import '../support/dating_shell.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

const _list = DatingNeverIntroduceList(
  ok: true,
  items: [
    DatingNeverIntroduceItem(id: 'n1', label: 'Kwame', lastTwo: '42'),
    DatingNeverIntroduceItem(id: 'n2', lastTwo: '07'),
  ],
);

final _number = find.byKey(const ValueKey('dating_never_number'));
final _label = find.byKey(const ValueKey('dating_never_label'));

PhoneCountry _country(String iso) =>
    PhoneCountries.all.firstWhere((c) => c.isoCode == iso);

void main() {
  final loc = AppLocalizationsEn();

  Future<(DatingShell, FakeNeverIntroduce)> open(
    WidgetTester t, {
    FakeNeverIntroduce? fake,
    String? accountPhone,
  }) async {
    final f = fake ?? FakeNeverIntroduce(_list);
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.neverIntroduce,
      overrides: [
        datingNeverIntroduceGatewayProvider.overrideWithValue(f),
        if (accountPhone != null)
          currentUserProvider.overrideWith(
            (ref) => User(
              id: ref.watch(datingTestAccount) ?? 'ama',
              phone: accountPhone,
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: '2026-11-20T00:00:00Z',
            ),
          ),
      ],
    );
    return (shell, f);
  }

  Future<void> add(WidgetTester t, String number) async {
    await t.enterText(_number, number);
    await t.pump();
    await tap(t, find.text(loc.dating_neverAdd));
  }

  group('C-1: the number it really is', () {
    test('as typed or pasted, for the picked country', () {
      final gh = _country('GH');
      final gb = _country('GB');
      for (final (text, country, want) in [
        ('+233 24 123 4567', gh, '+233241234567'),
        ('00233 24 123 4567', gh, '+233241234567'),
        // 00 is read as "+" whatever the picked country's own exit code
        // (the US dials 011, so its parser alone would refuse this).
        ('00233 24 123 4567', _country('US'), '+233241234567'),
        ('0044 7400 123456', _country('US'), '+447400123456'),
        ('024 123 4567', gh, '+233241234567'),
        ('(024) 123-4567', gh, '+233241234567'),
        ('+44 7400 123456', gh, '+447400123456'),
        ('07400 123456', gb, '+447400123456'),
        ('+233 24 123 4567', gb, '+233241234567'),
        ('07400 123456', gh, null),
        ('0241234', gh, null),
        ('+999 1234 5678', gh, null),
        ('not a number', gh, null),
        ('', gh, null),
      ]) {
        expect(
          datingNeverE164(text, country),
          want,
          reason: '$text (${country.isoCode})',
        );
      }
    });

    test('the picker starts on the account phone\'s country', () {
      expect(datingCountryForPhone('447400123456').isoCode, 'GB');
      expect(datingCountryForPhone('+2348031234567').isoCode, 'NG');
      expect(datingCountryForPhone(null).isoCode, 'GH');
      expect(datingCountryForPhone('').isoCode, 'GH');
    });

    testWidgets('a pasted +233 number is sent as itself, never +233233…', (
      t,
    ) async {
      final (_, fake) = await open(t);
      await add(t, '+233 24 123 4567');
      expect(fake.adds.single.$2, '+233241234567');
      expect(find.text(loc.dating_neverAdded), findsOneWidget);
    });

    testWidgets('00233 is the same number', (t) async {
      final (_, fake) = await open(t);
      await add(t, '00233 24 123 4567');
      expect(fake.adds.single.$2, '+233241234567');
    });

    testWidgets('a +44 number with Ghana picked is a UK number', (t) async {
      final (_, fake) = await open(t);
      await add(t, '+44 7400 123456');
      expect(fake.adds.single.$2, '+447400123456');
    });

    testWidgets('a UK local number once the UK is picked; the page stays', (
      t,
    ) async {
      final (_, fake) = await open(t);
      await tap(t, find.bySemanticsLabel(loc.dating_neverCountryCode('+233')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('dating_never_country_search')),
        'United Kingdom',
      );
      await t.pump();
      await tapInReach(t, find.textContaining('United Kingdom').last);
      await t.pumpAndSettle();
      // The sheet closes once: the page is still here (the shared sheet
      // closed itself and the page with it).
      expect(find.byType(DatingNeverIntroduceScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.bySemanticsLabel(loc.dating_neverCountryCode('+44')),
        findsOneWidget,
      );
      await add(t, '07400 123456');
      expect(fake.adds.single.$2, '+447400123456');
    });

    testWidgets('the account phone\'s country is picked first', (t) async {
      final (_, fake) = await open(t, accountPhone: '447400123456');
      expect(
        find.bySemanticsLabel(loc.dating_neverCountryCode('+44')),
        findsOneWidget,
      );
      await add(t, '07400 123456');
      expect(fake.adds.single.$2, '+447400123456');
    });

    testWidgets('not a real number: the check line, and nothing is sent', (
      t,
    ) async {
      final (_, fake) = await open(t);
      for (final bad in ['0241234', '07400 123456']) {
        await add(t, bad);
        expect(fake.adds, isEmpty, reason: bad);
        expect(find.text(loc.dating_neverCheckNumber), findsOneWidget);
        expect(find.text(loc.dating_neverAdded), findsNothing);
      }
    });
  });

  testWidgets('I-1: the fields hold still while an add is out; "Added." '
      'goes once anything is typed', (t) async {
    final fake = FakeNeverIntroduce(_list)..addHold = Completer<void>();
    await open(t, fake: fake);
    await t.enterText(_label, 'Kofi');
    await add(t, '0241234567');
    expect(fake.adds, hasLength(1));
    expect(t.widget<TextField>(_number).readOnly, isTrue);
    expect(t.widget<TextField>(_label).readOnly, isTrue);
    expect(find.text(loc.dating_neverAdded), findsNothing);
    fake.addHold!.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(t.widget<TextField>(_number).readOnly, isFalse);
    expect(t.widget<TextField>(_label).readOnly, isFalse);
    expect(find.text(loc.dating_neverAdded), findsOneWidget);
    await t.enterText(_number, '0201234567');
    await t.pump();
    expect(find.text(loc.dating_neverAdded), findsNothing);
    expect(find.text('0201234567'), findsOneWidget);
    // And a new name alone clears it too.
    fake.addHold = null;
    await tap(t, find.text(loc.dating_neverAdd));
    expect(find.text(loc.dating_neverAdded), findsOneWidget);
    await t.enterText(_label, 'Yaw');
    await t.pump();
    expect(find.text(loc.dating_neverAdded), findsNothing);
  });

  group('I-2: Remove asks first', () {
    final removeKwame = loc.dating_neverRemoveLabel(
      loc.dating_neverRowSpoken('Kwame', '42'),
    );
    Finder inSheet(String text) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(text),
    );

    testWidgets('Keep sends nothing', (t) async {
      final (_, fake) = await open(t);
      await tap(t, find.bySemanticsLabel(removeKwame));
      await t.pumpAndSettle();
      // W5 final fix (M-3): the confirm names the row.
      expect(
        find.text(loc.dating_neverRemoveTitleNamed('Kwame', '42')),
        findsOneWidget,
      );
      expect(find.text(loc.dating_neverRemoveBody), findsOneWidget);
      await tapInReach(t, inSheet(loc.dating_neverKeep));
      await t.pumpAndSettle();
      expect(fake.removes, isEmpty);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(loc.dating_neverRow('Kwame', '42')), findsOneWidget);
      // Remove is usable again.
      await tap(t, find.bySemanticsLabel(removeKwame));
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('Remove sends once, and the row goes at once (M-4)', (t) async {
      final (_, fake) = await open(t);
      await tap(t, find.bySemanticsLabel(removeKwame));
      await t.pumpAndSettle();
      // The re-read is held: the row must go on the remove's own ok.
      fake.hold = Completer<DatingNeverIntroduceList>();
      final remove = inSheet(loc.dating_neverRemove);
      await tapInReach(t, remove);
      await t.tap(remove, warnIfMissed: false);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(fake.removes, ['n1']);
      expect(find.text(loc.dating_neverRow('Kwame', '42')), findsNothing);
      expect(find.text(loc.dating_neverRowNoLabel('07')), findsOneWidget);
    });

    testWidgets('a refused remove keeps the row', (t) async {
      final (_, fake) = await open(t);
      fake.answer = const DatingWrite(ok: false, reason: 'failed');
      await tap(t, find.bySemanticsLabel(removeKwame));
      await t.pumpAndSettle();
      await tapInReach(t, inSheet(loc.dating_neverRemove));
      await t.pumpAndSettle();
      expect(fake.removes, ['n1']);
      expect(find.text(loc.dating_neverRow('Kwame', '42')), findsOneWidget);
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    });

    testWidgets('the confirm: goldens and guidelines', (t) async {
      Future<void> openConfirm(WidgetTester t) async {
        await tapInReach(t, find.bySemanticsLabel(removeKwame));
        await t.pumpAndSettle();
      }

      await expectFlowGoldens(
        t,
        'never_introduce_remove',
        () => const DatingNeverIntroduceScreen(),
        overrides: [
          ...datingShellOverrides(),
          datingNeverIntroduceGatewayProvider.overrideWithValue(
            FakeNeverIntroduce(_list),
          ),
        ],
        before: openConfirm,
      );
      await expectFlowGuidelines(t);
    });
  });

  testWidgets('M-3: a row is spoken with a comma', (t) async {
    final semantics = t.ensureSemantics();
    await open(t);
    expect(find.bySemanticsLabel('Kwame, ending 42'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('·')), findsNothing);
    semantics.dispose();
  });

  testWidgets('M-4: a quiet wait while the list is read', (t) async {
    // The next account's first read is held open (its list is unknown).
    final (shell, fake) = await open(t);
    fake.hold = Completer<DatingNeverIntroduceList>();
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(DatingNeverIntroduceScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel(loc.loadingDefaultMessage), findsOneWidget);
    fake.hold!.complete(_list);
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(loc.dating_neverRow('Kwame', '42')), findsOneWidget);
  });

  testWidgets('M-5: the country search never lets the keyboard learn', (
    t,
  ) async {
    await open(t);
    await tap(t, find.bySemanticsLabel(loc.dating_neverCountryCode('+233')));
    await t.pumpAndSettle();
    expectPrivateKeyboard(t, find.byType(BottomSheet));
    expect(find.text(loc.dating_neverCountryTitle), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('dating_never_country_search')),
      'zzzz',
    );
    await t.pump();
    expect(find.text(loc.dating_neverCountryNone), findsOneWidget);
  });

  testWidgets('M-6: the dial code and the number run left to right', (t) async {
    await open(t);
    expect(t.widget<TextField>(_number).textDirection, TextDirection.ltr);
    final dial = t.widget<Text>(
      find.descendant(
        of: find.byType(OutlinedButton),
        matching: find.text('+233'),
      ),
    );
    expect(dial.textDirection, TextDirection.ltr);
  });

  group('quick exit', () {
    setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));
    setUp(() {
      QuickExitService.clearStories = () async {};
      addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
    });

    for (final sheetOpen in [false, true]) {
      testWidgets('leaves nothing typed${sheetOpen ? ', sheet open' : ''}', (
        t,
      ) async {
        await pumpDatingShell(
          t,
          initial: DatingPaths.neverIntroduce,
          locked: true,
          wrap: (router, child) => QuickExitZone(router: router, child: child),
          overrides: [
            datingNeverIntroduceGatewayProvider.overrideWithValue(
              FakeNeverIntroduce(_list),
            ),
          ],
        );
        await t.enterText(_number, '0241234567');
        await t.enterText(_label, 'Kofi');
        await t.pump();
        if (sheetOpen) {
          await tap(
            t,
            find.bySemanticsLabel(loc.dating_neverCountryCode('+233')),
          );
          await t.pumpAndSettle();
          expect(find.byType(BottomSheet), findsOneWidget);
        }
        for (var i = 0; i < 3; i++) {
          await t.tap(
            find.byKey(const Key('quick_exit_zone')),
            warnIfMissed: false,
          );
          await t.pump(const Duration(milliseconds: 50));
        }
        await t.pumpAndSettle(const Duration(milliseconds: 400));
        expect(find.text('DECOY'), findsOneWidget);
        expect(
          find.byType(DatingNeverIntroduceScreen, skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
        expect(find.text('0241234567', skipOffstage: false), findsNothing);
        expect(find.text('Kofi', skipOffstage: false), findsNothing);
      });
    }
  });
}
