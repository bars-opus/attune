// Spec 2 W6c Task 9 fix round 1 (task-9-review.md; §3.6, §3.15 Chat; D8,
// D20). I-1: with the keyboard up the top cards step aside; down, Answer
// and Skip are reachable, the messages keep a usable height and the
// composer works, at 1.0, 1.3 and 2.0 on a 390×844 and a 360×640 phone.
// I-2: a guided answer, or a revealed pair, is one block under its
// question. I-3: an answer that lost the race (the question moved on, or
// the chat ended) says nothing wrong and goes to the composer. I-4: the
// tip until this side next writes; never once the questions are done.
// We met's calm line; the no-name waiting line; M-1 Close kindly's bubble
// in the app's words; M-2 day 21 answered only once Close kindly closed;
// M-3 a timebox dismissal kept and sent again; an account change empties
// the answer draft.
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String name = 'Kofi',
  List<Map<String, Object?>>? messages,
}) {
  final p = datingPageJson(name: name, messages: messages);
  final chat = Map<String, Object?>.from(p['chat']! as Map);
  chat['timebox'] = timebox;
  chat['we_met'] = {'mine': false, 'theirs': false};
  return {...p, 'chat': chat};
}

Map<String, Object?> answer(
  String id,
  String text, {
  bool mine = false,
  int minute = 0,
  String question = 'good_saturday',
}) => {
  ...datingMessageJson(id, text, mine: mine, minute: minute),
  'kind': 'guided_answer',
  'question_id': question,
};

const _saturday = DatingGuided(questionId: 'good_saturday');

