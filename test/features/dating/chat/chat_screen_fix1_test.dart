// Spec 2 W6a Task 4 fix round 1 (task-4-review.md): a failed background
// read keeps the chat and its shield (I-1); older pages and new messages
// merge by id with nothing lost (I-2); a Dating page reached as the only
// page has a way back (I-3); the four chat sheets under D8 and once (M-1);
// later success clears a line, too_early says when (M-4); offline swap
// and Cancel (M-5); named send refusals (M-6); the failed line's icon
// (M-7); masked bubbles: semantics and a whole-bubble target (M-8, M-9);
// the 1,000 limit counted as the server counts (M-10); older pages under
// an account change and their failures (M-11); large text with the
// keyboard up (M-12); the iPad column (M-14).
import 'dart:async';

import 'package:attune/features/dating/chat/conversations_screen.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/match_moment_screen.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

/// The chat in pages of [size], newest first, from [history] (oldest
/// first): the server's newest page and the page before a time.
class PagedChat extends FakeDatingChat {
  PagedChat(this.history, {this.size = 3});

  final List<Map<String, Object?>> history;
  final int size;
  Completer<DatingChatPage>? olderHold;
  String? olderRefusal;

  DateTime _at(Map<String, Object?> m) => DateTime.parse(m['at'] as String);

  @override
  Future<DatingChatPage> messages(String matchId, {DateTime? before}) async {
    reads.add((matchId, before));
    if (before != null) {
      final h = olderHold;
      if (h != null) return h.future;
      final r = olderRefusal;
      if (r != null) return DatingChatPage.fromJson({'ok': false, 'reason': r});
    } else {
      final h = hold;
      if (h != null) return h.future;
      final r = refusals['messages'];
      if (r != null) return DatingChatPage.fromJson({'ok': false, 'reason': r});
    }
    final newest = [
      for (final m in history.reversed)
        if (before == null || _at(m).isBefore(before)) m,
    ];
    return DatingChatPage.fromJson({
      ...pageJson,
      'messages': newest.take(size).toList(),
      'more': newest.length > size,
    });
  }
}

