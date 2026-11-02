import 'dart:async';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/routing/sign_in_redirect.dart'
    show returningSignUpLocation;
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/auth/sign_up/domain/phone_entry.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/birth_date_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/consent_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/name_step.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_sync_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate.dart';
import 'package:attune/features/onboarding/presentation/widgets/catch_up_steps.dart';
import 'package:attune/features/onboarding/presentation/widgets/couples_joined_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:attune/features/onboarding/presentation/widgets/path_step.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/safety/data/safety_sign_out.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// `/onboarding` (Spec 1 §5.2): the v2 gate under flow_paths_v2, today's
/// OnboardingGate otherwise (and for the debug preview).
class OnboardingEntry extends ConsumerWidget {
  const OnboardingEntry({super.key, this.previewOnboarding = false});

  final bool previewOnboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = kDebugMode && previewOnboarding;
    if (!preview && ref.watch(flowPathsV2Provider)) {
      return const OnboardingGateV2();
    }
    return OnboardingGate(previewOnboarding: previewOnboarding);
  }
}

/// The full app sign-out (the safety sign-out's sequence: wipes, push
/// release, Welcome), replaceable in tests.
final catchUpSignOutProvider = Provider<Future<void> Function()>(
  (ref) => () => safetySignOut(ref),
);

/// The OnboardingSyncService the gate replays the queue with.
final onboardingSyncServiceProvider = Provider<OnboardingSyncService>(
  (ref) => OnboardingSyncService(
    homeStateService: ref.read(homeStateServiceProvider),
  ),
);

enum _Step {
  loading,
  offline,
  hold,
  update,
  consent,
  birthDate,
  name,
  path,
  inviteCode,
  invitePartner,
  joined,
}

/// The v2 gate (Spec 1 §3.7, §3.15): shows only what the account lacks, in
/// order (A5c "We've updated our terms", A2 "Add your date of birth", A1,
/// A6), then R1 for a new Relationship. A hold opens H1; a need this build
/// doesn't know asks for an update; an account that doesn't exist goes
/// back to sign-up (W2 final review M-5). Every launch with `consent` in
/// `needs` comes here before home (M-3): HomeScreen's latch sends it.
class OnboardingGateV2 extends ConsumerStatefulWidget {
  const OnboardingGateV2({super.key});

  @override
  ConsumerState<OnboardingGateV2> createState() => _OnboardingGateV2State();
}

class _OnboardingGateV2State extends ConsumerState<OnboardingGateV2> {
  _Step _step = _Step.loading;
  String? _error;
  int _errorCount = 0;

  /// A6 chose Relationship in this visit: R1 follows.
  bool _relationshipChosen = false;

  /// A stored invite was accepted in this visit: "You are connected".
  bool _joined = false;

  /// The stored invite was tried once in this visit.
  bool _inviteTried = false;

  /// An open space was set as Relationship once in this visit (a server
  /// that still asks for the path then gets A6, never a loop).
  bool _quietTried = false;

  String? get _userId => ref.read(homeAuthProvider).currentUser?.id;

  OnboardingStore _store(String userId) => OnboardingStore(
    ref.read(sharedPreferencesProvider),
    scope: '${OnboardingStore.userScopePrefix}.$userId',
  );