void main() {
  final loc = AppLocalizationsEn();
  final answerButton = find.byKey(
    const ValueKey('dating_guided_answer_button'),
  );
  final skip = find.byKey(const ValueKey('dating_guided_skip'));
  final composer = find.byKey(const ValueKey('dating_chat_composer'));
  final send = find.byKey(const ValueKey('dating_chat_send'));
  final messagesList = find.byKey(const ValueKey('dating_chat_messages'));
  final tip = find.byKey(const ValueKey('dating_guided_tip'));

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

  Future<void> write(WidgetTester t, String text) async {
    await t.enterText(find.byKey(const ValueKey('dating_guided_answer')), text);
    await t.pump();
    await tap(t, find.text(loc.dating_chatSend));
    await t.pumpAndSettle();
  }

  group('I-1: the top area', () {
    const phones = {
      '390x844': (Size(390, 844), 336.0),
      '360x640': (Size(360, 640), 260.0),
    };
    for (final MapEntry(key: phone, value: (size, keyboard))
        in phones.entries) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('$phone at $scale: keyboard down, Answer and Skip reach; '
            'up, the cards step aside; the messages and composer stay '
            'usable', (t) async {
          final fake = FakeDatingChat(page: page(timebox: 'day7'))
            ..guidedState = _saturday;
          await open(t, fake, textScale: scale);
          t.view.physicalSize = size;
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          for (final target in [answerButton, skip]) {
            await bringIntoReach(t, target);
            expect(wouldHit(t, target), isTrue, reason: '$target');
          }
          // A visible scrollbar when the cards need more room than they get.
          final top = find.byKey(const ValueKey('dating_chat_top'));
          final bar = t.widget<Scrollbar>(
            find.descendant(of: top, matching: find.byType(Scrollbar)),
          );
          final scroll =
              t
                  .state<ScrollableState>(
                    find.descendant(of: top, matching: find.byType(Scrollable)),
                  )
                  .position;
          expect(bar.thumbVisibility, scroll.maxScrollExtent > 0);
          expect(t.getSize(messagesList).height, greaterThanOrEqualTo(96));
          expect(composer.hitTestable(), findsOneWidget);
          expect(send.hitTestable(), findsOneWidget);
          // Keyboard up: the cards step aside, the chat keeps its room.
          t.view.viewInsets = FakeViewPadding(bottom: keyboard);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text(loc.dating_guidedTitle), findsNothing);
          expect(find.text(loc.dating_timeboxDay7), findsNothing);
          expect(t.getSize(messagesList).height, greaterThanOrEqualTo(72));
          await t.enterText(composer, 'Hello there');
          await t.pump();
          expect(composer.hitTestable(), findsOneWidget);
          expect(send.hitTestable(), findsOneWidget);
          // Down again: back, never read out again.
          t.view.resetViewInsets();
          await t.pumpAndSettle();
          expect(find.text(loc.dating_guidedTitle), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(
                const ValueKey('dating_top_guided:good_saturday:false'),
              ),
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.liveRegion == true,
              ),
            ),
            findsNothing,
          );
        });
      }
    }
  });

  group('I-2: answers under their question', () {
    testWidgets('a revealed pair is one block captioned with its question, '
        'read with it', (t) async {
      final fake = FakeDatingChat(
          page: page(
            messages: [
              datingMessageJson('t3', 'Nice!', minute: 9),
              answer('g2', 'Church, then jollof', minute: 8),
              answer('g1', 'Market, then football', mine: true, minute: 8),
              datingMessageJson('t1', 'Hi Ama!', minute: 1),
            ],
          ),
        )
        ..guidedState = const DatingGuided(
          questionId: 'food_every_week',
          revealed: 1,
        );
      await open(t, fake);
      final block = find.byKey(
        const ValueKey('dating_guided_pair_good_saturday'),
      );
      expect(block, findsOneWidget);
      for (final text in [
        loc.dating_guided_good_saturday,
        'Church, then jollof',
        'Market, then football',
      ]) {
        expect(
          find.descendant(of: block, matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(
        t.getSemantics(block).label,
        contains(loc.dating_guided_good_saturday),
      );
      // Theirs above this side's.
      expect(
        t.getTopLeft(find.text('Church, then jollof')).dy,
        lessThan(t.getTopLeft(find.text('Market, then football')).dy),
      );
    });

    testWidgets('a waiting answer is captioned too', (t) async {
      final fake = FakeDatingChat(
          page: page(messages: [answer('g1', 'Market', mine: true, minute: 3)]),
        )
        ..guidedState = const DatingGuided(
          questionId: 'good_saturday',
          answered: true,
        );
      await open(t, fake);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dating_guided_pair_good_saturday')),
          matching: find.text('Market'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dating_guided_caption')),
        findsOneWidget,
      );
    });

    testWidgets('M-1: Close kindly\'s bubble is the app\'s words', (t) async {
      final fake = FakeDatingChat(
        page: page(
          messages: [
            {
              ...datingMessageJson('c1', 'SERVER WORDS', minute: 4),
              'kind': 'close_kindly',
            },
          ],
        ),
      );
      await open(t, fake);
      expect(find.text('SERVER WORDS'), findsNothing);
      expect(find.text(loc.dating_closeKindlyMessage), findsOneWidget);
    });
  });

  group('I-3: an answer that lost the race', () {
    for (final reason in ['invalid', 'closed']) {
      testWidgets('$reason: no error line; read again; the words go to the '
          'composer', (t) async {
        final fake =
            FakeDatingChat(page: page())
              ..guidedState = _saturday
              ..refusals['answerGuided'] = reason;
        await open(t, fake);
        final reads = fake.guidedReads;
        await tap(t, answerButton);
        await t.pumpAndSettle();
        await write(t, 'Market, then football');
        expect(fake.answers, hasLength(1));
        expect(find.text(loc.dating_errorGeneric), findsNothing);
        expect(fake.guidedReads, greaterThan(reads));
        expect(
          t.widget<TextField>(composer).controller!.text,
          'Market, then football',
        );
      });
    }

    testWidgets('after what was already in the composer', (t) async {
      final fake =
          FakeDatingChat(page: page())
            ..guidedState = _saturday
            ..refusals['answerGuided'] = 'invalid';
      await open(t, fake);
      await t.enterText(composer, 'Also');
      await tap(t, answerButton);
      await t.pumpAndSettle();
      await write(t, 'Market');
      expect(t.widget<TextField>(composer).controller!.text, 'Also\nMarket');
    });
  });

  group('I-4: the tip, once', () {
    final pair = [
      answer('g2', 'Church', minute: 5),
      answer('g1', 'Market', mine: true, minute: 5),
      datingMessageJson('t1', 'Hi Ama!', mine: true, minute: 3),
    ];

    testWidgets('after the first reveal until this side next writes', (
      t,
    ) async {
      final fake = FakeDatingChat(page: page(messages: pair))
        ..guidedState = const DatingGuided(
          questionId: 'food_every_week',
          revealed: 1,
        );
      await open(t, fake);
      expect(tip, findsOneWidget);
      // Their message after the reveal: still due.
      fake.pageJson = page(
        messages: [datingMessageJson('t2', 'So?', minute: 6), ...pair],
      );
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(tip, findsOneWidget);
      // This side writes: gone, and stays gone.
      await t.enterText(composer, 'Football too!');
      await tap(t, send);
      await t.pumpAndSettle();
      expect(tip, findsNothing);
      fake.pageJson = page(
        messages: [
          datingMessageJson('t3', 'Football too!', mine: true, minute: 7),
          datingMessageJson('t2', 'So?', minute: 6),
          ...pair,
        ],
      );
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(tip, findsNothing);
      // Opened again: not due (this side wrote after the reveal).
      await open(t, fake);
      expect(tip, findsNothing);
    });

    testWidgets('never once the questions are done', (t) async {
      final fake = FakeDatingChat(page: page(messages: pair))
        ..guidedState = const DatingGuided(revealed: 1);
      await open(t, fake);
      expect(find.text(loc.dating_guidedTitle), findsNothing);
      expect(tip, findsNothing);
    });
  });

  testWidgets('We met says one calm line', (t) async {
    final fake = FakeDatingChat(page: page());
    await open(t, fake);
    await tap(t, find.byKey(const ValueKey('dating_chat_safety')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_weMet));
    await t.pumpAndSettle();
    expect(fake.weMets, 1);
    expect(find.text(loc.dating_weMetNoted), findsOneWidget);
    expect(find.text(loc.dating_errorGeneric), findsNothing);
  });

  testWidgets('no name: the waiting line names nobody', (t) async {
    final fake = FakeDatingChat(page: page(name: ''))
      ..guidedState = const DatingGuided(
        questionId: 'good_saturday',
        answered: true,
      );
    await open(t, fake);
    expect(find.text(loc.dating_guidedWaitingNoName), findsOneWidget);
    expect(find.textContaining('this person'), findsNothing);
  });

  testWidgets('M-2: day 21, Close kindly refused: the card stays', (t) async {
    final fake = FakeDatingChat(page: page(timebox: 'day21'))
      ..refusals['closeKindly'] = 'busy';
    await open(t, fake);
    await tap(t, find.byKey(const ValueKey('dating_timebox_close')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_closeKindlySend));
    await t.pumpAndSettle();
    expect(fake.kindCloses, hasLength(1));
    expect(fake.timeboxes, isEmpty);
    expect(find.text(loc.dating_timeboxDay21), findsOneWidget);
    expect(find.text(loc.dating_busy), findsOneWidget);
  });

  group('M-3: a timebox dismissal is kept and sent again', () {
    testWidgets('refused: hidden, sent again on the next good read', (t) async {
      final fake = FakeDatingChat(page: page(timebox: 'day7'))
        ..refusals['dismissTimebox'] = 'failed';
      await open(t, fake);
      await tap(t, find.byKey(const ValueKey('dating_timebox_not_yet')));
      await t.pumpAndSettle();
      expect(fake.timeboxes, ['day7']);
      expect(find.text(loc.dating_timeboxDay7), findsNothing);
      fake.refusals.remove('dismissTimebox');
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(fake.timeboxes, ['day7', 'day7']);
      expect(find.text(loc.dating_timeboxDay7), findsNothing);
      // Confirmed: never sent again.
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(fake.timeboxes, ['day7', 'day7']);
    });

    testWidgets('offline: hidden, nothing sent, the offline line', (t) async {
      final fake = FakeDatingChat(page: page(timebox: 'day7'));
      await open(t, fake, online: false);
      await tap(t, find.byKey(const ValueKey('dating_timebox_not_yet')));
      await t.pumpAndSettle();
      expect(fake.timeboxes, isEmpty);
      expect(find.text(loc.dating_timeboxDay7), findsNothing);
      expect(find.text(loc.dating_offline), findsOneWidget);
    });
  });

  testWidgets('D8 on the screen alone: an account change empties the '
      'answer draft', (t) async {
    final fake =
        FakeDatingChat(page: page())
          ..guidedState = _saturday
          ..refusals['answerGuided'] = 'rate_limited';
    await pumpFlowScreen(
      t,
      () => DatingChatScreen(matchId: 'm1', now: () => datingChatT0),
      overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
    );
    final container = ProviderScope.containerOf(
      t.element(find.byType(MaterialApp)),
    );
    expect(find.text('Kofi, 31'), findsOneWidget);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    await write(t, 'Market, then football');
    expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
    container.read(datingTestAccount.notifier).state = 'esi';
    await t.pumpAndSettle();
    expect(find.text('Kofi, 31'), findsOneWidget);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    expect(
      t
          .widget<TextField>(find.byKey(const ValueKey('dating_guided_answer')))
          .controller!
          .text,
      isEmpty,
    );
  });

  test('M-3: the repository says whether the server confirmed', () async {
    Future<bool> dismiss(Object? answer) => DatingChatRepository(
      DatingRpc.withCall((fn, params) async {
        if (answer is Exception) throw answer;
        return answer;
      }),
      null,
    ).dismissTimebox('m1', 'day7');
    expect(await dismiss({'ok': true}), isTrue);
    expect(await dismiss({'ok': false, 'reason': 'invalid'}), isFalse);
    expect(await dismiss(Exception('socket')), isFalse);
  });
}
