import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_qr_code.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/relationships/data/invite_messages.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// R1 · Invite your partner, and R2 · the heads-up (Spec 1 §3.8, W4b,
/// under flow_couples_v2). The optional first name stays on this phone
/// (InviteDeviceStore); the message carries the code in every register;
/// the invite is made on opening (or, from another path, on the first
/// send, which is also the switch to Relationship, §3.12).
class InvitePartnerStep extends ConsumerStatefulWidget {
  const InvitePartnerStep({
    super.key,
    required this.invites,
    required this.onDone,
    this.switchPath = false,
    this.pauseConfirmed = false,
    this.onAlreadyInvited,
  });

  final RelationshipInviteService invites;
  final VoidCallback onDone;
  final bool switchPath;
  final bool pauseConfirmed;

  /// "My partner already invited me"; hidden when null.
  final VoidCallback? onAlreadyInvited;

  @override
  ConsumerState<InvitePartnerStep> createState() => _InvitePartnerStepState();
}

enum _Channel { whatsApp, share, qr, copy }

class _InvitePartnerStepState extends ConsumerState<InvitePartnerStep> {
  final _name = TextEditingController();
  RelationshipInvite? _invite;
  Future<RelationshipInvite?>? _making;
  InviteRegister _register = InviteRegister.simple;
  bool _foundItMyself = false;
  bool _whatsApp = false;
  bool _sent = false;
  bool _copied = false;
  bool _busy = false;
  String? _error;
  int _errorCount = 0;