void main() {
  final loc = AppLocalizationsEn();
  final composer = find.byKey(const ValueKey('dating_chat_composer'));
  final shield = find.byKey(const ValueKey('dating_chat_safety'));
  final rootBack = find.byKey(const ValueKey('dating_root_back'));

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingChat fake, {
    String initial = '/dating/chat/m1',
    bool online = true,
    double textScale = 1.0,
  }) => pumpDatingShell(
    t,
    initial: initial,
    online: online,
    textScale: textScale,
    overrides: datingChatOverrides(fake),
  );

  Future<void> write(WidgetTester t, String text) async {
    await t.enterText(composer, text);
    await tap(t, find.byKey(const ValueKey('dating_chat_send')));
    await t.pumpAndSettle();
  }

  group('I-1: a failed re-read keeps the chat', () {
    for (final (reason, line) in [
      ('busy', loc.dating_busy),
      ('failed', loc.dating_errorGeneric),
    ]) {
      testWidgets('$reason: the messages, a Not sent bubble, the composer '
          'and the shield stay; the line says why', (t) async {
        final fake = FakeDatingChat()..refusals['send'] = 'failed';
        await open(t, fake);
        expect(find.text('Kofi, 31'), findsOneWidget);
        await write(t, 'Hello Kofi');
        expect(find.text(loc.dating_chatNotSent), findsOneWidget);
        fake.refusals['messages'] = reason;
        fake.signalEvents.add(null);
        await t.pumpAndSettle();
        expect(find.text('Kofi, 31'), findsOneWidget);
        expect(find.text('Hi Ama!'), findsOneWidget);
        expect(find.text(loc.dating_chatNotSent), findsOneWidget);
        expect(composer, findsOneWidget);
        expect(shield, findsOneWidget);
        expect(find.text(line), findsOneWidget);
        // The next good read clears the line.
        fake.refusals.remove('messages');
        fake.signalEvents.add(null);
        await t.pumpAndSettle();
        expect(find.text(line), findsNothing);
      });
    }

    testWidgets('match_unavailable replaces the chat with its line', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      expect(composer, findsOneWidget);
      fake.refusals['messages'] = 'match_unavailable';
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_cardGone), findsOneWidget);
      expect(composer, findsNothing);
    });

    testWidgets('a first read refused shows the refusal with Try again', (
      t,
    ) async {
      final fake = FakeDatingChat()..refusals['messages'] = 'busy';
      await open(t, fake);
      expect(find.text(loc.dating_busy), findsOneWidget);
      expect(composer, findsNothing);
      fake.refusals.remove('messages');
      await tap(t, find.text(loc.dating_tryAgain));
      await t.pumpAndSettle();
      expect(composer, findsOneWidget);
    });
  });

  group('I-2: pages merge by id', () {
    List<Map<String, Object?>> history(int n) => [
      for (var i = 1; i <= n; i++)
        datingMessageJson('h$i', 'Note $i', minute: i),
    ];

    testWidgets('earlier messages, then a new one: every message stays, in '
        'order, once', (t) async {
      final fake = PagedChat(history(6));
      await open(t, fake);
      expect(find.text('Note 6'), findsOneWidget);
      expect(find.text('Note 3'), findsNothing);
      await tap(t, find.text(loc.dating_chatLoadOlder));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_chatLoadOlder), findsNothing);
      fake.history.add(datingMessageJson('h7', 'Note 7', minute: 7));
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      final ys = [
        for (var i = 1; i <= 7; i++)
          t.getTopLeft(find.text('Note $i')).dy, // each found exactly once
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: 'Note ${i + 1}');
      }
    });

    testWidgets('a newest page with no overlap starts again from it (no gap)', (
      t,
    ) async {
      final fake = PagedChat(history(6));
      await open(t, fake);
      for (var i = 7; i <= 12; i++) {
        fake.history.add(datingMessageJson('h$i', 'Note $i', minute: i));
      }
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      for (final i in [10, 11, 12]) {
        expect(find.text('Note $i'), findsOneWidget);
      }
      // Nothing older than the gap: earlier messages load from here.
      for (final i in [4, 5, 6]) {
        expect(find.text('Note $i'), findsNothing);
      }
      expect(find.text(loc.dating_chatLoadOlder), findsOneWidget);
      await tap(t, find.text(loc.dating_chatLoadOlder));
      await t.pumpAndSettle();
      for (final i in [7, 8, 9]) {
        expect(find.text('Note $i'), findsOneWidget);
      }
    });
  });

  group('I-3: the only page has a way back', () {
    testWidgets('a chat: back to Conversations (button and system back)', (
      t,
    ) async {
      var s = await open(t, FakeDatingChat());
      expect(s.router.canPop(), isFalse);
      expect(rootBack, findsOneWidget);
      await tap(t, rootBack);
      await t.pumpAndSettle();
      expect(s.location, DatingPaths.chats);
      expect(find.byType(DatingConversationsScreen), findsOneWidget);

      s = await open(t, FakeDatingChat());
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(s.location, DatingPaths.chats);
    });

    for (final (name, initial) in [
      ('Conversations', DatingPaths.chats),
      ('Today', DatingPaths.today),
      ('Dating settings', DatingPaths.settings),
    ]) {
      testWidgets('$name: back to Me', (t) async {
        final s = await pumpDatingShell(
          t,
          initial: initial,
          overrides: [
            ...datingChatOverrides(FakeDatingChat()),
            ...datingTodayOverrides(FakeDatingToday()),
          ],
        );
        expect(s.location, initial);
        expect(rootBack, findsOneWidget);
        await tap(t, rootBack);
        await t.pumpAndSettle();
        expect(find.text('ME me'), findsOneWidget);
      });
    }

    testWidgets('pushed: the ordinary back, no fallback', (t) async {
      final s = await open(t, FakeDatingChat(), initial: DatingPaths.chats);
      await tap(t, find.byKey(const ValueKey('dating_chats_row_m1')));
      await t.pumpAndSettle();
      expect(find.byType(DatingChatScreen), findsOneWidget);
      expect(rootBack, findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      s.router.pop();
      await t.pumpAndSettle();
      expect(find.byType(DatingConversationsScreen), findsOneWidget);
    });
  });

  group('M-1: each sheet under another account, and once', () {
    Future<void> openSheet(WidgetTester t, String sheet) async {
      switch (sheet) {
        case 'safety':
          await tap(t, shield);
        case 'unmatch':
          await tap(t, shield);
          await t.pumpAndSettle();
          await tap(t, find.text(loc.dating_chatSafetyUnmatch));
        case 'swap':
          await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
        case 'masked':
          await tap(t, find.byKey(const ValueKey('dating_chat_masked')));
      }
      await t.pumpAndSettle();
    }

    final shown = {
      'safety': loc.dating_chatSafetyResources,
      'unmatch': loc.dating_unmatchBody('Kofi'),
      'swap': loc.dating_chatSwapSheetBody,
      'masked': loc.dating_chatMaskedExplain,
    };

    for (final sheet in shown.keys) {
      testWidgets('$sheet: nothing of Kofi once the account changes', (
        t,
      ) async {
        final fake = FakeDatingChat();
        final s = await open(t, fake);
        expect(find.text('Kofi, 31'), findsOneWidget);
        await openSheet(t, sheet);
        expect(find.text(shown[sheet]!), findsOneWidget);
        fake.hold = Completer<DatingChatPage>();
        s.container.read(datingTestAccount.notifier).state = 'esi';
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text(shown[sheet]!), findsNothing);
        expect(find.textContaining('Kofi'), findsNothing);
        expect(fake.swaps, isEmpty);
        expect(fake.blocks, isEmpty);
        expect(fake.unmatches, isEmpty);
      });
    }

    testWidgets('each answers once', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      // Safety: a double tap on a row opens one Unmatch.
      await openSheet(t, 'safety');
      final row = find.text(loc.dating_chatSafetyUnmatch);
      await t.tap(row);
      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_unmatchBody('Kofi')), findsOneWidget);
      // Unmatch: one call.
      final target = find.text(loc.dating_unmatchConfirm);
      await t.tap(target);
      await t.tap(target, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(fake.unmatches, hasLength(1));

      // Swap: one offer.
      fake.pageJson = datingPageJson();
      await open(t, fake);
      await openSheet(t, 'swap');
      final swap = find.text(loc.dating_chatSwapConfirm);
      await t.tap(swap);
      await t.tap(swap, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(fake.swaps, [('m1', true)]);

      // Masked: OK closes it once, the chat stays.
      await open(t, fake);
      await openSheet(t, 'masked');
      final ok = find.text(loc.dating_chatOk);
      await t.tap(ok);
      await t.tap(ok, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_chatMaskedExplain), findsNothing);
      expect(find.byType(DatingChatScreen), findsOneWidget);
    });
  });

  group('M-4: lines', () {
    testWidgets('a later sent message clears the last line', (t) async {
      final fake = FakeDatingChat()..refusals['send'] = 'reverify_device';
      await open(t, fake);
      await write(t, 'Hello Kofi');
      expect(find.text(loc.dating_sectionReverify), findsOneWidget);
      fake.refusals.remove('send');
      await write(t, 'Hello again');
      expect(find.text(loc.dating_sectionReverify), findsNothing);
    });

    testWidgets('a later swap clears a refused send\'s line', (t) async {
      final fake = FakeDatingChat()..refusals['offerSwap'] = 'rate_limited';
      await open(t, fake);
      await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_chatSwapConfirm));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
      fake.refusals.remove('offerSwap');
      await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_chatSwapConfirm));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorRateLimited), findsNothing);
    });

    testWidgets('too_early says from when', (t) async {
      // The phone's clock (the real now) runs past `from`, so the chip is
      // open; the server's (T0) is before it, so it says too_early.
      final fake = FakeDatingChat(
        page: datingPageJson(
          swapFrom: datingChatT0.add(const Duration(hours: 1)),
        ),
      )..now = (() => datingChatT0);
      await open(t, fake);
      await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_chatSwapConfirm));
      await t.pumpAndSettle();
      expect(find.textContaining('${loc.dating_chatSwap} (from'), findsWidgets);
      expect(find.text(loc.dating_errorGeneric), findsNothing);
    });
  });

  group('M-5: offline', () {
    testWidgets('the Swap sheet waits; Cancel waits', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake, online: false);
      await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_offline), findsOneWidget);
      await t.tap(find.text(loc.dating_chatSwapConfirm), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(fake.swaps, isEmpty);
      await tap(t, find.text(loc.dating_chatSwapNotYet));
      await t.pumpAndSettle();

      fake.pageJson = datingPageJson(
        swap: const {'mine': true, 'theirs': false, 'both': false},
      );
      await open(t, fake, online: false);
      await tap(t, find.text(loc.dating_chatSwapCancel));
      await t.pumpAndSettle();
      expect(fake.swaps, isEmpty);
      expect(find.text(loc.dating_offline), findsOneWidget);
    });
  });

  group('M-6, M-7: a refused send', () {
    testWidgets('closed: "Not sent." once, the banner once, no retry', (
      t,
    ) async {
      final fake = FakeDatingChat()..refusals['send'] = 'closed';
      await open(t, fake);
      fake.pageJson = datingPageJson(ended: true);
      await write(t, 'Hello Kofi');
      expect(find.text(loc.dating_chatNotSentFinal), findsOneWidget);
      expect(find.text(loc.dating_chatEnded), findsOneWidget);
      expect(find.text(loc.dating_chatNotSent), findsNothing);
    });

    testWidgets('rate_limited: why, then Tap to try again, with an icon', (
      t,
    ) async {
      final fake = FakeDatingChat()..refusals['send'] = 'rate_limited';
      await open(t, fake);
      await write(t, 'Hello Kofi');
      expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
      expect(find.text(loc.dating_chatNotSent), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsWidgets);
      fake.refusals.remove('send');
      await tap(t, find.text(loc.dating_chatNotSent));
      await t.pumpAndSettle();
      expect(fake.sends, hasLength(2));
    });

    testWidgets('invalid: "Not sent.", no retry', (t) async {
      final fake = FakeDatingChat()..refusals['send'] = 'invalid';
      await open(t, fake);
      await write(t, 'Hello Kofi');
      expect(find.text(loc.dating_chatNotSentFinal), findsOneWidget);
      expect(find.text(loc.dating_chatNotSent), findsNothing);
      await tap(t, find.text(loc.dating_chatNotSentFinal));
      await t.pumpAndSettle();
      expect(fake.sends, hasLength(1));
    });

    testWidgets('match_unavailable: read again, then the gone line', (t) async {
      final fake = FakeDatingChat()..refusals['send'] = 'match_unavailable';
      await open(t, fake);
      fake.refusals['messages'] = 'match_unavailable';
      await write(t, 'Hello Kofi');
      expect(find.text(loc.dating_cardGone), findsOneWidget);
      expect(composer, findsNothing);
    });
  });

  group('M-8, M-9: a masked bubble', () {
    testWidgets('own sent and masked: read with a tap that explains', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final fake = FakeDatingChat(page: datingPageJson(messages: const []));
      await open(t, fake);
      await write(t, 'Call me on 0244 123 456');
      final node = t.getSemantics(
        find.bySemanticsLabel(RegExp('^${loc.dating_chatYou}: Call me on ')),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('the whole bubble is the target, at least 48 high', (t) async {
      await open(t, FakeDatingChat());
      final bubble = find.byKey(const ValueKey('dating_chat_bubble_d2'));
      expect(t.getSize(bubble).height, greaterThanOrEqualTo(48));
      // Its words, not the dots, explain too.
      await tap(t, find.textContaining('Call me on '));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_chatMaskedExplain), findsOneWidget);
    });
  });

  group('M-10: 1,000 characters as the server counts them', () {
    testWidgets('600 emoji (1,200 UTF-16 units) send', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      await write(t, '😀' * 600);
      expect(fake.sends, hasLength(1));
    });

    testWidgets('near the limit a counter; over it a line and no Send', (
      t,
    ) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      await t.enterText(composer, 'a' * 950);
      await t.pump();
      expect(
        find.text(loc.dating_chatCounter(950, kDatingMessageMax)),
        findsOneWidget,
      );
      // 501 flags: 501 characters on screen, 1,002 for the server.
      await t.enterText(composer, '🇬🇭' * 501);
      await t.pump();
      expect(find.text(loc.dating_chatTooLong), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('dating_chat_send')));
      expect(fake.sends, isEmpty);
      expect(
        t
            .widget<IconButton>(find.byKey(const ValueKey('dating_chat_send')))
            .onPressed,
        isNull,
      );
    });
  });

  group('M-11: earlier messages', () {
    testWidgets('busy and failed say so; the link stays', (t) async {
      final fake = PagedChat([
        for (var i = 1; i <= 6; i++)
          datingMessageJson('h$i', 'Note $i', minute: i),
      ])..olderRefusal = 'busy';
      await open(t, fake);
      await tap(t, find.text(loc.dating_chatLoadOlder));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_busy), findsOneWidget);
      expect(find.text(loc.dating_chatLoadOlder), findsOneWidget);
      fake.olderRefusal = 'failed';
      await tap(t, find.text(loc.dating_chatLoadOlder));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    });

    testWidgets('an account change mid-load: the next account can load', (
      t,
    ) async {
      final fake = PagedChat([
        for (var i = 1; i <= 6; i++)
          datingMessageJson('h$i', 'Note $i', minute: i),
      ])..olderHold = Completer<DatingChatPage>();
      final s = await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      await tap(t, find.text(loc.dating_chatLoadOlder));
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      expect(find.text('Kofi, 31'), findsOneWidget); // esi's own (same fake)
      fake.olderHold = null;
      final before = fake.reads.where((r) => r.$2 != null).length;
      await tap(t, find.text(loc.dating_chatLoadOlder));
      await t.pumpAndSettle();
      expect(fake.reads.where((r) => r.$2 != null).length, before + 1);
      expect(find.text('Note 1'), findsOneWidget);
    });
  });

  testWidgets('M-12: text 2.0 with the keyboard up: nothing overflows', (
    t,
  ) async {
    final fake = FakeDatingChat(
      page: datingPageJson(
        swap: const {'mine': false, 'theirs': true, 'both': false},
      ),
    )..refusals['offerSwap'] = 'rate_limited';
    await open(t, fake, textScale: 2.0);
    t.view.viewInsets = const FakeViewPadding(bottom: 336);
    await t.pumpAndSettle();
    await t.enterText(composer, 'One\nTwo\nThree\nFour\nFive\nSix');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_chatSwapConfirm));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
    expect(composer.hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dating_chat_send')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('M-14: on an iPad the chat sits in the chat column', (t) async {
    await open(t, FakeDatingChat());
    t.view.physicalSize = const Size(1366, 1024);
    await t.pumpAndSettle();
    expect(t.getSize(composer).width, lessThanOrEqualTo(840));
  });

  group('M-2, M-3: Today and the chat', () {
    testWidgets('M-2: act\'s match opens its own moment, not a namesake', (
      t,
    ) async {
      final fake =
          FakeDatingToday()
            ..answer =
                (id, action) => DatingActAnswer(
                  ok: true,
                  action: action,
                  matched: true,
                  matchId: 'mK',
                );
      await pumpDatingShell(
        t,
        initial: DatingPaths.today,
        overrides: datingTodayOverrides(fake),
      );
      fake.json = datingTodayJson({
        'cards': <Object?>[],
        'moments': [
          {'match_id': 'mK', 'display_name': 'Kofi'},
          {'match_id': 'mX', 'display_name': 'Kofi'},
        ],
      });
      await tap(t, find.text(loc.dating_cardInterested));
      await t.pumpAndSettle();
      final moment = t.widget<DatingMatchMomentScreen>(
        find.byType(DatingMatchMomentScreen),
      );
      expect(moment.matchId, 'mK');
    });

    testWidgets('M-3: Say hello, the chat, back: Today reads again', (t) async {
      final today = FakeDatingToday(
        today: datingTodayJson({
          'moments': [
            {'match_id': 'm1', 'display_name': 'Kofi'},
          ],
        }),
      );
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.today,
        overrides: datingTodayOverrides(today),
      );
      expect(find.text(loc.dating_momentSayHello), findsOneWidget);
      await tap(t, find.text(loc.dating_momentSayHello));
      await t.pumpAndSettle();
      expect(find.byType(DatingChatScreen), findsOneWidget);
      final reads = today.reads;
      s.router.pop();
      await t.pumpAndSettle();
      expect(find.byType(DatingTodayScreen), findsOneWidget);
      expect(today.reads, reads + 1);
    });
  });
}
