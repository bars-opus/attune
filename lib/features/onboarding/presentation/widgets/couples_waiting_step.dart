import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_info_tile.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';
import 'package:attune/features/onboarding/presentation/widgets/pending_invite_guide.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';

class CouplesWaitingStep extends StatefulWidget {
  const CouplesWaitingStep({
    super.key,
    required this.inviteService,
    required this.onFinish,
    this.onUseAlone,
  });

  final RelationshipInviteService inviteService;
  final VoidCallback onFinish;

  /// After day 7's "Use Attune on my own for now" has withdrawn the invites
  /// (Spec 5, R5-10); defaults to [onFinish].
  final VoidCallback? onUseAlone;

  @override
  State<CouplesWaitingStep> createState() => _CouplesWaitingStepState();
}

class _CouplesWaitingStepState extends State<CouplesWaitingStep> {
  RelationshipInvite? _invite;
  bool _isCreatingInvite = false;
  String? _errorMessage;
  Duration? _age;

  @override
  void initState() {
    super.initState();
    if (widget.inviteService.isConfigured) {
      _createInvite();
      _loadAge();
    }
  }

  Future<void> _loadAge() async {
    final age = await widget.inviteService.inviteAge();
    if (mounted) setState(() => _age = age);
  }

  Future<void> _useAlone() async {
    setState(() {
      _isCreatingInvite = true;
      _errorMessage = null;
    });
    try {
      await widget.inviteService.withdrawPendingInvites();
      if (!mounted) return;
      (widget.onUseAlone ?? widget.onFinish)();
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage =
              error is RelationshipInviteException
                  ? error.message
                  : 'Could not update your invite.';
        });
      }
    } finally {
      if (mounted) setState(() => _isCreatingInvite = false);
    }
  }

  Future<void> _createInvite({bool forceNew = false}) async {
    setState(() {
      _isCreatingInvite = true;
      _errorMessage = null;
    });

    try {
      final invite = await widget.inviteService.createInvite(
        forceNew: forceNew,
      );
      if (mounted) setState(() => _invite = invite);
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage =
              error is RelationshipInviteException
                  ? error.message
                  : 'Could not create invite.';
        });
      }
    } finally {
      if (mounted) setState(() => _isCreatingInvite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;

    return OnboardingStepFrame(
      title: 'Invite your partner',
      icon: Icons.person_add_alt_outlined,
      subtitle:
          'You can keep going while your partner completes their side of onboarding.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OnboardingInfoTile(
            icon: Icons.check_circle_outline,
            title: 'Your profile is ready',
            subtitle: 'You are all set on your side.',
          ),
          const OnboardingInfoTile(
            icon: Icons.favorite_border,
            title: 'Your space is being set up',
            subtitle:
                'Once your partner joins, your private chat opens for the two of you.',
          ),
          if (!widget.inviteService.isConfigured)
            const OnboardingInfoTile(
              icon: Icons.info_outline,
              title: 'Supabase not configured locally',
              subtitle:
                  'Add the new Supabase URL and anon key to generate real invites.',
            )
          else if (_isCreatingInvite)
            const OnboardingInfoTile(
              icon: Icons.pending_actions_outlined,
              title: 'Creating invite',
              subtitle: 'Preparing a private invite code.',
            )
          else if (invite != null)
            InviteCard(invite: invite, )
          else
            OnboardingInfoTile(
              icon: Icons.error_outline,
              title: 'Invite unavailable',
              subtitle: _errorMessage ?? 'Try creating the invite again.',
            ),
          // Fixed gap rather than Spacer: Spacer needs a bounded height, which
          // conflicts with the card.s scroll fallback on short screens.
          Gap(Spacing.xl.h),
          if (_errorMessage != null) ...[
            AppButton(
              label: 'Try again',
              prefixIcon: Icons.refresh,
              variant: ButtonVariant.outline,
              isDisabled: _isCreatingInvite,
              onPressed: _isCreatingInvite ? null : _createInvite,
              size: ButtonSize.small,
              height: OnboardingTokens.actionButtonHeight.h,
            ),
            Gap(Spacing.smMd.h),
          ],
          // Spec 5 (R5-9, R5-10): by how long they have waited.
          PendingInviteGuide(
            age: _age,
            busy: _isCreatingInvite,
            onContinue: widget.onFinish,
            onReflect: widget.onFinish,
            // C4: a plain fetch returns the live invite or mints one.
            onKeepWaiting: _createInvite,
            onUseAlone: _useAlone,
            onInviteSomeoneElse: () => _createInvite(forceNew: true),
          ),
        ],
      ),
    );
  }
}
