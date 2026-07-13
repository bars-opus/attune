import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Submission service double: fails until told otherwise, and records calls.
class _FakeSubmissionService implements OnboardingSubmissionService {
  _FakeSubmissionService({this.shouldFail = true});

  bool shouldFail;
  int submitCount = 0;
  OnboardingMode? lastMode;
  List<int>? lastAnswers;
  List<String>? lastAnchors;
  String? lastDisplayName;

  @override
  Future<void> submit({
    required OnboardingMode mode,
    required String displayName,
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async {
    submitCount++;
    lastMode = mode;
    lastDisplayName = displayName;
    lastAnswers = attachmentAnswers;
    lastAnchors = anchors;
    if (shouldFail) throw Exception('network down');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late OnboardingStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = OnboardingStore(prefs, scope: 'user.abc');
  });

  const submission = PendingOnboardingSubmission(
    mode: OnboardingMode.couples,
    displayName: 'Ama',
    attachmentAnswers: [1, 2, 3],
    anchors: ['honesty', 'time'],
  );

  test('a pending submission round-trips through the store', () async {
    expect(store.pendingSubmission, isNull);

    await store.savePendingSubmission(submission);

    final restored = store.pendingSubmission;
    expect(restored, isNotNull);
    expect(restored!.mode, OnboardingMode.couples);
    expect(restored.displayName, 'Ama');
    expect(restored.attachmentAnswers, [1, 2, 3]);
    expect(restored.anchors, ['honesty', 'time']);
  });

  test(
    'flush replays the pending submission and clears it on success',
    () async {
      await store.savePendingSubmission(submission);
      final fake = _FakeSubmissionService(shouldFail: false);

      await OnboardingSyncService(submissionService: fake).flush(store);

      expect(fake.submitCount, 1);
      expect(fake.lastMode, OnboardingMode.couples);
      expect(fake.lastDisplayName, 'Ama');
      expect(fake.lastAnswers, [1, 2, 3]);
      expect(fake.lastAnchors, ['honesty', 'time']);
      // Debt paid — nothing left to retry.
      expect(store.pendingSubmission, isNull);
    },
  );

  test(
    'flush KEEPS the payload when the retry fails, so a later launch retries',
    () async {
      await store.savePendingSubmission(submission);
      final fake = _FakeSubmissionService(shouldFail: true);

      await OnboardingSyncService(submissionService: fake).flush(store);

      expect(fake.submitCount, 1);
      // Still owed: this is what makes "we will sync later" true rather than a
      // silent data loss.
      expect(store.pendingSubmission, isNotNull);

      // Next launch, network back: the debt is paid.
      fake.shouldFail = false;
      await OnboardingSyncService(submissionService: fake).flush(store);
      expect(fake.submitCount, 2);
      expect(store.pendingSubmission, isNull);
    },
  );

  test('flush is a no-op when nothing is pending', () async {
    final fake = _FakeSubmissionService(shouldFail: false);

    await OnboardingSyncService(submissionService: fake).flush(store);

    expect(fake.submitCount, 0);
  });

  test('reset clears a pending submission', () async {
    await store.savePendingSubmission(submission);
    await store.reset();
    expect(store.pendingSubmission, isNull);
  });
}
