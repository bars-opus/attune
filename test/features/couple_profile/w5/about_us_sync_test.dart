// Spec 1 W5 (§3.14, §5.2): OnboardingSyncService replays queued About us
// answers after the path, and a failed replay never stops the rest.
import 'dart:async';

import 'package:attune/features/couple_profile/presentation/couple_profile_providers.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/home_harness.dart';

/// Records when the onboarding submission is sent.
class _Submissions implements OnboardingSubmissionService {
  int sent = 0;

  @override
  Future<void> submit({
    required OnboardingMode mode,
    required String displayName,
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async => sent++;
}

void main() {
  test('the About us replay never delays the onboarding submission '
      '(fix round 1, M-2)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = OnboardingStore(prefs, scope: 'user.u-sync');
    await store.savePendingSubmission(
      const PendingOnboardingSubmission(
        mode: OnboardingMode.couples,
        displayName: 'Ama',
        attachmentAnswers: [1, 2, 3],
        anchors: ['honesty'],
      ),
    );
    final replay = Completer<void>();
    final submissions = _Submissions();
    final flushing = OnboardingSyncService(
      homeStateService: HomeStateService(FakeHomeStateGateway()),
      submissionService: submissions,
      flushAboutUs: () => replay.future,
    ).flush(store);
    await pumpEventQueue();
    expect(submissions.sent, 1, reason: 'sent while About us still replays');
    expect(store.pendingSubmission, isNull);
    replay.complete();
    await flushing;
  });

  test('a flush replays About us answers; a failure is contained', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = OnboardingStore(prefs, scope: 'user.u-sync');
    var replays = 0;
    final service = OnboardingSyncService(
      homeStateService: HomeStateService(FakeHomeStateGateway()),
      flushAboutUs: () async => replays++,
    );
    await service.flush(store);
    expect(replays, 1);

    final failing = OnboardingSyncService(
      homeStateService: HomeStateService(FakeHomeStateGateway()),
      flushAboutUs: () async => throw StateError('offline'),
    );
    await expectLater(failing.flush(store), completes);
  });

  test('final review I-1: the flush never waits on the About us replay',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = OnboardingStore(prefs, scope: 'user.u-sync');
    final never = Completer<void>();
    var done = false;
    unawaited(
      OnboardingSyncService(
        homeStateService: HomeStateService(FakeHomeStateGateway()),
        flushAboutUs: () => never.future,
      ).flush(store).then((_) => done = true),
    );
    await pumpEventQueue();
    expect(done, isTrue, reason: 'a hanging replay must not hold the flush');
  });

  test('final review I-1: a replay that throws at once is contained',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = OnboardingStore(prefs, scope: 'user.u-sync');
    await expectLater(
      OnboardingSyncService(
        homeStateService: HomeStateService(FakeHomeStateGateway()),
        flushAboutUs: () => throw StateError('sync throw'),
      ).flush(store),
      completes,
    );
    await pumpEventQueue();
  });

  testWidgets('final review I-1: a hanging About us replay never delays '
      "HomeScreen's home-state refresh", (tester) async {
    final never = Completer<void>();
    late final FakeHomeStateGateway gateway;
    int? fetchesAtReplay;
    final h = await pumpHome(
      tester,
      prefsValues: {
        HomeStateStore.keyFor('u-home'):
            '{"tab":"chat","link":"pending","needs":[],"hold":false,'
            '"at":"2026-10-26T08:00:00.000Z"}',
      },
      server: homeJson(path: 'relationship', link: 'pending'),
      overrides: [
        aboutUsOutboxFlushProvider.overrideWithValue(() {
          fetchesAtReplay ??= gateway.count('get_my_home_state');
          // Ama accepted meanwhile: the server now says linked.
          gateway.state = homeJson(path: 'relationship', link: 'linked');
          return never.future;
        }),
      ],
      onGateway: (g) => gateway = g,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(fetchesAtReplay, isNotNull, reason: 'the replay was started');
    expect(
      h.gateway.count('get_my_home_state'),
      greaterThan(fetchesAtReplay!),
      reason: 'the reconcile refreshed the home state without the replay',
    );
    expect(find.text('TAB2 chat linked'), findsOneWidget);
    // Let any 20 s guard run out before teardown.
    await tester.pump(const Duration(seconds: 21));
  });
}