  HomeStateService get _service => ref.read(homeStateServiceProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  void _show(_Step step, {String? error}) {
    if (!mounted) return;
    final sameStep = step == _step;
    final previousError = _error;
    setState(() {
      _step = step;
      _error = error;
      if (error != null) _errorCount++;
    });
    if (error == null) return;
    // A step still on screen reads its own message out: A1, A2 and the
    // code step each time (errorCount), A6 when the words change. Anything
    // else is read out here, once.
    final readByStep =
        sameStep &&
        switch (step) {
          _Step.name || _Step.birthDate || _Step.inviteCode => true,
          _Step.path => error != previousError,
          _ => false,
        };
    if (!readByStep) {
      SemanticsService.announce(error, Directionality.of(context));
    }
  }

  /// The account itself is still owed (a queued A5) or the server has none
  /// yet: accept-invite and set_my_path wait for it (§3.14).
  bool _accountPending(String userId) =>
      _store(userId).pendingSignUp != null ||
      ref.read(homeStateProvider(userId)).server?.hasAccount == false;

  /// What an invite failure means, in the app's words (never the server's).
  String _inviteMessage(RelationshipInviteException error) {
    final loc = AppLocalizations.of(context)!;
    if (error.alreadyInRelationship) return loc.flow_inviteCodeAlreadyIn;
    if (error.retryable) return loc.flow_inviteCodeOffline;
    return loc.flow_inviteCodeRefused;
  }

  Future<void> _go(String location) async {
    final settled = await waitForRouterSettled();
    if (!mounted) return;
    (settled != null && settled.mounted ? settled : context).go(location);
  }

  /// Replays what the phone owes, reads the server, then shows the next
  /// step (or goes home).
  Future<void> _resolve() async {
    final userId = _userId;
    if (userId == null) {
      await _go(RouteNames.login);
      return;
    }
    final store = _store(userId);
    final home = ref.read(homeStateProvider(userId).notifier);
    try {
      await ref
          .read(onboardingSyncServiceProvider)
          .flush(store, onPathSynced: home.apply)
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
    final answer = await home.refresh();
    if (!mounted) return;
    await _next(userId, answer: answer);
  }

  Future<void> _next(String userId, {HomeState? answer}) async {
    final snapshot = ref.read(homeStateProvider(userId));
    final store = _store(userId);
    final live = answer ?? snapshot.server;
    final queuedSignUp = store.pendingSignUp != null;
    if (snapshot.hold) {
      // H1 first: it never waits on the keystore (review I-2).
      _show(_Step.hold);
      unawaited(_blockForAgeHold());
      return;
    }
    if (live == null && !snapshot.known && !queuedSignUp) {
      return _show(_Step.offline);
    }
    // M-5: signed in with no account (a refused or lost A5): sign-up again.
    if (live != null && !live.hasAccount && !queuedSignUp) {
      await _go(returningSignUpLocation);
      return;
    }
    final needs = snapshot.needs;
    if (needs.contains(HomeNeed.unknown)) return _show(_Step.update);
    if (needs.isEmpty) {
      if (_relationshipChosen) return _show(_Step.invitePartner);
      if (_joined) return _show(_Step.joined);
      await _go(RouteNames.home);
      return;
    }
    switch (needs.first) {
      case HomeNeed.consent:
        return _show(_Step.consent);
      case HomeNeed.birthDate:
        return _show(_Step.birthDate);
      case HomeNeed.name:
        return _show(_Step.name);
      case HomeNeed.path:
        // An open or paused shared space is the Relationship path (§3.11):
        // no question whose answer is already known.
        final link = snapshot.link;
        if (!_quietTried &&
            (link == LinkState.linked || link == LinkState.paused)) {
          return _setRelationshipQuietly(userId);
        }
        // A stored invite is accepted only now, after the name (§5.2),
        // and only once the account is on the server (§3.14, B3 I#2).
        if (!_inviteTried &&
            store.pendingInviteCode != null &&
            !_accountPending(userId)) {
          return _acceptStoredInvite(userId);
        }
        return _show(_Step.path);
      case HomeNeed.unknown:
        return _show(_Step.update);
    }
  }

  Future<void> _setRelationshipQuietly(String userId) async {
    _quietTried = true;
    final outcome = await choosePath(
      context,
      ref,
      userId: userId,
      path: AppPath.relationship,
      confirmed: true,
      queueOffline: true,
    );
    if (!mounted) return;
    // Only no connection is "couldn't check"; a refusal asks A6 (B3 #4).
    if (outcome == PathChoiceOutcome.offline) return _show(_Step.offline);
    if (outcome != PathChoiceOutcome.done) return _show(_Step.path);
    await _next(userId);
  }

  /// A6 while the account is still owed (B3 I#2, §3.14): a Relationship or
  /// Just for me choice is queued and counts as done, and the replay is
  /// tried again (A5, then A6); Dating is never queued (D20).
  Future<void> _queueFirstChoice(String userId, AppPath path) async {
    final loc = AppLocalizations.of(context)!;
    if (path == AppPath.dating) {
      return _show(_Step.path, error: loc.flow_pathDatingOffline);
    }
    final home = ref.read(homeStateProvider(userId).notifier);
    await _store(userId).savePendingPath(path);
    home.reloadLocal();
    // R1 makes an invite, which needs the account: Tab 2 offers it later.
    _relationshipChosen = false;
    if (!mounted) return;
    await _resolve();
  }

  /// [typed]: the code was just typed (RI-2), so a refusal stays on the
  /// code step; a stored one falls back to A6.
  Future<void> _acceptStoredInvite(String userId, {bool typed = false}) async {
    _inviteTried = true;
    final store = _store(userId);
    final code = store.pendingInviteCode;
    if (code == null) return _next(userId);
    try {
      await ref.read(invitePartnerServiceProvider).acceptInvite(code);
      await store.clearPendingInviteCode();
      _joined = true;
      if (!mounted) return;
      // Joining is the Relationship path; A6 is skipped (§3.8 RI-3).
      await _setRelationshipQuietly(userId);
    } on RelationshipInviteException catch (error) {
      if (!error.retryable) await store.clearPendingInviteCode();
      if (!mounted) return;
      _show(
        typed ? _Step.inviteCode : _Step.path,
        error: _inviteMessage(error),
      );
    } catch (_) {
      if (!mounted) return;
      if (typed) {
        _show(
          _Step.inviteCode,
          error: AppLocalizations.of(context)!.flow_inviteCodeOffline,
        );
      } else {
        _show(_Step.path);
      }
    }
  }

  /// A failed sign-out leaves the person where they are, never stuck in a
  /// thrown error (the step is free to try again).
  Future<void> _signOut() async {
    try {
      await ref.read(catchUpSignOutProvider)();
    } catch (error) {
      debugPrint('[gate] sign-out failed: ${error.runtimeType}');
    }
  }

  /// Ruling F-8: under 18 at the catch-up, this phone is blocked as W2's
  /// sign-up and A5 replay block it (X1), in the order that can't lose the
  /// block: block (prefs and keychain, then this session), then clear what
  /// this account left queued on the phone (W2 M-3); the caller then signs
  /// out. `entry=returning` stays open (W2 final review M-1).
  ///
  /// Read before the server call, so the block lands even if the gate has
  /// gone by the time the answer comes.
  Future<void> Function() _underAgeBlock(String userId) {
    final ageGate = ref.read(ageGateStoreProvider);
    RoutingNotifier? routing;
    try {
      routing = ref.read(routingNotifierProvider);
    } catch (error) {
      debugPrint('[gate] no session routing: ${error.runtimeType}');
    }
    final store = _store(userId);
    return () async {
      // Never throws (each place is written on its own), and never holds
      // the sign-out behind a hung keystore: the prefs copy is written
      // first (review I-2).
      await ageGate.block().timeout(_keystoreBound, onTimeout: () {});
      routing?.setUnderAgeBlocked(true);
      try {
        await store.reset();
      } catch (error) {
        debugPrint('[gate] queue not cleared: ${error.runtimeType}');
      }
    };
  }

  /// Ruling N-2: H1 for an age hold also blocks this phone, as F-8 does: a
  /// retried under-18 catch-up (`already_set`, the server already holds
  /// it) and a held minor signing back in through "I already have an
  /// account". The block closes creation and guest Opinions only;
  /// `entry=returning` stays open (M-1). The home state says only `hold`,
  /// and `age_review` is the one kind placed today (W1b).
  ///
  /// F-8's order (prefs and keychain, then this session), read before the
  /// first await and bounded like F-8 (review I-2).
  Future<void> _blockForAgeHold() async {
    final ageGate = ref.read(ageGateStoreProvider);
    RoutingNotifier? routing;
    try {
      routing = ref.read(routingNotifierProvider);
    } catch (error) {
      debugPrint('[gate] no session routing: ${error.runtimeType}');
    }
    await ageGate.block().timeout(_keystoreBound, onTimeout: () {});
    routing?.setUnderAgeBlocked(true);
  }

  /// The longest a block waits on the keystore (as restoreBlock, 1 s): the
  /// prefs copy, written first, already holds the block.
  static const _keystoreBound = Duration(seconds: 1);

  Future<void> _acceptTerms() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await _service.acceptUpdatedTerms();
    } catch (_) {
      if (mounted) {
        _show(
          _Step.consent,
          error: AppLocalizations.of(context)!.flow_saveFailed,
        );
      }
      return;
    }
    if (!mounted) return;
    await _resolve();
  }