  InviteDeviceStore? _store;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId != null) {
      try {
        _store = InviteDeviceStore(
          ref.read(sharedPreferencesProvider),
          userId: userId,
        );
        _name.text = _store!.partnerFirstName ?? '';
      } catch (_) {
        // No SharedPreferences (a bare host): the name lives in the field.
      }
    }
    unawaited(_checkWhatsApp());
    // Made after the first frame: the step reads its words from context.
    if (!widget.switchPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_ensureInvite());
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _checkWhatsApp() async {
    final can = await ref.read(inviteShareActionsProvider).canOpenWhatsApp();
    if (mounted) setState(() => _whatsApp = can);
  }

  String? get _partnerName {
    final name = _name.text.trim();
    return name.isEmpty ? null : name;
  }

  void _fail(String message) {
    setState(() {
      _error = message;
      _errorCount++;
    });
    SemanticsService.announce(message, Directionality.of(context));
  }

  /// The live invite, made once (concurrent taps share one call).
  Future<RelationshipInvite?> _ensureInvite() {
    final invite = _invite;
    if (invite != null) return Future.value(invite);
    return _making ??= _make().whenComplete(() => _making = null);
  }

  Future<RelationshipInvite?> _make() async {
    final loc = AppLocalizations.of(context)!;
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return null;
    // Read before the first await: ref can't be used once the step is gone.
    final home = ref.read(homeStateProvider(userId).notifier);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.switchPath) {
        final outcome = await choosePath(
          context,
          ref,
          userId: userId,
          path: AppPath.relationship,
          confirmed: widget.pauseConfirmed,
        );
        if (!mounted) return null;
        if (outcome == PathChoiceOutcome.cancelled) return null;
        if (outcome != PathChoiceOutcome.done) {
          _fail(
            outcome == PathChoiceOutcome.offline
                ? loc.flow_switchOffline
                : loc.flow_saveFailed,
          );
          return null;
        }
      }
      final invite = await widget.invites.createInvite();
      if (!mounted) return null;
      setState(() => _invite = invite);
      return invite;
    } on RelationshipInviteException catch (error) {
      if (!mounted) return null;
      if (error.alreadyActiveRelationship) {
        widget.onDone();
        return null;
      }
      _fail(inviteErrorCopy(loc, error));
      return null;
    } catch (_) {
      if (mounted) _fail(loc.flow_inviteErrorTryAgain);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
      // The link state changed (pending): every reader catches up.
      unawaited(home.refresh());
    }
  }

  String _message(AppLocalizations loc, String code) => inviteMessage(
    loc,
    register: _register,
    link: RelationshipInvite.linkFor(code),
    code: code,
    partnerFirstName: _partnerName,
    foundItMyself: _foundItMyself,
  );

  Future<void> _send(_Channel channel) async {
    final loc = AppLocalizations.of(context)!;
    final actions = ref.read(inviteShareActionsProvider);
    final metrics = ref.read(metricCounterProvider);
    final invite = await _ensureInvite();
    if (invite == null || !mounted) return;
    final text = _message(loc, invite.code);
    switch (channel) {
      case _Channel.whatsApp:
        metrics.bump(ClientMetricKey.inviteSharedWhatsapp);
        final opened = await actions.openWhatsApp(text);
        if (!opened) await actions.share(text);
      case _Channel.share:
        metrics.bump(ClientMetricKey.inviteSharedShare);
        await actions.share(text);
      case _Channel.qr:
        metrics.bump(ClientMetricKey.inviteSharedQr);
        await _showQr(invite);
      case _Channel.copy:
        metrics.bump(ClientMetricKey.inviteSharedCopy);
        await actions.copy(invite.code);
        if (!mounted) return;
        setState(() => _copied = true);
        SemanticsService.announce(
          loc.flow_r1CodeCopied,
          Directionality.of(context),
        );
    }
    if (mounted) setState(() => _sent = true);
  }

  Future<void> _showQr(RelationshipInvite invite) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) {
        final loc = AppLocalizations.of(sheet)!;
        final theme = Theme.of(sheet);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    loc.flow_r1QrTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Semantics(
                  image: true,
                  label: loc.flow_r1QrSemantics,
                  child: ExcludeSemantics(
                    child: InviteQrCode(data: invite.deepLink),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Semantics(
                  container: true,
                  label: loc.flow_inviteCodeSemantics(
                    invite.code.split('').join(' '),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      invite.code,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        letterSpacing: Spacing.xs,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                FlowSecondaryButton(
                  label: loc.flow_close,
                  onPressed: () => Navigator.of(sheet).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = _partnerName;
    final invite = _invite;
    final error = _error;
    final registers = offeredInviteRegisters();
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    return FlowFrame(
      title: loc.flow_invitePartnerTitle,
      hint:
          name == null
              ? loc.flow_invitePartnerBody
              : loc.flow_invitePartnerBodyNamed(name),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowTextField(
            controller: _name,
            label: loc.flow_r1NameLabel,
            // Long at large text sizes: above the field, never over it.
            labelAbove: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              LengthLimitingTextInputFormatter(InviteDeviceStore.maxNameLength),
            ],
            onChanged: (value) {
              setState(() {});
              unawaited(_store?.savePartnerFirstName(value));
            },
          ),
          const SizedBox(height: Spacing.xs),
          Text(loc.flow_r1NameHelper, style: bodyStyle),
          const SizedBox(height: Spacing.md),
          Semantics(
            header: true,
            child: Text(
              loc.flow_r1ToneTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: loc.flow_r1ToneGroup,
            child: Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                for (final register in registers)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    child: ChoiceChip(
                      label: Text(_registerLabel(loc, register)),
                      selected: _register == register,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _register = register);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _foundItMyself,
            title: Text(loc.flow_r1FoundMyselfToggle, style: bodyStyle),
            onChanged: (value) => setState(() => _foundItMyself = value),
          ),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    name == null
                        ? loc.flow_r1PreviewTitle
                        : loc.flow_r1PreviewTitleNamed(name),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                if (invite == null && _busy)
                  Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: loc.flow_r1Making,
                    ),
                  )
                else
                  Text(
                    _message(loc, invite?.code ?? loc.flow_r1CodePending),
                    style: bodyStyle,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          if (_whatsApp) ...[
            FlowPrimaryButton(
              label: loc.flow_r1SendWhatsApp,
              busy: _busy,
              onPressed: () => _send(_Channel.whatsApp),
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.flow_r1ShareOther,
              onPressed: _busy ? null : () => _send(_Channel.share),
            ),
          ] else
            FlowPrimaryButton(
              label: loc.flow_r1ShareOther,
              busy: _busy,
              onPressed: () => _send(_Channel.share),
            ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_r1ShowQr,
            onPressed: _busy ? null : () => _send(_Channel.qr),
          ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_r1CopyCode,
            onPressed: _busy ? null : () => _send(_Channel.copy),
          ),
          if (_copied) ...[
            const SizedBox(height: Spacing.xs),
            Text(loc.flow_r1CodeCopied, style: bodyStyle),
          ],
          if (error != null) ...[
            const SizedBox(height: Spacing.sm),
            FlowErrorLine(
              key: ValueKey(_errorCount),
              text: error,
              style: bodyStyle,
            ),
          ],
          // R2 (§3.8): the heads-up, once something was sent, while
          // notifications are off.
          if (_sent) ...[
            const SizedBox(height: Spacing.md),
            PushAskRow(
              askContext: PushAskContext.r2,
              reason:
                  name == null
                      ? loc.flow_pushAskR2
                      : loc.flow_pushAskR2Named(name),
              action: loc.flow_pushTurnOn,
            ),
          ],
        ],
      ),
      actions: [
        FlowTextLink(
          label: loc.flow_invitePartnerLater,
          onPressed: widget.onDone,
        ),
        if (widget.onAlreadyInvited != null)
          FlowTextLink(
            label: loc.flow_pathAlreadyInvited,
            onPressed: widget.onAlreadyInvited!,
          ),
      ],
    );
  }

  static String _registerLabel(AppLocalizations loc, InviteRegister register) =>
      switch (register) {
        InviteRegister.simple => loc.flow_r1ToneSimple,
        InviteRegister.casual => loc.flow_r1ToneCasual,
        InviteRegister.pidgin => loc.flow_r1TonePidgin,
      };
}
