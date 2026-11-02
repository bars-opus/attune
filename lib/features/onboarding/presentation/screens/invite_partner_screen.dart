import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The invite service, replaceable in tests.
final invitePartnerServiceProvider = Provider<RelationshipInviteService>(
  (ref) => RelationshipInviteService(),
);

/// R1 until W4b (Spec 1 §3.8; W3 plan P-8): "Invite your partner" with
/// today's invite (InviteCard: QR, code, Share, Copy), created only when the
/// person taps "Create my invite". From another path ([switchPath]) that
/// tap is also the switch to Relationship (§3.12: "path set when the
/// invite is sent"); [pauseConfirmed] says the Dating pause was already
/// confirmed. W4b's InvitePartnerStep replaces it under flow_couples_v2.
class InvitePartnerScreen extends ConsumerStatefulWidget {
  const InvitePartnerScreen({
    super.key,
    required this.onDone,
    this.switchPath = false,
    this.pauseConfirmed = false,
  });

  final VoidCallback onDone;
  final bool switchPath;
  final bool pauseConfirmed;

  @override
  ConsumerState<InvitePartnerScreen> createState() =>
      _InvitePartnerScreenState();
}

class _InvitePartnerScreenState extends ConsumerState<InvitePartnerScreen> {
  RelationshipInvite? _invite;
  bool _busy = false;
  String? _error;
  int _errorCount = 0;

  void _fail(String message) {
    setState(() {
      _error = message;
      _errorCount++;
    });
    SemanticsService.announce(message, Directionality.of(context));
  }

  Future<void> _create() async {
    if (_busy) return;
    final loc = AppLocalizations.of(context)!;
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return;
    // Read before the first await: the person may leave while it runs,
    // and ref can't be used once the screen is gone.
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
        if (!mounted) return;
        if (outcome == PathChoiceOutcome.cancelled) return;
        if (outcome != PathChoiceOutcome.done) {
          _fail(
            outcome == PathChoiceOutcome.offline
                ? loc.flow_switchOffline
                : loc.flow_saveFailed,
          );
          return;
        }
      }
      final invite =
          await ref.read(invitePartnerServiceProvider).createInvite();
      if (!mounted) return;
      setState(() => _invite = invite);
      SemanticsService.announce(invite.code, Directionality.of(context));
    } on RelationshipInviteException catch (error) {
      if (!mounted) return;
      if (error.alreadyActiveRelationship) {
        widget.onDone();
        return;
      }
      _fail(error.message);
    } catch (_) {
      if (mounted) _fail(loc.flow_saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
      // The link state changed (pending): every reader catches up.
      await home.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final invite = _invite;
    final error = _error;
    return FlowFrame(
      title: loc.flow_invitePartnerTitle,
      hint: loc.flow_invitePartnerBody,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (invite != null) InviteCard(invite: invite),
          if (error != null) ...[
            const SizedBox(height: Spacing.sm),
            FlowErrorLine(
              key: ValueKey(_errorCount),
              text: error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (invite == null) ...[
          FlowPrimaryButton(
            label: loc.flow_invitePartnerCreate,
            busy: _busy,
            onPressed: _create,
          ),
          FlowTextLink(
            label: loc.flow_invitePartnerLater,
            onPressed: widget.onDone,
          ),
        ] else
          FlowPrimaryButton(
            label: loc.flow_invitePartnerDone,
            onPressed: widget.onDone,
          ),
      ],
    );
  }
}
