// Spec 2 W6 final client fix wave (final-client-review.md): the chat and
// the conversations list read again when the connection comes back (I-1);
// a masked message flows as one text (I-2); an older page in flight when
// the newest page starts again is dropped (C-2); masked and plain bubbles
// keep one rhythm (C-3); the composer mirrors in RTL (C-4); the dismissal
// sender stops on another account (C-6); the guided card changes once
// after an answer (C-7); Answer outweighs Skip and a new top card slides
// in (C-8); the answer sheet says the answer waits (C-9); the only page
// keeps its back while a sheet is open (M-1); the pending dismissals
// leave with the session (M-3); the top cards' surface (M-6); no second
// Block (M-7); fewer reads (M-8); a guided answer survives a swipe (M-9);
// the server's ended answer after Block (M-10).
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/dating/chat/conversations_screen.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_providers.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
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

/// The fake with a held guided read, a held first dismissal, the guided
/// state the server moves to once an answer lands, and held older pages.
class _Fake extends FakeDatingChat {
  _Fake({super.page});

  Completer<DatingGuided>? guidedHold;
  Completer<bool>? dismissHold;
  Completer<DatingChatPage>? olderHold;
  Completer<bool>? timeboxHold;
  DatingGuided? afterAnswer;

  @override
  Future<bool> dismissTimebox(String matchId, String card) async {
    final h = timeboxHold;
    if (h == null) return super.dismissTimebox(matchId, card);
    timeboxHold = null;
    timeboxes.add(card);
    return h.future;
  }

  @override
  Future<DatingGuided> guided(String matchId) async {
    final h = guidedHold;
    if (h == null) return super.guided(matchId);
    guidedReads++;
    return h.future;
  }

  @override
  Future<bool> dismissCard(String id) async {
    final h = dismissHold;
    if (h == null) return super.dismissCard(id);
    dismissHold = null;
    dismissed.add(id);
    return h.future;
  }

  @override
  Future<DatingSendAnswer> answerGuided(
    String key,
    String matchId,
    String questionId,
    String text,
  ) async {
    final r = await super.answerGuided(key, matchId, questionId, text);
    final next = afterAnswer;
    if (r.ok && next != null) guidedState = next;
    return r;
  }

  @override
  Future<DatingChatPage> messages(String matchId, {DateTime? before}) {
    final h = olderHold;
    if (before != null && h != null) {
      reads.add((matchId, before));
      return h.future;
    }
    return super.messages(matchId, before: before);
  }
}

Map<String, Object?> _page({
  List<Map<String, Object?>>? messages,
  String? timebox,
  bool more = false,
}) {
  final p = datingPageJson(messages: messages, more: more);
  final chat = Map<String, Object?>.from(p['chat']! as Map);
  chat['timebox'] = timebox;
  return {...p, 'chat': chat};
}

const _saturday = DatingGuided(questionId: 'good_saturday');

