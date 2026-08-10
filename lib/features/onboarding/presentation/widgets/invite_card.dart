import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_qr_code.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Shows a just-created or still-live partner invite: code, link, and quick
/// actions (share / copy). Tapping the card opens a bottom sheet with the
/// full invite — including a QR code encoding the deep link, so a partner
/// standing right there can scan it instead of typing the code.
///
/// Used both mid-onboarding (couples_waiting_step.dart) and on the Chat
/// tab's locked-couples surface (chat_couples_locked_screen.dart) — any
/// visual/behavior change here applies to both.
class InviteCard extends StatelessWidget {
  const InviteCard({super.key, required this.invite});

  final RelationshipInvite invite;

  @override
  Widget build(BuildContext context) {
    return _InviteQrSheet(invite: invite);
  }
}

class _InviteQrSheet extends StatelessWidget {
  const _InviteQrSheet({required this.invite});

  final RelationshipInvite invite;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gap(Spacing.lg.h),
        Gap(Spacing.md.h),
        InviteQrCode(data: invite.deepLink),
        Gap(Spacing.xl.h),
        Center(
          child: Text(
            'Partner invite',
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onBackground,
            ),
          ),
        ),
       
        Gap(Spacing.xs.h),
        Center(
          child: SelectableText(
            invite.code,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: Spacing.xs,
              color: colorScheme.onBackground,
            ),
          ),
        ),
        Gap(Spacing.xs.h),
        Center(
          child: SelectableText(
            invite.deepLink,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Gap(Spacing.md.h),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Share',
                prefixIcon: Icons.ios_share,
                prefixIconColor: colorScheme.primary,
                elevation: 0,
                size: ButtonSize.small,
                variant: ButtonVariant.outline,
                height: OnboardingTokens.actionButtonHeight.h,
                onPressed: () {
                  Share.share(
                    'Join me on Attune: ${invite.deepLink}',
                    subject: 'Attune invite',
                  );
                },
              ),
            ),
            Gap(Spacing.smMd.w),
            Expanded(
              child: AppButton(
                label: 'Copy link',
                prefixIconColor: colorScheme.primary,
                prefixIcon: Icons.copy,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                height: OnboardingTokens.actionButtonHeight.h,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: invite.deepLink));
                  context.showSuccessSnackbar('Invite link copied.');
                },
              ),
            ),
          ],
        ),

        Gap(Spacing.md.h),
        Text(
          'Have your partner scan this, or share the code below. To join together as couples on Attune.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
        Gap(Spacing.xxl.h),
        // Gap(Spacing.xl.h),
      ],
    );
  }
}
