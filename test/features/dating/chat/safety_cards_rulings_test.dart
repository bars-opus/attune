// Spec 2 W6b Task 7 rulings (§3.6 Safety cards, §3.15 Chat; D8): the
// cards against the live chat. A re-read never hides a card or shows it
// twice (a failed or empty cards read, a refused background read); a card
// dismissed here never comes back while the chat is open; an ended chat's
// card offers Dismiss only, and a card's Block ends the chat; the card is
// announced and its actions are 48 dp; the chat never waits on the cards;
// another account sees no card of the last one; it renders in dark.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/features/dating/chat/safety_card.dart';
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

const _threat = DatingSafetyCard(
  id: 'e1',
  messageId: 'd2',
  family: 'threat_intimidation',
  resource: DatingCardResource(name: 'Ghana emergency', phone: '112'),
);

const _money = DatingSafetyCard(
  id: 'e2',
  messageId: 'd2',
  family: 'financial_request',
);

final _card = find.byKey(const ValueKey('dating_card_e1'));
final _block = find.byKey(const ValueKey('dating_card_block'));
final _dismiss = find.byKey(const ValueKey('dating_card_dismiss'));

/// A "something changed" signal, and the read it starts.
Future<void> signal(WidgetTester t, FakeDatingChat fake) async {
  fake.signalEvents.add(null);
  await t.pumpAndSettle();
}

