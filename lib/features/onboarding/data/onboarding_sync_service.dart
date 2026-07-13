import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:flutter/foundation.dart';

/// Replays an onboarding submission that never reached the server.
///
/// Onboarding completes locally even when the remote write fails, so the user
/// is never trapped in the flow by a bad network. That leaves a debt: the
/// user's mode / attachment answers / anchors exist only on the device. This
/// service pays that debt on a later launch, which is what makes the flow's
/// "we will sync when your connection is stable" message true.
///
/// The remote write is a set of idempotent upserts keyed by the user's own id,
/// so replaying it is safe even if part of the original attempt did land.
class OnboardingSyncService {
  OnboardingSyncService({OnboardingSubmissionService? submissionService})
    : _submissionService = submissionService ?? OnboardingSubmissionService();

  final OnboardingSubmissionService _submissionService;

  /// Flushes [store]'s pending submission, if any. Silent no-op when there is
  /// nothing owed. Failures are swallowed and the payload is KEPT, so the next
  /// launch tries again.
  Future<void> flush(OnboardingStore store) async {
    final pending = store.pendingSubmission;
    if (pending == null) return;

    try {
      await _submissionService.submit(
        mode: pending.mode,
        displayName: pending.displayName,
        attachmentAnswers: pending.attachmentAnswers,
        anchors: pending.anchors,
      );
      await store.clearPendingSubmission();
      debugPrint('[onboarding] pending submission synced');
    } catch (error) {
      // Keep the payload; a later launch retries. Log the category only.
      debugPrint('[onboarding] pending sync failed: ${error.runtimeType}');
    }
  }
}
