import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key, this.previewOnboarding = false});

  final bool previewOnboarding;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  final _authService = PasswordlessAuthService();
  final _inviteService = RelationshipInviteService();
  late final Future<_GateData> _gateDataFuture = _loadGateData();

  Future<_GateData> _loadGateData() async {
    final prefs = await SharedPreferences.getInstance();
    final store = OnboardingStore(prefs, scope: _storeScope);
    final userId = _authService.currentUser?.id;

    // Every authenticated arrival here — whether already signed in when the
    // invite link landed, or freshly verified via LoginScreen — has this as
    // its one and only chance to consume a pending invite: acceptInvite's
    // sole call site used to be OnboardingFlow's embedded PasswordlessAuthStep,
    // which no longer exists now that auth happens on LoginScreen before
    // /onboarding is ever reached. Accept it here, once, before the
    // isComplete check below decides where the user ends up, and remember
    // the outcome for OnboardingFlow's completedMode logic (couples vs.
    // couplesPending) since it can no longer infer that from a since-cleared
    // pendingInviteCode.
    var acceptedInvite = false;
    if (userId != null && store.pendingInviteCode != null) {
      acceptedInvite = await _acceptPendingInvite(store);
    }

    // Server-truth-first (see OnboardingStore.resolveIsComplete's doc): a
    // local-only isComplete check sent a returning, already-onboarded user
    // (onboarded on a different device/install) straight back into
    // OnboardingFlow.
    final isComplete = await store.resolveIsComplete(userId);
    return _GateData(
      store: store,
      isComplete: isComplete,
      acceptedInvite: acceptedInvite,
    );
  }

  /// Returns true only on a genuine, successful acceptance.
  Future<bool> _acceptPendingInvite(OnboardingStore store) async {
    final code = store.pendingInviteCode;
    if (code == null) return false;
    try {
      await _inviteService.acceptInvite(code);
      await store.clearPendingInviteCode();
      return true;
    } on RelationshipInviteException catch (error) {
      // Deterministic rejections (expired/self/already-accepted/invalid)
      // can never succeed on retry — drop the stale code so it doesn't
      // resurface and get retried on every future gate visit. Transient
      // failures (retryable) intentionally keep the code so the next visit
      // tries again, mirroring OnboardingFlow's own retry-once handling.
      if (!error.retryable) await store.clearPendingInviteCode();
      return false;
    } catch (_) {
      // Unreachable client/network failure — leave the code in place for
      // a later retry rather than silently discarding a real invite.
      return false;
    }
  }

  /// A plain addPostFrameCallback here raced GoRouter's own settling right
  /// after main.dart's deep-link handler had JUST issued its own .go() to
  /// land on this gate — one painted frame isn't proof the router's
  /// internal transition from that .go() has finished, and calling .go()
  /// again into the middle of it produced a transient "Page not found"
  /// GoException before self-correcting. waitForRouterSettled (shared with
  /// main.dart's own post-deep-link navigation) closes that window.
  Future<void> _redirectWhenSettled(String location) async {
    final settledContext = await waitForRouterSettled();
    if (settledContext == null || !settledContext.mounted || !mounted) return;
    settledContext.go(location);
  }

  String get _storeScope {
    if (kDebugMode && widget.previewOnboarding) {
      return OnboardingStore.previewScope;
    }

    final userId = _authService.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return OnboardingStore.anonymousScope;
    }

    return '${OnboardingStore.userScopePrefix}.$userId';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateData>(
      future: _gateDataFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        final store = snapshot.data!.store;
        final isComplete = snapshot.data!.isComplete;
        final isPreview = kDebugMode && widget.previewOnboarding;
        final isUnauthenticated = _authService.currentUser == null;
        // Auth now always happens on LoginScreen (the same phone-OTP screen
        // every other sign-in uses — see its own _goToOnboarding, which
        // accepts any pending invite before routing back here) rather than
        // OnboardingFlow's old embedded PasswordlessAuthStep. So an
        // unauthenticated visitor — first-time user or invitee alike — is
        // sent there instead of home; LoginScreen returns them to
        // /onboarding once verified, at which point they're authenticated
        // and fall through to the isComplete check below like anyone else.
        if (isUnauthenticated && !isPreview) {
          unawaited(_redirectWhenSettled(RouteNames.login));
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        if (isComplete) {
          unawaited(_redirectWhenSettled(RouteNames.home));
          return const Scaffold(
            body: Center(child: CircularLoadingIndicator()),
          );
        }

        // Debug-only UI preview; real onboarding is otherwise only ever
        // reached already-authenticated (see above), so OnboardingFlow no
        // longer needs an auth step of its own.
        return OnboardingFlow(
          store: store,
          acceptedPendingInvite: snapshot.data!.acceptedInvite,
          onComplete: () {
            context.go(RouteNames.home);
          },
        );
      },
    );
  }
}

class _GateData {
  const _GateData({
    required this.store,
    required this.isComplete,
    required this.acceptedInvite,
  });

  final OnboardingStore store;
  final bool isComplete;
  final bool acceptedInvite;
}
