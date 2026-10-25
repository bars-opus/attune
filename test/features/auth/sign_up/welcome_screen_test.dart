// Spec 1 W2a: WL1 Welcome, its three previews, and RI-1/RI-2.
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart'
    hide preferencesServiceProvider;
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/path_preview_sheet.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

/// First launch is marked done only when [gate] completes (review M-1).
class _SlowFirstLaunch extends PreferencesService {
  _SlowFirstLaunch(super.prefs, this.gate);

  final Completer<void> gate;

  @override
  Future<void> setFirstLaunchCompleted() async {
    await gate.future;
    await super.setFirstLaunchCompleted();
  }
}

/// Opens the Dating card's preview, scrolling to the card first when large
/// text has pushed it below the fold.
Future<void> _openDating(WidgetTester tester) async {
  await Scrollable.ensureVisible(
    tester.element(find.text('Single and open to dating')),
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Single and open to dating'));
  await tester.pumpAndSettle();
}

/// The preview's own fade (reduce motion), read where it is painted.
double _previewFade(WidgetTester tester) =>
    tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byType(PathPreviewSheet),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

void main() {
  test('country lists read as a sentence', () {
    String name(String iso) =>
        countryNameFor(iso, special: const {'GB': 'the UK', 'US': 'the US'});
    String pair(String a, String b) => '$a and $b';
    expect(formatCountryList(const [], nameOf: name, pair: pair), '');
    expect(formatCountryList(const ['GH'], nameOf: name, pair: pair), 'Ghana');
    expect(
      formatCountryList(const ['GB', 'GH'], nameOf: name, pair: pair),
      'the UK and Ghana',
    );
    expect(
      formatCountryList(const ['GH', 'KE', 'GB'], nameOf: name, pair: pair),
      'Ghana, Kenya and the UK',
    );
    expect(countryNameFor('zz'), 'ZZ');
  });

  test('invite codes: six of A-Z and 2-9, any case, spaces ignored', () {
    expect(normalizeInviteCode('k7p 2qm'), 'K7P2QM');
    expect(normalizeInviteCode('K7P2Q'), isNull);
    expect(
      normalizeInviteCode('K7P2Q0'),
      isNull,
      reason: '0 is not in the set',
    );
    expect(normalizeInviteCode('K7P2QM1'), isNull);
  });

  testWidgets('the three ways in, nothing preselected, every gate before typing', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(tester, () => const WelcomeScreen());
    expect(
      find.text('Love, dating and you, in one calm place.'),
      findsOneWidget,
    );
    for (final label in [
      'In a relationship. A private space for you and your partner. Opens a preview.',
      "Single and open to dating. A few introductions a day. Only when it's mutual. Opens a preview.",
      'Just for me. Your journal, quizzes and Healing. Opens a preview.',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    expect(
      find.text(
        'Attune is for adults (18+) and uses your phone number to sign in.',
      ),
      findsOneWidget,
    );
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  for (final (button, target) in [
    ('Get started', '/signup?entry=new'),
    ('I already have an account', '/signup?entry=returning'),
    ('I have an invite', '/invite'),
    ('Read Opinions first', '/guest-age'),
  ]) {
    testWidgets('"$button" marks first launch done and opens $target', (
      tester,
    ) async {
      final h = await pumpFlowScreen(
        tester,
        () => const WelcomeScreen(),
        routing: RoutingNotifier(isFirstLaunch: true, flowV2: true),
      );
      expect(PreferencesService(h.prefs).isFirstLaunch, isTrue);
      await tester.ensureVisible(find.text(button));
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(h.location, target);
      expect(PreferencesService(h.prefs).isFirstLaunch, isFalse);
      expect(h.routing.isFirstLaunch, isFalse);
    });
  }

  testWidgets(
    'a card opens its preview; the Dating one names the open countries',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await pumpFlowScreen(
        tester,
        () => const WelcomeScreen(),
        openCountries: const ['GB', 'GH'],
      );
      await tester.tap(find.text('Single and open to dating'));
      await tester.pumpAndSettle();
      expect(find.text('Introductions, not swiping'), findsOneWidget);
      expect(
        find.text('Dating is open in the UK and Ghana. More countries later.'),
        findsOneWidget,
      );
      expect(h.metrics, ['welcome_preview:dating']);
      // A screen reader hears that a sheet opened, and what it is (M-4).
      expect(
        tester.getSemantics(
          find
              .descendant(
                of: find.byType(PathPreviewSheet),
                matching: find.byType(Material),
              )
              .first,
        ),
        containsSemantics(
          scopesRoute: true,
          namesRoute: true,
          label: 'Introductions, not swiping',
        ),
      );
      await expectFlowGuidelines(tester);
      semantics.dispose();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Introductions, not swiping'), findsNothing);
    },
  );

  testWidgets('with no open-country list the line is left out', (tester) async {
    await pumpFlowScreen(tester, () => const WelcomeScreen());
    await tester.tap(find.text('Single and open to dating'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dating is open in'), findsNothing);
  });

  testWidgets("a preview's Get started starts sign-up", (tester) async {
    final h = await pumpFlowScreen(tester, () => const WelcomeScreen());
    await tester.tap(find.text('Just for me'));
    await tester.pumpAndSettle();
    expect(find.text('A private space for you'), findsOneWidget);
    await tester.tap(find.text('Get started').last);
    await tester.pumpAndSettle();
    expect(h.location, '/signup?entry=new');
  });

  testWidgets('the preview opens in 300 ms and closes in 200 ms', (
    tester,
  ) async {
    await pumpFlowScreen(tester, () => const WelcomeScreen());
    await tester.tap(find.text('In a relationship'));
    await tester.pump();
    double slide() =>
        tester
            .widget<SlideTransition>(
              find
                  .ancestor(
                    of: find.text('A space for the two of you'),
                    matching: find.byType(SlideTransition),
                  )
                  .first,
            )
            .position
            .value
            .dy;
    await tester.pump(const Duration(milliseconds: 150));
    expect(slide(), greaterThan(0), reason: 'still sliding in');
    await tester.pump(const Duration(milliseconds: 100));
    expect(slide(), greaterThan(0), reason: 'still sliding at 250 ms (M-3)');
    await tester.pump(const Duration(milliseconds: 50));
    expect(slide(), 0);

    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));
    expect(find.text('A space for the two of you'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('A space for the two of you'), findsNothing);
  });

  testWidgets(
    'with reduce motion the preview fades in 150 ms and never slides',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => const WelcomeScreen(),
        reduceMotion: true,
      );
      await tester.tap(find.text('In a relationship'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        find.ancestor(
          of: find.text('A space for the two of you'),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
      // Halfway, not 20 times faster (review M-2).
      expect(_previewFade(tester), inExclusiveRange(0.3, 0.7));
      await tester.pump(const Duration(milliseconds: 75));
      await tester.pump();
      expect(find.text('A space for the two of you'), findsOneWidget);
      expect(_previewFade(tester), 1);

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(
        find.text('A space for the two of you'),
        findsOneWidget,
        reason: 'still fading out',
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('A space for the two of you'), findsNothing);
    },
  );

  testWidgets('RI-2 asks for the code, refuses a bad one, then shows RI-1', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await pumpFlowScreen(tester, () => const InviteLandingScreen());
    expect(find.text('Enter your invite code'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Codes have 6 letters and numbers. Check it with the person who sent it.',
      ),
      findsOneWidget,
    );
    await expectFlowGuidelines(tester);

    await tester.enterText(find.byType(TextField), 'k7p 2qm');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text("You've been invited to Attune"), findsOneWidget);
    expect(
      OnboardingStore(
        h.prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      'K7P2QM',
    );
    expect(
      find.textContaining('invited you to a private space'),
      findsOneWidget,
    );

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(h.location, '/signup?entry=invite');
    semantics.dispose();
  });

  testWidgets(
    'RI-1 with a code from a link names nobody and offers both ways in',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await pumpFlowScreen(
        tester,
        () => const InviteLandingScreen(),
        prefsValues: {
          'attune.onboarding.anonymous.pending_invite':
              '{"code":"K7P2QM","stored_at":"${DateTime.now().toUtc().toIso8601String()}"}',
        },
      );
      expect(find.text("You've been invited to Attune"), findsOneWidget);
      await expectFlowGuidelines(tester);
      semantics.dispose();
      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      expect(h.location, '/signup?entry=returning');
    },
  );

  // Batch 2 additions (not in the Task 3 brief).

  // Ruling C6: Welcome opens the shared read-only legal sheets.
  for (final (link, title) in [
    ('Terms', 'Terms of Service'),
    ('Privacy', 'Privacy Policy'),
  ]) {
    testWidgets('Welcome\'s $link link opens $title', (tester) async {
      await pumpFlowScreen(tester, () => const WelcomeScreen());
      await tester.ensureVisible(find.text(link));
      await tester.tap(find.text(link));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(find.text('I Agree'), findsNothing);
    });
  }

  // Batch 1 review M-4: every failed submit is read out, even the same one.
  testWidgets('RI-2 reads out the same bad code again', (tester) async {
    await pumpFlowScreen(tester, () => const InviteLandingScreen());
    const message =
        'Codes have 6 letters and numbers. Check it with the person who sent it.';
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(tester.takeAnnouncements().map((a) => a.message), [message]);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(tester.takeAnnouncements().map((a) => a.message), [message]);
  });

  // Batch 2 fix round 1.

  for (final (card, key) in [
    ('In a relationship', 'welcome_preview:relationship'),
    ('Single and open to dating', 'welcome_preview:dating'),
    ('Just for me', 'welcome_preview:just_me'),
  ]) {
    testWidgets('"$card" counts $key (M-3)', (tester) async {
      final h = await pumpFlowScreen(tester, () => const WelcomeScreen());
      await tester.tap(find.text(card));
      await tester.pumpAndSettle();
      expect(h.metrics, [key]);
    });
  }

  for (final scale in [1.3, 2.0]) {
    testWidgets('at text size $scale the preview keeps both buttons on screen '
        '(M-5)', (tester) async {
      await pumpFlowScreen(
        tester,
        () => const WelcomeScreen(),
        textScale: scale,
        openCountries: const ['GB', 'GH'],
      );
      await _openDating(tester);
      final screen = Offset.zero & tester.view.physicalSize;
      for (final button in [
        find.widgetWithText(FilledButton, 'Get started').last,
        find.widgetWithText(OutlinedButton, 'Close'),
      ]) {
        final rect = tester.getRect(button);
        expect(screen.contains(rect.topLeft), isTrue, reason: '$rect');
        expect(screen.contains(rect.bottomRight), isTrue, reason: '$rect');
      }
    });
  }

  testWidgets('leaving survives Welcome closing mid-write (M-1)', (
    tester,
  ) async {
    final gate = Completer<void>();
    final h = await pumpFlowScreen(
      tester,
      () => const WelcomeScreen(),
      routing: RoutingNotifier(isFirstLaunch: true, flowV2: true),
      overrides: [
        preferencesServiceProvider.overrideWith(
          (ref) => _SlowFirstLaunch(ref.watch(sharedPreferencesProvider), gate),
        ),
      ],
    );
    await tester.ensureVisible(find.text('Get started'));
    await tester.tap(find.text('Get started'));
    await tester.pump();
    // Something else (an invite link, the flag going off) moves on while the
    // write is still going.
    h.router.go('/elsewhere');
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(h.routing.isFirstLaunch, isFalse);
    expect(PreferencesService(h.prefs).isFirstLaunch, isFalse);
  });
}
