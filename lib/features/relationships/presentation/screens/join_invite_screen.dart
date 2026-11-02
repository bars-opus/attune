import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/features/relationships/presentation/widgets/linked_moment.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// RI-2 (signed in), RI-3 · Join {name}? and RI-4 · Expired (Spec 1 §3.8,
/// W4b, under flow_couples_v2). The one place an invite is accepted: only
/// after an explicit "Join {name}" tap (D9). The code comes from this
/// account's slot (a link, the Install Referrer, or typed here); the
/// inviter's name only after sign-in, from preview_relationship_invite.
/// Every way out but a retryable failure drops the stored code, so it is
/// never accepted later by whoever is signed in (W4 plan P-10), a system
/// back included (preflight F-9). Nothing is joined before the account has
/// its name (D9): the gate asks for what is missing first.
class JoinInviteScreen extends ConsumerStatefulWidget {
  const JoinInviteScreen({
    super.key,
    required this.onDone,
    required this.onJoined,
    required this.onChooseAnotherWay,
    required this.onNeedsAccount,
    this.onHeld,
  });

  /// "Not now", or nothing to join.
  final VoidCallback onDone;

  /// Joined, after R4: the chat.
  final VoidCallback onJoined;

  /// "Not what you expected? Choose another way to use Attune": A6 when
  /// no path is chosen yet ([firstChoice]), else Settings → How you use
  /// Attune (W4 plan P-11).
  final void Function(bool firstChoice) onChooseAnotherWay;

  /// The account still lacks something (no date of birth, sign-up not
  /// finished): the code is kept and the gate asks for it (§3.8 RI-3).
  final VoidCallback onNeedsAccount;

  /// The acceptor's own hold (account:hold): the gate's H1 path, which
  /// shows H1 and blocks this phone even if its read fails (ruling N-2).
  /// Without it, [onNeedsAccount] (the gate reads the hold itself).
  final VoidCallback? onHeld;

  @override
  ConsumerState<JoinInviteScreen> createState() => _JoinInviteScreenState();
}

enum _Join { loading, enterCode, ready, expired, invalid, own, failed, joined }

class _JoinInviteScreenState extends ConsumerState<JoinInviteScreen> {
  final _code = TextEditingController();
  _Join _state = _Join.loading;
  String? _name;
  String? _relationshipId;
  String? _error;
  int _errorCount = 0;
  bool _busy = false;

  /// The failure can be tried again (offline, too many tries).
  bool _retryable = false;

  String? get _userId => ref.read(homeAuthProvider).currentUser?.id;

  OnboardingStore? _store() {
    final userId = _userId;
    if (userId == null) return null;
    return OnboardingStore(
      ref.read(sharedPreferencesProvider),
      scope: '${OnboardingStore.userScopePrefix}.$userId',
    );
  }