  Future<void> _saveBirthDate(DateTime date) async {
    final userId = _userId;
    if (userId == null) return;
    // Read before the call: the stop must finish even if the gate is gone.
    final blockUnderAge = _underAgeBlock(userId);
    final signOut = ref.read(catchUpSignOutProvider);
    final router = GoRouter.of(context);
    final BirthDateOutcome outcome;
    try {
      outcome = await _service.setBirthDate(date);
    } catch (_) {
      if (mounted) {
        _show(
          _Step.birthDate,
          error: AppLocalizations.of(context)!.flow_saveFailed,
        );
      }
      return;
    }
    // Under 18: the server placed a hold (§3.15). Ruling (B3 fix round,
    // W2 I-3): block, clear, sign out at once (a minor never stays signed
    // in), then X1, which needs no session.
    if (outcome == BirthDateOutcome.notEligible) {
      await blockUnderAge();
      try {
        await signOut();
      } catch (error) {
        debugPrint('[gate] under-18 sign-out failed: ${error.runtimeType}');
      }
      router.go('${RouteNames.ageStop}?from=account');
      return;
    }
    if (!mounted) return;
    await _resolve();
  }

  Future<void> _saveName(String name) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      await _service.saveDisplayName(userId, name);
    } catch (_) {
      if (mounted) {
        _show(_Step.name, error: AppLocalizations.of(context)!.flow_saveFailed);
      }
      return;
    }
    if (!mounted) return;
    await _resolve();
  }

  Future<void> _choosePath(AppPath path) async {
    final userId = _userId;
    if (userId == null) return;
    final loc = AppLocalizations.of(context)!;
    if (_accountPending(userId)) return _queueFirstChoice(userId, path);
    final outcome = await choosePath(
      context,
      ref,
      userId: userId,
      path: path,
      queueOffline: true,
    );
    if (!mounted) return;
    switch (outcome) {
      case PathChoiceOutcome.done:
        _relationshipChosen = path == AppPath.relationship;
        await _next(userId);
      case PathChoiceOutcome.cancelled:
        return;
      case PathChoiceOutcome.datingOffline:
        _show(_Step.path, error: loc.flow_pathDatingOffline);
      case PathChoiceOutcome.relationshipOpen:
        _show(_Step.path, error: loc.flow_pathOpenSpace);
      case PathChoiceOutcome.needsSignUp:
        if (_accountPending(userId)) return _queueFirstChoice(userId, path);
        _show(_Step.path, error: loc.flow_saveFailed);
      case PathChoiceOutcome.offline:
      case PathChoiceOutcome.failed:
        _show(_Step.path, error: loc.flow_saveFailed);
    }
  }

  Future<void> _submitInviteCode(String raw) async {
    final userId = _userId;
    if (userId == null) return;
    final code = normalizeInviteCode(raw);
    if (code == null) {
      return _show(
        _Step.inviteCode,
        error: AppLocalizations.of(context)!.flow_inviteCodeError,
      );
    }
    await _store(userId).storePendingInviteCode(code);
    if (!mounted) return;
    // No account on the server yet (a queued A5): the code waits for it,
    // and joining is the Relationship path, queued like any first choice.
    if (_accountPending(userId)) {
      return _queueFirstChoice(userId, AppPath.relationship);
    }
    _inviteTried = false;
    await _acceptStoredInvite(userId, typed: true);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.read(homeAuthProvider).currentUser;
    final step = switch (_step) {
      _Step.loading => Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            semanticsLabel: AppLocalizations.of(context)!.flow_accountChecking,
          ),
        ),
      ),
      _Step.offline => CheckOfflineStep(onRetry: _resolve, onSignOut: _signOut),
      _Step.hold => AccountHoldStep(onSignOut: _signOut),
      _Step.update => UpdateAppStep(onSignOut: _signOut),
      _Step.consent => ConsentStep(
        updatedTerms: true,
        errorText: _error,
        onAgree: _acceptTerms,
        onNotNow: _signOut,
      ),
      _Step.birthDate => BirthDateStep(
        order: birthDateOrderFor(Localizations.localeOf(context)),
        todayUtc: _todayUtc(),
        title: AppLocalizations.of(context)!.flow_dobAddTitle,
        errorText: _error,
        errorCount: _errorCount,
        onSubmit: _saveBirthDate,
      ),
      _Step.name => NameStep(
        errorText: _error,
        errorCount: _errorCount,
        onSubmit: _saveName,
      ),
      _Step.path => PathStep(
        ownCountry: countryOfPhone(_e164(user?.phone)),
        openCountries: ref.watch(datingOpenCountriesProvider),
        errorText: _error,
        onContinue: _choosePath,
        onAlreadyInvited: () => _show(_Step.inviteCode),
      ),
      _Step.inviteCode => InviteCodeStep(
        errorText: _error,
        errorCount: _errorCount,
        onSubmit: _submitInviteCode,
        onBack: () => _show(_Step.path),
      ),
      _Step.invitePartner => InvitePartnerScreen(
        onDone: () => unawaited(_go(RouteNames.home)),
      ),
      // Today's "You are connected" card, in the deck it was built for.
      _Step.joined => Scaffold(
        body: SafeArea(
          child: OnboardingDeckScope(
            cardKey: 0,
            accent: OnboardingDeckAccent.couples,
            enableDeck: false,
            child: CouplesJoinedStep(
              onFinish: () => unawaited(_go(RouteNames.home)),
            ),
          ),
        ),
      ),
    };
    return step;
  }

  static DateTime _todayUtc() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  static String _e164(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    return phone.startsWith('+') ? phone : '+$phone';
  }
}

/// RI-2 for a signed-in person (A6's "My partner already invited me"):
/// the code, then today's silent accept until W4b's RI-3.
class InviteCodeStep extends StatefulWidget {
  const InviteCodeStep({
    super.key,
    required this.onSubmit,
    required this.onBack,
    required this.errorCount,
    this.errorText,
  });

  final Future<void> Function(String code) onSubmit;
  final VoidCallback onBack;
  final String? errorText;
  final int errorCount;

  @override
  State<InviteCodeStep> createState() => _InviteCodeStepState();
}

class _InviteCodeStepState extends State<InviteCodeStep> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_code.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return FlowFrame(
      title: loc.flow_inviteCodeTitle,
      onBack: widget.onBack,
      body: FlowTextField(
        controller: _code,
        label: loc.flow_inviteCodeLabel,
        errorText: widget.errorText,
        errorCount: widget.errorCount,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        inputFormatters: [LengthLimitingTextInputFormatter(12)],
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_continue,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
