// Spec 2 W5b Task 7 fix round 1 (task-7-review.md): the Undo bar never
// outlives its window or Today (I-1); Today reads again on the way back
// from every page it opens (I-2); the moment is the account's own and a
// link never lands on a blank page (M-1, M-2); Not for me fades as it
// collapses (M-5); the quiet note, the day line and the names read right
// when something is missing (M-6 to M-8); the moment settles once within
// 600 ms (M-9); and the goldens and guidelines the review asked for
// (M-10): the card's answers, Noted, the error line, dark, Widen and
// paused.
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

const _momentJson = {'match_id': 'm1', 'display_name': 'Kofi'};

void main() {
  final loc = AppLocalizationsEn();

  setUp(() async {
    datingFetched.clear();
    await DatingPhotoMemory.clear();
  });

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingToday fake, {
    String initial = DatingPaths.today,
  }) => pumpDatingShell(
    t,
    initial: initial,
    overrides: datingTodayOverrides(fake),
  );

  /// Each variant in a fresh ProviderScope (no last read carried over).
  Future<void> goldens(
    WidgetTester t,
    String name,
    FakeDatingToday Function() fake, {
    Future<void> Function(WidgetTester t)? before,
    bool dark = false,
    bool guidelines = false,
  }) async {
    for (final (variant, scale, direction) in [
      if (dark) flowGoldenVariants.first else ...flowGoldenVariants,
    ]) {
      await t.pumpWidget(const SizedBox());
      await pumpFlowScreen(
        t,
        () =>
            dark
                ? Theme(
                  data: AppTheme.darkTheme,
                  child: const DatingTodayScreen(),
                )
                : const DatingTodayScreen(),
        textScale: scale,
        direction: direction,
        overrides: [...datingShellOverrides(), ...datingTodayOverrides(fake())],
      );
      if (before != null) await before(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.$variant.png'),
      );
      expect(t.takeException(), isNull, reason: '$name at $variant');
      if (guidelines && variant == 'scale1.0') await expectFlowGuidelines(t);
    }
  }

  group('I-1: the Undo bar', () {
    testWidgets('leaving Today inside the window leaves no bar, no error', (
      t,
    ) async {
      for (final reader in [false, true]) {
        if (reader) {
          t.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(accessibleNavigation: true);
        }
        final fake = FakeDatingToday();
        final shell = await open(t, fake);
        await tap(t, find.text(loc.dating_cardNotForMe));
        expect(find.text(loc.dating_cardNotForMeDone), findsOneWidget);
        shell.router.go('/home');
        await t.pumpAndSettle();
        expect(find.text('ME '), findsOneWidget, reason: '$reader');
        expect(
          find.text(loc.dating_cardNotForMeDone),
          findsNothing,
          reason: '$reader',
        );
        expect(find.text(loc.dating_undo), findsNothing, reason: '$reader');
        expect(t.takeException(), isNull);
        expect(fake.acts.map((a) => a.$3), ['passed']);
        t.platformDispatcher.clearAccessibilityFeaturesTestValue();
      }
    });
  });

  group('N-1: the bar goes at once (fix round 2)', () {
    testWidgets('leaving Today, to Me or to the decoy: no bar on the next '
        'frame', (t) async {
      for (final to in ['/home', RouteNames.neutralScreen]) {
        for (final reader in [false, true]) {
          if (reader) {
            t.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(accessibleNavigation: true);
          }
          final fake = FakeDatingToday();
          final shell = await open(t, fake);
          await tap(t, find.text(loc.dating_cardNotForMe));
          expect(find.text(loc.dating_cardNotForMeDone), findsOneWidget);
          shell.router.go(to);
          await t.pump();
          expect(
            find.text(loc.dating_cardNotForMeDone, skipOffstage: false),
            findsNothing,
            reason: '$to $reader',
          );
          expect(
            find.text(loc.dating_undo, skipOffstage: false),
            findsNothing,
            reason: '$to $reader',
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(fake.acts.map((a) => a.$3), ['passed']);
          t.platformDispatcher.clearAccessibilityFeaturesTestValue();
        }
      }
    });

    testWidgets('Today torn down with no page change still sends the held '
        'pass (dispose)', (t) async {
      final fake = FakeDatingToday();
      await open(t, fake);
      await tap(t, find.text(loc.dating_cardNotForMe));
      await t.pumpWidget(const SizedBox());
      expect(fake.acts.map((a) => a.$3), ['passed']);
    });

    testWidgets('another account: no bar on the next frame', (t) async {
      final fake = FakeDatingToday();
      final shell = await open(t, fake);
      await tap(t, find.text(loc.dating_cardNotForMe));
      fake.hold = Completer<DatingToday>();
      shell.container.read(datingTestAccount.notifier).state = 'kwame';
      await t.pump();
      await t.pump();
      expect(find.text(loc.dating_cardNotForMeDone), findsNothing);
      expect(fake.acts, isEmpty);
    });
  });

  group('I-2: Today reads again on the way back', () {
    testWidgets('paused, Settings, Resume, back: the day shows', (t) async {
      final fake = FakeDatingToday(today: {'ok': false, 'reason': 'paused'});
      final shell = await open(t, fake);
      await tap(t, find.text(loc.dating_settingsTitle));
      await t.pumpAndSettle();
      // (A push keeps the router's location; Settings is on top.)
      expect(find.text(loc.dating_todayTitle), findsNothing);
      // Resumed in Settings: the server's day is open again.
      fake.json = datingTodayJson();
      shell.router.pop();
      await t.pumpAndSettle();
      expect(find.text(loc.dating_sectionPaused), findsNothing);
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
    });

    testWidgets('the quiet note opens Dating settings and reads again', (
      t,
    ) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'today_state': 'empty',
          'cards': <Object?>[],
          'quiet_note': true,
        }),
      );
      final shell = await open(t, fake);
      final reads = fake.reads;
      await tap(t, find.text(loc.dating_settingsTitle));
      await t.pumpAndSettle();
      // (A push keeps the router's location; Settings is on top.)
      expect(find.text(loc.dating_todayTitle), findsNothing);
      shell.router.pop();
      await t.pumpAndSettle();
      expect(fake.reads, reads + 1);
    });

    testWidgets('Widen, an edit, back: Widen shows the new ages', (t) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({'today_state': 'empty', 'cards': <Object?>[]}),
      );
      final shell = await open(t, fake);
      await tap(t, find.text(loc.dating_todayWiden));
      await tap(t, find.text(loc.dating_widenAges(25, 40)));
      await t.pumpAndSettle();
      fake.json = datingTodayJson({
        'today_state': 'empty',
        'cards': <Object?>[],
        'widen': {'min_age': 25, 'max_age': 50, 'scope': 'region'},
      });
      shell.router.pop();
      await t.pumpAndSettle();
      await tap(t, find.text(loc.dating_todayWiden));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_widenAges(25, 50)), findsOneWidget);
      expect(find.text(loc.dating_widenAges(25, 40)), findsNothing);
    });
  });

  group('the moment', () {
    testWidgets('M-1: another account never sees it', (t) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'moments': [_momentJson],
        }),
      );
      final shell = await open(t, fake);
      expect(find.text(loc.dating_momentTitle('Kofi')), findsOneWidget);
      expect(fake.seen, ['m1']);
      fake.hold = Completer<DatingToday>();
      shell.container.read(datingTestAccount.notifier).state = 'kwame';
      await t.pump();
      await t.pump();
      expect(find.text(loc.dating_momentTitle('Kofi')), findsNothing);
      fake.hold!.complete(
        DatingToday.fromJson(
          datingTodayJson({'cards': <Object?>[], 'today_state': 'empty'}),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(loc.dating_momentTitle('Kofi')), findsNothing);
      expect(fake.seen, ['m1']);
    });

    testWidgets('M-2: a link whose moment is gone goes to Today', (t) async {
      final gone = FakeDatingToday();
      final shell = await open(t, gone, initial: DatingPaths.match('m1'));
      expect(shell.location, DatingPaths.today);
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      final still = FakeDatingToday(
        today: datingTodayJson({
          'moments': [_momentJson],
        }),
      );
      final s2 = await open(t, still, initial: DatingPaths.match('m1'));
      expect(s2.location, DatingPaths.match('m1'));
      expect(find.text(loc.dating_momentTitle('Kofi')), findsOneWidget);
    });

    testWidgets('M-9: one settle within 600 ms and one light haptic', (
      t,
    ) async {
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
      final fake =
          FakeDatingToday()
            ..answer =
                (id, action) =>
                    DatingActAnswer(ok: true, action: action, matched: true);
      await open(t, fake);
      fake.json = datingTodayJson({
        'moments': [_momentJson],
      });
      await tapInReach(t, find.text(loc.dating_cardInterested));
      final avatars = find.byKey(const ValueKey('dating_moment_avatars'));
      for (var i = 0; i < 10 && avatars.evaluate().isEmpty; i++) {
        await t.pump();
      }
      expect(avatars, findsOneWidget);
      // The settle starts on the next frame (its ticker's first tick).
      await t.pump();
      double moved() => t
          .widgetList<Transform>(
            find.descendant(of: avatars, matching: find.byType(Transform)),
          )
          .map((w) => w.transform.getTranslation().x.abs())
          .reduce((a, b) => a > b ? a : b);
      await t.pump(const Duration(milliseconds: 300));
      expect(moved(), greaterThan(0));
      await t.pump(const Duration(milliseconds: 320));
      expect(moved(), 0);
      await t.pump(const Duration(seconds: 2));
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('M-8: no name, no blank title or disc', (t) async {
      await open(
        t,
        FakeDatingToday(
          today: datingTodayJson({
            'moments': [
              {'match_id': 'm1', 'display_name': ''},
            ],
          }),
        ),
      );
      expect(find.text(loc.dating_momentTitleNoName), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsNWidgets(2));
    });
  });

  group('the card and the day', () {
    testWidgets('M-5: Not for me fades while it collapses; reduce motion '
        'just goes', (t) async {
      await open(t, FakeDatingToday());
      await tapInReach(t, find.text(loc.dating_cardNotForMe));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final fade = t.widget<FadeTransition>(
        find
            .descendant(
              of: find.byKey(const ValueKey('dating_today_card_i1')),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, inExclusiveRange(0.05, 0.95));
      await t.pump(const Duration(milliseconds: 150));
      expect(find.text(loc.dating_cardInterested), findsNothing);

      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await open(t, FakeDatingToday());
      await tapInReach(t, find.text(loc.dating_cardNotForMe));
      await t.pump();
      await t.pump();
      expect(find.text(loc.dating_cardInterested), findsNothing);
    });

    testWidgets('M-8: Interested on a card with no name', (t) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'cards': [
            datingCardJson('n', {'display_name': null}),
          ],
        }),
      );
      await open(t, fake);
      await tap(t, find.text(loc.dating_cardInterested));
      expect(find.text(loc.dating_cardNotedNoName), findsOneWidget);
      expect(find.textContaining('If  is'), findsNothing);
    });

    testWidgets('M-6: the quiet note with no region name; M-7: every day '
        'says something', (t) async {
      await open(
        t,
        FakeDatingToday(
          today: datingTodayJson({
            'today_state': 'empty',
            'cards': <Object?>[],
            'quiet_note': true,
            'region_name_key': null,
          }),
        ),
      );
      expect(find.text(loc.dating_quietNoteNoRegion), findsOneWidget);
      expect(find.textContaining(loc.dating_widenCountry), findsNothing);
      for (final state in ['before_drop', 'cool_off']) {
        await open(
          t,
          FakeDatingToday(
            today: datingTodayJson({
              'today_state': state,
              'cards': <Object?>[],
              'drop_at': null,
            }),
          ),
        );
        expect(
          find.text(loc.dating_todayLaterNoTime),
          findsOneWidget,
          reason: state,
        );
      }
      for (final state in ['a_new_state', 'delivered']) {
        await open(
          t,
          FakeDatingToday(
            today: datingTodayJson({
              'today_state': state,
              'cards': <Object?>[],
            }),
          ),
        );
        expect(
          find.text(loc.dating_todayNothingNew),
          findsOneWidget,
          reason: state,
        );
      }
    });
  });

  group('M-10: goldens and guidelines', () {
    testWidgets('the card\'s answers, Noted and the error line', (t) async {
      final one = datingTodayJson({'family_question': false});
      await goldens(
        t,
        'today_actions',
        () => FakeDatingToday(today: one),
        before: (t) async {
          await t.ensureVisible(find.text(loc.dating_cardNotForMe));
          await t.pumpAndSettle();
        },
        guidelines: true,
      );
      await goldens(
        t,
        'today_noted',
        () => FakeDatingToday(
          today: datingTodayJson({
            'cards': [
              datingCardJson('i1', {'acted': 'interested'}),
            ],
          }),
        ),
        before: (t) async {
          await t.ensureVisible(find.text(loc.dating_cardNoted('Kofi')));
          await t.pumpAndSettle();
        },
      );
      await goldens(
        t,
        'today_error',
        () => FakeDatingToday(today: one)
          ..answer =
              (id, action) =>
                  const DatingActAnswer(ok: false, reason: 'failed'),
        before: (t) async {
          await t.ensureVisible(find.text(loc.dating_cardInterested));
          await t.pumpAndSettle();
          await t.tap(find.text(loc.dating_cardInterested));
          await t.pumpAndSettle();
          await t.ensureVisible(find.text(loc.dating_errorGeneric));
          await t.pumpAndSettle();
        },
        guidelines: true,
      );
      await goldens(
        t,
        'today_dark',
        () => FakeDatingToday(today: one),
        dark: true,
      );
    });

    testWidgets('Widen and paused', (t) async {
      await goldens(
        t,
        'widen_sheet',
        () => FakeDatingToday(
          today: datingTodayJson({
            'today_state': 'empty',
            'cards': <Object?>[],
          }),
        ),
        before: (t) async {
          await t.tap(find.text(loc.dating_todayWiden));
          await t.pumpAndSettle();
        },
        guidelines: true,
      );
      await goldens(
        t,
        'today_paused',
        () => FakeDatingToday(today: {'ok': false, 'reason': 'paused'}),
        guidelines: true,
      );
    });
  });
}