  RelationshipInviteService get _invites =>
      ref.read(invitePartnerServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _show(_Join state, {String? error, bool retryable = false}) {
    if (!mounted) return;
    setState(() {
      _state = state;
      _error = error;
      _retryable = retryable;
      if (error != null) _errorCount++;
    });
    if (error != null && state != _Join.enterCode) {
      SemanticsService.announce(error, Directionality.of(context));
    }
  }

  Future<void> _start() async {
    final code = _store()?.pendingInviteCode;
    if (code == null) return _show(_Join.enterCode);
    await _preview(code);
  }

  Future<void> _drop() async => _store()?.clearPendingInviteCode();

  /// A failure in the app's words (batch 5): the attempt limit says so; the
  /// server's own failure (it answered) never blames the connection; only
  /// no connection says "when you're online"; a refusal for good is the
  /// neutral "couldn't link".
  String _failureWords(
    AppLocalizations loc,
    RelationshipInviteException error,
  ) {
    if (error.alreadyInRelationship) return loc.flow_joinAlreadyIn;
    if (error.kind == InviteRefusalKind.tryLater) return loc.flow_joinTryLater;
    if (!error.retryable) return loc.flow_joinNotPossible;
    if (error.serverError) return loc.flow_inviteCodeServerError;
    return loc.flow_inviteCodeOffline;
  }

  /// D9: the account is set up (its name, date of birth and consent on the
  /// server, nothing queued) before anything is joined; only the path may
  /// still be owed, since joining is the path. Null when it couldn't be
  /// read.
  Future<bool?> _accountReady(String userId, OnboardingStore store) async {
    if (store.pendingSignUp != null) return false;
    var snapshot = ref.read(homeStateProvider(userId));
    if (snapshot.server == null) {
      await ref.read(homeStateProvider(userId).notifier).refresh();
      if (!mounted) return null;
      snapshot = ref.read(homeStateProvider(userId));
    }
    if (!snapshot.known) return null;
    if (snapshot.server?.hasAccount == false) return false;
    return !snapshot.needs.any((need) => need != HomeNeed.path);
  }

  void _held() => (widget.onHeld ?? widget.onNeedsAccount)();

  Future<void> _preview(String code) async {
    final loc = AppLocalizations.of(context)!;
    _show(_Join.loading);
    final InvitePreview preview;
    try {
      preview = await _invites.previewInvite(code);
    } on RelationshipInviteException catch (error) {
      if (!error.retryable) await _drop();
      return _show(
        _Join.failed,
        error: _failureWords(loc, error),
        retryable: error.retryable,
      );
    }
    if (!mounted) return;
    _name = preview.inviterFirstName;
    switch (preview.state) {
      case InvitePreviewState.ok:
        return _show(_Join.ready);
      case InvitePreviewState.expired:
        await _drop();
        return _show(_Join.expired);
      case InvitePreviewState.invalid:
        await _drop();
        return _show(_Join.invalid);
      case InvitePreviewState.own:
        await _drop();
        return _show(_Join.own);
      case InvitePreviewState.linked:
        await _drop();
        widget.onJoined();
    }
  }

  Future<void> _submitCode() async {
    final loc = AppLocalizations.of(context)!;
    final code = normalizeInviteCode(_code.text);
    if (code == null) {
      return _show(_Join.enterCode, error: loc.flow_inviteCodeError);
    }
    await _store()?.storePendingInviteCode(code);
    if (!mounted) return;
    await _preview(code);
  }

  Future<void> _join() async {
    if (_busy) return;
    final loc = AppLocalizations.of(context)!;
    final store = _store();
    final code = store?.pendingInviteCode;
    final userId = _userId;
    if (store == null || code == null || userId == null) {
      return _show(_Join.enterCode);
    }
    final home = ref.read(homeStateProvider(userId).notifier);
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() => _busy = true);
    try {
      final ready = await _accountReady(userId, store);
      if (!mounted) return;
      if (ready == null) {
        return _show(
          _Join.failed,
          error: loc.flow_inviteCodeOffline,
          retryable: true,
        );
      }
      // Ruling M-3: a hold drops the code, as the refusal path does.
      if (ref.read(homeStateProvider(userId)).hold) {
        await store.clearPendingInviteCode();
        return _held();
      }
      if (!ready) return widget.onNeedsAccount();
      final joined = await _invites.acceptInvite(code);
      await store.clearPendingInviteCode();
      _relationshipId = joined.relationshipId;
      // Seen here: R4 is this screen's last step, so the home's R4 doesn't
      // show it again on this phone.
      await InviteDeviceStore(
        prefs,
        userId: userId,
      ).markLinkedMomentSeen(joined.relationshipId);
      unawaited(home.refresh());
      _show(_Join.joined);
    } on RelationshipInviteException catch (error) {
      if (error.signUpIncomplete ||
          error.kind == InviteRefusalKind.ageRequired) {
        widget.onNeedsAccount();
        return;
      }
      if (!error.retryable) await store.clearPendingInviteCode();
      if (!mounted) return;
      // The acceptor's own hold is H1, from the gate (carried: never
      // "couldn't link").
      if (error.kind == InviteRefusalKind.hold) return _held();
      switch (error.kind) {
        case InviteRefusalKind.expired:
          return _show(_Join.expired);
        case InviteRefusalKind.own:
          return _show(_Join.own);
        case InviteRefusalKind.invalid || InviteRefusalKind.alreadyAccepted:
          return _show(_Join.invalid);
        default:
          return _show(
            _Join.failed,
            error: _failureWords(loc, error),
            retryable: error.retryable,
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave(VoidCallback then) async {
    await _drop();
    then();
  }

  Future<void> _askOnWhatsApp() async {
    final loc = AppLocalizations.of(context)!;
    final name = _name;
    final text =
        name == null
            ? loc.flow_joinExpiredMessageUnnamed
            : loc.flow_joinExpiredMessage(name);
    final actions = ref.read(inviteShareActionsProvider);
    if (!await actions.openWhatsApp(text)) await actions.share(text);
  }

  bool get _backDropsCode => switch (_state) {
    _Join.loading || _Join.joined => false,
    _Join.failed => !_retryable,
    _ => true,
  };

  @override
  Widget build(BuildContext context) => PopScope(
    // Batch-5 review M-1: never left mid-accept (R4 is marked seen as the
    // accept lands, so it and its ask would be lost).
    canPop: !_busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop || !_backDropsCode) return;
      final store = _store();
      if (store != null) unawaited(store.clearPendingInviteCode());
    },
    child: _page(context),
  );

  Widget _page(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = _name;
    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    Widget words(String text) => Text(text, style: bodyStyle);
    final otherWay = FlowTextLink(
      label: loc.flow_joinOtherWay,
      onPressed: () {
        final userId = _userId;
        final firstChoice =
            userId == null || ref.read(homeStateProvider(userId)).path == null;
        _leave(() => widget.onChooseAnotherWay(firstChoice));
      },
    );

    switch (_state) {
      case _Join.loading:
        return FlowFrame(
          title: loc.flow_inviteCodeTitle,
          body: Center(
            child: CircularProgressIndicator(
              semanticsLabel: loc.flow_joinChecking,
            ),
          ),
        );
      case _Join.enterCode:
        return FlowFrame(
          title: loc.flow_inviteCodeTitle,
          onBack: () => _leave(widget.onDone),
          body: FlowTextField(
            controller: _code,
            label: loc.flow_inviteCodeLabel,
            errorText: _error,
            errorCount: _errorCount,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(12)],
            autofocus: true,
            onSubmitted: (_) => _submitCode(),
          ),
          actions: [
            FlowPrimaryButton(label: loc.flow_continue, onPressed: _submitCode),
          ],
        );
      case _Join.ready:
        return FlowFrame(
          title:
              name == null ? loc.flow_ri3TitleUnnamed : loc.flow_ri3Title(name),
          body: words(
            name == null ? loc.flow_ri3BodyUnnamed : loc.flow_ri3Body(name),
          ),
          actions: [
            FlowPrimaryButton(
              label:
                  name == null
                      ? loc.flow_ri3ButtonUnnamed
                      : loc.flow_ri3Button(name),
              busy: _busy,
              onPressed: _join,
            ),
            FlowSecondaryButton(
              label: loc.flow_notNow,
              onPressed: _busy ? null : () => _leave(widget.onDone),
            ),
            otherWay,
          ],
        );
      // Never animated (§2.2): the expired and refusal states are plain.
      case _Join.expired:
        return FlowFrame(
          title: loc.flow_joinExpiredTitle,
          body: words(
            name == null
                ? loc.flow_joinExpiredUnnamed
                : loc.flow_joinExpired(name),
          ),
          actions: [
            FlowPrimaryButton(
              label:
                  name == null
                      ? loc.flow_joinAskWhatsAppUnnamed
                      : loc.flow_joinAskWhatsApp(name),
              onPressed: _askOnWhatsApp,
            ),
            FlowSecondaryButton(
              label: loc.flow_notNow,
              onPressed: () => _leave(widget.onDone),
            ),
          ],
        );
      case _Join.invalid:
      case _Join.own:
        return FlowFrame(
          title: loc.flow_inviteCodeTitle,
          body: FlowErrorLine(
            text: _state == _Join.own ? loc.flow_joinOwn : loc.flow_joinInvalid,
            style: bodyStyle,
            liveRegion: true,
          ),
          actions: [
            FlowPrimaryButton(
              label: loc.flow_joinEnterAgain,
              onPressed: () {
                _code.clear();
                _show(_Join.enterCode);
              },
            ),
            FlowSecondaryButton(
              label: loc.flow_notNow,
              onPressed: () => _leave(widget.onDone),
            ),
          ],
        );
      case _Join.failed:
        return FlowFrame(
          title: loc.flow_inviteCodeTitle,
          body: FlowErrorLine(
            key: ValueKey(_errorCount),
            text: _error ?? loc.flow_inviteCodeOffline,
            style: bodyStyle,
            liveRegion: true,
          ),
          actions: [
            if (_retryable)
              FlowPrimaryButton(label: loc.flow_tryAgain, onPressed: _start),
            FlowSecondaryButton(
              label: loc.flow_notNow,
              onPressed: () => _leave(widget.onDone),
            ),
          ],
        );
      case _Join.joined:
        return LinkedMoment(
          relationshipId: _relationshipId ?? '',
          partnerFirstName: name,
          onContinue: widget.onJoined,
        );
    }
  }
}
