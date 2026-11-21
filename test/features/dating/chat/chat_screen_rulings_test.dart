// Spec 2 W6a Task 4 (the dispatch's live-code rulings, after Tasks 1-3's
// fix rounds): `unavailable` says messages are paused and the chat stays
// open (never re-read or shown as ended; the same request again); a swap
// answer uses the send's reason map; a chat that reads ended with no list
// row is read-only with no Unmatch; one's own message reads as the server
// returns it (masked too, §6.1); every reverify_device answer shows the
// re-check line (W4b carry 9).
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/tap_in_reach.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_shell.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  final loc = AppLocalizationsEn();

  Future<DatingShell> open(WidgetTester t, FakeDatingChat fake) =>
      pumpDatingShell(
        t,
        initial: '/dating/chat/m1',
        overrides: datingChatOverrides(fake),
      );

  Future<void> write(WidgetTester t, String text) async {
    await t.enterText(find.byKey(const ValueKey('dating_chat_composer')), text);
    await tap(t, find.byKey(const ValueKey('dating_chat_send')));
    await t.pumpAndSettle();
  }

  void expectOpen() {
    expect(find.byKey(const ValueKey('dating_chat_composer')), findsOneWidget);
    expect(find.byKey(const ValueKey('dating_chat_swap')), findsOneWidget);
    expect(find.text(loc.dating_chatEnded), findsNothing);
  }

  group('unavailable', () {
    testWidgets('a send: paused, still "Tap to try again", the chat stays '
        'open and is not read again; the same request again', (t) async {
      final fake = FakeDatingChat()..refusals['send'] = 'unavailable';
      await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      final reads = fake.reads.length;
      await write(t, 'Hello Kofi');
      expect(find.text(loc.dating_chatPaused), findsOneWidget);
      expect(find.text(loc.dating_chatNotSent), findsOneWidget);
      expect(find.text(loc.dating_errorGeneric), findsNothing);
      expect(fake.reads.length, reads);
      expectOpen();

      // A new message with the same words is the same request (settled as
      // busy: the server kept nothing).
      await write(t, 'Hello Kofi');
      expect(fake.sends.length, 2);
      expect(fake.sends[1].$1, fake.sends[0].$1);

      fake.refusals.remove('send');
      await tap(t, find.text(loc.dating_chatNotSent).first);
      await t.pumpAndSettle();
      expect(fake.sends.length, 3);
      expect(fake.sends[2].$1, fake.sends[0].$1);
      expect(fake.sends[2].$3, 'Hello Kofi');
    });

    testWidgets('a swap offer: paused, the header stays active, no read', (
      t,
    ) async {
      final fake = FakeDatingChat()..refusals['offerSwap'] = 'unavailable';
      await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      final reads = fake.reads.length;
      await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_chatSwapConfirm));
      await t.pumpAndSettle();
      expect(fake.swaps, [('m1', true)]);
      expect(find.text(loc.dating_chatPaused), findsOneWidget);
      expect(fake.reads.length, reads);
      expectOpen();
    });
  });

  group('a swap answer uses the send\'s reason map', () {
    testWidgets('restricted', (t) async {
      final fake = FakeDatingChat()..refusals['offerSwap'] = 'restricted';
      await open(t, fake);
      await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_chatSwapConfirm));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_chatRestricted), findsOneWidget);
      expect(find.text(loc.dating_errorGeneric), findsNothing);
      expectOpen();
    });

    testWidgets('closed: read again, then ended and read-only', (t) async {
      final fake = FakeDatingChat()..refusals['offerSwap'] = 'closed';
      await open(t, fake);
      await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
      await t.pumpAndSettle();
      final reads = fake.reads.length;
      fake.pageJson = datingPageJson(ended: true);
      await tap(t, find.text(loc.dating_chatSwapConfirm));
      await t.pumpAndSettle();
      expect(fake.reads.length, reads + 1);
      expect(find.text(loc.dating_chatEnded), findsWidgets);
      expect(find.byKey(const ValueKey('dating_chat_composer')), findsNothing);
    });

    testWidgets('a withdraw refused: its line, the offer still shown', (
      t,
    ) async {
      final fake = FakeDatingChat(
        page: datingPageJson(
          swap: const {'mine': true, 'theirs': false, 'both': false},
        ),
      )..refusals['withdrawSwap'] = 'rate_limited';
      await open(t, fake);
      await tap(t, find.text(loc.dating_chatSwapCancel));
      await t.pumpAndSettle();
      expect(fake.swaps, [('m1', false)]);
      expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
      expect(find.text(loc.dating_chatSwapOffered('Kofi')), findsOneWidget);
    });
  });

  testWidgets('a chat that reads ended (in neither list): read-only, and its '
      'Safety sheet offers no Unmatch', (t) async {
    final fake = FakeDatingChat(page: datingPageJson(ended: true));
    await open(t, fake);
    expect(find.text('Kofi, 31'), findsOneWidget);
    expect(find.text(loc.dating_chatEnded), findsOneWidget);
    expect(find.byKey(const ValueKey('dating_chat_composer')), findsNothing);
    expect(find.byKey(const ValueKey('dating_chat_swap')), findsNothing);
    await tap(t, find.byKey(const ValueKey('dating_chat_safety')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_blockRow('Kofi')), findsOneWidget);
    expect(find.text(loc.dating_chatSafetyResources), findsOneWidget);
    expect(find.text(loc.dating_chatSafetyUnmatch), findsNothing);
  });

  group('one\'s own message reads as the server returns it (§6.1)', () {
    testWidgets('listed: masked, read as hidden', (t) async {
      final fake = FakeDatingChat(
        page: datingPageJson(
          messages: [
            datingMessageJson('d1', 'Text me on •••', mine: true, minute: 1),
          ],
        ),
      );
      await open(t, fake);
      expect(find.text(kDatingMask), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '${loc.dating_chatYou}: Text me on ${loc.dating_chatMaskedLabel}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sent: the answer\'s copy replaces what was typed', (t) async {
      final fake = FakeDatingChat(page: datingPageJson(messages: const []));
      await open(t, fake);
      await write(t, 'Call me on 0244 123 456');
      expect(fake.sends.single.$3, 'Call me on 0244 123 456');
      expect(find.textContaining('0244'), findsNothing);
      expect(find.text(kDatingMask), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^${loc.dating_chatYou}: Call me on '
            '${loc.dating_chatMaskedLabel}',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('a message with two hidden spans: each reads hidden and each '
      'explains on a tap', (t) async {
    final fake = FakeDatingChat(
      page: datingPageJson(
        messages: [
          datingMessageJson('d2', 'Call me on •••, or ••• later', minute: 2),
        ],
      ),
    );
    await open(t, fake);
    expect(t.takeException(), isNull);
    final hidden = loc.dating_chatMaskedLabel;
    expect(
      find.bySemanticsLabel(
        RegExp('^Kofi: Call me on $hidden ?, or $hidden later\$'),
      ),
      findsOneWidget,
    );
    expect(find.text(kDatingMask), findsNWidgets(2));
    await tap(t, find.byKey(const ValueKey('dating_chat_masked')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_chatMaskedExplain), findsOneWidget);
  });

  testWidgets('reverify_device on a send shows the re-check line', (t) async {
    final fake = FakeDatingChat()..refusals['send'] = 'reverify_device';
    await open(t, fake);
    await write(t, 'Hello Kofi');
    expect(find.text(loc.dating_sectionReverify), findsOneWidget);
    expect(find.text(loc.dating_chatNotSent), findsOneWidget);
    expectOpen();
  });

  test('carry 7: act\'s answer names its match (or none)', () {
    expect(
      DatingActAnswer.fromJson({
        'ok': true,
        'matched': true,
        'match_id': 'm7',
      }).matchId,
      'm7',
    );
    expect(DatingActAnswer.fromJson({'ok': true}).matchId, isNull);
    expect(
      DatingActAnswer.fromJson({'ok': true, 'match_id': 7}).matchId,
      isNull,
    );
  });
}
