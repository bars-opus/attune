// Spec 2 W6c Task 10 fix round 1 (§3.6 meeting kit and check-in; review
// I-1..I-6, M-1, M-2, M-4, M-5, M-7, M-8): the kit reads the server's
// check-in (on open; memory only when it can't), keeps what the server
// did when the kit has gone, shows the check-in with its day and drops it
// once passed, says when no push can arrive; the date picker offers only
// days inside the server's window and a meet outside it says so before
// asking; the share sheet opens from the tapped button, a failure says
// so, and a text falls back to the share sheet; Message someone you
// trust is offered on every path of Get help; Get help reaches S1's v2
// directory; the time picker closes on another account; progress shows;
// the title is read once and the Where field is labelled; the chat's
// lines never squeeze the messages (M-12); the data layer reads Task 8's
// check-in and sends UTC; goldens of the states below Check on me.
import 'dart:async';
import 'dart:convert';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/chat/dating_chat_screen.dart';
import 'package:attune/features/dating/chat/plan_meet_screen.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:attune/features/safety/presentation/screens/support_resources_v2_screen.dart';
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
final _checkin = _meet.add(kDatingCheckinAfter);
const _plan = '/dating/chat/m1/plan';
final _checkOnMe = find.byKey(const ValueKey('dating_plan_check_on_me'));

Future<void> _remember(String place, {DateTime? at}) async {
  await DatingPlanMemory.clear();
  DatingPlanMemory.account = 'ama';
  DatingPlanMemory.place = place;
  DatingPlanMemory.at = at ?? _meet;
}

