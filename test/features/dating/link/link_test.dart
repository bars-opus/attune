// Spec 2 W9 (§3.6, §3.9 steps 1-4, §3.14, §3.15, §7.4; carry 6; D8):
// "Become a couple on Attune" in the chat and on /dating/link/:matchId.
import 'dart:async';

import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/link/link_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_link_fakes.dart';
import '../support/dating_shell.dart';

const _busyLine =
    'This is taking a little longer than usual. Try again in a moment.';

const _asked = DatingLinkPage(
  ok: true,
  displayName: 'Kofi',
  link: DatingLink(state: DatingLinkState.askedYou, requestId: 'r9'),
);

/// The chat's page with [link] in its header (and either side's We met).
FakeDatingChat _chat(
  Map<String, Object?>? link, {
  bool theyMet = true,
  bool ended = false,
}) {
  final page = datingPageJson(ended: ended);
  final chat = page['chat']! as Map<String, Object?>;
  chat['we_met'] = {'mine': false, 'theirs': theyMet};
  chat['link'] = link;
  return FakeDatingChat(page: page);
}

Future<DatingShell> _link(
  WidgetTester t,
  FakeDatingLink fake, {
  bool online = true,
}) => pumpDatingShell(
  t,
  initial: '/dating/link/m1',
  online: online,
  overrides: datingLinkOverrides(fake),
);

Future<DatingShell> _inChat(
  WidgetTester t,
  FakeDatingChat chat,
  FakeDatingLink fake,
) => pumpDatingShell(
  t,
  initial: '/dating/chat/m1',
  overrides: [...datingChatOverrides(chat), ...datingLinkOverrides(fake)],
);

