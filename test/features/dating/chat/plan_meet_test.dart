// Spec 2 W6c (§3.6 meeting kit and check-in, §3.15 Meeting kit; D20, S21):
// Plan a meet (the checklist; When and Where in memory only; Share my plan
// and Send as text message with the plan's words and never the match's
// name; Check on me three hours after the meet, cancellable); the entries
// (the Safety sheet, the day-7 card, the meet-in-private card only); the
// plan forgotten by quick exit, sign-out and another account; the
// check-in (I'm OK, Get help asks first, then the support directory and a
// text the person sends; We met; Not now).
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/chat/checkin_screen.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
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

final _meet = DateTime(2026, 11, 21, 15, 30);

Future<void> _remember(String place) async {
  await DatingPlanMemory.clear();
  DatingPlanMemory.account = 'ama';
  DatingPlanMemory.place = place;
  DatingPlanMemory.at = _meet;
}

void main() {
  final loc = AppLocalizationsEn();
  final shared = <String>[];
  final texts = <String>[];
  List<Override> kit(FakeDatingChat fake) => [
    ...datingChatOverrides(fake),
    // Task 10 fix round 1 (I-5): both take the tapped button's rect.
    datingShareProvider.overrideWithValue(
      (text, origin) async => shared.add(text),
    ),
    datingSmsProvider.overrideWithValue(
      (body, origin) async => texts.add(body),
    ),
  ];
  final resources = GoRoute(
    path: SafetyResourcesScreen.routeName,
    builder: (_, __) => const Scaffold(body: Text('RESOURCES')),
  );

  setUp(() async {
    shared.clear();
    texts.clear();
    await DatingPlanMemory.clear();
  });

  testWidgets('the checklist; Share and Send wait for When and Where; the '
      'words carry the plan and never the name', (t) async {
    final fake = FakeDatingChat();
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1/plan',
      overrides: kit(fake),
    );
    for (final line in [
      loc.dating_planCheck1,
      loc.dating_planCheck2,
      loc.dating_planCheck3,
      loc.dating_planCheck4,
      loc.dating_planCheck5,
    ]) {
      expect(find.text(line), findsOneWidget);
    }
    await tap(t, find.text(loc.dating_planShare));
    expect(shared, isEmpty);

    await _remember('Accra Mall food court');
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1/plan',
      overrides: kit(fake),
    );
    expect(find.text('Accra Mall food court'), findsOneWidget);
    await tap(t, find.text(loc.dating_planShare));
    await tap(t, find.text(loc.dating_planSms));
    final words = loc.dating_planShareText(
      MyDateFormat.toDate(_meet),
      MyDateFormat.toTime(_meet),
      'Accra Mall food court',
      MyDateFormat.toTime(_meet.add(const Duration(hours: 3))),
    );
    expect(shared, [words]);
    expect(texts, [words]);
    expect(words, isNot(contains('Kofi')));
  });

  testWidgets('Check on me asks for one push three hours after the meet; '
      'Cancel takes it back', (t) async {
    await _remember('Accra Mall food court');
    final fake = FakeDatingChat();
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1/plan',
      overrides: kit(fake),
    );
    await tap(t, find.text(loc.dating_planCheckOnMe));
    await t.pumpAndSettle();
    expect(fake.checkins, [_meet.add(kDatingCheckinAfter)]);
    expect(kDatingCheckinAfter, const Duration(hours: 3));
    expect(
      find.text(
        // Task 10 fix round 1 (I-2): with its day.
        loc.dating_planCheckinSet(
          MyDateFormat.toDate(_meet.add(kDatingCheckinAfter)),
          MyDateFormat.toTime(_meet.add(kDatingCheckinAfter)),
        ),
      ),
      findsOneWidget,
    );
    await tap(t, find.text(loc.dating_planCheckinCancel));
    await t.pumpAndSettle();
    expect(fake.checkins.last, isNull);
    expect(find.text(loc.dating_planCheckOnMe), findsOneWidget);
  });

  testWidgets('another account sees no plan; quick exit and sign-out forget '
      'it', (t) async {
    await _remember('Accra Mall food court');
    final s = await pumpDatingShell(
      t,
      initial: '/dating/chat/m1/plan',
      overrides: kit(FakeDatingChat()),
    );
    expect(find.text(loc.dating_planTitle), findsWidgets);
    expect(find.text('Accra Mall food court'), findsOneWidget);
    s.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pumpAndSettle();
    expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
    expect(find.text(loc.dating_planCheck1), findsOneWidget);
    expect(find.text('Accra Mall food court'), findsNothing);
    expect(DatingPlanMemory.place, isNull);

    for (final moment in [WipeMoment.quickExit, WipeMoment.signOut]) {
      await _remember('Osu');
      final registry = DeviceWipeRegistry();
      registerDatingDeviceWipes(registry);
      await registry.run(moment);
      expect(DatingPlanMemory.place, isNull, reason: '$moment');
      expect(DatingPlanMemory.at, isNull, reason: '$moment');
    }
  });

  testWidgets('Plan a meet from the Safety sheet, the day-7 card and the '
      'meet-in-private card (not the threat card)', (t) async {
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      overrides: kit(FakeDatingChat()),
    );
    expect(find.text(loc.dating_planCheck1), findsNothing);
    await tap(t, find.byKey(const ValueKey('dating_chat_safety')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_planTitle));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_planCheck1), findsOneWidget);
    expect(find.byType(DatingPlanMeetScreen), findsOneWidget);

    final page = datingPageJson();
    final chat = Map<String, Object?>.from(page['chat']! as Map)
      ..['timebox'] = 'day7';
    final day7 = FakeDatingChat(page: {...page, 'chat': chat});
    await pumpDatingShell(t, initial: '/dating/chat/m1', overrides: kit(day7));
    await tap(t, find.byKey(const ValueKey('dating_timebox_plan')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_planCheck1), findsOneWidget);
    expect(day7.timeboxes, ['day7']);

    final cards =
        FakeDatingChat()
          ..cardList = const [
            DatingSafetyCard(
              id: 'e1',
              messageId: 'd2',
              family: 'threat_intimidation',
            ),
            DatingSafetyCard(
              id: 'e2',
              messageId: 'd1',
              family: 'meet_private_pressure',
            ),
          ];
    await pumpDatingShell(t, initial: '/dating/chat/m1', overrides: kit(cards));
    expect(find.byKey(const ValueKey('dating_card_plan')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dating_card_e2')),
        matching: find.byKey(const ValueKey('dating_card_plan')),
      ),
      findsOneWidget,
    );
    await tap(t, find.byKey(const ValueKey('dating_card_plan')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_planCheck1), findsOneWidget);
  });

  testWidgets('the check-in: Get help asks first, then the support '
      'directory and a text the person sends', (t) async {
    await _remember('Osu');
    final s = await pumpDatingShell(
      t,
      initial: '/dating/checkin',
      extraRoutes: [resources],
      overrides: kit(FakeDatingChat()),
    );
    for (final label in [
      loc.dating_checkinOk,
      loc.dating_checkinHelp,
      loc.dating_weMet,
      loc.dating_checkinNotNow,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text(loc.dating_checkinMessageSomeone), findsNothing);
    await tap(t, find.text(loc.dating_checkinHelp));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_checkinHelpTitle), findsOneWidget);
    expect(find.text('RESOURCES'), findsNothing);
    await tap(t, find.text(loc.dating_checkinHelpShow));
    await t.pumpAndSettle();
    expect(find.text('RESOURCES'), findsOneWidget);
    s.router.pop();
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_checkinMessageSomeone));
    expect(texts, [loc.dating_checkinHelpText('Osu')]);
    expect(texts.single, 'I need help. I\'m at Osu. Please call me.');

    await DatingPlanMemory.clear();
    await pumpDatingShell(
      t,
      initial: '/dating/checkin',
      extraRoutes: [resources],
      overrides: kit(FakeDatingChat()),
    );
    await tap(t, find.text(loc.dating_checkinHelp));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_blockCancel));
    await t.pumpAndSettle();
    expect(find.text('RESOURCES'), findsNothing);
    // Task 10 fix round 1 (I-6): Cancel leaves the silent text offered.
    expect(find.text(loc.dating_checkinMessageSomeone), findsOneWidget);
  });

  testWidgets('We met opens the conversations; Not now leaves', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: '/dating/checkin',
      overrides: kit(FakeDatingChat()),
    );
    await tap(t, find.text(loc.dating_weMet));
    await t.pumpAndSettle();
    expect(s.location, '/dating/chats');
    final n = await pumpDatingShell(
      t,
      initial: '/dating/checkin',
      overrides: kit(FakeDatingChat()),
    );
    await tap(t, find.text(loc.dating_checkinNotNow));
    await t.pumpAndSettle();
    expect(n.location, startsWith('/home'));
  });

  testWidgets('goldens and guidelines: the meeting kit and the check-in', (
    t,
  ) async {
    await _remember('Accra Mall food court');
    await expectFlowGoldens(
      t,
      'dating_plan_meet',
      () => const DatingPlanMeetScreen(matchId: 'm1'),
      overrides: [...datingShellOverrides(), ...kit(FakeDatingChat())],
    );
    await expectFlowGuidelines(t);
    await expectFlowGoldens(
      t,
      'dating_checkin',
      () => const DatingCheckinScreen(),
      overrides: [...datingShellOverrides(), ...kit(FakeDatingChat())],
    );
    await expectFlowGuidelines(t);
  });
}
