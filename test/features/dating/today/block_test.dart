// Spec 2 W5b Task 7b (§3.4 the card's "More", §3.6 Block; D8; Ruling R-36):
// the card's overflow offers Block; the confirm names the person, says the
// person won't be told and won't be introduced again, and sends one request
// under one key; the card collapses to a calm line; each refusal is the
// card's own calm line or error row, and a busy retry keeps its key;
// offline, Block waits; an open confirm shows nothing of the last account
// and closes as the next one, sending nothing; an answer that comes back
// after the account changed shows nothing. (N-2, Task 7's review) a Not
// for me held when More covers Today is sent once, never dropped.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

void main() {
  final loc = AppLocalizationsEn();

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingToday fake, {
    bool online = true,
  }) => pumpDatingShell(
    t,
    initial: DatingPaths.today,
    online: online,
    overrides: datingTodayOverrides(fake),
  );

  /// More, then "Block Kofi": the confirm is open and settled.
  Future<void> confirm(WidgetTester t) async {
    await tapInReach(t, find.text(loc.dating_cardMore));
    await t.pumpAndSettle();
    await tapInReach(t, find.text(loc.dating_blockRow('Kofi')));
    await t.pumpAndSettle();
  }

  test(
    'the answer reads fail closed; the repository sends its one RPC',
    () async {
      expect(DatingBlockAnswer.fromJson({'ok': true}).ok, isTrue);
      for (final r in datingBlockReasons) {
        expect(
          DatingBlockAnswer.fromJson({'ok': false, 'reason': r}).reason,
          r,
        );
      }
      expect(
        DatingBlockAnswer.fromJson({
          'ok': false,
          'reason': 'a server text',
        }).reason,
        'failed',
      );
      expect(DatingBlockAnswer.fromJson(null).reason, 'failed');
      expect(DatingBlockAnswer.fromJson('x').ok, isFalse);
      final calls = <(String, Map<String, dynamic>?)>[];
      Object? Function() reply = () => {'ok': true};
      final repo = DatingTodayRepository(
        DatingRpc.withCall((fn, p) async {
          calls.add((fn, p));
          return reply();
        }),
        (body) async => null,
      );
      expect((await repo.block('b' * 20, 'i1')).ok, isTrue);
      expect(calls.single.$1, 'block_dating_introduction');
      expect(calls.single.$2, {
        'p_idempotency_key': 'b' * 20,
        'p_introduction_id': 'i1',
      });
      reply = () => throw PostgrestException(message: 'dating:busy');
      expect((await repo.block('b' * 20, 'i1')).reason, 'busy');
      reply = () => throw PostgrestException(message: 'a server\'s own words');
      expect((await repo.block('b' * 20, 'i1')).reason, 'failed');
    },
  );

  testWidgets(
    'More offers Block; the confirm names the person and says what happens; Cancel sends nothing',
    (t) async {
      final semantics = t.ensureSemantics();
      final fake = FakeDatingToday();
      await open(t, fake);
      expect(
        find.bySemanticsLabel(loc.dating_cardMoreLabel('Kofi')),
        findsOneWidget,
      );
      await tapInReach(t, find.text(loc.dating_cardMore));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_blockRow('Kofi')), findsOneWidget);
      await tapInReach(t, find.text(loc.dating_blockRow('Kofi')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_blockTitle('Kofi')), findsOneWidget);
      expect(find.text(loc.dating_blockBody('Kofi')), findsOneWidget);
      expect(loc.dating_blockBody('Kofi'), contains("Kofi won't be told."));
      expect(
        loc.dating_blockBody('Kofi'),
        contains("You won't be introduced again"),
      );
      for (final line in [
        loc.dating_blockTitle('Kofi'),
        loc.dating_blockBody('Kofi'),
        loc.dating_blockRow('Kofi'),
        loc.dating_blockDone('Kofi'),
        loc.dating_cardMoreLabel('Kofi'),
      ]) {
        expect(
          RegExp(r'\bthey\b', caseSensitive: false).hasMatch(line),
          isFalse,
          reason: line,
        );
      }
      expect(
        find.bySemanticsLabel(loc.dating_blockRow('Kofi')),
        findsOneWidget,
      );
      expect(
        t
            .getSize(find.widgetWithText(FilledButton, loc.dating_cardBlock))
            .height,
        greaterThanOrEqualTo(48),
      );
      await tapInReach(t, find.text(loc.dating_blockCancel));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_blockTitle('Kofi')), findsNothing);
      expect(fake.blocks, isEmpty);
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'Block: one request under one key; the card collapses to a calm line',
    (t) async {
      final fake = FakeDatingToday();
      await open(t, fake);
      await confirm(t);
      await tapInReach(t, find.text(loc.dating_cardBlock));
      await t.pumpAndSettle();
      expect(fake.blocks.map((b) => b.$2), ['i1']);
      expect(fake.blocks.single.$1.length, greaterThanOrEqualTo(16));
      expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
      expect(find.text(loc.dating_cardInterested), findsNothing);
      expect(find.text(loc.dating_cardMore), findsNothing);
      expect(fake.acts, isEmpty);
      await t.pump(const Duration(seconds: 30));
      expect(fake.blocks, hasLength(1));
    },
  );

  testWidgets(
    'each refusal: the re-check, calm busy (a retry keeps its key), the gone line, the error rows; offline, Block waits',
    (t) async {
      for (final (reason, line) in [
        ('reverify_device', loc.dating_sectionReverify),
        ('busy', loc.dating_busy),
        ('introduction_unavailable', loc.dating_cardGone),
        ('rate_limited', loc.dating_errorRateLimited),
        ('invalid', loc.dating_errorGeneric),
        ('failed', loc.dating_errorGeneric),
      ]) {
        final fake =
            FakeDatingToday()
              ..blockAnswer =
                  (id) => DatingBlockAnswer(ok: false, reason: reason);
        await open(t, fake);
        await confirm(t);
        await tapInReach(t, find.text(loc.dating_cardBlock));
        await t.pumpAndSettle();
        expect(find.text(line), findsOneWidget, reason: reason);
        expect(find.text(loc.dating_cardInterested), findsOneWidget);
        expect(find.text(loc.dating_blockDone('Kofi')), findsNothing);
        if (reason == 'busy') {
          await confirm(t);
          await tapInReach(t, find.text(loc.dating_cardBlock));
          await t.pumpAndSettle();
          expect(fake.blocks, hasLength(2));
          expect(fake.blocks[1].$1, fake.blocks[0].$1);
        }
      }
      final offline = FakeDatingToday();
      await open(t, offline, online: false);
      await confirm(t);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(loc.dating_offline),
        ),
        findsOneWidget,
      );
      await t.tap(find.text(loc.dating_cardBlock), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(offline.blocks, isEmpty);
      expect(find.text(loc.dating_blockTitle('Kofi')), findsOneWidget);
    },
  );

  testWidgets('a double tap sends one request; More waits while it is open', (
    t,
  ) async {
    final fake = FakeDatingToday()..blockHold = Completer<DatingBlockAnswer>();
    await open(t, fake);
    await confirm(t);
    final block = find.text(loc.dating_cardBlock);
    await t.tap(block);
    await t.tap(block, warnIfMissed: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(loc.dating_todayTitle), findsOneWidget);
    expect(fake.blocks, hasLength(1));
    await tapInReach(t, find.text(loc.dating_cardMore));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(loc.dating_blockRow('Kofi')), findsNothing);
    fake.blockHold!.complete(const DatingBlockAnswer(ok: true));
    await t.pumpAndSettle();
    expect(fake.blocks, hasLength(1));
    expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
  });

  testWidgets(
    'D8: an open confirm closes as the next account and sends nothing; an answer after the change shows nothing',
    (t) async {
      final fake = FakeDatingToday();
      final shell = await open(t, fake);
      await confirm(t);
      fake.hold = Completer<DatingToday>();
      shell.container.read(datingTestAccount.notifier).state = 'kwame';
      await t.pump();
      expect(find.textContaining('Kofi'), findsNothing);
      await t.pump(const Duration(seconds: 1));
      // (Its exit animation starts on the frame after the close: one more.)
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(BottomSheet), findsNothing);
      expect(fake.blocks, isEmpty);

      final held =
          FakeDatingToday()..blockHold = Completer<DatingBlockAnswer>();
      final next = await open(t, held);
      await confirm(t);
      await tapInReach(t, find.text(loc.dating_cardBlock));
      await t.pump();
      expect(held.blocks, hasLength(1));
      held.hold = Completer<DatingToday>();
      next.container.read(datingTestAccount.notifier).state = 'kwame';
      await t.pump();
      held.blockHold!.complete(const DatingBlockAnswer(ok: true));
      await t.pump();
      held.hold!.complete(
        DatingToday.fromJson(
          datingTodayJson({
            'cards': [
              datingCardJson('i1', {'display_name': 'Yaw'}),
            ],
          }),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Kofi'), findsNothing);
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      expect(held.blocks, hasLength(1));
    },
  );

  testWidgets(
    'D8, Today kept on screen: a block answer that lands after the account '
    'changed shows nothing on the next account\'s card',
    (t) async {
      // (In the Dating shell the lock gate builds a new Today for the next
      // account; here the same Today stays, so only the account check
      // stands between the late answer and the next person's card.)
      final held =
          FakeDatingToday()..blockHold = Completer<DatingBlockAnswer>();
      await pumpFlowScreen(
        t,
        () => const DatingTodayScreen(),
        overrides: [...datingShellOverrides(), ...datingTodayOverrides(held)],
      );
      await confirm(t);
      await tapInReach(t, find.text(loc.dating_cardBlock));
      await t.pump();
      expect(held.blocks, hasLength(1));
      held.hold = Completer<DatingToday>();
      ProviderScope.containerOf(t.element(find.byType(DatingTodayScreen)))
          .read(datingTestAccount.notifier)
          .state = 'kwame';
      await t.pump();
      held.blockHold!.complete(const DatingBlockAnswer(ok: true));
      await t.pump();
      held.hold!.complete(
        DatingToday.fromJson(
          datingTodayJson({
            'cards': [
              datingCardJson('i1', {'display_name': 'Yaw'}),
            ],
          }),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Kofi'), findsNothing);
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      expect(held.blocks, hasLength(1));
    },
  );

  testWidgets(
    'N-2 (Task 7 review): a Not for me held on a waiting card is sent once '
    'when More covers Today, and never dropped',
    (t) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'waiting': [
            datingCardJson('w1', {'display_name': 'Yaw'}),
          ],
        }),
      );
      await open(t, fake);
      // Not for me on Yaw's waiting card: held for its undo window.
      await tapInReach(t, find.text(loc.dating_cardNotForMe).last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(loc.dating_cardNotForMeDone), findsOneWidget);
      expect(fake.acts, isEmpty);
      // More on Kofi's card covers Today: the bar goes on that frame and
      // the held pass is sent once the frame ends.
      await tapInReach(t, find.text(loc.dating_cardMore));
      await t.pump();
      expect(find.text(loc.dating_cardNotForMeDone), findsNothing);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(loc.dating_blockRow('Kofi')), findsOneWidget);
      expect(fake.acts.map((a) => (a.$2, a.$3)), [('w1', 'passed')]);
      // Closed choosing nothing: the window's end sends nothing more.
      await t.tapAt(const Offset(195, 20));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_blockRow('Kofi')), findsNothing);
      await t.pump(const Duration(seconds: 30));
      expect(fake.acts, hasLength(1));
      // Then Block on Kofi: the pass is not sent again, Yaw's card stays
      // folded away, and one block goes.
      await confirm(t);
      await tapInReach(t, find.text(loc.dating_cardBlock));
      await t.pumpAndSettle();
      expect(fake.acts.map((a) => (a.$2, a.$3)), [('w1', 'passed')]);
      expect(fake.blocks.map((b) => b.$2), ['i1']);
      expect(find.textContaining('Yaw'), findsNothing);
      expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
    },
  );

  testWidgets('the confirm: goldens, guidelines, dark', (t) async {
    Future<void> openConfirm(WidgetTester t) async {
      await tapInReach(t, find.text(loc.dating_cardMore));
      await t.pumpAndSettle();
      await tapInReach(t, find.text(loc.dating_blockRow('Kofi')));
      await t.pumpAndSettle();
    }

    await expectFlowGoldens(
      t,
      'today_block_sheet',
      () => const DatingTodayScreen(),
      overrides: [
        ...datingShellOverrides(),
        ...datingTodayOverrides(FakeDatingToday()),
      ],
      before: openConfirm,
    );
    await pumpFlowScreen(
      t,
      () => const DatingTodayScreen(),
      overrides: [
        ...datingShellOverrides(),
        ...datingTodayOverrides(FakeDatingToday()),
      ],
    );
    await openConfirm(t);
    await expectFlowGuidelines(t);
    await pumpFlowScreen(
      t,
      () => Theme(data: AppTheme.darkTheme, child: const DatingTodayScreen()),
      overrides: [
        ...datingShellOverrides(),
        ...datingTodayOverrides(FakeDatingToday()),
      ],
    );
    await openConfirm(t);
    expect(find.text(loc.dating_blockTitle('Kofi')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
