// Spec 2 W6c Task 9 rulings (§3.6, §3.15 Chat; D8, D20): the guided state
// is read beside the page and a failed re-read keeps it; only a top card
// new to the open chat is read out (never on a rebuild or a reopen); the
// day-21 card stays when Close kindly is cancelled; Close kindly and the
// answer sheet close under another account with nothing sent; offline,
// Skip, We met, Answer and Close kindly wait; a refused answer says why
// and is offered again; a double tap skips once; a skip that lost the
// race reads again with no line; a pair ended by a block shows no Close
// kindly or We met; the data reads defensively and calls Task 8's RPCs;
// dark, and text 2.0 with the keyboard up.
import 'dart:async';
import 'dart:convert';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_shell.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Map<String, Object?> page({
  String? timebox,
  bool weMet = false,
  bool ended = false,
  bool nullWeMet = false,
}) {
  final p = datingPageJson(ended: ended);
  final chat = Map<String, Object?>.from(p['chat']! as Map);
  chat['timebox'] = timebox;
  chat['we_met'] = nullWeMet ? null : {'mine': weMet, 'theirs': false};
  return {...p, 'chat': chat};
}

const _saturday = DatingGuided(questionId: 'good_saturday');

/// The live regions inside the top card [id].
Finder live(String id) => find.descendant(
  of: find.byKey(ValueKey('dating_top_$id')),
  matching: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.liveRegion == true,
  ),
);