void main() {
  final loc = AppLocalizationsEn();

  Future<DatingShell> open(WidgetTester t, FakeDatingChat fake) =>
      pumpDatingShell(
        t,
        initial: '/dating/chat/m1',
        overrides: datingChatOverrides(fake),
      );

  testWidgets('a re-read never hides a card or shows it twice: a failed '
      'cards read, the same card again, a refused background read', (t) async {
    final fake = FakeDatingChat()..cardList = const [_threat];
    await open(t, fake);
    expect(find.text('Kofi, 31'), findsOneWidget);
    expect(_card, findsOneWidget);

    fake.refusals['cards'] = 'failed';
    await signal(t, fake);
    expect(_card, findsOneWidget, reason: 'a failed cards read');

    fake.refusals.remove('cards');
    await signal(t, fake);
    expect(_card, findsOneWidget, reason: 'the same card read again');

    fake.refusals['messages'] = 'busy';
    await signal(t, fake);
    expect(find.text(loc.dating_busy), findsOneWidget);
    expect(_card, findsOneWidget, reason: 'a refused background read (I-1)');
    expect(fake.cardReads.length, greaterThanOrEqualTo(4));
  });

  testWidgets('a new message keeps the card under its own message, once', (
    t,
  ) async {
    final fake = FakeDatingChat()..cardList = const [_threat];
    await open(t, fake);
    fake.pageJson = datingPageJson(
      messages: [
        datingMessageJson('d3', 'Are you free Saturday?', minute: 3),
        datingMessageJson('d2', 'Call me on •••', minute: 2),
        datingMessageJson('d1', 'Hi Ama!', mine: true, minute: 1),
      ],
    );
    await signal(t, fake);
    expect(find.text('Are you free Saturday?'), findsOneWidget);
    expect(_card, findsOneWidget);
    final card = t.getRect(_card);
    expect(
      card.top,
      greaterThan(t.getRect(find.textContaining('Call me on ')).top),
    );
    expect(
      card.bottom,
      lessThan(t.getRect(find.text('Are you free Saturday?')).top),
      reason: 'the card sits between its message and the next',
    );
  });

  testWidgets('a card dismissed here never comes back while the chat is '
      'open, even if a read still lists it; the others stay', (t) async {
    // Fix round 1: a read that started before the dismissal was confirmed
    // still lists it (this fake's cards ignore dismissals).
    final fake = _StaleCards()..cardList = const [_threat, _money];
    await open(t, fake);
    expect(find.text(loc.dating_safetyFinancial), findsOneWidget);
    // The first raised sits nearest its message.
    expect(
      t.getRect(_card).top,
      lessThan(t.getRect(find.byKey(const ValueKey('dating_card_e2'))).top),
    );
    await tap(t, find.descendant(of: _card, matching: _dismiss));
    await t.pumpAndSettle();
    expect(_card, findsNothing);
    await signal(t, fake);
    expect(_card, findsNothing);
    expect(find.text(loc.dating_safetyFinancial), findsOneWidget);
    expect(fake.dismissed, ['e1']);
  });

  testWidgets('an ended chat\'s card offers Dismiss only; a card\'s Block '
      'ends the chat and its Block goes', (t) async {
    final ended = FakeDatingChat(page: datingPageJson(ended: true))
      ..cardList = const [_threat];
    await open(t, ended);
    expect(find.text(loc.dating_chatEnded), findsOneWidget);
    expect(_card, findsOneWidget);
    expect(_block, findsNothing);
    expect(_dismiss, findsOneWidget);

    final fake = FakeDatingChat()..cardList = const [_threat];
    await open(t, fake);
    await tap(t, _block);
    await t.pumpAndSettle();
    await tap(
      t,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(loc.dating_cardBlock),
      ),
    );
    await t.pumpAndSettle();
    expect(fake.blocks.length, 1);
    expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
    expect(_card, findsOneWidget);
    expect(_block, findsNothing);
    expect(find.byKey(const ValueKey('dating_chat_composer')), findsNothing);
  });

  testWidgets('a card\'s Block, cancelled, sends nothing', (t) async {
    final fake = FakeDatingChat()..cardList = const [_threat];
    await open(t, fake);
    await tap(t, _block);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_blockTitle('Kofi')), findsOneWidget);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(fake.blocks, isEmpty);
    expect(_block, findsOneWidget);
  });

  testWidgets('a new card is announced as one live region; its actions are '
      'at least 48 dp', (t) async {
    final handle = t.ensureSemantics();
    // Fix round 1 (I-1): a card new to the open chat is the one read out.
    final fake = FakeDatingChat();
    await open(t, fake);
    fake.cardList = const [_threat];
    await signal(t, fake);
    final line = loc.dating_safetyThreat('Ghana emergency (112)');
    expect(
      find.ancestor(
        of: find.text(line),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.liveRegion == true && w.container,
        ),
      ),
      findsOneWidget,
    );
    for (final action in [_block, _dismiss]) {
      final size = t.getSize(action);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    handle.dispose();
  });

  testWidgets('the chat never waits on the cards', (t) async {
    final fake = _SlowCards()..cardList = const [_threat];
    await open(t, fake);
    expect(find.text('Kofi, 31'), findsOneWidget);
    expect(find.text('Hi Ama!'), findsOneWidget);
    expect(_card, findsNothing);
    fake.gate.complete();
    await t.pumpAndSettle();
    expect(_card, findsOneWidget);
  });

  testWidgets('D8: another account sees no card of the last one', (t) async {
    final fake = FakeDatingChat()..cardList = const [_threat];
    final s = await open(t, fake);
    expect(find.text('Kofi, 31'), findsOneWidget);
    expect(_card, findsOneWidget);
    fake
      ..cardList = const []
      ..hold = Completer<DatingChatPage>();
    s.container.read(datingTestAccount.notifier).state = 'esi';
    await t.pump();
    expect(_card, findsNothing);
    expect(
      find.text(loc.dating_safetyThreat('Ghana emergency (112)')),
      findsNothing,
    );
    fake.hold!.complete(DatingChatPage.fromJson(datingPageJson(name: 'Yaw')));
    await t.pumpAndSettle();
    expect(find.text('Yaw, 31'), findsOneWidget);
    expect(_card, findsNothing);
  });

  testWidgets('a card renders in dark, with no name as "this person"', (
    t,
  ) async {
    final fake = FakeDatingChat(page: datingPageJson(name: ''))
      ..cardList = const [
        DatingSafetyCard(id: 'e1', messageId: 'd2', family: 'harassment_abuse'),
      ];
    await pumpFlowScreen(
      t,
      () => Theme(
        data: AppTheme.darkTheme,
        child: DatingChatScreen(matchId: 'm1', now: () => datingChatT0),
      ),
      overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
    );
    expect(t.takeException(), isNull);
    expect(
      find.text(loc.dating_safetyHarassment('this person')),
      findsOneWidget,
    );
    final view = t.widget<DatingSafetyCardView>(
      find.byType(DatingSafetyCardView),
    );
    expect(view.name, '');
  });
}

/// The cards answer only when the test opens [gate].
class _SlowCards extends FakeDatingChat {
  final gate = Completer<void>();

  @override
  Future<List<DatingSafetyCard>> cards(String matchId) async {
    await gate.future;
    return super.cards(matchId);
  }
}

/// Every cards read lists the cards, dismissed or not (a read that started
/// before a dismissal was confirmed).
class _StaleCards extends FakeDatingChat {
  @override
  Future<List<DatingSafetyCard>> cards(String matchId) async => cardList;
}
