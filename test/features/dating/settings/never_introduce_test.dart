// Spec 2 W5c (§3.12, §3.15; carry 16; D8): Never introduce me. "Added."
// for any number (the add from any phone); the country code and the number
// as E.164; the name optional, at most 20; no field lets the keyboard
// learn; rows read "{label} · ending {digits}" with Remove; a kept entry is
// only counted; a refusal in its own words (the re-check for Remove on
// another phone); offline the add waits; the next account sees nothing.
// Task 9 fix round 1: the number as the real number (C-1: the trunk 0
// dropped), the second add really sent (M-1), the add's every refusal
// (M-1, M-2), Remove through its confirm (I-2) and spoken with a comma
// (M-3), and the next account sees none of the last one's rows (M-1).
import 'dart:async';

import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/never_introduce_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  keptCount: 2,
);

void main() {
  final loc = AppLocalizationsEn();

  Future<(DatingShell, FakeNeverIntroduce)> open(
    WidgetTester t, {
    bool online = true,
  }) async {
    final fake = FakeNeverIntroduce(_list);
    final shell = await pumpDatingShell(
      t,
      initial: DatingPaths.neverIntroduce,
      online: online,
      overrides: [datingNeverIntroduceGatewayProvider.overrideWithValue(fake)],
    );
    return (shell, fake);
  }

  testWidgets(
    'the copy, the rows, the kept count; no field learns what is typed',
    (t) async {
      await open(t);
      for (final line in [
        loc.dating_neverTitle,
        loc.dating_neverBody,
        loc.dating_neverCode,
      ]) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.text(loc.dating_neverRow('Kwame', '42')), findsOneWidget);
      expect(find.text(loc.dating_neverRowNoLabel('07')), findsOneWidget);
      expect(find.text(loc.dating_neverIntroduceKept(2)), findsOneWidget);
      expectPrivateKeyboard(t, find.byType(DatingNeverIntroduceScreen));
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('dating_never_label')))
            .maxLength,
        20,
      );
    },
  );

  testWidgets(
    '"Added." for any number, sent as E.164 with the name; fields cleared',
    (t) async {
      final (_, fake) = await open(t);
      await t.enterText(
        find.byKey(const ValueKey('dating_never_number')),
        '024 123 4567',
      );
      await t.enterText(
        find.byKey(const ValueKey('dating_never_label')),
        'Kofi',
      );
      await t.pump();
      await tap(t, find.text(loc.dating_neverAdd));
      // Fix 1 (C-1): the number it really is (the trunk 0 dropped).
      expect(fake.adds.single.$2, '+233241234567');
      expect(fake.adds.single.$3, 'Kofi');
      expect(find.text(loc.dating_neverAdded), findsOneWidget);
      expect(find.text('024 123 4567'), findsNothing);
      fake.answer = const DatingWrite(ok: true);
      await t.enterText(
        find.byKey(const ValueKey('dating_never_number')),
        '0241234567',
      );
      await t.pump();
      await tap(t, find.text(loc.dating_neverAdd));
      expect(find.text(loc.dating_neverAdded), findsOneWidget);
      // Fix 1 (M-1): the second add was sent, as a new request.
      expect(fake.adds, hasLength(2));
      expect(fake.adds.last.$2, '+233241234567');
      expect(fake.adds.last.$3, isNull);
      expect(fake.adds.last.$1, isNot(fake.adds.first.$1));
    },
  );

  testWidgets(
    'refusals in their own words; Remove on another phone asks for the check',
    (t) async {
      final (_, fake) = await open(t);
      for (final (w, line) in [
        (
          const DatingWrite(ok: false, reason: 'invalid', field: 'phone'),
          loc.dating_neverCheckNumber,
        ),
        (
          const DatingWrite(ok: false, reason: 'invalid', field: 'label'),
          loc.dating_neverCheckLabel,
        ),
        (
          const DatingWrite(ok: false, reason: 'limit_reached'),
          loc.dating_neverLimit,
        ),
        (const DatingWrite(ok: false, reason: 'busy'), loc.dating_busy),
        // Fix 1 (M-1, M-2): every refusal the add can give.
        (
          const DatingWrite(ok: false, reason: 'rate_limited'),
          loc.dating_errorRateLimited,
        ),
        (
          const DatingWrite(ok: false, reason: 'feature_unavailable'),
          loc.dating_neverNotNow,
        ),
        (
          const DatingWrite(ok: false, reason: 'not_eligible'),
          loc.dating_neverNotNow,
        ),
        (
          const DatingWrite(ok: false, reason: 'failed'),
          loc.dating_errorGeneric,
        ),
      ]) {
        fake.answer = w;
        await t.enterText(
          find.byKey(const ValueKey('dating_never_number')),
          '0241234567',
        );
        await t.pump();
        final sent = fake.adds.length;
        await tap(t, find.text(loc.dating_neverAdd));
        expect(fake.adds, hasLength(sent + 1), reason: '${w.reason}');
        expect(find.text(line), findsOneWidget, reason: '${w.reason}');
      }
      expect(find.text(loc.dating_sectionUnavailable), findsNothing);
      fake.answer = const DatingWrite(ok: false, reason: 'reverify_device');
      await tap(
        t,
        find.bySemanticsLabel(
          loc.dating_neverRemoveLabel(loc.dating_neverRowSpoken('Kwame', '42')),
        ),
      );
      await t.pumpAndSettle();
      // Fix 1 (I-2): the confirm first.
      expect(fake.removes, isEmpty);
      await tap(
        t,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(loc.dating_neverRemove),
        ),
      );
      await t.pumpAndSettle();
      expect(fake.removes, ['n1']);
      expect(find.text(loc.dating_sectionReverify), findsOneWidget);
    },
  );

  testWidgets('offline the add waits; the next account sees nothing typed', (
    t,
  ) async {
    final (shell, fake) = await open(t, online: false);
    await t.enterText(
      find.byKey(const ValueKey('dating_never_number')),
      '0241234567',
    );
    await t.pump();
    await tap(t, find.text(loc.dating_neverAdd));
    expect(fake.adds, isEmpty);
    expect(find.text(loc.dating_offline), findsOneWidget);
    // Fix 1 (M-1): the next account's read is held open, so nothing of
    // the last account's list may show while it is read.
    final next = Completer<DatingNeverIntroduceList>();
    fake.hold = next;
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // The page is there for the next account (not just the lock's blank).
    expect(find.byType(DatingNeverIntroduceScreen), findsOneWidget);
    expect(find.text('0241234567'), findsNothing);
    expect(find.text(loc.dating_neverRow('Kwame', '42')), findsNothing);
    expect(find.text(loc.dating_neverRowNoLabel('07')), findsNothing);
    expect(find.text(loc.dating_neverIntroduceKept(2)), findsNothing);
    next.complete(const DatingNeverIntroduceList(ok: true));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_neverRow('Kwame', '42')), findsNothing);
    expect(find.text(loc.dating_neverIntroduceKept(2)), findsNothing);
  });

  testWidgets('goldens and guidelines', (t) async {
    await expectFlowGoldens(
      t,
      'never_introduce',
      () => const DatingNeverIntroduceScreen(),
      overrides: [
        ...datingShellOverrides(),
        datingNeverIntroduceGatewayProvider.overrideWithValue(
          FakeNeverIntroduce(_list),
        ),
      ],
    );
    await expectFlowGuidelines(t);
  });
}
