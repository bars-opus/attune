// Spec 2 W6c (§3.6): the guided first conversation (the current question;
// Answer sends it as a guided answer; then "{Name} will see your answer
// once {Name} answers too."; Skip this one; the tip after the first
// reveal), the day-7 and day-21 cards (each answered once), Close kindly
// (the reviewed message, confirmed) and We met from the Safety sheet; none
// of it on an ended chat.
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
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
}) {
  final p = datingPageJson(ended: ended);
  final chat = Map<String, Object?>.from(p['chat']! as Map);
  chat['timebox'] = timebox;
  chat['we_met'] = {'mine': weMet, 'theirs': false};
  return {...p, 'chat': chat};
}

void main() {
  final loc = AppLocalizationsEn();

  Future<void> open(WidgetTester t, FakeDatingChat fake) {
    if (fake.guidedState.questionId == null && fake.guidedState.revealed == 0) {
      fake.guidedState = const DatingGuided(questionId: 'good_saturday');
    }
    return pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      overrides: datingChatOverrides(fake),
    );
  }

  testWidgets('the current question; Answer sends it as this side\'s answer; '
      'then the waiting line', (t) async {
    final fake = FakeDatingChat(page: page());
    await open(t, fake);
    expect(find.text(loc.dating_guidedTitle), findsOneWidget);
    expect(find.text(loc.dating_guided_good_saturday), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_guided_answer_button')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('dating_guided_answer')),
      'Market, then football',
    );
    await t.pump();
    fake.guidedState = const DatingGuided(
      questionId: 'good_saturday',
      answered: true,
    );
    await tap(t, find.text(loc.dating_chatSend));
    await t.pumpAndSettle();
    expect(fake.answers.single.$2, 'good_saturday');
    expect(fake.answers.single.$3, 'Market, then football');
    expect(find.text(loc.dating_guidedWaiting('Kofi')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dating_guided_answer_button')),
      findsNothing,
    );
  });

  testWidgets('Skip this one skips the current question; the tip follows '
      'the first reveal', (t) async {
    final fake = FakeDatingChat(page: page());
    await open(t, fake);
    fake.guidedState = const DatingGuided(
      questionId: 'food_every_week',
      revealed: 1,
    );
    await tap(t, find.byKey(const ValueKey('dating_guided_skip')));
    await t.pumpAndSettle();
    expect(fake.skips, ['good_saturday']);
    expect(find.text(loc.dating_guided_food_every_week), findsOneWidget);
    expect(find.text(loc.dating_guidedTip('Kofi')), findsOneWidget);
  });

  testWidgets('day 7: Not yet answers it once; day 21: Close kindly asks '
      'first, then closes', (t) async {
    final fake = FakeDatingChat(page: page(timebox: 'day7'));
    await open(t, fake);
    expect(find.text(loc.dating_timeboxDay7), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_timebox_not_yet')));
    await t.pumpAndSettle();
    expect(fake.timeboxes, ['day7']);
    expect(find.text(loc.dating_timeboxDay7), findsNothing);

    final late = FakeDatingChat(page: page(timebox: 'day21'));
    await open(t, late);
    expect(find.text(loc.dating_timeboxDay21), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_timebox_close')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_closeKindlyTitle), findsOneWidget);
    expect(find.text(loc.dating_closeKindlyMessage), findsOneWidget);
    await tap(t, find.text(loc.dating_closeKindlySend));
    await t.pumpAndSettle();
    expect(late.kindCloses.length, 1);
    expect(late.timeboxes, ['day21']);
  });

  testWidgets('the Safety sheet offers Close kindly and We met (once)', (
    t,
  ) async {
    final fake = FakeDatingChat(page: page());
    await open(t, fake);
    await tap(t, find.byKey(const ValueKey('dating_chat_safety')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_closeKindly), findsOneWidget);
    await tap(t, find.text(loc.dating_weMet));
    await t.pumpAndSettle();
    expect(fake.weMets, 1);

    final met = FakeDatingChat(page: page(weMet: true));
    await open(t, met);
    await tap(t, find.byKey(const ValueKey('dating_chat_safety')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_weMet), findsNothing);
  });

  testWidgets('an ended chat shows no guided or timebox card', (t) async {
    final fake = FakeDatingChat(page: page(timebox: 'day21', ended: true));
    await open(t, fake);
    expect(find.text(loc.dating_guidedTitle), findsNothing);
    expect(find.text(loc.dating_timeboxDay21), findsNothing);
    expect(find.text(loc.dating_chatEnded), findsOneWidget);
  });

  testWidgets('goldens and guidelines with the guided and day-7 cards', (
    t,
  ) async {
    final fake = FakeDatingChat(page: page(timebox: 'day7'))
      ..guidedState = const DatingGuided(questionId: 'good_saturday');
    await expectFlowGoldens(
      t,
      'dating_chat_guided',
      () => DatingChatScreen(matchId: 'm1', now: () => datingChatT0),
      overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
    );
    await expectFlowGuidelines(t);
  });
}
