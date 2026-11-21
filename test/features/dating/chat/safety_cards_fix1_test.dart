// Spec 2 W6b Task 7 fix round 1 (§3.6 Safety cards, §6.1, §3.15 Chat; D8,
// D20). I-1: only a card first seen on a later read slides in and is read
// out; a card already there when the chat opens, or one that scrolls back
// into view, is shown as it is and never moves the chat. I-2: the threat
// card names a number only when there is one to call; the sextortion card
// names its resource with a phone, a text number or its address (plain
// text), else points at Safety resources. M-1: a Dismiss the server has
// not confirmed stays hidden and is sent again (offline it says so). M-2:
// the threat card's number can be called, after the S1 confirm. M-3: the
// sextortion card without a resource opens Safety resources. M-4, M-5:
// another account never sees the last one's cards, from a late read or
// from what the screen held.
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/features/dating/chat/safety_card.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

const _sextortion = DatingSafetyCard(
  id: 'e3',
  messageId: 'd2',
  family: 'sextortion',
);

final _card = find.byKey(const ValueKey('dating_card_e1'));
final _dismiss = find.byKey(const ValueKey('dating_card_dismiss'));

/// The card's slide, as far as it has gone.
double slide(WidgetTester t) =>
    t
        .widget<SizeTransition>(
          find.descendant(
            of: find.byType(DatingSafetyCardView),
            matching: find.byType(SizeTransition),
          ),
        )
        .sizeFactor
        .value;

/// A card node that is a live region (read out when it appears).
final _live = find.descendant(
  of: find.byType(DatingSafetyCardView),
  matching: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.liveRegion == true,
  ),
);

/// The cards answer only when the test opens [gate] (each call, or only
/// the first with [firstOnly], answering [first] then).
class _GatedCards extends FakeDatingChat {
  _GatedCards({this.firstOnly = false, this.first});

  final bool firstOnly;
  final List<DatingSafetyCard>? first;
  final gate = Completer<void>();
  int calls = 0;

  @override
  Future<List<DatingSafetyCard>> cards(String matchId) async {
    final n = ++calls;
    if (!firstOnly || n == 1) await gate.future;
    if (n == 1 && first != null) return first!;
    return super.cards(matchId);
  }
}