bool _enabled(WidgetTester t, Finder button) =>
    t
        .widget<ButtonStyleButton>(
          find.descendant(
            of: button,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .onPressed !=
    null;

void main() {
  final loc = AppLocalizationsEn();
  final shared = <(String, Rect?)>[];
  final texts = <(String, Rect?)>[];
  List<Override> kit(FakeDatingChat fake) => [
    ...datingChatOverrides(fake),
    datingShareProvider.overrideWithValue(
      (text, origin) async => shared.add((text, origin)),
    ),
    datingSmsProvider.overrideWithValue(
      (body, origin) async => texts.add((body, origin)),
    ),
  ];
  String setLine(DateTime at) => loc.dating_planCheckinSet(
    MyDateFormat.toDate(at),
    MyDateFormat.toTime(at),
  );

  setUp(() async {
    shared.clear();
    texts.clear();
    await DatingPlanMemory.clear();
  });

  group('I-1: the server\'s check-in', () {
    testWidgets('a check-in set as the kit closed is kept', (t) async {
      await _remember('Osu');
      final fake = FakeDatingChat()..checkinHold = Completer();
      final s = await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
      await tap(t, _checkOnMe);
      s.router.go('/home');
      await t.pumpAndSettle();
      fake.checkinHold!.complete(const DatingChatAnswer(ok: true));
      await t.pumpAndSettle();
      expect(DatingPlanMemory.checkinAt, _checkin);
      // Offline (no read): the kit shows what the server did.
      await pumpDatingShell(
        t,
        initial: _plan,
        online: false,
        overrides: kit(fake),
      );
      expect(find.text(setLine(_checkin)), findsOneWidget);
    });

    testWidgets('a read that fails keeps memory; a read that answers '
        'replaces it (none: no line, no Cancel)', (t) async {
      await _remember('Osu');
      DatingPlanMemory.checkinAt = _checkin;
      final failing = FakeDatingChat()..refusals['checkin'] = 'failed';
      await pumpDatingShell(t, initial: _plan, overrides: kit(failing));
      expect(failing.checkinReads, 1);
      expect(find.text(setLine(_checkin)), findsOneWidget);
      expect(find.text(loc.dating_planCheckinCancel), findsOneWidget);

      final none = FakeDatingChat();
      await pumpDatingShell(t, initial: _plan, overrides: kit(none));
      expect(find.text(setLine(_checkin)), findsNothing);
      expect(find.text(loc.dating_planCheckinCancel), findsNothing);
      expect(DatingPlanMemory.checkinAt, isNull);
    });

    testWidgets('another account reads its own check-in', (t) async {
      await _remember('Osu');
      final fake = FakeDatingChat()..checkinAt = _checkin.toUtc();
      final s = await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
      expect(find.text(setLine(_checkin)), findsOneWidget);
      fake.checkinAt = null;
      s.container.read(datingTestAccount.notifier).state = 'kwame';
      await t.pumpAndSettle();
      expect(fake.checkinReads, greaterThanOrEqualTo(2));
      expect(find.text(setLine(_checkin)), findsNothing);
    });
  });

  group('I-1: reads that the route alone can\'t show', () {
    testWidgets('opened from a chat (the connection already known), the kit '
        'reads the server', (t) async {
      await _remember('Osu');
      final fake = FakeDatingChat()..checkinAt = _checkin.toUtc();
      await pumpDatingShell(
        t,
        initial: '/dating/chat/m1',
        overrides: kit(fake),
      );
      await tap(t, find.byKey(const ValueKey('dating_chat_safety')));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_planTitle));
      await t.pumpAndSettle();
      expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
      expect(find.text(setLine(_checkin)), findsOneWidget);
    });

    testWidgets('alone: another account reads its own check-in', (t) async {
      await _remember('Osu');
      final fake = FakeDatingChat();
      await pumpFlowScreen(
        t,
        () => const DatingPlanMeetScreen(matchId: 'm1'),
        overrides: [...datingShellOverrides(), ...kit(fake)],
      );
      expect(find.text(setLine(_checkin)), findsNothing);
      fake.checkinAt = _checkin.toUtc();
      ProviderScope.containerOf(t.element(find.byType(MaterialApp)))
          .read(datingTestAccount.notifier)
          .state = 'kwame';
      await t.pumpAndSettle();
      expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
      expect(find.text(setLine(_checkin)), findsOneWidget);
    });

    testWidgets('the schedule\'s own answer about push devices wins over the '
        'last read', (t) async {
      await _remember('Osu');
      final fake = FakeDatingChat();
      await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
      // The device went away after the kit read.
      fake.checkinPush = false;
      await tap(t, _checkOnMe);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_planCheckinNoPush), findsOneWidget);
    });
  });

  testWidgets('D8 with the check-in unreadable: another account keeps '
      'nothing of the last plan, the time included', (t) async {
    await _remember('Accra Mall food court');
    final s = await pumpDatingShell(
      t,
      initial: _plan,
      overrides: kit(FakeDatingChat()..refusals['checkin'] = 'failed'),
    );
    expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
    s.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pumpAndSettle();
    expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
    expect(find.text(loc.dating_planPickWhen), findsOneWidget);
    expect(DatingPlanMemory.place, isNull);
    expect(DatingPlanMemory.at, isNull);
  });

  group('I-2: the day, and a check-in that has passed', () {
    testWidgets('a check-in another day shows its day', (t) async {
      await _remember('Osu');
      final later = DateTime(2026, 11, 25, 18, 30);
      await pumpDatingShell(
        t,
        initial: _plan,
        overrides: kit(FakeDatingChat()..checkinAt = later.toUtc()),
      );
      expect(find.text(setLine(later)), findsOneWidget);
      expect(find.textContaining(MyDateFormat.toDate(later)), findsWidgets);
    });

    testWidgets('a check-in whose time has passed is not shown', (t) async {
      await _remember('Osu');
      final past = datingTestNow.subtract(const Duration(minutes: 1));
      await pumpDatingShell(
        t,
        initial: _plan,
        overrides: kit(FakeDatingChat()..checkinAt = past.toUtc()),
      );
      expect(find.text(setLine(past)), findsNothing);
      expect(find.text(loc.dating_planCheckinCancel), findsNothing);
      expect(_enabled(t, _checkOnMe), isTrue);
    });
  });

  group('I-3: no push can arrive', () {
    for (final (why, push, allowed) in [
      ('no device', false, true),
      ('notifications off on this phone', true, false),
    ]) {
      testWidgets('$why: the line says so, never "will check on you"', (
        t,
      ) async {
        await _remember('Osu');
        final fake = FakeDatingChat()..checkinPush = push;
        await pumpDatingShell(
          t,
          initial: _plan,
          overrides: [
            ...kit(fake),
            datingPushAllowedProvider.overrideWithValue(() => allowed),
          ],
        );
        await tap(t, _checkOnMe);
        await t.pumpAndSettle();
        expect(fake.checkins, [_checkin]);
        expect(find.text(loc.dating_planCheckinNoPush), findsOneWidget);
        expect(find.text(setLine(_checkin)), findsNothing);
        expect(find.text(loc.dating_planCheckinCancel), findsOneWidget);
      });
    }
  });

  group('M-2: the window', () {
    test('the last day the picker offers keeps every time inside it', () {
      expect(
        datingPlanLastDay(DateTime(2026, 11, 21, 9)),
        DateTime(2026, 11, 27),
      );
      expect(
        datingPlanLastDay(DateTime(2026, 11, 21, 3, 30)),
        DateTime(2026, 11, 27),
      );
      for (final now in [
        DateTime(2026, 11, 21, 9),
        DateTime(2026, 11, 21, 23, 59),
        DateTime(2026, 11, 30, 2, 58),
      ]) {
        final last = datingPlanLastDay(now);
        expect(
          datingCheckinInWindow(
            DateTime(last.year, last.month, last.day, 23, 59),
            now,
          ),
          isTrue,
          reason: '$now',
        );
      }
    });

    testWidgets('the date picker runs from today to that day', (t) async {
      await _remember('Osu');
      await pumpDatingShell(
        t,
        initial: _plan,
        overrides: kit(FakeDatingChat()),
      );
      await tap(t, find.byKey(const ValueKey('dating_plan_when')));
      await t.pumpAndSettle();
      final dialog = t.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(dialog.firstDate, DateTime(2026, 11, 21));
      expect(dialog.lastDate, datingPlanLastDay(datingTestNow));
    });

    // Final client fix (M-4): a remembered meet that has passed is dropped
    // when the kit opens, so the window is pinned with one still ahead
    // whose check-in falls past the 7 days.
    testWidgets('a meet whose check-in is outside the window says so before '
        'asking', (t) async {
      await _remember('Osu', at: DateTime(2026, 11, 28, 7));
      final fake = FakeDatingChat();
      await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
      expect(find.text(loc.dating_planCheckinInvalid), findsOneWidget);
      expect(_enabled(t, _checkOnMe), isFalse);
      await tap(t, _checkOnMe);
      expect(fake.checkins, isEmpty);
    });
  });

  group('I-5: the share sheet and the text message', () {
    testWidgets('Share opens from the tapped button', (t) async {
      await _remember('Osu');
      await pumpDatingShell(
        t,
        initial: _plan,
        overrides: kit(FakeDatingChat()),
      );
      final button = find.byKey(const ValueKey('dating_plan_share'));
      await tap(t, button);
      expect(shared, hasLength(1));
      expect(shared.single.$2, t.getRect(button));
    });

    testWidgets('a share or text that fails says so', (t) async {
      await _remember('Osu');
      await pumpDatingShell(
        t,
        initial: _plan,
        overrides: [
          ...kit(FakeDatingChat()),
          datingShareProvider.overrideWithValue(
            (text, origin) async => throw StateError('iPad, no origin'),
          ),
        ],
      );
      await tap(t, find.text(loc.dating_planShare));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    });

    testWidgets('a text with no messages app goes to the share sheet, from '
        'the tapped button; with one, only the link opens', (t) async {
      await _remember('Osu');
      final launched = <Uri>[];
      for (final opens in [false, true]) {
        shared.clear();
        launched.clear();
        await pumpDatingShell(
          t,
          initial: _plan,
          overrides: [
            ...datingChatOverrides(FakeDatingChat()),
            datingShareProvider.overrideWithValue(
              (text, origin) async => shared.add((text, origin)),
            ),
            datingLaunchProvider.overrideWithValue((uri) async {
              launched.add(uri);
              return opens;
            }),
          ],
        );
        final button = find.byKey(const ValueKey('dating_plan_sms'));
        await tap(t, button);
        await t.pumpAndSettle();
        final words = datingPlanText(loc, _meet, 'Osu');
        expect(launched, [datingSmsUri(words)], reason: '$opens');
        expect(
          shared,
          opens ? isEmpty : [(words, t.getRect(button))],
          reason: '$opens',
        );
      }
    });
  });

  group('I-6 and I-4: Get help', () {
    final resources = GoRoute(
      path: SafetyResourcesScreen.routeName,
      builder: (_, __) => const Scaffold(body: Text('RESOURCES')),
    );

    testWidgets('Message someone you trust on the confirm itself, and '
        'under Get help after Cancel', (t) async {
      await _remember('Osu');
      await pumpDatingShell(
        t,
        initial: '/dating/checkin',
        extraRoutes: [resources],
        overrides: kit(FakeDatingChat()),
      );
      await tap(t, find.text(loc.dating_checkinHelp));
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('dating_checkin_help_message')));
      await t.pumpAndSettle();
      expect(texts.map((e) => e.$1), [loc.dating_checkinHelpText('Osu')]);
      expect(find.text('RESOURCES'), findsNothing);
      expect(find.text(loc.dating_checkinHelpTitle), findsNothing);
      // Still offered under Get help.
      await tap(t, find.byKey(const ValueKey('dating_checkin_message')));
      expect(texts, hasLength(2));
    });

    testWidgets('a text that can\'t open says so', (t) async {
      await pumpDatingShell(
        t,
        initial: '/dating/checkin',
        overrides: [
          ...kit(FakeDatingChat()),
          datingSmsProvider.overrideWithValue(
            (body, origin) async => throw StateError('nothing opened'),
          ),
        ],
      );
      await tap(t, find.text(loc.dating_checkinHelp));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_blockCancel));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_checkinMessageSomeone));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
    });

    testWidgets('Show opens S1\'s v2 directory (support_resources_v2)', (
      t,
    ) async {
      await pumpDatingShell(
        t,
        initial: '/dating/checkin',
        extraRoutes: [
          GoRoute(
            path: SafetyResourcesScreen.routeName,
            builder: (_, __) => const SafetyResourcesScreen(),
          ),
        ],
        overrides: [
          ...kit(FakeDatingChat()),
          supportResourcesV2Provider.overrideWithValue(true),
        ],
      );
      await tap(t, find.text(loc.dating_checkinHelp));
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_checkinHelpShow));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(SupportResourcesV2Screen), findsOneWidget);
      // The directory's own bundled-catalogue timer.
      await t.pump(const Duration(seconds: 5));
    });
  });

  group('M-4, M-5, M-7, M-8', () {
    testWidgets('M-4: offline, the kit\'s line sits under Check on me only '
        'when Check on me is there', (t) async {
      await DatingPlanMemory.clear();
      await pumpDatingShell(
        t,
        initial: _plan,
        online: false,
        overrides: kit(FakeDatingChat()),
      );
      // No When yet: no Check on me to explain.
      expect(find.text(loc.dating_planCheckOnMeOffline), findsNothing);
      await _remember('Osu');
      await pumpDatingShell(
        t,
        initial: _plan,
        online: false,
        overrides: kit(FakeDatingChat()),
      );
      expect(find.text(loc.dating_planCheckOnMeOffline), findsOneWidget);
    });

    testWidgets('M-5: setting and cancelling show progress', (t) async {
      await _remember('Osu');
      final fake = FakeDatingChat()..checkinHold = Completer();
      await pumpDatingShell(t, initial: _plan, overrides: kit(fake));
      await tap(t, _checkOnMe);
      await t.pump(const Duration(milliseconds: 500));
      expect(
        find.descendant(
          of: _checkOnMe,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      fake.checkinHold!.complete(const DatingChatAnswer(ok: true));
      await t.pumpAndSettle();
      expect(find.text(setLine(_checkin)), findsOneWidget);
    });

    testWidgets('M-7: the check-in\'s title is read once; Where is its own '
        'heading and labels its field', (t) async {
      final semantics = t.ensureSemantics();
      await _remember('Osu');
      await pumpDatingShell(
        t,
        initial: '/dating/checkin',
        overrides: kit(FakeDatingChat()),
      );
      expect(find.bySemanticsLabel(loc.dating_checkinTitle), findsOneWidget);
      await pumpDatingShell(
        t,
        initial: _plan,
        overrides: kit(FakeDatingChat()),
      );
      final field = t.getSemantics(find.byType(EditableText));
      expect(field.label, contains(loc.dating_planWhere));
      expect(field.value, 'Osu');
      expect(field.label, isNot(contains('120')));
      expect(find.bySemanticsLabel(loc.dating_planWhere), findsNWidgets(2));
      semantics.dispose();
    });

    testWidgets('M-8: another account closes the time picker', (t) async {
      await _remember('Osu');
      final s = await pumpDatingShell(
        t,
        initial: _plan,
        overrides: kit(FakeDatingChat()),
      );
      expect(find.byType(DatingPlanMeetScreen), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('dating_plan_when')));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      s.container.read(datingTestAccount.notifier).state = 'kwame';
      await t.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(DatingPlanMemory.at, isNull);
    });

    test('M-8: the data layer reads the check-in and sends UTC', () async {
      final calls = <String>[];
      Object? answer = {
        'ok': true,
        'at': '2026-11-21T18:30:00Z',
        'push': false,
      };
      final repo = DatingChatRepository(
        DatingRpc.withCall((fn, params) async {
          calls.add('$fn ${jsonEncode(params)}');
          return answer;
        }),
        null,
      );
      final read = await repo.checkin();
      expect(read.known, isTrue);
      expect(read.at, DateTime.utc(2026, 11, 21, 18, 30));
      expect(read.push, isFalse);
      answer = {'ok': true, 'at': null, 'push': true};
      expect((await repo.checkin()).at, isNull);
      answer = 'nonsense';
      expect((await repo.checkin()).known, isFalse);
      answer = {'ok': true, 'at': '2026-11-21T18:30:00Z', 'push': true};
      final local = DateTime(2026, 11, 21, 18, 30);
      expect((await repo.scheduleCheckin(local)).push, isTrue);
      final sent = calls.last;
      final at = (jsonDecode(sent.split(' ').last) as Map)['p_at'] as String;
      expect(at, endsWith('Z'));
      expect(DateTime.parse(at).isAtSameMomentAs(local), isTrue);
      expect(calls.first, 'get_my_dating_checkin {}');
    });
  });

  testWidgets('M-1 (M-12): text 2.0 with the keyboard up and every line '
      'under the chat showing, the messages keep their least height', (
    t,
  ) async {
    final fake = FakeDatingChat(
      page: datingPageJson(
        swap: const {'mine': false, 'theirs': true, 'both': false},
      ),
    )..refusals['offerSwap'] = 'rate_limited';
    await pumpDatingShell(
      t,
      initial: '/dating/chat/m1',
      textScale: 2.0,
      overrides: datingChatOverrides(fake),
    );
    t.view.viewInsets = const FakeViewPadding(bottom: 336);
    await t.pumpAndSettle();
    final composer = find.byKey(const ValueKey('dating_chat_composer'));
    await t.enterText(
      composer,
      List.generate(12, (i) => 'Line ${i + 1}').join('\n'),
    );
    await t.pumpAndSettle();
    // A swap refused (the action line) and a re-read that failed (the read
    // line with Try again), both under the chat with the composer.
    await tap(t, find.byKey(const ValueKey('dating_chat_swap')));
    await t.pumpAndSettle();
    await tap(t, find.text(loc.dating_chatSwapConfirm));
    await t.pumpAndSettle();
    fake.refusals['messages'] = 'failed';
    fake.signalEvents.add(null);
    await t.pumpAndSettle();
    expect(find.text(loc.dating_errorRateLimited), findsOneWidget);
    expect(find.text(loc.dating_tryAgain), findsOneWidget);
    final messages = t.getSize(
      find.byKey(const ValueKey('dating_chat_messages')),
    );
    expect(messages.height, greaterThanOrEqualTo(kDatingMessagesMin));
  });

  group('M-8: goldens below Check on me', () {
    Future<void> toEnd(WidgetTester t) async {
      await t.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -3000),
      );
      await t.pumpAndSettle();
    }

    testWidgets('a check-in set (four variants)', (t) async {
      await _remember('Accra Mall food court');
      await expectFlowGoldens(
        t,
        'dating_plan_meet_set',
        () => const DatingPlanMeetScreen(matchId: 'm1'),
        overrides: [
          ...datingShellOverrides(),
          ...kit(FakeDatingChat()..checkinAt = _checkin.toUtc()),
        ],
        before: toEnd,
      );
      await expectFlowGuidelines(t);
    });

    for (final (name, online, push, reason) in [
      ('dating_plan_meet_offline', false, true, null),
      ('dating_plan_meet_nopush', true, false, null),
      ('dating_plan_meet_refused', true, true, 'rate_limited'),
    ]) {
      testWidgets(name, (t) async {
        await _remember('Accra Mall food court');
        final fake =
            FakeDatingChat()
              ..checkinPush = push
              ..checkinAt = push && reason == null ? null : _checkin.toUtc();
        if (reason != null) {
          fake
            ..checkinAt = null
            ..refusals['scheduleCheckin'] = reason;
        }
        await pumpFlowScreen(
          t,
          () => const DatingPlanMeetScreen(matchId: 'm1'),
          overrides: [...datingShellOverrides(online: online), ...kit(fake)],
        );
        if (reason != null) {
          await tap(t, _checkOnMe);
          await t.pumpAndSettle();
        }
        await toEnd(t);
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$name.scale1.0.png'),
        );
      });
    }

    testWidgets('dark: a check-in set', (t) async {
      await _remember('Accra Mall food court');
      await pumpFlowScreen(
        t,
        () => Theme(
          data: AppTheme.darkTheme,
          child: const DatingPlanMeetScreen(matchId: 'm1'),
        ),
        overrides: [
          ...datingShellOverrides(),
          ...kit(FakeDatingChat()..checkinAt = _checkin.toUtc()),
        ],
      );
      await toEnd(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/dating_plan_meet_set.dark.png'),
      );
      await expectFlowGuidelines(t);
    });
  });
}
