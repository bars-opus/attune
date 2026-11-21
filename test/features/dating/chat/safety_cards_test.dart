// Spec 2 W6b (§3.6 Safety cards, §6.1, §3.15 Chat; chat spec §4.1): the
// recipient's cards. A card shows under the message that raised it, in the
// spec's words with the person's name ("this person" without one) and the
// country's number or resource (a plain line without one); Dismiss hides
// it and asks the server once; Block confirms, then blocks; it slides in
// at 150 ms and not at all under reduce motion.
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

void main() {
  final loc = AppLocalizationsEn();

  testWidgets('a card shows under the message that raised it, with the '
      'country\'s number', (t) async {
    final fake = FakeDatingChat()..cardList = const [_threat];
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      overrides: datingChatOverrides(fake),
    );
    final line = loc.dating_safetyThreat('Ghana emergency (112)');
    expect(find.text(line), findsOneWidget);
    final card = t.getTopLeft(find.byKey(const ValueKey('dating_card_e1')));
    final message = t.getBottomLeft(find.textContaining('Call me on '));
    expect(card.dy, greaterThan(message.dy - 1));
    expect(find.text('Hi Ama!'), findsOneWidget);
    expect(find.byKey(const ValueKey('dating_card_block')), findsOneWidget);
    expect(find.byKey(const ValueKey('dating_card_dismiss')), findsOneWidget);
  });

  test('each family in the spec\'s words; no name is "this person"; no '
      'resource, a plain line', () {
    DatingSafetyCard c(String family, [DatingCardResource? r]) =>
        DatingSafetyCard(id: 'x', messageId: 'm', family: family, resource: r);
    // Fix round 1 (I-2): a resource is named with a way to reach it.
    const sos = DatingCardResource(name: 'CSA 292', phone: '292');
    expect(
      datingCardText(loc, c('sexual_pressure'), 'Kofi'),
      loc.dating_safetySexualPressure('Kofi'),
    );
    expect(
      datingCardText(loc, c('harassment_abuse'), ''),
      loc.dating_safetyHarassment('this person'),
    );
    expect(
      datingCardText(loc, c('contact_migration_pressure'), 'Kofi'),
      loc.dating_safetyContactMigration,
    );
    expect(
      datingCardText(loc, c('meet_private_pressure'), 'Kofi'),
      loc.dating_safetyMeetPrivate,
    );
    expect(
      datingCardText(loc, c('threat_intimidation'), 'Kofi'),
      loc.dating_safetyThreatNoNumber,
    );
    expect(
      datingCardText(loc, c('financial_request'), 'Kofi'),
      loc.dating_safetyFinancial,
    );
    expect(
      datingCardText(loc, c('sextortion', sos), 'Kofi'),
      loc.dating_safetySextortion('CSA 292 (292)'),
    );
    expect(
      datingCardText(loc, c('sextortion'), 'Kofi'),
      loc.dating_safetySextortionNoResource,
    );
    expect(
      datingCardText(loc, c('child_access'), 'Kofi'),
      loc.dating_safetyChildAccess,
    );
    expect(
      DatingSafetyCard.listFromJson({
        'ok': true,
        'cards': [
          {'id': 'e2', 'message_id': 'd1', 'family': 'age_signal'},
          {
            'id': 'e3',
            'message_id': 'd1',
            'family': 'financial_request',
            'resource': null,
          },
        ],
      }).map((c) => c.id),
      ['e3'],
    );
  });

  testWidgets('Dismiss hides it and asks once; Block confirms, then blocks', (
    t,
  ) async {
    final fake = FakeDatingChat()..cardList = const [_threat];
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      overrides: datingChatOverrides(fake),
    );
    await tap(t, find.byKey(const ValueKey('dating_card_dismiss')));
    await t.pump();
    expect(find.byKey(const ValueKey('dating_card_e1')), findsNothing);
    expect(fake.dismissed, ['e1']);

    final again = FakeDatingChat()..cardList = const [_threat];
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      overrides: datingChatOverrides(again),
    );
    await tap(t, find.byKey(const ValueKey('dating_card_block')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_blockTitle('Kofi')), findsOneWidget);
    await tap(
      t,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(loc.dating_cardBlock),
      ),
    );
    await t.pumpAndSettle();
    expect(again.blocks.length, 1);
    expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
  });

  testWidgets('a new card slides in at 150 ms; not at all under reduce '
      'motion', (t) async {
    for (final reduce in [false, true]) {
      if (reduce) {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
      }
      final fake = FakeDatingChat();
      await pumpDatingShell(
        t,
        initial: '/dating/chat/m1',
        overrides: datingChatOverrides(fake),
      );
      fake.cardList = const [_threat];
      fake.signalEvents.add(null);
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      final size =
          t
              .widget<SizeTransition>(
                find.descendant(
                  of: find.byType(DatingSafetyCardView),
                  matching: find.byType(SizeTransition),
                ),
              )
              .sizeFactor
              .value;
      if (reduce) {
        expect(size, 1.0, reason: 'reduce motion');
      } else {
        expect(size, inExclusiveRange(0.0, 1.0));
      }
      await t.pumpAndSettle();
      t.platformDispatcher.clearAccessibilityFeaturesTestValue();
    }
    expect(kDatingCardSlide, const Duration(milliseconds: 150));
  });

  testWidgets('goldens and guidelines with a card', (t) async {
    final fake = FakeDatingChat()..cardList = const [_threat];
    await expectFlowGoldens(
      t,
      'dating_chat_card',
      () => DatingChatScreen(matchId: 'm1', now: () => datingChatT0),
      overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
    );
    await expectFlowGuidelines(t);
  });
}
