// Spec 2 W6c Task 10 rulings (§3.6 meeting kit and check-in, §3.15 Meeting
// kit; D8, D20; R-46): a refused check-in says why (invalid, rate_limited,
// closed and anything else); offline, Share and Send still work and Check
// on me and Cancel wait; a new When offers Check on me again and the kit
// shows the check-in it set when opened again; another account closes the
// date picker and the Get help confirm (each on screen first) and keeps
// nothing of the last plan, the time included; quick exit and the Dating
// lock close them too; the only page has a way back; the plan card waits
// on an ended chat; the text message link is percent-encoded; the data
// layer calls Task 8's RPCs; dark.
import 'dart:async';
import 'dart:convert';

import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/chat/checkin_screen.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
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
const _plan = '/dating/chat/m1/plan';

Future<void> _remember(String place, {DateTime? checkinAt}) async {
  await DatingPlanMemory.clear();
  DatingPlanMemory.account = 'ama';
  DatingPlanMemory.place = place;
  DatingPlanMemory.at = _meet;
  DatingPlanMemory.checkinAt = checkinAt;
}

Future<void> _quickExit(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.tap(find.byKey(const Key('quick_exit_zone')), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle(const Duration(milliseconds: 400));
}

/// When's pickers, both answered with what they open on.
Future<void> _pickNow(WidgetTester t) async {
  await tap(t, find.byKey(const ValueKey('dating_plan_when')));
  await t.pumpAndSettle();
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
}

void main() {
  final loc = AppLocalizationsEn();
  final shared = <String>[];
  final texts = <String>[];
  List<Override> kit(FakeDatingChat fake) => [
    ...datingChatOverrides(fake),
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

  setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));
  setUp(() async {
    shared.clear();
    texts.clear();
    await DatingPlanMemory.clear();
    QuickExitService.clearStories = () async {};
    addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
  });

  testWidgets('a refused check-in says why, and sets nothing', (t) async {
    for (final (reason, line) in [
      ('invalid', loc.dating_planCheckinInvalid),
      ('rate_limited', loc.dating_errorRateLimited),
      ('closed', loc.dating_errorGeneric),
      ('busy', loc.dating_errorGeneric),
      ('failed', loc.dating_errorGeneric),
    ]) {
      await _remember('Osu');
      final fake = FakeDatingChat()..refusals['scheduleCheckin'] = reason;
      await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
      await tap(t, find.text(loc.dating_planCheckOnMe));
      await t.pumpAndSettle();
      expect(fake.checkins, [_meet.add(kDatingCheckinAfter)], reason: reason);
      expect(find.text(line), findsOneWidget, reason: reason);
      expect(find.text(loc.dating_planCheckinCancel), findsNothing);
      expect(DatingPlanMemory.checkinAt, isNull, reason: reason);
      expect(find.text(loc.dating_planCheckOnMe), findsOneWidget);
    }
  });

  testWidgets('a refused cancel keeps the check-in and says so', (t) async {
    final at = _meet.add(kDatingCheckinAfter);
    await _remember('Osu', checkinAt: at);
    final fake =
        FakeDatingChat()
          ..refusals['cancelCheckin'] = 'failed'
          ..checkinAt = at;
    await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
    await tap(t, find.text(loc.dating_planCheckinCancel));
    await t.pumpAndSettle();
    expect(fake.checkins, [null]);
    expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    expect(
      find.text(
        loc.dating_planCheckinSet(
          MyDateFormat.toDate(at),
          MyDateFormat.toTime(at),
        ),
      ),
      findsOneWidget,
    );
    expect(DatingPlanMemory.checkinAt, at);
  });

  testWidgets('offline: Share and Send work; Check on me and Cancel wait', (
    t,
  ) async {
    await _remember('Osu');
    final fake = FakeDatingChat();
    await pumpDatingShell(
      t,
      initial: _plan,
      online: false,
      overrides: kit(fake),
    );
    // Fix round 1 (M-4): the kit's own line, under Check on me only.
    expect(find.text(loc.dating_planCheckOnMeOffline), findsOneWidget);
    expect(find.text(loc.dating_offline), findsNothing);
    await tap(t, find.text(loc.dating_planShare));
    await tap(t, find.text(loc.dating_planSms));
    expect(shared, hasLength(1));
    expect(texts, hasLength(1));
    await tap(t, find.text(loc.dating_planCheckOnMe));
    expect(fake.checkins, isEmpty);

    await _remember('Osu', checkinAt: _meet.add(kDatingCheckinAfter));
    await pumpDatingShell(
      t,
      initial: _plan,
      online: false,
      overrides: kit(fake),
    );
    await tap(t, find.text(loc.dating_planCheckinCancel));
    expect(fake.checkins, isEmpty);
  });

  testWidgets('the kit shows the server\'s check-in when opened (even with '
      'nothing in memory); a new When offers Check on me again, which '
      'replaces it (R-46)', (t) async {
    await _remember('Osu');
    // Set from another phone, or before quick exit: only the server knows.
    DatingPlanMemory.checkinAt = null;
    final first = DateTime(2026, 11, 22, 12);
    final fake = FakeDatingChat()..checkinAt = first.toUtc();
    await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
    expect(fake.checkinReads, 1);
    expect(
      find.text(
        loc.dating_planCheckinSet(
          MyDateFormat.toDate(first),
          MyDateFormat.toTime(first),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(loc.dating_planCheckinCancel), findsOneWidget);
    expect(DatingPlanMemory.checkinAt, first);
    // The plan's meet is another time: Check on me again replaces it.
    expect(find.text(loc.dating_planCheckOnMe), findsOneWidget);
    await tap(t, find.text(loc.dating_planCheckOnMe));
    await t.pumpAndSettle();
    final at = _meet.add(kDatingCheckinAfter);
    expect(fake.checkins, [at]);
    expect(
      find.text(
        loc.dating_planCheckinSet(
          MyDateFormat.toDate(at),
          MyDateFormat.toTime(at),
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(loc.dating_planCheckOnMe), findsNothing);

    // Opened again: still the server's (now the new one).
    await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
    expect(find.text(loc.dating_planCheckinCancel), findsOneWidget);
    expect(find.text(loc.dating_planCheckOnMe), findsNothing);
  });

  testWidgets('D8: another account closes the date picker and keeps '
      'nothing of the plan, the time included', (t) async {
    await _remember('Accra Mall food court');
    final s = await pumpDatingShell(
      t,
      initial: _plan,
      overrides: kit(FakeDatingChat()),
    );
    expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
    await tap(t, find.byKey(const ValueKey('dating_plan_when')));
    await t.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    s.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
    expect(find.text(loc.dating_planPickWhen), findsOneWidget);
    expect(DatingPlanMemory.place, isNull);
    expect(DatingPlanMemory.at, isNull);
    expect(DatingPlanMemory.checkinAt, isNull);
  });

  testWidgets('D8: a check-in answered after the account changed sets '
      'nothing, and the next account can ask', (t) async {
    await _remember('Osu');
    final fake = FakeDatingChat()..checkinHold = Completer();
    final s = await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
    await tap(t, find.text(loc.dating_planCheckOnMe));
    s.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    fake.checkinHold!.complete(const DatingChatAnswer(ok: true));
    await t.pumpAndSettle();
    expect(find.textContaining('Attune will check on you'), findsNothing);
    expect(DatingPlanMemory.checkinAt, isNull);
    fake.checkinHold = null;
    await _pickNow(t);
    await tap(t, find.text(loc.dating_planCheckOnMe));
    await t.pumpAndSettle();
    expect(fake.checkins, hasLength(2));
    expect(DatingPlanMemory.account, 'kwame');
  });

  testWidgets('D8: another account closes Get help\'s confirm, choosing '
      'nothing, and hides Message someone you trust', (t) async {
    await _remember('Osu');
    final s = await pumpDatingShell(
      t,
      initial: '/dating/checkin',
      extraRoutes: [resources],
      overrides: kit(FakeDatingChat()),
    );
    expect(find.byType(DatingCheckinScreen), findsOneWidget);
    await tap(t, find.text(loc.dating_checkinHelp));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_checkinHelpTitle), findsOneWidget);
    s.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pumpAndSettle();
    expect(find.text(loc.dating_checkinHelpTitle), findsNothing);
    expect(find.text('RESOURCES'), findsNothing);
    expect(find.byType(DatingCheckinScreen), findsOneWidget);

    s.container.read(datingTestAccount.notifier).state = 'ama';
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_checkinHelp));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_checkinHelpShow));
    await t.pumpAndSettle();
    s.router.pop();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_checkinMessageSomeone), findsOneWidget);
    s.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pumpAndSettle();
    expect(find.text(loc.dating_checkinMessageSomeone), findsNothing);
    await tap(t, find.text(loc.dating_checkinHelp));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_checkinHelpShow));
    await t.pumpAndSettle();
    s.router.pop();
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_checkinMessageSomeone));
    // The last account's place is never in the next one's text.
    expect(texts, [loc.dating_checkinHelpTextNoPlace]);
  });

  // The screens alone (no Dating lock gate, which builds a new page for
  // another account): their own account guards (R-35's "either alone").
  ProviderContainer containerOf(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

  testWidgets('alone, D8: a check-in in flight when the account changed '
      'leaves Check on me free for the next account', (t) async {
    await _remember('Osu');
    final fake = FakeDatingChat()..checkinHold = Completer();
    await pumpFlowScreen(
      t,
      () => const DatingPlanMeetScreen(matchId: 'm1'),
      overrides: [...datingShellOverrides(), ...kit(fake)],
    );
    await tap(t, find.text(loc.dating_planCheckOnMe));
    containerOf(t).read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    fake.checkinHold!.complete(const DatingChatAnswer(ok: true));
    await t.pumpAndSettle();
    expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
    fake.checkinHold = null;
    await _pickNow(t);
    await tap(t, find.text(loc.dating_planCheckOnMe));
    await t.pumpAndSettle();
    expect(fake.checkins, hasLength(2));
  });

  testWidgets('alone, D8: another account hides Message someone you trust', (
    t,
  ) async {
    await _remember('Osu');
    final h = await pumpFlowScreen(
      t,
      () => const DatingCheckinScreen(),
      overrides: [...datingShellOverrides(), ...kit(FakeDatingChat())],
    );
    await tap(t, find.text(loc.dating_checkinHelp));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_checkinHelpShow));
    await t.pumpAndSettle();
    expect(find.text('at /safety-resources'), findsOneWidget);
    h.router.pop();
    await t.pumpAndSettle();
    expect(find.text(loc.dating_checkinMessageSomeone), findsOneWidget);
    containerOf(t).read(datingTestAccount.notifier).state = 'kwame';
    await t.pumpAndSettle();
    expect(find.byType(DatingCheckinScreen), findsOneWidget);
    expect(find.text(loc.dating_checkinMessageSomeone), findsNothing);
  });

  testWidgets('quick exit closes Get help\'s confirm and the date picker, '
      'and forgets the plan', (t) async {
    await _remember('Osu');
    for (final (path, open, gone) in [
      (
        '/dating/checkin',
        find.text(loc.dating_checkinHelp),
        find.text(loc.dating_checkinHelpTitle),
      ),
      (
        _plan,
        find.byKey(const ValueKey('dating_plan_when')),
        find.byType(DatePickerDialog),
      ),
    ]) {
      await pumpDatingShell(
        t,
        initial: path,
        overrides: kit(FakeDatingChat()),
        wrap: (router, child) => QuickExitZone(router: router, child: child),
      );
      await tap(t, open);
      await t.pumpAndSettle();
      expect(gone, findsOneWidget, reason: path);
      await _quickExit(t);
      expect(find.text('DECOY'), findsOneWidget, reason: path);
      expect(gone, findsNothing, reason: path);
      expect(
        find.byType(DatingCheckinScreen, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byType(DatingPlanMeetScreen, skipOffstage: false),
        findsNothing,
      );
      expect(DatingPlanMemory.place, isNull, reason: path);
    }
  });

  testWidgets('the Dating lock closes Get help\'s confirm and the date '
      'picker: the Safety PIN first', (t) async {
    for (final (path, open, gone) in [
      (
        '/dating/checkin',
        find.text(loc.dating_checkinHelp),
        find.text(loc.dating_checkinHelpTitle),
      ),
      (
        _plan,
        find.byKey(const ValueKey('dating_plan_when')),
        find.byType(DatePickerDialog),
      ),
    ]) {
      final s = await pumpDatingShell(
        t,
        initial: path,
        locked: true,
        pinSet: true,
        overrides: kit(FakeDatingChat()),
      );
      expect(s.location, startsWith('/dating/unlock?from='));
      s.container.read(datingUnlockedProvider.notifier).unlock();
      s.router.go(path);
      await t.pumpAndSettle();
      await tap(t, open);
      await t.pumpAndSettle();
      expect(gone, findsOneWidget, reason: path);
      s.container.read(datingUnlockedProvider.notifier).lock();
      await t.pumpAndSettle();
      expect(gone, findsNothing, reason: path);
      expect(s.location, startsWith('/dating/unlock?from='), reason: path);
      expect(find.text('Enter your Safety PIN'), findsOneWidget);
    }
  });

  testWidgets('the only page has a way back: the kit to its chat, the '
      'check-in home', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: _plan,
      overrides: kit(FakeDatingChat()),
    );
    await tap(t, find.byKey(const ValueKey('dating_root_back')));
    await t.pumpAndSettle();
    expect(s.location, '/dating/chat/m1');
    final c = await pumpDatingShell(
      t,
      initial: '/dating/checkin',
      overrides: kit(FakeDatingChat()),
    );
    await tap(t, find.byKey(const ValueKey('dating_root_back')));
    await t.pumpAndSettle();
    expect(c.location, '/home');
    final ok = await pumpDatingShell(
      t,
      initial: '/dating/checkin',
      overrides: kit(FakeDatingChat()),
    );
    await tap(t, find.text(loc.dating_checkinOk));
    await t.pumpAndSettle();
    expect(ok.location, '/home');
  });

  testWidgets('an ended chat offers no Plan a meet (Safety sheet, card)', (
    t,
  ) async {
    final ended = FakeDatingChat(page: datingPageJson(ended: true))
      ..cardList = const [
        DatingSafetyCard(
          id: 'e2',
          messageId: 'd1',
          family: 'meet_private_pressure',
        ),
      ];
    await pumpDatingShell(t, initial: '/dating/chat/m1', overrides: kit(ended));
    expect(find.byKey(const ValueKey('dating_card_e2')), findsOneWidget);
    expect(find.byKey(const ValueKey('dating_card_plan')), findsNothing);
    await tap(t, find.byKey(const ValueKey('dating_chat_safety')));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_chatSafety), findsOneWidget);
    expect(find.text(loc.dating_planTitle), findsNothing);
  });

  testWidgets('the day-7 card\'s Plan a meet offline: the kit opens, the '
      'card waits to be dismissed', (t) async {
    final page = datingPageJson();
    final chat = Map<String, Object?>.from(page['chat']! as Map)
      ..['timebox'] = 'day7';
    final day7 = FakeDatingChat(page: {...page, 'chat': chat});
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      online: false,
      overrides: kit(day7),
    );
    await tap(t, find.byKey(const ValueKey('dating_timebox_plan')));
    await t.pumpAndSettle();
    expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
    expect(day7.timeboxes, isEmpty);
  });

  test('the text message link is percent-encoded (never "+")', () {
    expect(
      datingSmsUri(
        'I need help. I\'m at Osu & Labone. Please call me.',
      ).toString(),
      'sms:?body=I%20need%20help.%20I\'m%20at%20Osu%20%26%20Labone.%20Please%20call%20me.',
    );
  });

  test('the data layer calls Task 8\'s RPCs', () async {
    final calls = <String>[];
    var answer = <String, Object?>{'ok': true};
    final repo = DatingChatRepository(
      DatingRpc.withCall((fn, params) async {
        calls.add('$fn ${jsonEncode(params)}');
        return answer;
      }),
      null,
    );
    expect(
      (await repo.scheduleCheckin(DateTime.utc(2026, 11, 21, 18, 30))).ok,
      isTrue,
    );
    expect((await repo.cancelCheckin()).ok, isTrue);
    answer = {'ok': false, 'reason': 'invalid'};
    expect(
      (await repo.scheduleCheckin(DateTime.utc(2026, 12, 1))).reason,
      'invalid',
    );
    answer = {'ok': false, 'reason': 'something else'};
    expect(
      (await repo.scheduleCheckin(DateTime.utc(2026, 12, 1))).reason,
      'failed',
    );
    expect(calls.take(2), [
      'schedule_dating_checkin {"p_at":"2026-11-21T18:30:00.000Z"}',
      'cancel_dating_checkin {}',
    ]);
  });

  testWidgets('the manual: the meeting kit, and the check-in push as the '
      'server words it', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    String content(String id) =>
        DatingModeDocs()
            .getSections(context)
            .expand((s) => s.contents)
            .firstWhere((c) => c.id == id)
            .content;
    // schedule_dating_checkin's body, word for word.
    for (final id in ['dating_meet', 'dating_notifications']) {
      expect(content(id), contains('"A quick check-in from Attune."'));
    }
    final meet = content('dating_meet');
    for (final words in [
      'Plan a meet',
      'Share my plan',
      'Check on me',
      'three hours after the meet',
      'Get help asks first',
      'needs notifications on',
      'never includes the other person\'s name or photo',
      'quick exit forgets it',
      'Only the check-in time you ask for is kept',
    ]) {
      expect(meet, contains(words));
    }
  });

  testWidgets('dark: the meeting kit and the check-in (goldens)', (t) async {
    await _remember('Accra Mall food court');
    for (final (name, screen) in [
      ('dating_plan_meet', const DatingPlanMeetScreen(matchId: 'm1')),
      ('dating_checkin', const DatingCheckinScreen()),
    ]) {
      await pumpFlowScreen(
        t,
        () => Theme(data: AppTheme.darkTheme, child: screen),
        overrides: [...datingShellOverrides(), ...kit(FakeDatingChat())],
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.dark.png'),
      );
      await expectFlowGuidelines(t);
    }
  });
}
