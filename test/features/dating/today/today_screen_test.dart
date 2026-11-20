// Spec 2 W5b (§3.1, §3.4, §3.5, §3.15, §5.6, §7.4; D8): Today and the
// match moment. Each day state in its own words (never a date on a card);
// Interested says Noted once; Not for me collapses and holds the answer
// for its undo window (5 s, 20 s with a screen reader), sent when the
// window ends, at the next answer, or when the screen closes, and never as
// the next account; offline the actions wait; refusals are calm or the
// error line; data saver waits for a tap; the family question and the
// quiet note once; Widen opens the editors and comes back; the moment once,
// marked seen, no motion under reduce motion; the section opens Today.
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/match_moment_screen.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

/// tapInReach, then the frames its answer starts.
Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  final loc = AppLocalizationsEn();

  setUp(() async {
    datingFetched.clear();
    await DatingPhotoMemory.clear();
  });

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingToday fake, {
    bool online = true,
    String initial = DatingPaths.today,
  }) => pumpDatingShell(
    t,
    initial: initial,
    online: online,
    overrides: datingTodayOverrides(fake),
  );

  group('the day', () {
    testWidgets('each state in its own words; no date on any card', (t) async {
      final at = DateTime.utc(2026, 11, 20, 19);
      for (final (state, line) in [
        ('before_drop', loc.dating_todayBeforeDrop('19:00')),
        ('empty', loc.dating_todayEmpty(loc.dating_region_gh_aa)),
        ('queue_full', loc.dating_todayQueueFull),
        ('paused_open_chats', loc.dating_todayPausedChats),
      ]) {
        final fake = FakeDatingToday(
          today: datingTodayJson({
            'today_state': state,
            'cards': <Object?>[],
            'drop_at': at.toIso8601String(),
          }),
        );
        await open(t, fake);
        expect(
          find.textContaining(line.split('{').first.substring(0, 20)),
          findsOneWidget,
          reason: state,
        );
      }
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'waiting': [
            datingCardJson('w1', {'display_name': 'Esi'}),
          ],
        }),
      );
      await open(t, fake);
      expect(find.text(loc.dating_todayWaiting), findsOneWidget);
      expect(find.text(loc.dating_cardWhyTitle), findsNWidgets(2));
      expect(find.text(loc.dating_reasonSameCommitted), findsNWidgets(2));
      expect(find.text(loc.dating_cardChemistry), findsNWidgets(2));
      expect(
        find.textContaining(RegExp(r'\b(20|19):00\b|expire|left|ago')),
        findsNothing,
      );
    });

    testWidgets(
      'the refusals: the re-check, calm busy, the error line and Retry; offline',
      (t) async {
        final fake = FakeDatingToday(today: {'ok': false, 'reason': 'busy'});
        await open(t, fake);
        expect(find.text(loc.dating_busy), findsOneWidget);
        fake.json = datingTodayJson();
        await tap(t, find.text(loc.dating_tryAgain));
        expect(find.text(loc.dating_cardInterested), findsOneWidget);
        await open(
          t,
          FakeDatingToday(today: {'ok': false, 'reason': 'reverify_device'}),
        );
        expect(find.text(loc.dating_sectionReverify), findsOneWidget);
        await open(
          t,
          FakeDatingToday(today: {'ok': false, 'reason': 'a server text'}),
        );
        expect(find.text(loc.dating_errorGeneric), findsOneWidget);
        expect(find.textContaining('server text'), findsNothing);
        final offline = FakeDatingToday();
        await open(t, offline, online: false);
        expect(find.text(loc.dating_offline), findsOneWidget);
        await tap(t, find.text(loc.dating_cardInterested));
        expect(offline.acts, isEmpty);
      },
    );
  });

  group('the answers', () {
    testWidgets('Interested: "Noted." once; a double tap sends one answer', (
      t,
    ) async {
      final fake = FakeDatingToday();
      await open(t, fake);
      // T7 fix 1 (M-9): two taps before the first answer lands.
      final interested = find.text(loc.dating_cardInterested);
      await bringIntoReach(t, interested);
      await t.tap(interested);
      await t.tap(interested);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(loc.dating_cardNoted('Kofi')), findsOneWidget);
      expect(find.text(loc.dating_cardInterested), findsNothing);
      expect(fake.acts.map((a) => a.$3), ['interested']);
      expect(fake.acts.single.$1.length, greaterThanOrEqualTo(16));
    });

    testWidgets(
      'Not for me: the card goes, Undo brings it back and sends nothing',
      (t) async {
        final fake = FakeDatingToday();
        await open(t, fake);
        await tap(t, find.text(loc.dating_cardNotForMe));
        expect(find.text(loc.dating_cardInterested), findsNothing);
        expect(find.text(loc.dating_cardNotForMeDone), findsOneWidget);
        await t.tap(find.text(loc.dating_undo));
        await t.pumpAndSettle();
        expect(find.text(loc.dating_cardInterested), findsOneWidget);
        await t.pump(const Duration(seconds: 30));
        expect(fake.acts, isEmpty);
      },
    );

    testWidgets(
      'the window: 5 s, then sent once; 20 s with a screen reader (§7.4)',
      (t) async {
        final fake = FakeDatingToday();
        await open(t, fake);
        await tap(t, find.text(loc.dating_cardNotForMe));
        await t.pump(const Duration(seconds: 4));
        expect(fake.acts, isEmpty);
        await t.pump(const Duration(seconds: 2));
        expect(fake.acts.map((a) => a.$3), ['passed']);
        await t.pump(const Duration(seconds: 30));
        expect(fake.acts, hasLength(1));
        // T7 fix 1 (I-1): the bar went with its window.
        expect(find.text(loc.dating_cardNotForMeDone), findsNothing);

        final reader = FakeDatingToday();
        t.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(accessibleNavigation: true);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
        await open(t, reader);
        await tap(t, find.text(loc.dating_cardNotForMe));
        await t.pump(const Duration(seconds: 19));
        expect(reader.acts, isEmpty);
        await t.pump(const Duration(seconds: 2));
        expect(reader.acts.map((a) => a.$3), ['passed']);
        // T7 fix 1 (I-1): a screen reader keeps a bar with an action up
        // until it is dismissed; the sent pass takes it down (no Undo left
        // that would undo nothing).
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text(loc.dating_cardNotForMeDone), findsNothing);
        expect(find.text(loc.dating_undo), findsNothing);
      },
    );

    testWidgets('the next answer, or leaving, sends the held one first', (
      t,
    ) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'cards': [
            datingCardJson('a'),
            datingCardJson('b', {'display_name': 'Yaw'}),
          ],
        }),
      );
      final shell = await open(t, fake);
      await tap(t, find.text(loc.dating_cardNotForMe).first);
      await tap(t, find.text(loc.dating_cardInterested).first);
      expect(fake.acts.map((a) => (a.$2, a.$3)), [
        ('a', 'passed'),
        ('b', 'interested'),
      ]);
      final leave = FakeDatingToday();
      final s2 = await open(t, leave);
      await tap(t, find.text(loc.dating_cardNotForMe));
      s2.router.go('/home');
      await t.pumpAndSettle();
      expect(leave.acts.map((a) => a.$3), ['passed']);
      expect(shell.location, isNotNull);
    });

    testWidgets(
      'D8: a held answer is never sent as the next account; nothing of the last shows',
      (t) async {
        final fake = FakeDatingToday();
        final shell = await open(t, fake);
        await tap(t, find.text(loc.dating_cardNotForMe));
        fake.hold = Completer<DatingToday>();
        shell.container.read(datingTestAccount.notifier).state = 'kwame';
        await t.pump();
        await t.pump(const Duration(seconds: 30));
        expect(fake.acts, isEmpty);
        expect(find.textContaining('Kofi'), findsNothing);
        fake.hold!.complete(
          DatingToday.fromJson(
            datingTodayJson({'cards': <Object?>[], 'today_state': 'empty'}),
          ),
        );
        await t.pumpAndSettle();
        expect(find.textContaining('Kofi'), findsNothing);
      },
    );

    testWidgets(
      'a gone introduction says so calmly; busy is calm; a failure is the error line',
      (t) async {
        for (final (reason, line) in [
          ('introduction_unavailable', loc.dating_cardGone),
          ('busy', loc.dating_busy),
          ('failed', loc.dating_errorGeneric),
        ]) {
          final fake =
              FakeDatingToday()
                ..answer =
                    (id, action) => DatingActAnswer(ok: false, reason: reason);
          await open(t, fake);
          await tap(t, find.text(loc.dating_cardInterested));
          expect(find.text(line), findsOneWidget, reason: reason);
        }
      },
    );
  });

  group('photos, notes, widen', () {
    testWidgets('photos load from their URLs; data saver waits for a tap', (
      t,
    ) async {
      final fake = FakeDatingToday();
      await open(t, fake);
      expect(datingFetched, ['https://s.test/1', 'https://s.test/2']);
      datingFetched.clear();
      await DatingPhotoMemory.clear();
      final saver = FakeDatingToday(
        today: datingTodayJson({
          'data_saver': true,
          'cards': [datingCardJson('s')],
        }),
      );
      await open(t, saver);
      expect(datingFetched, isEmpty);
      await tap(t, find.text(loc.dating_cardShowPhotos));
      expect(saver.photoCalls, [('introduction', 's')]);
      final later = FakeDatingToday(
        today: datingTodayJson({
          'cards': [
            datingCardJson('l', {
              'photos_after_mutual': true,
              'photos': <Object?>[],
            }),
          ],
        }),
      );
      await open(t, later);
      expect(find.text(loc.dating_cardPhotosLater), findsOneWidget);
      expect(later.photoCalls, isEmpty);
    });

    testWidgets('the family question once: an answer or Skip', (t) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({'family_question': true}),
      );
      await open(t, fake);
      await tap(t, find.text(loc.dating_familyEarly));
      expect(fake.families, ['early']);
      expect(find.text(loc.dating_familyQuestion), findsNothing);
      final skip = FakeDatingToday(
        today: datingTodayJson({'family_question': true}),
      );
      await open(t, skip);
      await tap(t, find.text(loc.dating_familySkip));
      expect(skip.notes, ['family']);
      expect(find.text(loc.dating_familyQuestion), findsNothing);
    });

    testWidgets(
      'the quiet note once; Widen opens the editors and comes back to Today',
      (t) async {
        final fake = FakeDatingToday(
          today: datingTodayJson({
            'today_state': 'empty',
            'cards': <Object?>[],
            'quiet_note': true,
          }),
        );
        final shell = await open(t, fake);
        expect(
          find.text(loc.dating_quietNote(loc.dating_region_gh_aa)),
          findsOneWidget,
        );
        await tap(t, find.text(loc.dating_todayWiden));
        expect(fake.notes, ['quiet']);
        expect(find.text(loc.dating_widenAges(25, 40)), findsOneWidget);
        expect(
          find.text(loc.dating_widenHowFar(loc.dating_scopeRegion)),
          findsOneWidget,
        );
        await tap(t, find.text(loc.dating_widenAges(25, 40)));
        await t.pumpAndSettle();
        final step = t.widget<DatingSetupStepRoute>(
          find.byType(DatingSetupStepRoute),
        );
        expect((step.step, step.from), ('meet', 'today'));
        expect(shell.location, isNotNull);
      },
    );
  });

  group('the match moment', () {
    testWidgets('shown once from Today, marked seen; Later goes back', (
      t,
    ) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'my_name': 'Ama',
          'moments': [
            {'match_id': 'm1', 'display_name': 'Kofi'},
          ],
        }),
      );
      final shell = await open(t, fake);
      expect(shell.location, isNotNull);
      expect(find.text(loc.dating_momentTitle('Kofi')), findsOneWidget);
      expect(find.text(loc.dating_momentBody), findsOneWidget);
      expect(find.text(loc.dating_momentSayHello), findsNothing);
      expect(fake.seen, ['m1']);
      await tap(t, find.text(loc.dating_momentLater));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_momentTitle('Kofi')), findsNothing);
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      expect(fake.seen, ['m1']);
    });

    testWidgets('one settle within 600 ms; none under reduce motion', (
      t,
    ) async {
      expect(kDatingMomentSettle, const Duration(milliseconds: 600));
      // T7 fix 1 (M-9): the haptics, counted (one light one, none under
      // reduce motion); the timing is in today_screen_rulings_test.
      final haptics = <Object?>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'moments': [
            {'match_id': 'm1', 'display_name': 'Kofi'},
          ],
        }),
      );
      await open(t, fake);
      // Under reduce motion the avatars fade; nothing moves them.
      final moving = find.descendant(
        of: find.byKey(const ValueKey('dating_moment_avatars')),
        matching: find.byType(Transform),
      );
      expect(moving, findsNothing);
      expect(haptics, isEmpty);
      t.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await open(
        t,
        FakeDatingToday(
          today: datingTodayJson({
            'moments': [
              {'match_id': 'm2', 'display_name': 'Yaw'},
            ],
          }),
        ),
      );
      expect(moving, findsNWidgets(2));
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });
  });

  testWidgets('the section, active, opens Today (§3.1)', (t) async {
    final h = await pumpFlowScreen(
      t,
      () => const Scaffold(body: SingleChildScrollView(child: DatingSection())),
      overrides: datingShellOverrides(
        home: FakeDatingHomeGateway(
          home: const DatingHome(state: DatingHomeState.active),
        ),
      ),
    );
    await tap(t, find.text(loc.dating_sectionOpenToday));
    await t.pumpAndSettle();
    expect(find.text('at ${DatingPaths.today}'), findsOneWidget);
    expect(h.location, isNotNull);
  });

  group('goldens and accessibility', () {
    testWidgets('Today and the moment: goldens, guidelines, dark', (t) async {
      for (final (name, json) in [
        ('today_delivered', datingTodayJson({'family_question': true})),
        (
          'today_empty',
          datingTodayJson({'today_state': 'empty', 'cards': <Object?>[]}),
        ),
      ]) {
        // Task 7 ruling: a fresh ProviderScope per golden (pumpFlowScreen
        // reuses the last one, and with it the last Today read).
        await t.pumpWidget(const SizedBox());
        await expectFlowGoldens(
          t,
          name,
          () => const DatingTodayScreen(),
          overrides: [
            ...datingShellOverrides(),
            ...datingTodayOverrides(FakeDatingToday(today: json)),
          ],
        );
      }
      await t.pumpWidget(const SizedBox());
      await expectFlowGoldens(
        t,
        'match_moment',
        () => const DatingMatchMomentScreen(
          matchId: 'm1',
          moment: DatingMoment(matchId: 'm1', name: 'Kofi'),
          myName: 'Ama',
          account: 'ama',
        ),
        overrides: [
          ...datingShellOverrides(),
          ...datingTodayOverrides(FakeDatingToday()),
        ],
      );
      await pumpFlowScreen(
        t,
        () => const DatingTodayScreen(),
        overrides: [
          ...datingShellOverrides(),
          ...datingTodayOverrides(FakeDatingToday()),
        ],
      );
      await expectFlowGuidelines(t);
      await pumpFlowScreen(
        t,
        () => Theme(data: AppTheme.darkTheme, child: const DatingTodayScreen()),
        overrides: [
          ...datingShellOverrides(),
          ...datingTodayOverrides(FakeDatingToday()),
        ],
      );
      expect(t.takeException(), isNull);
    });
  });
}