void main() {
  final loc = AppLocalizationsEn();
  final composer = find.byKey(const ValueKey('dating_chat_composer'));
  final shield = find.byKey(const ValueKey('dating_chat_safety'));
  final rootBack = find.byKey(const ValueKey('dating_root_back'));
  final answerButton = find.byKey(
    const ValueKey('dating_guided_answer_button'),
  );
  final skip = find.byKey(const ValueKey('dating_guided_skip'));
  final answerField = find.byKey(const ValueKey('dating_guided_answer'));

  /// The connection, as the test turns it off and on.
  late StreamController<bool> network;

  setUp(() => network = StreamController<bool>.broadcast());
  tearDown(() => network.close());

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingChat fake, {
    String initial = '/dating/chat/m1',
    double textScale = 1.0,
    bool reduceMotion = false,
  }) async {
    final s = await pumpDatingShell(
      t,
      initial: initial,
      textScale: textScale,
      overrides: [
        ...datingChatOverrides(fake),
        datingOnlineProvider.overrideWith((ref) async* {
          yield true;
          yield* network.stream;
        }),
      ],
    );
    if (reduceMotion) {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await t.pumpAndSettle();
    }
    return s;
  }

  Future<void> goOffline(WidgetTester t) async {
    network.add(false);
    await t.pumpAndSettle();
  }

  Future<void> goOnline(WidgetTester t) async {
    network.add(true);
    await t.pumpAndSettle();
  }

  group('I-1: the connection comes back', () {
    testWidgets('the open chat reads again: a message written during the '
        'gap shows with no signal', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      expect(find.text('Hi Ama!'), findsOneWidget);
      await goOffline(t);
      fake.pageJson = _page(
        messages: [
          datingMessageJson('d3', 'Still there?', minute: 3),
          datingMessageJson('d2', 'Call me on •••', minute: 2),
          datingMessageJson('d1', 'Hi Ama!', mine: true, minute: 1),
        ],
      );
      final before = fake.reads.length;
      await goOnline(t);
      expect(fake.reads.length, before + 1);
      expect(find.text('Still there?'), findsOneWidget);
    });

    testWidgets('the open list reads again', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake, initial: DatingPaths.chats);
      expect(find.text('Kofi, 31'), findsOneWidget);
      await goOffline(t);
      fake.listJson = datingConversationsJson(
        rows: [
          {
            'match_id': 'm3',
            'display_name': 'Esi',
            'age': 29,
            'last': datingMessageJson('e1', 'Hello', minute: 4),
            'new': true,
          },
        ],
      );
      final before = fake.listReads;
      await goOnline(t);
      expect(fake.listReads, before + 1);
      expect(find.text('Esi, 29'), findsOneWidget);
    });

    testWidgets('the first value is not a return (no extra read)', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      expect(fake.reads.length, 1);
    });
  });

  group('I-2: a masked message flows as one text', () {
    const long =
        'You can reach me on 0244 123 456 after six, or try me@mail.com if '
        'that fails, any evening this week works for me';

    testWidgets('each hidden span sits inside the message\'s one text', (
      t,
    ) async {
      await open(
        t,
        FakeDatingChat(page: _page(messages: [datingMessageJson('d9', long)])),
      );
      final first = find.byKey(const ValueKey('dating_chat_masked'));
      final second = find.byKey(const ValueKey('dating_chat_masked_2'));
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      final text = find.ancestor(of: first, matching: find.byType(Text));
      expect(text, findsOneWidget);
      expect(
        find.ancestor(of: second, matching: find.byType(Text)),
        findsOneWidget,
      );
      final rich = t.widget<Text>(text).textSpan!.toPlainText();
      expect(rich, startsWith('You can reach me on '));
      expect(rich, endsWith('works for me'));
      // Flowing text: the dots follow "on" on its line, never a run of
      // their own at the bubble's start.
      final bubble = t.getRect(
        find.byKey(const ValueKey('dating_chat_bubble_d9')),
      );
      expect(t.getRect(first).left, greaterThan(bubble.left + Spacing.md + 1));
      expect(t.getRect(first).center.dy, lessThan(t.getRect(second).center.dy));
    });
  });

  group('C-2: an older page in flight when the newest starts again', () {
    List<Map<String, Object?>> history(int from, int to) => [
      for (var i = to; i >= from; i--)
        datingMessageJson('h$i', 'Note $i', minute: i),
    ];

    testWidgets('is dropped: no gap, and earlier messages still load', (
      t,
    ) async {
      final fake = _Fake(page: _page(messages: history(4, 6), more: true));
      await open(t, fake);
      expect(find.text('Note 6'), findsOneWidget);
      fake.olderHold = Completer<DatingChatPage>();
      await tap(t, find.text(loc.dating_chatLoadOlder));
      // More arrived than a page holds: the newest page starts again.
      fake.pageJson = _page(messages: history(10, 12), more: true);
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(find.text('Note 12'), findsOneWidget);
      fake.olderHold!.complete(
        DatingChatPage.fromJson(_page(messages: history(1, 3))),
      );
      await t.pumpAndSettle();
      for (final i in [1, 2, 3]) {
        expect(find.text('Note $i'), findsNothing, reason: 'Note $i');
      }
      expect(find.text(loc.dating_chatLoadOlder), findsOneWidget);
    });
  });

  testWidgets('C-3: masked and plain bubbles keep one rhythm', (t) async {
    await open(
      t,
      FakeDatingChat(
        page: _page(
          messages: [
            datingMessageJson('d4', 'Four', minute: 4),
            datingMessageJson('d3', 'Three', minute: 3),
            datingMessageJson('d2', 'Call me on •••', minute: 2),
            datingMessageJson('d1', 'One', minute: 1),
          ],
        ),
      ),
    );
    Rect face(String id) {
      final bubble = find.byKey(ValueKey('dating_chat_bubble_$id'));
      // The painted bubble: a plain one's box inside its margin, a masked
      // one's ink.
      final surface = find.descendant(
        of: bubble,
        matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox || (w is Ink && w.decoration != null),
        ),
      );
      return t.getRect(surface.first);
    }

    final one = face('d1');
    final masked = face('d2');
    final three = face('d3');
    final four = face('d4');
    expect(masked.height, one.height);
    final gaps = [
      masked.top - one.bottom,
      three.top - masked.bottom,
      four.top - three.bottom,
    ];
    expect(gaps.toSet(), hasLength(1), reason: '$gaps');
    // The tap still covers at least 48.
    expect(
      t.getSize(find.byKey(const ValueKey('dating_chat_bubble_d2'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('C-4: the composer mirrors in RTL', (t) async {
    await open(t, FakeDatingChat());
    final width = t.getSize(find.byType(DatingChatScreen)).width;
    final ltr = t.getRect(composer);
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      wrap:
          (router, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child),
    );
    final rtl = t.getRect(composer);
    expect(width - rtl.right, closeTo(ltr.left, 0.01));
  });

  group('C-6: the dismissal sender on another account', () {
    testWidgets('stops; the first account keeps its ids; the next account\'s '
        'sender is not blocked', (t) async {
      final fake = _Fake();
      final s = await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      final ama = s.container.read(datingPendingCardDismissalsProvider('ama'));
      final esi = s.container.read(datingPendingCardDismissalsProvider('esi'));
      ama.addAll(['e1', 'e2', 'e3']);
      esi.add('x1');
      final hold = fake.dismissHold = Completer<bool>();
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(fake.dismissed, hasLength(1));
      final first = fake.dismissed.single;
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      expect(fake.dismissed, [first, 'x1']);
      hold.complete(true);
      await t.pumpAndSettle();
      // Sent as ama before the switch: confirmed for ama; the rest wait.
      expect(fake.dismissed, [first, 'x1']);
      expect(ama, {'e1', 'e2', 'e3'}..remove(first));
      expect(esi, isEmpty);
    });

    testWidgets('the chat alone (no lock gate rebuilding it): the next '
        'account\'s senders never wait on the last one\'s', (t) async {
      final fake = _Fake(page: _page(timebox: 'day7'));
      await pumpFlowScreen(
        t,
        () => DatingChatScreen(matchId: 'm1', now: () => datingChatT0),
        overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
      );
      expect(find.text('Kofi, 31'), findsOneWidget);
      final container = ProviderScope.containerOf(
        t.element(find.byType(MaterialApp)),
      );
      final amaCards = container.read(
        datingPendingCardDismissalsProvider('ama'),
      )..addAll(['e1', 'e2']);
      final amaBoxes = container.read(
        datingPendingTimeboxDismissalsProvider('ama'),
      )..addAll(['m1|day7', 'm1|day21']);
      container.read(datingPendingCardDismissalsProvider('esi')).add('x1');
      container
          .read(datingPendingTimeboxDismissalsProvider('esi'))
          .add('m1|day7');
      final cardHold = fake.dismissHold = Completer<bool>();
      final boxHold = fake.timeboxHold = Completer<bool>();
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(fake.dismissed, hasLength(1));
      expect(fake.timeboxes, hasLength(1));
      container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      expect(find.byType(DatingChatScreen), findsOneWidget);
      expect(fake.dismissed.last, 'x1');
      expect(fake.timeboxes, hasLength(2));
      cardHold.complete(true);
      boxHold.complete(true);
      await t.pumpAndSettle();
      expect(fake.dismissed, hasLength(2));
      expect(fake.timeboxes, hasLength(2));
      expect(amaCards, hasLength(1));
      expect(amaBoxes, hasLength(1));
    });

    testWidgets('stops once the chat has closed (another account signs in '
        'after)', (t) async {
      final fake = _Fake();
      final s = await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      final ama = s.container.read(datingPendingCardDismissalsProvider('ama'));
      ama.addAll(['e1', 'e2']);
      final hold = fake.dismissHold = Completer<bool>();
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(fake.dismissed, hasLength(1));
      s.router.go(DatingPaths.settings);
      await t.pumpAndSettle();
      expect(find.byType(DatingChatScreen), findsNothing);
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      hold.complete(true);
      await t.pumpAndSettle();
      expect(fake.dismissed, hasLength(1));
      expect(ama, hasLength(1));
    });

    testWidgets('the timebox sender too: one per account, stopped on a '
        'switch', (t) async {
      final fake = _Fake(page: _page(timebox: 'day7'));
      final s = await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      final ama = s.container.read(
        datingPendingTimeboxDismissalsProvider('ama'),
      );
      final esi = s.container.read(
        datingPendingTimeboxDismissalsProvider('esi'),
      );
      ama.addAll(['m1|day7', 'm1|day21']);
      esi.add('m1|day7');
      final hold = fake.timeboxHold = Completer<bool>();
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(fake.timeboxes, hasLength(1));
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      expect(fake.timeboxes, hasLength(2), reason: 'esi\'s is not blocked');
      expect(esi, isEmpty);
      hold.complete(true);
      await t.pumpAndSettle();
      expect(fake.timeboxes, hasLength(2));
      expect(ama, hasLength(1));
    });
  });

  group('C-7: after an answer the card changes once', () {
    Future<void> answer(WidgetTester t, String text) async {
      await tap(t, answerButton);
      await t.pumpAndSettle();
      await t.enterText(answerField, text);
      await t.pump();
      await tap(t, find.text(loc.dating_chatSend));
    }

    testWidgets('the other had answered: no waiting line, the buttons wait '
        'for the read, then the next question', (t) async {
      final fake =
          _Fake(page: _page())
            ..guidedState = _saturday
            ..afterAnswer = const DatingGuided(
              questionId: 'food_every_week',
              revealed: 1,
            );
      await open(t, fake);
      final hold = fake.guidedHold = Completer<DatingGuided>();
      await answer(t, 'Market');
      await t.pumpAndSettle();
      expect(fake.answers, hasLength(1));
      expect(find.text(loc.dating_guidedWaiting('Kofi')), findsNothing);
      expect(
        t.widget<ButtonStyleButton>(answerButton).onPressed,
        isNull,
        reason: 'disabled until the read lands',
      );
      fake.guidedHold = null;
      hold.complete(fake.guidedState);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_guided_food_every_week), findsOneWidget);
      expect(find.text(loc.dating_guidedWaiting('Kofi')), findsNothing);
      expect(t.widget<ButtonStyleButton>(answerButton).onPressed, isNotNull);
    });

    testWidgets('the read fails: the waiting line (this side answered)', (
      t,
    ) async {
      final fake = _Fake(page: _page())..guidedState = _saturday;
      await open(t, fake);
      fake.refusals['guided'] = 'busy';
      await answer(t, 'Market');
      await t.pumpAndSettle();
      expect(find.text(loc.dating_guidedWaiting('Kofi')), findsOneWidget);
      expect(answerButton, findsNothing);
    });
  });

  group('C-8: Answer and the top cards', () {
    testWidgets('Answer is tonal, Skip plain, both 48 high', (t) async {
      await open(t, FakeDatingChat(page: _page())..guidedState = _saturday);
      expect(t.widget(answerButton), isA<FilledButton>());
      expect(t.widget(skip), isA<TextButton>());
      expect(t.getSize(answerButton).height, greaterThanOrEqualTo(48));
      expect(t.getSize(answerButton).width, greaterThanOrEqualTo(48));
    });

    double slide(WidgetTester t, String id) =>
        t
            .widget<SizeTransition>(
              find.descendant(
                of: find.byKey(ValueKey('dating_top_$id')),
                matching: find.byType(SizeTransition),
              ),
            )
            .sizeFactor
            .value;

    testWidgets('a card new to the open chat slides in at 150 ms; one there '
        'when it opens does not', (t) async {
      final fake = FakeDatingChat(page: _page(timebox: 'day7'));
      await open(t, fake, initial: DatingPaths.chats);
      // The chat's first read lands with the card already there.
      final first = fake.hold = Completer<DatingChatPage>();
      await tap(t, find.byKey(const ValueKey('dating_chats_row_m1')));
      fake.hold = null;
      first.complete(DatingChatPage.fromJson(_page(timebox: 'day7')));
      await t.pump();
      await t.pump();
      expect(slide(t, 'timebox:day7'), 1);
      await t.pumpAndSettle();
      fake.pageJson = _page(timebox: 'day21');
      fake.signalEvents.add(null);
      await t.pump();
      await t.pump();
      expect(slide(t, 'timebox:day21'), lessThan(1));
      await t.pump(const Duration(milliseconds: 160));
      expect(slide(t, 'timebox:day21'), 1);
    });

    testWidgets('under reduce motion nothing slides', (t) async {
      final fake = FakeDatingChat(page: _page());
      await open(t, fake, reduceMotion: true);
      fake.pageJson = _page(timebox: 'day21');
      fake.signalEvents.add(null);
      await t.pump();
      await t.pump();
      expect(slide(t, 'timebox:day21'), 1);
    });
  });

  testWidgets('C-9: the answer sheet says the answer waits, with its own '
      'hint', (t) async {
    await open(t, FakeDatingChat(page: _page())..guidedState = _saturday);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_guidedWaitingNoName), findsOneWidget);
    expect(
      t.widget<TextField>(answerField).decoration?.hintText,
      loc.dating_guidedAnswerHint,
    );
  });

  testWidgets('M-1: the only page keeps its back while a sheet is open', (
    t,
  ) async {
    final fake = FakeDatingChat();
    final s = await open(t, fake);
    expect(s.router.canPop(), isFalse);
    expect(rootBack, findsOneWidget);
    await tap(t, shield);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_chatSafety), findsOneWidget);
    // The chat rebuilds under the sheet (a signal's read).
    fake.signalEvents.add(null);
    await t.pumpAndSettle();
    expect(fake.reads.length, greaterThan(1));
    expect(rootBack, findsOneWidget, reason: 'still there under the sheet');
    // Dismissed choosing nothing.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_chatSafety), findsNothing);
    expect(rootBack, findsOneWidget);
    await tap(t, rootBack);
    await t.pumpAndSettle();
    expect(s.location, DatingPaths.chats);
  });

  testWidgets('M-3: quick exit and sign-out empty the pending dismissals', (
    t,
  ) async {
    final s = await open(t, FakeDatingChat());
    expect(find.text('Kofi, 31'), findsOneWidget);
    final cards = s.container.read(datingPendingCardDismissalsProvider('ama'))
      ..add('e1');
    final boxes = s.container.read(
      datingPendingTimeboxDismissalsProvider('ama'),
    )..add('m1|day7');
    for (final moment in [WipeMoment.quickExit, WipeMoment.signOut]) {
      cards.add('e1');
      boxes.add('m1|day7');
      final registry = DeviceWipeRegistry();
      registerDatingDeviceWipes(registry);
      await registry.run(moment);
      expect(cards, isEmpty, reason: '$moment');
      expect(boxes, isEmpty, reason: '$moment');
    }
  });

  testWidgets('M-6: the top cards: the safety card\'s surface and hairline, '
      'not a bubble\'s fill', (t) async {
    await open(t, FakeDatingChat(page: _page())..guidedState = _saturday);
    final card = t.widget<Container>(
      find.byKey(const ValueKey('dating_guided')),
    );
    final box = card.decoration! as BoxDecoration;
    final scheme = Theme.of(t.element(answerButton)).colorScheme;
    expect(box.color, scheme.surfaceContainerHigh);
    expect(box.border, Border.all(color: scheme.outlineVariant));
    expect(box.borderRadius, BorderRadiusTokens.mdAll);
  });

  group('M-7, M-10: after Block', () {
    testWidgets('the server answers ended: the blocked line, no composer, '
        'no Block or Unmatch in the sheet', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      await tap(t, shield);
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_blockRow('Kofi')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_cardBlock));
      await t.pumpAndSettle();
      expect(fake.blocks, hasLength(1));
      // The fake answers as the server: the re-read is ended.
      expect(fake.reads.length, greaterThan(1));
      expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
      expect(find.text(loc.dating_chatEnded), findsNothing);
      expect(composer, findsNothing);
      await tap(t, shield);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_chatSafetyResources), findsOneWidget);
      expect(find.text(loc.dating_blockRow('Kofi')), findsNothing);
      expect(find.text(loc.dating_chatSafetyUnmatch), findsNothing);
    });
  });

  group('M-8: fewer reads', () {
    testWidgets('a covered list waits for the way back', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake, initial: DatingPaths.chats);
      await tap(t, find.byKey(const ValueKey('dating_chats_row_m1')));
      await t.pumpAndSettle();
      expect(find.byType(DatingChatScreen), findsOneWidget);
      final before = fake.listReads;
      fake.signalsFor('ama').add(null);
      await t.pumpAndSettle();
      expect(fake.listReads, before);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(DatingConversationsScreen), findsOneWidget);
      expect(fake.listReads, before + 1);
      // Shown again, a signal reads it.
      fake.signalsFor('ama').add(null);
      await t.pumpAndSettle();
      expect(fake.listReads, before + 2);
    });

    testWidgets('the guided state is read only while a question is open', (
      t,
    ) async {
      final done = FakeDatingChat(page: _page());
      await open(t, done);
      expect(done.guidedReads, 1);
      done.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(done.guidedReads, 1, reason: 'the questions are done');

      final open1 = FakeDatingChat(page: _page())..guidedState = _saturday;
      await open(t, open1);
      open1.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(open1.guidedReads, 2);

      // A failed first read is read again.
      final failed = FakeDatingChat(page: _page())..refusals['guided'] = 'busy';
      await open(t, failed);
      failed.refusals.remove('guided');
      failed.guidedState = _saturday;
      failed.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(failed.guidedReads, 2);
      expect(find.text(loc.dating_guided_good_saturday), findsOneWidget);
    });
  });

  testWidgets('M-9: an answer typed in the sheet survives a swipe down', (
    t,
  ) async {
    final fake = FakeDatingChat(page: _page())..guidedState = _saturday;
    await open(t, fake);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    await t.enterText(answerField, 'Market on Saturdays');
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(answerField, findsNothing);
    expect(fake.answers, isEmpty);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(answerField).controller!.text,
      'Market on Saturdays',
    );
  });

  testWidgets('M-9, D8, the chat alone (no lock gate rebuilding it): what '
      'was typed never reaches the next account', (t) async {
    final fake = FakeDatingChat(page: _page())..guidedState = _saturday;
    await pumpFlowScreen(
      t,
      () => DatingChatScreen(matchId: 'm1', now: () => datingChatT0),
      overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
    );
    expect(find.text('Kofi, 31'), findsOneWidget);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    await t.enterText(answerField, 'Market on Saturdays');
    await t.pump();
    final container = ProviderScope.containerOf(
      t.element(find.byType(MaterialApp)),
    );
    container.read(datingTestAccount.notifier).state = 'esi';
    await t.pumpAndSettle();
    expect(find.byType(DatingChatScreen), findsOneWidget);
    expect(answerField, findsNothing);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    expect(t.widget<TextField>(answerField).controller!.text, isEmpty);
  });

  testWidgets('M-9, D8: what was typed never reaches the next account', (
    t,
  ) async {
    final fake = FakeDatingChat(page: _page())..guidedState = _saturday;
    final s = await open(t, fake);
    expect(find.text('Kofi, 31'), findsOneWidget);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    await t.enterText(answerField, 'Market on Saturdays');
    await t.pump();
    s.container.read(datingTestAccount.notifier).state = 'esi';
    await t.pumpAndSettle();
    expect(answerField, findsNothing);
    expect(find.text('Kofi, 31'), findsOneWidget);
    await tap(t, answerButton);
    await t.pumpAndSettle();
    expect(t.widget<TextField>(answerField).controller!.text, isEmpty);
  });

  group('goldens (I-2, M-10)', () {
    final at = datingChatT0.add(const Duration(minutes: 30));
    Widget chat() => DatingChatScreen(matchId: 'm1', now: () => at);

    testWidgets('I-2: a long message with two hidden spans', (t) async {
      final fake = FakeDatingChat(
        page: _page(
          messages: [
            datingMessageJson(
              'd3',
              'You can reach me on 0244 123 456 after six, or try '
                  'me@mail.com if that fails, any evening works',
              minute: 3,
            ),
            datingMessageJson('d1', 'Hi Kofi!', mine: true, minute: 1),
          ],
        ),
      );
      await expectFlowGoldens(
        t,
        'dating_chat_masked_long',
        chat,
        overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
      );
    });

    for (final (name, screen) in [
      ('dating_chat', chat),
      ('dating_chats', () => const DatingConversationsScreen()),
    ]) {
      testWidgets('M-10: $name in dark', (t) async {
        await pumpFlowScreen(
          t,
          () => Theme(data: AppTheme.darkTheme, child: screen()),
          overrides: [
            ...datingShellOverrides(),
            ...datingChatOverrides(FakeDatingChat()),
          ],
        );
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$name.dark.png'),
        );
      });
    }

    testWidgets('M-10: an ended chat', (t) async {
      await pumpFlowScreen(
        t,
        chat,
        overrides: [
          ...datingShellOverrides(),
          ...datingChatOverrides(
            FakeDatingChat(page: datingPageJson(ended: true)),
          ),
        ],
      );
      expect(find.text(loc.dating_chatEnded), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/dating_chat_ended.scale1.0.png'),
      );
      await expectFlowGuidelines(t);
    });

    testWidgets('M-10: a chat just blocked', (t) async {
      final fake = FakeDatingChat();
      await pumpFlowScreen(
        t,
        chat,
        overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
      );
      await tap(t, shield);
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_blockRow('Kofi')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_cardBlock));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/dating_chat_blocked.scale1.0.png'),
      );
      await expectFlowGuidelines(t);
    });
  });
}
