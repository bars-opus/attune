// Spec 2 W4a (§3.1, §3.3.2, §3.15 D11; carry 1; R-10): the capture
// prompts are spoken through the screen reader and tick unless reduce
// motion is on; the practice capture runs for the fake vendor only; the
// section's verifying card and the verification pause open the check.
import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/verify/dating_capture.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_verify_fakes.dart';

Future<FakeHaptics> _practice(
  WidgetTester t, {
  bool screenReader = false,
  bool reduceMotion = false,
  List<DatingCaptureResult?>? results,
  String vendor = 'fake',
}) async {
  final haptics = FakeHaptics();
  await pumpFlowScreen(
    t,
    () => Builder(
      builder:
          (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = await const DatingDevCaptureLauncher().liveness(
                    context,
                    vendor: vendor,
                    vendorRef: 'ref-1',
                  );
                  results?.add(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
    ),
    reduceMotion: reduceMotion,
    overrides: [hapticsProvider.overrideWithValue(haptics)],
  );
  if (screenReader) {
    t
        .platformDispatcher
        .accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
      accessibleNavigation: true,
      disableAnimations: reduceMotion,
    );
  }
  await tapInReach(t, find.text('open'));
  // The page, then its first prompt (a post-frame callback).
  await t.pump();
  await t.pump();
  return haptics;
}

void main() {
  testWidgets('the prompts in turn, spoken with a screen reader on, a tick '
      'each', (t) async {
    final haptics = await _practice(t, screenReader: true);
    expect(find.text('Move the phone a little closer'), findsOneWidget);
    await t.pump(kDatingPromptGap);
    expect(find.text('Hold still'), findsOneWidget);
    await t.pump(kDatingPromptGap);
    expect(find.text('Done'), findsOneWidget);
    await t.pumpAndSettle();
    expect(
      [for (final a in t.takeAnnouncements()) a.message],
      ['Move the phone a little closer', 'Hold still', 'Done'],
    );
    expect(haptics.selectionCount, 3);
  });

  testWidgets('no screen reader: shown, never announced; reduce motion: no '
      'ticks', (t) async {
    final haptics = await _practice(t, reduceMotion: true);
    await t.pump(kDatingPromptGap);
    await t.pump(kDatingPromptGap);
    await t.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    expect(t.takeAnnouncements(), isEmpty);
    expect(haptics.selectionCount, 0);
  });

  testWidgets('the practice capture answers the scenario picked, or '
      'cancelled', (t) async {
    final results = <DatingCaptureResult?>[];
    await _practice(t, results: results);
    await t.pumpAndSettle();
    await tapInReach(t, find.text('under_25'));
    await t.pump();
    await tapInReach(t, find.text('Continue'));
    await t.pumpAndSettle();
    expect(results.single!.kind, DatingCaptureKind.done);
    expect(results.single!.scenario, 'under_25');
    await tapInReach(t, find.text('open'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('Cancel'));
    await t.pumpAndSettle();
    expect(results.last!.kind, DatingCaptureKind.cancelled);
  });

  testWidgets('R-10: any vendor but the fake has no capture yet: unavailable, '
      'nothing opens', (t) async {
    final results = <DatingCaptureResult?>[];
    await _practice(t, results: results, vendor: 'aws_rekognition');
    await t.pumpAndSettle();
    expect(find.byType(DatingPracticeCaptureScreen), findsNothing);
    expect(results.single!.kind, DatingCaptureKind.unavailable);
  });

  group('the section', () {
    Future<void> section(
      WidgetTester t,
      DatingHome home, {
      DatingVerification? verification,
    }) async {
      final s = await pumpDatingShell(
        t,
        initial: '/me',
        home: FakeDatingHomeGateway(home: home),
        extraRoutes: [
          GoRoute(
            path: '/me',
            builder:
                (_, __) => const Scaffold(
                  body: SingleChildScrollView(child: DatingSection()),
                ),
          ),
        ],
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(
              FakeHomeStateGateway(state: homeJson(path: 'dating')),
            ),
          ),
          if (verification != null)
            datingVerificationGatewayProvider.overrideWithValue(
              FakeDatingVerificationGateway(state: verification),
            ),
        ],
      );
      expect(s.location, '/me');
    }

    // Task 4 (carry 3; fix round 1 M-7): a person's review and an ID
    // check both wait under the one line that names no video.
    testWidgets('verifying: a person\'s review or an ID check, the line '
        'names no video', (t) async {
      for (final (step, text) in [
        ('id', "We're checking it's you. This usually takes less than a day."),
        (
          'human',
          "We're checking it's you. This usually takes less than a day.",
        ),
      ]) {
        await section(
          t,
          const DatingHome(state: DatingHomeState.verifying, hasData: true),
          verification: DatingVerification(
            available: true,
            session: DatingVerifySession(
              id: datingTestSession,
              step: step,
              state: 'awaiting_review',
              open: true,
            ),
          ),
        );
        expect(find.text(text), findsOneWidget, reason: step);
        expect(find.textContaining('video'), findsNothing, reason: step);
      }
    });

    testWidgets('verifying: the card reads no verification status', (t) async {
      final held =
          FakeDatingVerificationGateway()
            ..hold = Completer<DatingVerification>();
      await pumpDatingShell(
        t,
        initial: '/me',
        home: FakeDatingHomeGateway(
          home: const DatingHome(
            state: DatingHomeState.verifying,
            hasData: true,
          ),
        ),
        extraRoutes: [
          GoRoute(
            path: '/me',
            builder:
                (_, __) => const Scaffold(
                  body: SingleChildScrollView(child: DatingSection()),
                ),
          ),
        ],
        overrides: [
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(
              FakeHomeStateGateway(state: homeJson(path: 'dating')),
            ),
          ),
          datingVerificationGatewayProvider.overrideWithValue(held),
        ],
      );
      expect(
        find.text(
          "We're checking it's you. This usually takes less than a day.",
        ),
        findsOneWidget,
      );
      expect(held.reads, 0);
      held.hold!.complete(const DatingVerification(available: true));
      await t.pumpAndSettle();
    });

    testWidgets('verifying: the waiting line, and its link opens the check', (
      t,
    ) async {
      await section(
        t,
        const DatingHome(state: DatingHomeState.verifying, hasData: true),
      );
      expect(
        find.text(
          "We're checking it's you. This usually takes less than a day.",
        ),
        findsOneWidget,
      );
      expect(find.text('Dating settings'), findsOneWidget);
      await tapInReach(t, find.text('See where it is'));
      await t.pumpAndSettle();
      // (A push doesn't change the router's location: the screen shown.)
      expect(find.text('Step 10 of 12'), findsOneWidget);
    });

    // Task 3 deviation (T1 fix round 1, M-2): the server's can_resume is
    // false while the check fails, true once a new check passes.
    // Fix round 1 (M-8): the whole card opens the check too.
    testWidgets('verifying: a tap on the card opens the check', (t) async {
      await section(
        t,
        const DatingHome(state: DatingHomeState.verifying, hasData: true),
      );
      await tapInReach(
        t,
        find.text(
          "We're checking it's you. This usually takes less than a day.",
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Step 10 of 12'), findsOneWidget);
    });

    testWidgets('carry 1: a verification pause offers the check, never '
        'Resume', (t) async {
      await section(
        t,
        const DatingHome(
          state: DatingHomeState.paused,
          pauseReason: DatingPauseReason.verification,
          canResume: false,
          check: DatingPauseCheck.needed, // Spec 2 W4b (Task 3 M-4)
          hasData: true,
        ),
      );
      expect(
        find.text("Dating is paused until you verify it's you again."),
        findsOneWidget,
      );
      expect(find.text('Resume'), findsNothing);
      await tapInReach(t, find.text("Verify it's you"));
      await t.pumpAndSettle();
      // (A push doesn't change the router's location: the screen shown.)
      expect(find.text('Step 10 of 12'), findsOneWidget);
    });

    testWidgets('carry 1: once the check holds again (can_resume), a plain '
        'pause that Resume ends; the check is not offered again', (t) async {
      await section(
        t,
        const DatingHome(
          state: DatingHomeState.paused,
          pauseReason: DatingPauseReason.verification,
          canResume: true,
          hasData: true,
        ),
      );
      expect(
        find.text('Dating is paused. Nobody new sees you.'),
        findsOneWidget,
      );
      expect(
        find.text("Dating is paused until you verify it's you again."),
        findsNothing,
      );
      expect(find.text("Verify it's you"), findsNothing);
      expect(find.text('Resume'), findsOneWidget);
    });
  });
}