void main() {
  final loc = AppLocalizationsEn();

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingChat fake, {
    bool online = true,
    List<Override> overrides = const [],
  }) => pumpDatingShell(
    t,
    initial: '/dating/chat/m1',
    online: online,
    overrides: [...datingChatOverrides(fake), ...overrides],
    extraRoutes: [
      GoRoute(
        path: RouteNames.safetyResources,
        builder: (_, __) => const Scaffold(body: Text('RESOURCES')),
      ),
    ],
  );

  group('I-1: only a new card moves or speaks', () {
    testWidgets('a card already there when the chat opens is shown as it '
        'is: no slide, not read out, the message not pushed', (t) async {
      final fake = _GatedCards()..cardList = const [_threat];
      await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(_card, findsNothing);
      fake.gate.complete();
      // The read lands, then its frame.
      await t.pump();
      await t.pump();
      expect(_card, findsOneWidget);
      expect(slide(t), 1.0);
      expect(_live, findsNothing);
      final top = t.getRect(find.textContaining('Call me on ')).top;
      await t.pumpAndSettle();
      expect(t.getRect(find.textContaining('Call me on ')).top, top);
    });

    testWidgets('a card that arrives while the chat is open slides in and '
        'is read out', (t) async {
      final fake = FakeDatingChat();
      await open(t, fake);
      fake.cardList = const [_threat];
      fake.signalEvents.add(null);
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(slide(t), inExclusiveRange(0.0, 1.0));
      expect(_live, findsOneWidget);
      await t.pumpAndSettle();
    });

    testWidgets('a card scrolled away and back is shown as it is: no slide, '
        'not read out, the newest message where it was', (t) async {
      final fake = FakeDatingChat(
          page: datingPageJson(
            messages: [
              for (var i = 39; i >= 0; i--)
                datingMessageJson('n$i', 'Note $i', minute: i),
            ],
          ),
        )
        ..cardList = const [
          DatingSafetyCard(
            id: 'e1',
            messageId: 'n39',
            family: 'threat_intimidation',
          ),
        ];
      await open(t, fake);
      expect(_card, findsOneWidget);
      final top = t.getRect(find.text('Note 39')).top;
      final list = find.byKey(const ValueKey('dating_chat_messages'));
      await t.drag(list, const Offset(0, 4000));
      await t.pumpAndSettle();
      expect(_card, findsNothing, reason: 'scrolled out and disposed');
      await t.drag(list, const Offset(0, -6000));
      await t.pump();
      expect(_card, findsOneWidget);
      expect(slide(t), 1.0);
      expect(_live, findsNothing);
      expect(t.getRect(find.text('Note 39')).top, top);
      await t.pumpAndSettle();
      expect(t.getRect(find.text('Note 39')).top, top);
    });

    testWidgets('a card that slid in, scrolled away and back, is shown as '
        'it is', (t) async {
      final fake = FakeDatingChat(
        page: datingPageJson(
          messages: [
            for (var i = 39; i >= 0; i--)
              datingMessageJson('n$i', 'Note $i', minute: i),
          ],
        ),
      );
      await open(t, fake);
      fake.cardList = const [
        DatingSafetyCard(
          id: 'e1',
          messageId: 'n39',
          family: 'threat_intimidation',
        ),
      ];
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(_card, findsOneWidget);
      final top = t.getRect(find.text('Note 39')).top;
      final list = find.byKey(const ValueKey('dating_chat_messages'));
      await t.drag(list, const Offset(0, 4000));
      await t.pumpAndSettle();
      expect(_card, findsNothing, reason: 'scrolled out and disposed');
      await t.drag(list, const Offset(0, -6000));
      await t.pump();
      expect(_card, findsOneWidget);
      expect(slide(t), 1.0);
      expect(_live, findsNothing);
      expect(t.getRect(find.text('Note 39')).top, top);
      await t.pumpAndSettle();
    });

    testWidgets('a card that slid in is shown as it is when the chat is '
        'opened again', (t) async {
      final fake = FakeDatingChat();
      final s = await open(t, fake);
      fake.cardList = const [_threat];
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(_card, findsOneWidget);
      s.router.go(DatingPaths.chats);
      await t.pumpAndSettle();
      expect(_card, findsNothing);
      s.router.go('/dating/chat/m1');
      for (var i = 0; i < 10 && _card.evaluate().isEmpty; i++) {
        await t.pump();
      }
      expect(_card, findsOneWidget);
      expect(slide(t), 1.0);
      expect(_live, findsNothing);
      await t.pumpAndSettle();
    });
  });

  group('I-2: a resource is named with a way to reach it', () {
    DatingSafetyCard c(String family, [DatingCardResource? r]) =>
        DatingSafetyCard(id: 'x', messageId: 'm', family: family, resource: r);

    test('a phone: the threat card\'s number, the sextortion card\'s '
        'contact', () {
      const r = DatingCardResource(name: 'CSA 292', phone: '292', sms: '293');
      expect(
        datingCardText(loc, c('threat_intimidation', r), 'Kofi'),
        loc.dating_safetyThreat('CSA 292 (292)'),
      );
      expect(
        datingCardText(loc, c('sextortion', r), 'Kofi'),
        loc.dating_safetySextortion('CSA 292 (292)'),
      );
    });

    test('a text number only: no number to call; the sextortion card names '
        'the text number', () {
      const r = DatingCardResource(name: 'CSA 292', sms: '292');
      expect(
        datingCardText(loc, c('threat_intimidation', r), 'Kofi'),
        loc.dating_safetyThreatNoNumber,
      );
      expect(
        datingCardText(loc, c('sextortion', r), 'Kofi'),
        loc.dating_safetySextortion('CSA 292 (292)'),
      );
    });

    test('an address only: no number to call; the sextortion card names '
        'the address as plain text', () {
      const r = DatingCardResource(
        name: 'StopNCII',
        url: 'https://stopncii.org/',
      );
      expect(
        datingCardText(loc, c('threat_intimidation', r), 'Kofi'),
        loc.dating_safetyThreatNoNumber,
      );
      expect(
        datingCardText(loc, c('sextortion', r), 'Kofi'),
        loc.dating_safetySextortion('StopNCII (stopncii.org)'),
      );
    });

    test('nothing to reach it by: the plain lines', () {
      const r = DatingCardResource(name: 'Find a helpline');
      expect(
        datingCardText(loc, c('threat_intimidation', r), 'Kofi'),
        loc.dating_safetyThreatNoNumber,
      );
      expect(
        datingCardText(loc, c('sextortion', r), 'Kofi'),
        loc.dating_safetySextortionNoResource,
      );
    });

    test('the server\'s answer: the international (XX) entry with an '
        'address, a text number, and an address that is not https', () {
      List<DatingSafetyCard> read(Map<String, Object?> resource) =>
          DatingSafetyCard.listFromJson({
            'ok': true,
            'cards': [
              {
                'id': 'e9',
                'message_id': 'd1',
                'family': 'sextortion',
                'resource': resource,
              },
            ],
          });
      final xx = read({
        'name': 'StopNCII',
        'phone': null,
        'sms': null,
        'url': 'https://stopncii.org',
      });
      expect(
        datingCardText(loc, xx.single, 'Kofi'),
        loc.dating_safetySextortion('StopNCII (stopncii.org)'),
      );
      final sms = read({
        'name': 'CSA 292',
        'phone': null,
        'sms': '292',
        'url': null,
      });
      expect(sms.single.resource!.sms, '292');
      expect(
        datingCardText(loc, sms.single, 'Kofi'),
        loc.dating_safetySextortion('CSA 292 (292)'),
      );
      final odd = read({'name': 'Odd', 'url': 'javascript:alert(1)'});
      expect(
        datingCardText(loc, odd.single, 'Kofi'),
        loc.dating_safetySextortionNoResource,
      );
    });
  });

  group('M-1: a Dismiss not yet confirmed', () {
    testWidgets('stays hidden when the chat opens again, and is sent again '
        'until the server confirms it', (t) async {
      final fake = FakeDatingChat()..cardList = const [_threat];
      fake.refusals['dismissCard'] = 'failed';
      final s = await open(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      await tap(t, _dismiss);
      await t.pumpAndSettle();
      expect(_card, findsNothing);
      expect(fake.dismissed, ['e1']);
      s.router.go(DatingPaths.chats);
      await t.pumpAndSettle();
      s.router.go('/dating/chat/m1');
      await t.pumpAndSettle();
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(_card, findsNothing, reason: 'the chat opened again');
      expect(fake.dismissed, ['e1', 'e1'], reason: 'sent again');
      fake.refusals.remove('dismissCard');
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(fake.dismissed, ['e1', 'e1', 'e1']);
      fake.signalEvents.add(null);
      await t.pumpAndSettle();
      expect(fake.dismissed.length, 3, reason: 'confirmed: never sent again');
      expect(_card, findsNothing);
    });

    testWidgets('offline: hidden, nothing sent, and the offline line says '
        'why', (t) async {
      final fake = FakeDatingChat()..cardList = const [_threat];
      await open(t, fake, online: false);
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(find.text(loc.dating_offline), findsNothing);
      await tap(t, _dismiss);
      await t.pumpAndSettle();
      expect(_card, findsNothing);
      expect(fake.dismissed, isEmpty);
      expect(find.text(loc.dating_offline), findsOneWidget);
    });
  });

  group('M-2: the threat card\'s number', () {
    testWidgets('Call asks first (the S1 confirm), then dials; Cancel '
        'dials nothing', (t) async {
      final launched = <String>[];
      final fake = FakeDatingChat()..cardList = const [_threat];
      await open(
        t,
        fake,
        overrides: [
          supportLauncherProvider.overrideWithValue(
            (context, url) async => launched.add(url),
          ),
        ],
      );
      final call = find.text(loc.support_call('112'));
      expect(call, findsOneWidget);
      // The copy itself is unchanged.
      expect(
        find.text(loc.dating_safetyThreat('Ghana emergency (112)')),
        findsOneWidget,
      );
      await tap(t, call);
      await t.pumpAndSettle();
      expect(find.text(loc.support_callConfirmTitle('112')), findsOneWidget);
      expect(find.text(loc.support_callConfirmBody), findsOneWidget);
      await tap(
        t,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(loc.dating_blockCancel),
        ),
      );
      await t.pumpAndSettle();
      expect(launched, isEmpty);
      await tap(t, call);
      await t.pumpAndSettle();
      await tap(
        t,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(loc.support_callConfirmCall),
        ),
      );
      await t.pumpAndSettle();
      expect(launched, ['tel:112']);
    });

    testWidgets('no phone, no Call', (t) async {
      final fake =
          FakeDatingChat()
            ..cardList = const [
              DatingSafetyCard(
                id: 'e1',
                messageId: 'd2',
                family: 'threat_intimidation',
                resource: DatingCardResource(name: 'Helpline', sms: '292'),
              ),
            ];
      await open(t, fake);
      expect(find.text(loc.dating_safetyThreatNoNumber), findsOneWidget);
      expect(find.byKey(const ValueKey('dating_card_call')), findsNothing);
    });
  });

  testWidgets('M-3: the sextortion card with no resource opens Safety '
      'resources; with one, it does not offer it', (t) async {
    final fake = FakeDatingChat()..cardList = const [_sextortion];
    await open(t, fake);
    expect(find.text(loc.dating_safetySextortionNoResource), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_card_resources')));
    await t.pumpAndSettle();
    expect(find.text('RESOURCES'), findsOneWidget);

    final reached =
        FakeDatingChat()
          ..cardList = const [
            DatingSafetyCard(
              id: 'e3',
              messageId: 'd2',
              family: 'sextortion',
              resource: DatingCardResource(name: 'CSA 292', phone: '292'),
            ),
          ];
    await open(t, reached);
    expect(
      find.text(loc.dating_safetySextortion('CSA 292 (292)')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('dating_card_resources')), findsNothing);
  });

  group('D8 on the screen alone (no lock gate to rebuild it)', () {
    Future<ProviderContainer> pumpAlone(
      WidgetTester t,
      FakeDatingChat fake,
    ) async {
      await pumpFlowScreen(
        t,
        () => DatingChatScreen(matchId: 'm1', now: () => datingChatT0),
        overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
      );
      return ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
    }

    testWidgets('M-4: a cards read that answers after the account changed '
        'never shows on the next account', (t) async {
      final fake = _GatedCards(firstOnly: true, first: const [_threat]);
      final container = await pumpAlone(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(_card, findsNothing);
      container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      expect(find.text('Kofi, 31'), findsOneWidget);
      fake.gate.complete();
      await t.pumpAndSettle();
      expect(fake.calls, 2);
      expect(_card, findsNothing);
    });

    testWidgets('M-5: the screen\'s own switch clears the cards it held', (
      t,
    ) async {
      final fake = FakeDatingChat()..cardList = const [_threat];
      final container = await pumpAlone(t, fake);
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(_card, findsOneWidget);
      fake.cardList = const [];
      container.read(datingTestAccount.notifier).state = 'esi';
      await t.pumpAndSettle();
      expect(find.text('Kofi, 31'), findsOneWidget);
      expect(_card, findsNothing);
    });
  });

  testWidgets('M-7: the card in dark (golden)', (t) async {
    final fake = FakeDatingChat()..cardList = const [_threat];
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
      matchesGoldenFile('goldens/dating_chat_card.dark.png'),
    );
  });
}
