// Spec 2 W6a (§3.5, §3.6, §3.15 Chat, §6.1, §7.4; D8): the conversations
// list and the chat. Rows read the name, the last message as the reader
// reads it and a dot for something new; the chat reads with sender names,
// a hidden span says why on a tap and reads "hidden contact detail"; a
// send shows "Sending…", then nothing, or "Not sent. Tap to try again."
// (the same request again); offline nothing is sent and the words stay;
// Swap from 72 hours, then each state; Block and Unmatch from the Safety
// sheet; an ended chat is read-only; a chat signal reads again; another
// account sees nothing of this chat and nothing typed is sent as it; the
// moment's Say hello opens the chat.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/chat/conversations_screen.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  final loc = AppLocalizationsEn();
  final now = datingChatT0.add(const Duration(minutes: 30));

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingChat fake, {
    bool online = true,
    String initial = '/dating/chat/m1',
    double textScale = 1.0,
  }) => pumpDatingShell(
    t,
    initial: initial,
    online: online,
    textScale: textScale,
    overrides: datingChatOverrides(fake),
  );

  group('the list', () {
    testWidgets('rows: name and age, the last message as read, a dot for '
        'something new, the ended ones below; a row opens its chat', (t) async {
      final fake = FakeDatingChat(
        list: datingConversationsJson(
          ended: [
            {'match_id': 'm9', 'display_name': 'Esi'},
          ],
        ),
      );
      await open(t, fake, initial: DatingPaths.chats);
      expect(find.text(loc.dating_chatsTitle), findsOneWidget);
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(find.text('Call me on •••'), findsOneWidget);
      expect(find.text(loc.dating_chatsNoMessage), findsOneWidget);
      expect(find.byKey(const ValueKey('dating_chats_dot')), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Kofi, 31, Call me on ${loc.dating_chatMaskedLabel}, ${loc.dating_chatsNew}',
        ),
        findsOneWidget,
      );
      expect(find.text(loc.dating_chatsEnded), findsOneWidget);
      expect(find.text('Esi'), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('dating_chats_row_m1')));
      await t.pumpAndSettle();
      expect(find.byType(DatingChatScreen), findsOneWidget);
    });

    testWidgets('empty: the spec\'s line', (t) async {
      final fake = FakeDatingChat(
        list: datingConversationsJson(rows: const []),
      );
      await open(t, fake, initial: DatingPaths.chats);
      expect(find.text(loc.dating_chatsEmpty), findsOneWidget);
    });
  });

  group('the chat', () {
    testWidgets('the header, messages with sender names, a hidden span read '
        'as hidden and explained on a tap; no receipts', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Kofi: Call me on ${loc.dating_chatMaskedLabel}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('${loc.dating_chatYou}: Hi Ama!'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(loc.dating_chatSafetyLabel), findsWidgets);
      for (final word in ['Seen', 'Read', 'typing', 'Online', 'Last seen']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      await tap(t, find.byKey(const ValueKey('dating_chat_masked')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_chatMaskedExplain), findsOneWidget);
    });

    testWidgets('a send shows Sending…, then nothing; a failure says so and a '
        'tap tries the same request again', (t) async {
      final fake = FakeDatingChat();
      final hold = fake.sendHold = Completer<DatingSendAnswer>();
      await open(t, fake);
      await t.enterText(
        find.byKey(const ValueKey('dating_chat_composer')),
        'Hello Kofi',
      );
      await tap(t, find.byKey(const ValueKey('dating_chat_send')));
      expect(find.text(loc.dating_chatSending), findsOneWidget);
      expect(find.text('Hello Kofi'), findsOneWidget);
      hold.complete(DatingSendAnswer.failed);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_chatNotSent), findsOneWidget);
      fake.sendHold = null;
      await tap(t, find.text(loc.dating_chatNotSent));
      await t.pumpAndSettle();
      expect(fake.sends.length, 2);
      expect(fake.sends[1].$1, fake.sends[0].$1);
      expect(fake.sends[1].$3, 'Hello Kofi');
      expect(find.text(loc.dating_chatSending), findsNothing);
      expect(find.text(loc.dating_chatNotSent), findsNothing);
      expect(fake.reads.length, greaterThanOrEqualTo(2));
    });

    testWidgets('offline: nothing is sent, the words stay, the spec\'s line', (
      t,
    ) async {
      final fake = FakeDatingChat();
      await open(t, fake, online: false);
      await t.enterText(
        find.byKey(const ValueKey('dating_chat_composer')),
        'Hello Kofi',
      );
      await tap(t, find.byKey(const ValueKey('dating_chat_send')));
      expect(fake.sends, isEmpty);
      expect(find.text(loc.dating_chatOffline), findsOneWidget);
      expect(find.text('Hello Kofi'), findsOneWidget);
    });

    testWidgets('Swap: disabled before 72 hours with its time; open: the sheet '
        'and its card, then Swap; each state after', (t) async {
      // The screen reads the real clock here (no now:): a time two days
      // from now is always ahead (W8a Ruling; datingChatT0 has passed).
      final fake = FakeDatingChat(
        page: datingPageJson(
          swapFrom: DateTime.now().toUtc().add(const Duration(days: 2)),
        ),
      );
      await pumpDatingShell(
        t,
        initial: '/dating/chat/m1',
        overrides: datingChatOverrides(fake),
      );
      expect(
        find.textContaining('${loc.dating_chatSwap} (from'),
        findsOneWidget,
      );
      final chip = t.widget<ActionChip>(
        find.byKey(const ValueKey('dating_chat_swap')),
      );
      expect(chip.onPressed, isNull);

      fake.pageJson = datingPageJson();
      await pumpDatingShell(
        t,
        initial: '/dating/chat/m1',
        overrides: datingChatOverrides(fake),
      );
      await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_chatSwapSheetBody), findsOneWidget);
      expect(find.text(loc.dating_chatSwapCard), findsOneWidget);
      await tap(t, find.text(loc.dating_chatSwapConfirm));
      await t.pumpAndSettle();
      expect(fake.swaps, [('m1', true)]);

      for (final (swap, line) in [
        (
          {'mine': true, 'theirs': false, 'both': false},
          loc.dating_chatSwapOffered('Kofi'),
        ),
        (
          {'mine': false, 'theirs': true, 'both': false},
          loc.dating_chatSwapTheirs('Kofi'),
        ),
        ({'mine': true, 'theirs': true, 'both': true}, loc.dating_chatSwapDone),
      ]) {
        fake.pageJson = datingPageJson(swap: swap);
        await pumpDatingShell(
          t,
          initial: '/dating/chat/m1',
          overrides: datingChatOverrides(fake),
        );
        expect(find.text(line), findsOneWidget, reason: '$swap');
      }
      fake.pageJson = datingPageJson(
        swap: const {'mine': true, 'theirs': false, 'both': false},
      );
      await pumpDatingShell(
        t,
        initial: '/dating/chat/m1',
        overrides: datingChatOverrides(fake),
      );
      await tap(t, find.text(loc.dating_chatSwapCancel));
      await t.pumpAndSettle();
      expect(fake.swaps.last, ('m1', false));
    });

    testWidgets(
      'Block and Unmatch from the Safety sheet, each confirmed once',
      (t) async {
        final fake = FakeDatingChat();
        await open(t, fake);
        await tap(t, find.byKey(const ValueKey('dating_chat_safety')));
        await t.pumpAndSettle();
        expect(find.text(loc.dating_blockRow('Kofi')), findsOneWidget);
        expect(find.text(loc.dating_chatSafetyUnmatch), findsOneWidget);
        expect(find.text(loc.dating_chatSafetyResources), findsOneWidget);
        await tap(t, find.text(loc.dating_chatSafetyUnmatch));
        await t.pumpAndSettle();
        expect(find.text(loc.dating_unmatchTitle('Kofi')), findsOneWidget);
        expect(find.text(loc.dating_unmatchBody('Kofi')), findsOneWidget);
        fake.pageJson = datingPageJson(ended: true);
        await tap(t, find.text(loc.dating_unmatchConfirm));
        await t.pumpAndSettle();
        expect(fake.unmatches.length, 1);
        expect(find.text(loc.dating_chatEnded), findsOneWidget);
        expect(
          find.byKey(const ValueKey('dating_chat_composer')),
          findsNothing,
        );

        fake.pageJson = datingPageJson();
        await open(t, fake);
        await tap(t, find.byKey(const ValueKey('dating_chat_safety')));
        await t.pumpAndSettle();
        await tap(t, find.text(loc.dating_blockRow('Kofi')));
        await t.pumpAndSettle();
        await tap(t, find.text(loc.dating_cardBlock));
        await t.pumpAndSettle();
        expect(fake.blocks.length, 1);
        expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('dating_chat_composer')),
          findsNothing,
        );
      },
    );

    testWidgets('a chat signal reads again', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      final before = fake.reads.length;
      fake.pageJson = datingPageJson(
        messages: [
          datingMessageJson('d3', 'Are you free Saturday?', minute: 3),
        ],
      );
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(fake.reads.length, before + 1);
      expect(find.text('Are you free Saturday?'), findsOneWidget);
    });

    testWidgets('D8: another account sees nothing of this chat, and nothing '
        'typed is sent as it', (t) async {
      final fake = FakeDatingChat();
      final s = await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('dating_chat_composer')),
        'Hello Kofi',
      );
      fake.hold = Completer<DatingChatPage>();
      s.container.read(datingTestAccount.notifier).state = 'esi';
      await t.pump();
      expect(find.text('Kofi, 31'), findsNothing);
      expect(find.text('Call me on •••'), findsNothing);
      expect(find.text('Hello Kofi'), findsNothing);
      // The next account's own chat (a test stands it in under the same id).
      fake.hold!.complete(DatingChatPage.fromJson(datingPageJson(name: 'Yaw')));
      await t.pumpAndSettle();
      expect(find.text('Yaw, 31'), findsOneWidget);
      expect(
        t
            .widget<TextField>(
              find.byKey(const ValueKey('dating_chat_composer')),
            )
            .controller!
            .text,
        isEmpty,
      );
      await tap(t, find.byKey(const ValueKey('dating_chat_send')));
      expect(fake.sends, isEmpty);
    });

    testWidgets('the moment\'s Say hello opens the chat', (t) async {
      final fake = FakeDatingChat();
      final s = await pumpDatingShell(
        t,
        initial: '/dating/match/m1',
        overrides: [
          ...datingChatOverrides(fake),
          ...datingTodayOverrides(
            FakeDatingToday(
              today: datingTodayJson({
                'moments': [
                  {'match_id': 'm1', 'display_name': 'Kofi'},
                ],
              }),
            ),
          ),
        ],
      );
      await tap(t, find.text(loc.dating_momentSayHello));
      await t.pumpAndSettle();
      expect(find.byType(DatingChatScreen), findsOneWidget);
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(s.router.canPop(), isFalse);
    });
  });

  testWidgets('goldens, guidelines and a dark render', (t) async {
    for (final (name, screen) in [
      ('dating_chat', () => DatingChatScreen(matchId: 'm1', now: () => now)),
      ('dating_chats', () => const DatingConversationsScreen()),
    ]) {
      await t.pumpWidget(const SizedBox());
      await expectFlowGoldens(
        t,
        name,
        screen,
        overrides: [
          ...datingShellOverrides(),
          ...datingChatOverrides(FakeDatingChat()),
        ],
      );
      await pumpFlowScreen(
        t,
        screen,
        overrides: [
          ...datingShellOverrides(),
          ...datingChatOverrides(FakeDatingChat()),
        ],
      );
      await expectFlowGuidelines(t);
      await pumpFlowScreen(
        t,
        () => Theme(data: AppTheme.darkTheme, child: screen()),
        overrides: [
          ...datingShellOverrides(),
          ...datingChatOverrides(FakeDatingChat()),
        ],
      );
      expect(t.takeException(), isNull);
    }
  });
}
