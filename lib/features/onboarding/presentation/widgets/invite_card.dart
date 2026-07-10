import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter/services.dart';

class InviteCard extends StatelessWidget {
  const InviteCard({super.key, required this.invite});

  final RelationshipInvite invite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SemanticContainerWidget(
      content: '',
      icon: Icons.ios_share_outlined,
      title: 'Partner invite',
      backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
      borderColor: colorScheme.primary,
      iconColor: colorScheme.primary,
      textTheme: textTheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Gap(Spacing.smMd.h),
          SelectableText(
            invite.code,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: Spacing.xs,
            ),
          ),
          Gap(Spacing.sm.h),
          SelectableText(invite.deepLink),
          Gap(Spacing.smMd.h),
          AppButton(
            label: 'Copy link',
            prefixIcon: Icons.copy,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: invite.deepLink));
              context.showSuccessSnackbar('Invite link copied.');
            },
          ),
        ],
      ),
    );
  }
}
