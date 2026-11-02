import 'package:attune/features/auth/sign_up/data/account_service.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  OnboardingSyncService({
    OnboardingSubmissionService? submissionService,
    AccountService? accountService,
    HomeStateService? homeStateService,
    Future<void> Function()? onSignUpNotEligible,
  }) : _submissionService = submissionService ?? OnboardingSubmissionService(),
       _accountService = accountService,
       _homeStateService = homeStateService,
       _onSignUpNotEligible = onSignUpNotEligible ?? _blockAndSignOut;

  final OnboardingSubmissionService _submissionService;
  final AccountService? _accountService;
  final HomeStateService? _homeStateService;
  final Future<void> Function() _onSignUpNotEligible;

  /// Flushes [store]'s pending submission, if any. Silent no-op when there is
  /// nothing owed. Failures are swallowed and the payload is KEPT, so the next
  /// launch tries again.
  ///
  /// Spec 1 W3a: after the account, A6's queued choice (set_my_path);
  /// [onPathSynced] receives the home state the server answered.
  Future<void> flush(
    OnboardingStore store, {
    void Function(HomeState state)? onPathSynced,
  }) async {
    // Spec 1 W2b: the account itself first (A5 queued offline), so the
    // users row exists before today's onboarding writes land.
    await _flushSignUp(store);
    // Review M-3: while the account is still owed, today's onboarding waits.
    if (store.pendingSignUp != null) return;
    await _flushPath(store, onPathSynced);

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

  /// Replays A5's complete_sign_up (idempotent). A refusal can't succeed on
  /// a retry, so the payload goes; an under-18 refusal also blocks this
  /// phone and signs out, as X1's server variant does (spec §3.3 A5).
  /// Offline: kept for the next launch.
  Future<void> _flushSignUp(OnboardingStore store) async {
    final pending = store.pendingSignUp;
    if (pending == null) return;
    try {
      final accounts =
          _accountService ?? AccountService(SupabaseAccountGateway());
      await accounts.completeSignUp(
        displayName: pending.displayName,
        birthDate: pending.birthDate,
      );
      await store.clearPendingSignUp();
      debugPrint('[onboarding] pending sign-up synced');
    } on SignUpRefused catch (refused) {
      debugPrint('[onboarding] pending sign-up refused: ${refused.reason.name}');
      if (refused.reason == SignUpRefusal.notEligible) {
        // The stop first, so a failed reset can't skip the block.
        await _onSignUpNotEligible();
        // Review M-3: nothing the refused person entered stays on the phone.
        await store.reset();
      }
      await store.clearPendingSignUp();
    } catch (error) {
      debugPrint('[onboarding] pending sign-up kept: ${error.runtimeType}');
    }
  }

  /// Replays A6's queued Relationship or Just for me (Spec 1 §3.7, §3.14;
  /// never Dating, D20). A refusal that a replay can't fix drops it, and
  /// the gate asks again; offline, or an account not ready yet, keeps it.
  /// It is sent only while the server still asks for a path, so it never
  /// replaces one chosen on another device.
  Future<void> _flushPath(
    OnboardingStore store,
    void Function(HomeState state)? onPathSynced,
  ) async {
    final path = store.pendingPath;
    if (path == null) return;
    try {
      final service =
          _homeStateService ?? HomeStateService(SupabaseHomeStateGateway());
      // Batch-1 review #7: only while the account still owes a path. One
      // chosen meanwhile (another device) wins; the stale choice goes.
      final current = await service.fetch();
      if (!current.needs.contains(HomeNeed.path)) {
        await store.clearPendingPath();
        onPathSynced?.call(current);
        debugPrint('[onboarding] pending path dropped: already chosen');
        return;
      }
      final state = await service.setPath(
        path,
        confirmed: store.pendingPathConfirmed,
      );
      onPathSynced?.call(state);
      await store.clearPendingPath();
      debugPrint('[onboarding] pending path synced');
    } on PathRefused catch (refused) {
      debugPrint('[onboarding] pending path refused: ${refused.reason.name}');
      if (refused.reason != PathRefusal.needsSignUp) {
        await store.clearPendingPath();
      }
    } catch (error) {
      debugPrint('[onboarding] pending path kept: ${error.runtimeType}');
    }
  }

  static Future<void> _blockAndSignOut() async {
    try {
      await AgeGateStore(await SharedPreferences.getInstance()).block();
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      debugPrint('[onboarding] age refusal handling failed: ${error.runtimeType}');
    }
  }
}