void main() {
  group('the Safety sheet (§3.6; carry 6)', () {
    for (final (what, link, theyMet, offered) in [
      (
        'the other side said We met, nothing asked',
        <String, Object?>{'state': 'none'},
        true,
        true,
      ),
      ('nobody said We met', null, false, false),
      (
        'already asked',
        <String, Object?>{'state': 'asked', 'request_id': 'r1'},
        true,
        false,
      ),
    ]) {
      testWidgets('Become a couple on Attune: $what', (t) async {
        await _inChat(t, _chat(link, theyMet: theyMet), FakeDatingLink());
        await tapInReach(
          t,
          find.bySemanticsLabel('Safety options for this conversation'),
        );
        await t.pumpAndSettle();
        expect(
          find.text('Become a couple on Attune'),
          offered ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('its row opens the link page for this chat', (t) async {
      final fake = FakeDatingLink();
      await _inChat(t, _chat({'state': 'none'}), fake);
      await tapInReach(
        t,
        find.bySemanticsLabel('Safety options for this conversation'),
      );
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Become a couple on Attune'));
      await t.pumpAndSettle();
      expect(find.byType(DatingLinkScreen), findsOneWidget);
      expect(fake.pages, ['m1']);
      expect(find.text('What are we agreeing to?'), findsOneWidget);
    });
  });

  group('asking (step 1)', () {
    testWidgets('the private step is read in full, then Ask {Name} sends this '
        'side\'s Yes with its keep choice, once', (t) async {
      final fake = FakeDatingLink();
      fake.hold = Completer<void>();
      await _link(t, fake);
      expect(find.text('What are we agreeing to?'), findsOneWidget);
      expect(
        find.text(
          "Your Dating profiles pause for both of you. You'll share a private space for the two of you. "
          'Either of you can end it at any time.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "Keep our first messages as a 'How we met' card (only if Kofi agrees too)",
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_link_keep')));
      await t.pump();
      await tapInReach(t, find.text('Ask Kofi'));
      await tapInReach(t, find.text('Ask Kofi'));
      await t.pump();
      expect(fake.asks, hasLength(1));
      expect(fake.asks.single.$2, 'm1');
      expect(fake.asks.single.$3, isTrue);
      fake.pageAnswer = const DatingLinkPage(
        ok: true,
        displayName: 'Kofi',
        link: DatingLink(state: DatingLinkState.asked, requestId: 'r1'),
      );
      fake.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text("You've asked Kofi."), findsOneWidget);
      expect(find.text('Take it back'), findsOneWidget);
    });

    testWidgets('Not now asks nothing and goes back to the chat', (t) async {
      final fake = FakeDatingLink();
      final s = await _link(t, fake);
      await tapInReach(t, find.text('Not now'));
      await t.pumpAndSettle();
      expect(fake.asks, isEmpty);
      expect(s.location, '/dating/chat/m1');
    });

    testWidgets('Take it back withdraws the request', (t) async {
      final fake = FakeDatingLink(
        pageAnswer: const DatingLinkPage(
          ok: true,
          displayName: 'Kofi',
          link: DatingLink(state: DatingLinkState.asked, requestId: 'r1'),
        ),
      );
      await _link(t, fake);
      await tapInReach(t, find.text('Take it back'));
      await t.pumpAndSettle();
      expect(fake.cancels, ['r1']);
    });
  });

  testWidgets('taking it back as the couple links reads the link again: '
      '"You decided together."', (t) async {
    final fake = FakeDatingLink(
      pageAnswer: const DatingLinkPage(
        ok: true,
        displayName: 'Kofi',
        link: DatingLink(state: DatingLinkState.asked, requestId: 'r1'),
      ),
    );
    fake.answer = const DatingLinkAnswer(ok: false, reason: 'linked');
    final s = await _link(t, fake);
    fake.pageAnswer = const DatingLinkPage(
      ok: true,
      displayName: 'Kofi',
      link: DatingLink(state: DatingLinkState.linked, moment: true),
    );
    await tapInReach(t, find.text('Take it back'));
    await t.pumpAndSettle();
    expect(fake.cancels, ['r1']);
    expect(find.text('You decided together.'), findsOneWidget);
    expect(s.location, '/dating/link/m1');
  });

  group('the other side (steps 2-4)', () {
    testWidgets(
      'Yes, let\'s sends the second Yes with this side\'s own choice; '
      '"You decided together." settles once, then the Relationship home',
      (t) async {
        final fake = FakeDatingLink(pageAnswer: _asked);
        fake.answer = const DatingLinkAnswer(ok: true, relationshipId: 'rel-1');
        final s = await _link(t, fake);
        expect(
          find.text('Kofi would like to become a couple on Attune.'),
          findsOneWidget,
        );
        await tapInReach(t, find.text("Yes, let's"));
        await t.pump();
        expect(fake.confirms.single.$2, 'r9');
        expect(fake.confirms.single.$3, isFalse);
        expect(find.text('You decided together.'), findsOneWidget);
        // One settle, at most 600 ms: half-way in, then still.
        double opacity() =>
            t
                .widget<Opacity>(
                  find
                      .ancestor(
                        of: find.text('You decided together.'),
                        matching: find.byType(Opacity),
                      )
                      .first,
                )
                .opacity;
        await t.pump(const Duration(milliseconds: 300));
        expect(opacity(), lessThan(1));
        await t.pump(const Duration(milliseconds: 300));
        expect(opacity(), 1);
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(s.location, startsWith('/home?tab=chat'));
      },
    );

    testWidgets('Not right now declines and goes back to the chat', (t) async {
      final fake = FakeDatingLink(pageAnswer: _asked);
      final s = await _link(t, fake);
      await tapInReach(t, find.text('Not right now'));
      await t.pumpAndSettle();
      expect(fake.declines, ['r9']);
      expect(fake.confirms, isEmpty);
      expect(s.location, '/dating/chat/m1');
    });

    testWidgets('offline the second Yes waits: "You\'re offline. Nothing has '
        'changed yet."', (t) async {
      final fake = FakeDatingLink(pageAnswer: _asked);
      await _link(t, fake, online: false);
      expect(
        find.text("You're offline. Nothing has changed yet."),
        findsOneWidget,
      );
      await tapInReach(t, find.text("Yes, let's"));
      await t.pump();
      expect(fake.confirms, isEmpty);
    });

    testWidgets('a refusal is a calm line and nothing moves', (t) async {
      final fake = FakeDatingLink(pageAnswer: _asked);
      fake.answer = const DatingLinkAnswer(ok: false, reason: 'unavailable');
      final s = await _link(t, fake);
      await tapInReach(t, find.text("Yes, let's"));
      await t.pumpAndSettle();
      expect(find.text("This isn't possible right now."), findsOneWidget);
      expect(find.text('You decided together.'), findsNothing);
      expect(s.location, '/dating/link/m1');
    });

    // Task 1's carry: the second Yes is idempotent by the request's state,
    // so busy (or a lost answer) after a sent Yes may hide a link that
    // landed: the page reads the link again, never calls it a failure.
    for (final answer in [DatingLinkAnswer.busy, DatingLinkAnswer.failed]) {
      testWidgets('${answer.reason} after a sent Yes reads the link again: a '
          'link that landed shows "You decided together."', (t) async {
        final fake = FakeDatingLink(pageAnswer: _asked);
        fake.answer = answer;
        await _link(t, fake);
        expect(fake.pages, ['m1']);
        fake.pageAnswer = const DatingLinkPage(
          ok: true,
          displayName: 'Kofi',
          link: DatingLink(state: DatingLinkState.linked),
        );
        await tapInReach(t, find.text("Yes, let's"));
        await t.pumpAndSettle();
        expect(fake.confirms, hasLength(1));
        expect(fake.pages, ['m1', 'm1']);
        expect(find.text('You decided together.'), findsOneWidget);
        expect(find.text(_busyLine), findsNothing);
        expect(find.text('Something went wrong. Try again.'), findsNothing);
      });
    }

    testWidgets('busy, and the re-read can\'t answer either: the calm line, '
        'and "Yes, let\'s" stays to try again', (t) async {
      final fake = FakeDatingLink(pageAnswer: _asked);
      fake.answer = DatingLinkAnswer.busy;
      await _link(t, fake);
      fake.pageAnswer = DatingLinkPage.busy;
      await tapInReach(t, find.text("Yes, let's"));
      await t.pumpAndSettle();
      expect(fake.pages, hasLength(2));
      expect(find.text(_busyLine), findsOneWidget);
      expect(find.text('You decided together.'), findsNothing);
      await tapInReach(t, find.text("Yes, let's"));
      await t.pumpAndSettle();
      expect(fake.confirms, hasLength(2));
    });

    testWidgets('the asker who wasn\'t there sees the moment once, and it is '
        'marked seen', (t) async {
      final fake = FakeDatingLink(
        pageAnswer: const DatingLinkPage(
          ok: true,
          displayName: 'Kofi',
          link: DatingLink(state: DatingLinkState.linked, moment: true),
        ),
      );
      final s = await _link(t, fake);
      expect(find.text('You decided together.'), findsOneWidget);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(fake.dismissals, [DatingPostLinkOffer.linked]);
      expect(s.location, startsWith('/home?tab=chat'));
    });
  });

  group('the chat\'s card (§3.9 step 2)', () {
    testWidgets('the other side\'s request, with See what this means', (
      t,
    ) async {
      final fake = FakeDatingLink(pageAnswer: _asked);
      await _inChat(t, _chat({'state': 'asked_you', 'request_id': 'r9'}), fake);
      expect(
        find.text('Kofi would like to become a couple on Attune.'),
        findsOneWidget,
      );
      await tapInReach(t, find.text('See what this means'));
      await t.pumpAndSettle();
      expect(find.byType(DatingLinkScreen), findsOneWidget);
      expect(find.text("Yes, let's"), findsOneWidget);
    });

    testWidgets(
      "Not right now's answer to the asker: {Name} isn't ready yet.",
      (t) async {
        await _inChat(t, _chat({'state': 'not_ready'}), FakeDatingLink());
        expect(find.text("Kofi isn't ready yet."), findsOneWidget);
      },
    );

    testWidgets('taking back a request that moved on says nothing; the '
        'chat reads again', (t) async {
      final chat = _chat({'state': 'asked', 'request_id': 'r1'});
      final fake = FakeDatingLink();
      fake.answer = const DatingLinkAnswer(
        ok: false,
        reason: 'request_unavailable',
      );
      await _inChat(t, chat, fake);
      final before = chat.reads.length;
      await tapInReach(t, find.text('Take it back'));
      await t.pumpAndSettle();
      expect(fake.cancels, ['r1']);
      expect(find.text('Something went wrong. Try again.'), findsNothing);
      expect(chat.reads.length, greaterThan(before));
    });

    // R-W9-3: a linked chat has ended (closed): the moment is shown in the
    // ended line's place, once.
    for (final moment in [true, false]) {
      testWidgets('the chat the link ended, moment $moment', (t) async {
        final fake = FakeDatingLink();
        final s = await _inChat(
          t,
          _chat({'state': 'linked', 'moment': moment}, ended: true),
          fake,
        );
        expect(
          find.text('You decided together.'),
          moment ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('This conversation has ended.'),
          moment ? findsNothing : findsOneWidget,
        );
        if (!moment) return;
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(fake.dismissals, [DatingPostLinkOffer.linked]);
        expect(s.location, startsWith('/home?tab=chat'));
      });
    }

    testWidgets('the asker can take it back from the chat', (t) async {
      final fake = FakeDatingLink();
      await _inChat(t, _chat({'state': 'asked', 'request_id': 'r1'}), fake);
      expect(find.text("You've asked Kofi."), findsOneWidget);
      await tapInReach(t, find.text('Take it back'));
      await t.pumpAndSettle();
      expect(fake.cancels, ['r1']);
    });
  });

  testWidgets('D8: another account sees nothing of the last one\'s link page', (
    t,
  ) async {
    final fake = FakeDatingLink(pageAnswer: _asked);
    final s = await _link(t, fake);
    expect(
      find.text('Kofi would like to become a couple on Attune.'),
      findsOneWidget,
    );
    fake.pageAnswer = const DatingLinkPage(reason: 'match_unavailable');
    s.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    expect(find.textContaining('Kofi'), findsNothing);
    await t.pumpAndSettle();
    expect(find.textContaining('Kofi'), findsNothing);
    expect(find.text("This isn't available any more."), findsOneWidget);
  });

  group('fix round 1', () {
    const linkedMoment = DatingLinkPage(
      ok: true,
      displayName: 'Kofi',
      link: DatingLink(state: DatingLinkState.linked, moment: true),
    );

    /// The Relationship home's card offer, kept read for the test's account
    /// (the couple link known on), as the home would.
    Future<void> watchOffer(DatingShell s) async {
      final account = s.container.read(datingAccountProvider);
      await s.container.read(datingCoupleLinkReadProvider(account!).future);
      s.container.listen(datingPostLinkOfferProvider(account), (_, _) {});
      await s.container.read(datingPostLinkOfferProvider(account).future);
    }

    final linkOn = [
      datingCoupleLinkReadProvider.overrideWith((ref, account) async => true),
    ];

    // I-1: Continue waits for "seen" before the Relationship home reads its
    // card, so the moment never shows twice in a row.
    for (final where in ['link page', 'chat']) {
      testWidgets('I-1: Continue on the moment ($where) waits for seen, '
          'then the home reads its card anew', (t) async {
        final fake =
            FakeDatingLink(pageAnswer: linkedMoment)
              ..offerAnswer = DatingPostLinkOffer.linked
              ..dismissHold = Completer<void>();
        final s = await pumpDatingShell(
          t,
          initial: where == 'chat' ? '/dating/chat/m1' : '/dating/link/m1',
          overrides: [
            if (where == 'chat')
              ...datingChatOverrides(
                _chat({'state': 'linked', 'moment': true}, ended: true),
              ),
            ...datingLinkOverrides(fake),
            ...linkOn,
          ],
        );
        await watchOffer(s);
        expect(fake.offerReads, [0]);
        final here = s.location;
        await tapInReach(t, find.text('Continue'));
        await t.pump();
        await tapInReach(t, find.text('Continue'));
        await t.pump(const Duration(seconds: 1));
        expect(fake.dismissals, [DatingPostLinkOffer.linked]);
        expect(s.location, here, reason: 'nothing goes before seen lands');
        fake.dismissHold!.complete();
        await t.pumpAndSettle();
        expect(s.location, startsWith('/home?tab=chat'));
        expect(fake.offerReads, [0, 1]);
        expect(fake.dismissals, hasLength(1));
      });
    }

    testWidgets('I-1: a seen that never answers waits at most 3 s, then goes '
        'on', (t) async {
      final fake = FakeDatingLink(pageAnswer: linkedMoment)
        ..dismissHold = Completer<void>();
      final s = await _link(t, fake);
      await tapInReach(t, find.text('Continue'));
      await t.pump(const Duration(milliseconds: 2900));
      expect(s.location, '/dating/link/m1');
      await t.pump(const Duration(milliseconds: 200));
      // Frames only (a settle would run the clock on past any wait).
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(s.location, startsWith('/home?tab=chat'));
      fake.dismissHold!.complete();
      await t.pumpAndSettle();
    });

    testWidgets('M-2: seen already, the link page says the chat has ended '
        'and marks nothing', (t) async {
      final fake = FakeDatingLink(
        pageAnswer: const DatingLinkPage(
          ok: true,
          displayName: 'Kofi',
          link: DatingLink(state: DatingLinkState.linked),
        ),
      );
      final s = await _link(t, fake);
      expect(find.text('You decided together.'), findsNothing);
      expect(find.text('This conversation has ended.'), findsOneWidget);
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(fake.dismissals, isEmpty);
      expect(s.location, startsWith('/home?tab=chat'));
    });

    for (final how in ['the app bar', 'the system back']) {
      testWidgets('M-3, M-8: back from the moment ($how) is the Relationship '
          'home, and the title no longer asks', (t) async {
        final fake = FakeDatingLink(pageAnswer: linkedMoment);
        final s = await _link(t, fake);
        expect(find.text('Become a couple on Attune'), findsNothing);
        if (how == 'the app bar') {
          await tapInReach(
            t,
            find.byKey(const ValueKey('dating_link_back_home')),
          );
        } else {
          await t.binding.handlePopRoute();
        }
        await t.pumpAndSettle();
        expect(fake.dismissals, [DatingPostLinkOffer.linked]);
        expect(s.location, startsWith('/home?tab=chat'));
      });
    }

    testWidgets('M-3: back from the confirmer\'s moment (pushed over the '
        'chat) is the Relationship home too', (t) async {
      final fake = FakeDatingLink(pageAnswer: _asked)
        ..answer = const DatingLinkAnswer(ok: true, relationshipId: 'rel-1');
      final s = await _inChat(
        t,
        _chat({'state': 'asked_you', 'request_id': 'r9'}),
        fake,
      );
      await tapInReach(t, find.text('See what this means'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text("Yes, let's"));
      await t.pumpAndSettle();
      expect(find.text('You decided together.'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(s.location, startsWith('/home?tab=chat'));
      expect(fake.dismissals, isEmpty, reason: 'the confirmer saw it at once');
    });

    testWidgets('M-1: Take it back in the chat is sent once', (t) async {
      final fake = FakeDatingLink()..hold = Completer<void>();
      await _inChat(t, _chat({'state': 'asked', 'request_id': 'r1'}), fake);
      await tapInReach(t, find.text('Take it back'));
      await t.pump();
      await tapInReach(t, find.text('Take it back'));
      await t.pump();
      expect(fake.cancels, ['r1']);
      fake.hold!.complete();
      await t.pumpAndSettle();
      expect(fake.cancels, ['r1']);
    });

    testWidgets('M-5: offline, the asked view says why Take it back waits', (
      t,
    ) async {
      final fake = FakeDatingLink(
        pageAnswer: const DatingLinkPage(
          ok: true,
          displayName: 'Kofi',
          link: DatingLink(state: DatingLinkState.asked, requestId: 'r1'),
        ),
      );
      await _link(t, fake, online: false);
      expect(
        find.text("You're offline. Dating needs a connection."),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Take it back'));
      await t.pump();
      expect(fake.cancels, isEmpty);
    });

    for (final (reason, same) in [('unavailable', false), ('busy', true)]) {
      testWidgets('M-6: after $reason the next Ask is '
          '${same ? 'the same request' : 'a new one'}', (t) async {
        final fake =
            FakeDatingLink()
              ..answer = DatingLinkAnswer(ok: false, reason: reason);
        await _link(t, fake);
        await tapInReach(t, find.text('Ask Kofi'));
        await t.pumpAndSettle();
        await tapInReach(t, find.text('Ask Kofi'));
        await t.pumpAndSettle();
        expect(fake.asks, hasLength(2));
        expect(fake.asks[0].$1 == fake.asks[1].$1, same);
      });
    }

    testWidgets('M-9: the chat\'s moment: goldens and the three guidelines', (
      t,
    ) async {
      final overrides = [
        ...datingShellOverrides(),
        ...datingChatOverrides(
          _chat({'state': 'linked', 'moment': true}, ended: true),
        ),
      ];
      Widget screen() =>
          DatingChatScreen(matchId: 'm1', now: () => datingChatT0);
      await expectFlowGoldens(
        t,
        'dating_link_chat_moment',
        screen,
        overrides: overrides,
      );
      await pumpFlowScreen(t, screen, overrides: overrides);
      expect(find.text('You decided together.'), findsOneWidget);
      await expectFlowGuidelines(t);
    });
  });

  group('final client fix', () {
    const linkedMoment = DatingLinkPage(
      ok: true,
      displayName: 'Kofi',
      link: DatingLink(state: DatingLinkState.linked, moment: true),
    );

    /// Every location the router reports while the test runs.
    List<String> track(DatingShell s) {
      final seen = <String>[];
      void note() => seen.add(s.location);
      s.router.routerDelegate.addListener(note);
      addTearDown(() => s.router.routerDelegate.removeListener(note));
      return seen;
    }

    // M-1: alone (the Dating lock's return), linked, the system back is the
    // link page's only: the Relationship home once seen lands, never the
    // route's fallback (the chat) first.
    testWidgets('M-1: the only page, linked: the system back never shows '
        'the chat on the way to the Relationship home', (t) async {
      final fake = FakeDatingLink(pageAnswer: linkedMoment)
        ..dismissHold = Completer<void>();
      final s = await _link(t, fake);
      final seen = track(s);
      await t.binding.handlePopRoute();
      await t.pump(const Duration(seconds: 1));
      expect(s.location, '/dating/link/m1', reason: 'seen still in flight');
      fake.dismissHold!.complete();
      await t.pumpAndSettle();
      expect(s.location, startsWith('/home?tab=chat'));
      expect(seen.where((l) => l.startsWith('/dating/chat')), isEmpty);
      expect(fake.dismissals, [DatingPostLinkOffer.linked]);
    });

    testWidgets('M-1: the only page, not linked: back is still its chat', (
      t,
    ) async {
      final s = await _link(t, FakeDatingLink());
      expect(find.byKey(const ValueKey('dating_root_back')), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(s.location, '/dating/chat/m1');
    });

    // M-3: back from the ended chat while the asker's moment shows answers
    // it as Continue does: seen first (bounded), then the Relationship home;
    // never Conversations first.
    for (final how in ['the system back', 'the app bar']) {
      testWidgets('M-3: back from the chat\'s moment ($how) marks it seen, '
          'then the Relationship home', (t) async {
        final fake = FakeDatingLink()..dismissHold = Completer<void>();
        final s = await _inChat(
          t,
          _chat({'state': 'linked', 'moment': true}, ended: true),
          fake,
        );
        expect(find.text('You decided together.'), findsOneWidget);
        final seen = track(s);
        if (how == 'the app bar') {
          await tapInReach(
            t,
            find.byKey(const ValueKey('dating_link_back_home')),
          );
        } else {
          await t.binding.handlePopRoute();
        }
        await t.pump(const Duration(seconds: 1));
        expect(fake.dismissals, [DatingPostLinkOffer.linked]);
        expect(s.location, '/dating/chat/m1', reason: 'seen still in flight');
        fake.dismissHold!.complete();
        await t.pumpAndSettle();
        expect(s.location, startsWith('/home?tab=chat'));
        expect(seen.where((l) => l.startsWith('/dating/chats')), isEmpty);
        expect(fake.dismissals, hasLength(1));
      });
    }

    testWidgets('M-3: pushed over Conversations, the system back from the '
        'chat\'s moment marks it seen, then the Relationship home', (t) async {
      final fake = FakeDatingLink()..dismissHold = Completer<void>();
      final s = await pumpDatingShell(
        t,
        initial: '/dating/chats',
        overrides: [
          ...datingChatOverrides(
            _chat({'state': 'linked', 'moment': true}, ended: true),
          ),
          ...datingLinkOverrides(fake),
        ],
      );
      unawaited(s.router.push('/dating/chat/m1'));
      await t.pumpAndSettle();
      expect(find.text('You decided together.'), findsOneWidget);
      final seen = track(s);
      await t.binding.handlePopRoute();
      await t.pump(const Duration(seconds: 1));
      expect(fake.dismissals, [DatingPostLinkOffer.linked]);
      // (A push keeps the router's location: the chat itself is checked.)
      expect(find.text('You decided together.'), findsOneWidget);
      expect(seen, isEmpty, reason: 'not popped');
      fake.dismissHold!.complete();
      await t.pumpAndSettle();
      expect(s.location, startsWith('/home?tab=chat'));
      expect(seen, hasLength(1), reason: 'straight to the Relationship home');
    });

    testWidgets('M-3: an ended chat with no moment to show leaves as before', (
      t,
    ) async {
      final fake = FakeDatingLink();
      final s = await _inChat(
        t,
        _chat({'state': 'linked', 'moment': false}, ended: true),
        fake,
      );
      expect(find.text('This conversation has ended.'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(s.location, '/dating/chats');
      expect(fake.dismissals, isEmpty);
    });

    // M-4: a busy first read can be tried again, as a failed one.
    testWidgets('M-4: a busy first read offers Try again', (t) async {
      final fake = FakeDatingLink(pageAnswer: DatingLinkPage.busy);
      await _link(t, fake);
      expect(find.text(_busyLine), findsOneWidget);
      fake.pageAnswer = const DatingLinkPage(
        ok: true,
        displayName: 'Kofi',
        link: DatingLink(state: DatingLinkState.none),
      );
      await tapInReach(t, find.byKey(const ValueKey('dating_link_try_again')));
      await t.pumpAndSettle();
      expect(fake.pages, ['m1', 'm1']);
      expect(find.text('Ask Kofi'), findsOneWidget);
    });
  });

  for (final (name, page) in [
    (
      'dating_link_ask',
      const DatingLinkPage(
        ok: true,
        displayName: 'Kofi',
        link: DatingLink(state: DatingLinkState.none),
      ),
    ),
    ('dating_link_answer', _asked),
    (
      'dating_link_moment',
      const DatingLinkPage(
        ok: true,
        displayName: 'Kofi',
        link: DatingLink(state: DatingLinkState.linked, moment: true),
      ),
    ),
  ]) {
    testWidgets('goldens and the three guidelines: $name', (t) async {
      final overrides = [
        ...datingShellOverrides(),
        ...datingLinkOverrides(FakeDatingLink(pageAnswer: page)),
      ];
      Widget screen() => const DatingLinkScreen(matchId: 'm1');
      await expectFlowGoldens(t, name, screen, overrides: overrides);
      await pumpFlowScreen(t, screen, overrides: overrides);
      await expectFlowGuidelines(t);
    });
  }

  test('R-W9-16: one get_dating_home answer says both Dating flags', () {
    const mode = DatingFeatureFlags.datingModeEnabled;
    const link = DatingFeatureFlags.coupleLink;
    expect(
      DatingFeatureFlags.flagsFrom({'state': 'ready', 'couple_link': true}),
      {mode, link},
    );
    expect(DatingFeatureFlags.flagsFrom({'state': 'ready'}), {mode});
    expect(
      DatingFeatureFlags.flagsFrom({'state': 'ready', 'couple_link': 'true'}),
      {mode},
    );
    expect(
      DatingFeatureFlags.flagsFrom({'state': 'feature_unavailable'}),
      isEmpty,
    );
    expect(DatingFeatureFlags.flagsFrom(null), isEmpty);
  });

  test('the server\'s link is read defensively', () {
    expect(
      DatingLink.fromJson({'state': 'asked'}),
      isNull,
      reason: 'a request with no id',
    );
    expect(DatingLink.fromJson({'state': 'odd'}), isNull);
    expect(
      DatingLink.fromJson({'state': 'linked', 'moment': true})!.moment,
      isTrue,
    );
    expect(
      DatingLinkAnswer.fromJson({
        'ok': false,
        'reason': 'Kofi is married',
      }).reason,
      'failed',
    );
    expect(
      DatingLinkPage.fromJson({
        'ok': true,
        'display_name': ' Kofi ',
        'link': null,
      }).displayName,
      'Kofi',
    );
  });
}
