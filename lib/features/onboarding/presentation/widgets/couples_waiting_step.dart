import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_info_tile.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';

class CouplesWaitingStep extends StatefulWidget {
  const CouplesWaitingStep({
    super.key,
    required this.inviteService,
    required this.onFinish,
  });

  final RelationshipInviteService inviteService;
  final VoidCallback onFinish;

  @override
  State<CouplesWaitingStep> createState() => _CouplesWaitingStepState();
}

class _CouplesWaitingStepState extends State<CouplesWaitingStep> {
  RelationshipInvite? _invite;
  bool _isCreatingInvite = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.inviteService.isConfigured) {
      _createInvite();
    }
  }

  Future<void> _createInvite() async {
    setState(() {
      _isCreatingInvite = true;
      _errorMessage = null;
    });

    try {
      final invite = await widget.inviteService.createInvite();
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
    final colorScheme = Theme.of(context).colorScheme;

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
          Text(
            'Next: use private reflection mode while your partner completes onboarding.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          Gap(Spacing.smMd.h),
          AppButton(
            label: 'Enter reflection mode',
            onPressed: widget.onFinish,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
  }
}
