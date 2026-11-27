// Spec 1 W2a: WL1 Welcome and RI-1/RI-2. Owner 2026-11-26: Welcome is the
// path question; a card starts sign-up on its path (no preview).
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/shared_preferences_service.dart'
    hide preferencesServiceProvider;
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/invite_landing_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
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

  testWidgets('asks what brings you, three paths, nothing preselected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpFlowScreen(tester, () => const WelcomeScreen());
    expect(find.text('What brings you to Attune?'), findsOneWidget);
    for (final label in [
      'In a relationship. A private space for you and your partner.',
      "Single and open to dating. A few introductions a day. Only when it's mutual.",
      'Just for me. Your journal, quizzes and Healing.',
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

  testWidgets('the intro has the other ways in: none of them here', (
    tester,
  ) async {
    await pumpFlowScreen(tester, () => const WelcomeScreen());
    for (final gone in [
      'Get started',
      'I already have an account',
      'Read Opinions first',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
  });

  // Entry gates (b, owner 2026-11-27): RI-2 is reachable from Welcome, so
  // a code typed from an invite message (an iOS install loses the link, the
  // Play referrer only prefills) has a way in before sign-up.
  testWidgets('a quiet "I have an invite" link sits at the bottom, under '
      'the Terms and Privacy links', (tester) async {
    await pumpFlowScreen(tester, () => const WelcomeScreen());
    final link = find.widgetWithText(TextButton, 'I have an invite');
    expect(link, findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'I have an invite'), findsNothing);
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(link).dy,
      greaterThan(tester.getTopLeft(find.text('Privacy')).dy),
    );
  });

  testWidgets('"I have an invite" marks first launch done and opens RI-2', (
    tester,
  ) async {
    final h = await pumpFlowScreen(
      tester,
      () => const WelcomeScreen(),
      routing: RoutingNotifier(isFirstLaunch: true, flowV2: true),
    );
    await tester.ensureVisible(find.text('I have an invite'));
    await tester.tap(find.text('I have an invite'));
    await tester.pumpAndSettle();
    expect(h.location, '/invite');
    expect(PreferencesService(h.prefs).isFirstLaunch, isFalse);
    expect(h.routing.isFirstLaunch, isFalse);
    expect(h.metrics, isEmpty, reason: 'no path was chosen');
  });

  for (final (card, target) in [
    ('In a relationship', '/signup?entry=new&path=relationship'),
    ('Single and open to dating', '/signup?entry=new&path=dating'),
    ('Just for me', '/signup?entry=new&path=justMe'),
  ]) {
    testWidgets('"$card" marks first launch done and opens $target', (
      tester,
    ) async {
      final h = await pumpFlowScreen(
        tester,
        () => const WelcomeScreen(),
        routing: RoutingNotifier(isFirstLaunch: true, flowV2: true),
      );
      expect(PreferencesService(h.prefs).isFirstLaunch, isTrue);
      await tester.ensureVisible(find.text(card));
      await tester.tap(find.text(card));
      await tester.pumpAndSettle();
      expect(h.location, target);
      expect(find.byType(BottomSheet), findsNothing, reason: 'no preview');
      expect(PreferencesService(h.prefs).isFirstLaunch, isFalse);
      expect(h.routing.isFirstLaunch, isFalse);
    });
  }

  // Fix round I-2: the guest tab's Get started opens Welcome with its own
  // back, which A1's Back then returns to.
  testWidgets('a back given to Welcome goes on to sign-up', (tester) async {
    final h = await pumpFlowScreen(
      tester,
      () => const WelcomeScreen(backTo: '/home?tab=chat'),
    );
    await tester.tap(find.text('Just for me'));
    await tester.pumpAndSettle();
    final uri = Uri.parse(h.location);
    expect(uri.path, '/signup');
    expect(uri.queryParameters, {
      'entry': 'new',
      'back': '/home?tab=chat',
      'path': 'justMe',
    });
  });

  testWidgets('with nothing under it, a given back is where Back goes', (
    tester,
  ) async {
    final h = await pumpFlowScreen(
      tester,
      () => const WelcomeScreen(backTo: '/home?tab=chat'),
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(h.location, '/home?tab=chat');
  });

  // Fix round M-3: one navigation and one count, however fast the taps.
  testWidgets('a second tap while leaving does nothing', (tester) async {
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
    await tester.tap(find.text('In a relationship'));
    await tester.pump();
    await tester.tap(find.text('Just for me'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(h.location, '/signup?entry=new&path=relationship');
    expect(h.metrics, ['welcome_preview:relationship']);
  });

  testWidgets('back with nothing under Welcome opens the intro', (
    tester,
  ) async {
    final h = await pumpFlowScreen(tester, () => const WelcomeScreen());
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(h.location, '/start');
  });

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
      await tester.ensureVisible(find.text(card));
      await tester.tap(find.text(card));
      await tester.pumpAndSettle();
      expect(h.metrics, [key]);
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
    await tester.ensureVisible(find.text('Just for me'));
    await tester.tap(find.text('Just for me'));
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