void main() {
  final loc = AppLocalizationsEn();
  final answerButton = find.byKey(
    const ValueKey('dating_guided_answer_button'),
  );
  final skip = find.byKey(const ValueKey('dating_guided_skip'));
  final shield = find.byKey(const ValueKey('dating_chat_safety'));

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingChat fake, {
    bool online = true,
    double textScale = 1.0,
  }) => pumpDatingShell(
    t,
    initial: '/dating/chat/m1',
    online: online,
    textScale: textScale,
    overrides: datingChatOverrides(fake),
  );

  testWidgets('Ruling 4: a failed guided re-read keeps the card', (t) async {
    final fake = FakeDatingChat(page: page())..guidedState = _saturday;
    await open(t, fake);
    expect(find.text(loc.dating_guided_good_saturday), findsOneWidget);
    fake.refusals['guided'] = 'busy';
    fake.signalEvents.add(null);
    await t.pumpAndSettle();
    expect(fake.guidedReads, greaterThan(1));
    expect(find.text(loc.dating_guided_good_saturday), findsOneWidget);
    expect(answerButton, findsOneWidget);
  });

  testWidgets('Ruling 5: the chat never waits on the guided read', (t) async {
    final gate = Completer<void>();
    final fake = _GatedGuided(gate)..guidedState = _saturday;
    await open(t, fake);
    expect(find.text('Kofi, 31'), findsOneWidget);
    expect(find.text('Hi Ama!'), findsOneWidget);
    expect(find.text(loc.dating_guidedTitle), findsNothing);
    gate.complete();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_guidedTitle), findsOneWidget);
  });

  group('Ruling 6: only a top card new to the open chat is read out', () {
    testWidgets('cards there when the chat opens are not; a new question '
        'and the tip are, once', (t) async {
      final fake = FakeDatingChat(page: page(timebox: 'day7'))
        ..guidedState = _saturday;
      await open(t, fake);
      expect(find.text(loc.dating_timeboxDay7), findsOneWidget);
      expect(live('timebox:day7'), findsNothing);
      expect(live('guided:good_saturday:false'), findsNothing);
      fake.guidedState = const DatingGuided(
        questionId: 'food_every_week',
        revealed: 1,
      );
      await tap(t, skip);
      await t.pumpAndSettle();
      expect(live('guided:food_every_week:false'), findsOneWidget);
      expect(live('tip'), findsOneWidget);
      // A rebuild (another read) never reads them out again.
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(live('guided:food_every_week:false'), findsOneWidget);
      // Opened again: there before, so shown as they are.
      await open(t, fake);
      expect(find.text(loc.dating_guided_food_every_week), findsOneWidget);
      expect(live('guided:food_every_week:false'), findsNothing);
      expect(live('tip'), findsNothing);
    });

    testWidgets('a timebox card that arrives later is read out', (t) async {
      final fake = FakeDatingChat(page: page());
      await open(t, fake);
      fake.pageJson = page(timebox: 'day21');
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_timeboxDay21), findsOneWidget);
      expect(live('timebox:day21'), findsOneWidget);
    });

    testWidgets('the waiting line after an answer is read out', (t) async {
      final fake = FakeDatingChat(page: page())..guidedState = _saturday;
      await open(t, fake);
      await tap(t, answerButton);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('dating_guided_answer')),
        'Market',
      );
      await t.pump();
      await tap(t, find.text(loc.dating_chatSend));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_guidedWaiting('Kofi')), findsOneWidget);
      expect(live('guided:good_saturday:true'), findsOneWidget);
    });
  });

  testWidgets('Ruling 7: day 21, Close kindly then Cancel: the card stays, '
      'nothing is sent', (t) async {
    final fake = FakeDatingChat(page: page(timebox: 'day21'));
    await open(t, fake);
    await tap(t, find.byKey(const ValueKey('dating_timebox_close')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_closeKindlyMessage), findsOneWidget);
    await tap(t, find.text(loc.dating_blockCancel));
    await t.pumpAndSettle();
    expect(fake.kindCloses, isEmpty);
    expect(fake.timeboxes, isEmpty);
    expect(find.text(loc.dating_timeboxDay21), findsOneWidget);
    // Keep chatting answers it.
    await tap(t, find.byKey(const ValueKey('dating_timebox_keep')));
    await t.pumpAndSettle();
    expect(fake.timeboxes, ['day21']);
    expect(find.text(loc.dating_timeboxDay21), findsNothing);
  });

  group('D8: another account', () {
    testWidgets('Close kindly: the sheet closes, nothing is sent', (t) async {
      final fake = FakeDatingChat(page: page());
      final s = await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      await tap(t, shield);
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_closeKindly));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_closeKindlyMessage), findsOneWidget);
      fake.hold = Completer<DatingChatPage>();
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(loc.dating_closeKindlyMessage), findsNothing);
      expect(find.textContaining('Kofi'), findsNothing);
      expect(fake.kindCloses, isEmpty);
    });

    testWidgets('the answer sheet: closes, nothing is sent', (t) async {
      final fake = FakeDatingChat(page: page())..guidedState = _saturday;
      final s = await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      await tap(t, answerButton);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('dating_guided_answer')),
        'Market',
      );
      fake.hold = Completer<DatingChatPage>();
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('dating_guided_answer')), findsNothing);
      expect(find.text(loc.dating_guided_good_saturday), findsNothing);
      expect(fake.answers, isEmpty);
    });
  });

  group('Ruling 8: offline waits (nothing is queued)', () {
    testWidgets('Skip and We met say offline and send nothing', (t) async {
      final fake = FakeDatingChat(page: page())..guidedState = _saturday;
      await open(t, fake, online: false);
      await tap(t, skip);
      await t.pumpAndSettle();
      expect(fake.skips, isEmpty);
      expect(find.text(loc.dating_offline), findsOneWidget);
      await tap(t, shield);
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_weMet));
      await t.pumpAndSettle();
      expect(fake.weMets, 0);
      expect(find.text(loc.dating_offline), findsOneWidget);
    });

    testWidgets('the answer sheet and Close kindly wait', (t) async {
      final fake = FakeDatingChat(page: page())..guidedState = _saturday;
      await open(t, fake, online: false);
      await tap(t, answerButton);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('dating_guided_answer')),
        'Market',
      );
      await t.pump();
      expect(find.text(loc.dating_offline), findsOneWidget);
      await t.tap(find.text(loc.dating_chatSend), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(fake.answers, isEmpty);
      await tap(t, find.text(loc.dating_blockCancel));
      await t.pumpAndSettle();
      await tap(t, shield);
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_closeKindly));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_offline), findsOneWidget);
      await t.tap(find.text(loc.dating_closeKindlySend), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(fake.kindCloses, isEmpty);
    });
  });

  testWidgets('Ruling 10: a refused answer says why and is offered again', (
    t,
  ) async {
    final fake =
        FakeDatingChat(page: page())
          ..guidedState = _saturday
          ..refusals['answerGuided'] = 'rate_limited';
    await open(t, fake);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('dating_guided_answer')),
      'Market, then football',
    );
    await t.pump();
    await tap(t, find.text(loc.dating_chatSend));
    await t.pumpAndSettle();
    expect(fake.answers, hasLength(1));
    expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
    expect(answerButton, findsOneWidget);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    expect(find.text('Market, then football'), findsOneWidget);
    // Paused: its own line.
    fake.refusals['answerGuided'] = 'unavailable';
    await tap(t, find.text(loc.dating_chatSend));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_chatPaused), findsOneWidget);
  });

  testWidgets('Ruling 11: the answer is counted as the server counts it', (
    t,
  ) async {
    final fake = FakeDatingChat(page: page())..guidedState = _saturday;
    await open(t, fake);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('dating_guided_answer')),
      '😀' * 600,
    );
    await t.pump();
    await tap(t, find.text(loc.dating_chatSend));
    await t.pumpAndSettle();
    expect(fake.answers.single.$3, '😀' * 600);
    fake.guidedState = const DatingGuided(questionId: 'food_every_week');
    fake.signalEvents.add(null);
    await t.pumpAndSettle();
    await tap(t, answerButton);
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('dating_guided_answer')),
      'a' * 1001,
    );
    await t.pump();
    expect(find.text(loc.dating_chatTooLong), findsOneWidget);
    await t.tap(find.text(loc.dating_chatSend), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(fake.answers, hasLength(1));
  });

  testWidgets('Ruling 12: a double tap on Skip skips once; a skip that lost '
      'the race reads again with no line', (t) async {
    final hold = Completer<DatingChatAnswer>();
    final held = _HeldSkip(hold)..guidedState = _saturday;
    await open(t, held);
    await t.tap(skip);
    await t.pump();
    await t.tap(skip, warnIfMissed: false);
    await t.pump();
    hold.complete(const DatingChatAnswer(ok: false, reason: 'invalid'));
    await t.pumpAndSettle();
    expect(held.skips, ['good_saturday']);
    expect(find.text(loc.dating_errorGeneric), findsNothing);
    expect(held.guidedReads, greaterThan(1));
  });

  testWidgets('We met refused (the chat ended): the ended line', (t) async {
    final fake = FakeDatingChat(page: page())..refusals['weMet'] = 'closed';
    await open(t, fake);
    await tap(t, shield);
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_weMet));
    await t.pumpAndSettle();
    expect(fake.weMets, 1);
    expect(find.text(loc.dating_chatEnded), findsOneWidget);
  });

  testWidgets('Close kindly ends the chat: read-only, no top cards', (t) async {
    final fake = _Closing()..guidedState = _saturday;
    await open(t, fake);
    await tap(t, shield);
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_closeKindly));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_closeKindlySend));
    await t.pumpAndSettle();
    expect(fake.kindCloses, hasLength(1));
    expect(find.text(loc.dating_chatEnded), findsOneWidget);
    expect(find.byKey(const ValueKey('dating_chat_composer')), findsNothing);
    expect(find.text(loc.dating_guidedTitle), findsNothing);
    expect(find.text(loc.dating_timeboxDay7), findsNothing);
  });

  testWidgets('a pair ended by a block (we_met and timebox null): no Close '
      'kindly, no We met', (t) async {
    final fake = FakeDatingChat(page: page(ended: true, nullWeMet: true));
    await open(t, fake);
    await tap(t, shield);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_chatSafetyResources), findsOneWidget);
    expect(find.text(loc.dating_closeKindly), findsNothing);
    expect(find.text(loc.dating_weMet), findsNothing);
  });

  testWidgets('text 2.0 with the keyboard up and both cards: nothing '
      'overflows, the composer stays reachable', (t) async {
    final fake = FakeDatingChat(page: page(timebox: 'day21'))
      ..guidedState = const DatingGuided(
        questionId: 'before_first_meeting',
        revealed: 1,
      );
    await open(t, fake, textScale: 2.0);
    t.view.viewInsets = const FakeViewPadding(bottom: 336);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('dating_chat_composer')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('dating_chat_send')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('the guided and day-21 cards in dark (golden)', (t) async {
    final fake = FakeDatingChat(page: page(timebox: 'day21'))
      ..guidedState = const DatingGuided(
        questionId: 'good_saturday',
        answered: true,
        revealed: 1,
      );
    await pumpFlowScreen(
      t,
      () => Theme(
        data: AppTheme.darkTheme,
        child: DatingChatScreen(matchId: 'm1', now: () => datingChatT0),
      ),
      overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dating_chat_guided.dark.png'),
    );
    await expectFlowGuidelines(t);
  });

  test('the data: header and guided state read defensively', () {
    DatingChatHeader header(Object? timebox, Object? weMet) =>
        DatingChatPage.fromJson({
          ...datingPageJson(),
          'chat': {
            ...datingPageJson()['chat']! as Map<String, Object?>,
            'timebox': timebox,
            'we_met': weMet,
          },
        }).header!;
    expect(header('day7', null).timebox, 'day7');
    expect(header('day21', null).timebox, 'day21');
    expect(header('2026-11-27', null).timebox, isNull);
    expect(header(null, null).weMet, isFalse);
    final met = header(null, {'mine': false, 'theirs': true});
    expect((met.weMet, met.theyMet), (false, true));
    final g = DatingGuided.fromJson({
      'ok': true,
      'question_id': 'laugh_with',
      'answered': true,
      'revealed': 4,
    });
    expect(
      (g.ok, g.questionId, g.answered, g.revealed),
      (true, 'laugh_with', true, 4),
    );
    // An id the app has no words for is no question; all done is ok.
    expect(
      DatingGuided.fromJson({
        'ok': true,
        'question_id': 'drop table',
      }).questionId,
      isNull,
    );
    final done = DatingGuided.fromJson({
      'ok': true,
      'question_id': null,
      'revealed': 9,
    });
    expect((done.ok, done.questionId, done.revealed), (true, null, 9));
    expect(DatingGuided.fromJson({'ok': false, 'reason': 'x'}).ok, isFalse);
    expect(DatingGuided.fromJson('nope').ok, isFalse);
  });

  test('the repository calls Task 8\'s RPCs with their parameters', () async {
    final calls = <String>[];
    final repo = DatingChatRepository(
      DatingRpc.withCall((fn, params) async {
        calls.add('$fn ${jsonEncode(params)}');
        return switch (fn) {
          'get_dating_guided_state' => {
            'ok': true,
            'question_id': 'proud_of',
            'answered': false,
            'revealed': 3,
          },
          'send_dating_message' => {
            'ok': true,
            'message': datingMessageJson('g1', 'Mine', mine: true),
          },
          _ => {'ok': true},
        };
      }),
      null,
    );
    expect((await repo.guided('m1')).questionId, 'proud_of');
    expect(
      (await repo.answerGuided(
        'key-guided-0123456789',
        'm1',
        'proud_of',
        'Mine',
      )).ok,
      isTrue,
    );
    expect((await repo.skipGuided('m1', 'proud_of')).ok, isTrue);
    expect((await repo.weMet('m1')).ok, isTrue);
    await repo.dismissTimebox('m1', 'day7');
    expect((await repo.closeKindly('key-close-0123456789', 'm1')).ok, isTrue);
    expect(calls, [
      'get_dating_guided_state {"p_match_id":"m1"}',
      'send_dating_message {"p_idempotency_key":"key-guided-0123456789","p_match_id":"m1","p_body":"Mine","p_kind":"guided_answer","p_question_id":"proud_of"}',
      'skip_dating_guided_question {"p_match_id":"m1","p_question_id":"proud_of"}',
      'mark_dating_we_met {"p_match_id":"m1"}',
      'dismiss_dating_timebox {"p_match_id":"m1","p_card":"day7"}',
      'close_dating_match_kindly {"p_idempotency_key":"key-close-0123456789","p_match_id":"m1"}',
    ]);
    // A failure: the guided read is failed (never none), the rest fixed.
    final down = DatingChatRepository(
      DatingRpc.withCall((fn, params) async => throw StateError('socket')),
      null,
    );
    expect((await down.guided('m1')).ok, isFalse);
    expect((await down.skipGuided('m1', 'proud_of')).reason, 'failed');
    expect((await down.weMet('m1')).reason, 'failed');
    await down.dismissTimebox('m1', 'day21');
    expect(
      (await down.closeKindly('key-close-0123456789', 'm1')).reason,
      'failed',
    );
  });
}

/// The guided read answers only when the test opens [gate].
class _GatedGuided extends FakeDatingChat {
  _GatedGuided(this.gate) : super(page: page());

  final Completer<void> gate;

  @override
  Future<DatingGuided> guided(String matchId) async {
    await gate.future;
    return super.guided(matchId);
  }
}

/// A skip that answers when the test completes [hold].
class _HeldSkip extends FakeDatingChat {
  _HeldSkip(this.skipHold) : super(page: page());

  final Completer<DatingChatAnswer> skipHold;

  @override
  Future<DatingChatAnswer> skipGuided(String matchId, String questionId) {
    skips.add(questionId);
    return skipHold.future;
  }
}

/// Close kindly as the server does it: the chat has ended once it answers.
class _Closing extends FakeDatingChat {
  _Closing() : super(page: page(timebox: 'day7'));

  @override
  Future<DatingChatAnswer> closeKindly(String key, String matchId) async {
    final r = await super.closeKindly(key, matchId);
    pageJson = page(ended: true);
    return r;
  }
}
