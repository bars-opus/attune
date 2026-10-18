// lib/features/onboarding/presentation/widgets/pending_invite_guide.dart
//
// Spec 5 (R5-9, R5-10; MASTER_SPEC "48-hour solo reflection fallback" and
// "Day 7 pivot"): what the waiting person is offered, by how long they have
// waited (from the server, get_my_invite_age):
//   before 48 h  a gentle line and Continue (plan review I4)
//   48 h to 7 d  the private reflection space
//   7 d on       keep waiting / on my own for now / invite someone else
//                (and Continue, where there is a next step)
// Shared by the onboarding waiting step and the locked Chat screen.

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_info_tile.dart';

class PendingInviteGuide extends StatelessWidget {
  const PendingInviteGuide({
    super.key,
    required this.age,
    required this.onReflect,
    required this.onKeepWaiting,
    required this.onUseAlone,
    required this.onInviteSomeoneElse,
    this.onContinue,
    this.busy = false,
  });

  static const reflectAfter = Duration(hours: 48);
  static const pivotAfter = Duration(days: 7);

  /// Null: unknown, treated as just started.
  final Duration? age;
  final VoidCallback onReflect;
  final VoidCallback onKeepWaiting;
  final VoidCallback onUseAlone;
  final VoidCallback onInviteSomeoneElse;

  /// Before 48 hours; null hides the button (the Chat screen has no "next").
  final VoidCallback? onContinue;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final waited = age ?? Duration.zero;
    final buttonHeight = OnboardingTokens.actionButtonHeight.h;

    if (waited >= pivotAfter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OnboardingInfoTile(
            icon: Icons.hourglass_bottom_outlined,
            title: "It's been a week",
            subtitle: 'Your invite has run its week. What would you like to do?',
          ),
          Gap(Spacing.smMd.h),
          AppButton(
            label: 'Keep waiting',
            onPressed: busy ? null : onKeepWaiting,
            size: ButtonSize.small,
            height: buttonHeight,
          ),
          Gap(Spacing.sm.h),
          AppButton(
            label: 'Use Attune on my own for now',
            variant: ButtonVariant.outline,
            onPressed: busy ? null : onUseAlone,
            size: ButtonSize.small,
            height: buttonHeight,
          ),
          Gap(Spacing.sm.h),
          AppButton(
            label: 'Invite someone else',
            variant: ButtonVariant.outline,
            onPressed: busy ? null : onInviteSomeoneElse,
            size: ButtonSize.small,
            height: buttonHeight,
          ),
          // Deciding later is always possible (final review I-1).
          if (onContinue != null) ...[
            Gap(Spacing.sm.h),
            AppButton(
              label: 'Continue',
              variant: ButtonVariant.outline,
              onPressed: busy ? null : onContinue,
              size: ButtonSize.small,
              height: buttonHeight,
            ),
          ],
        ],
      );
    }

    if (waited >= reflectAfter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OnboardingInfoTile(
            icon: Icons.edit_note_outlined,
            title: 'A private space while you wait',
            subtitle: 'Write or reflect on your own in the meantime.',
          ),
          Text(
            'Your reflections stay private to you.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          Gap(Spacing.smMd.h),
          AppButton(
            label: 'Open reflection mode',
            onPressed: onReflect,
            size: ButtonSize.small,
            height: buttonHeight,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "We'll suggest a private reflection space if this takes a little while.",
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        if (onContinue != null) ...[
          Gap(Spacing.smMd.h),
          AppButton(
            label: 'Continue',
            onPressed: onContinue,
            size: ButtonSize.small,
            height: buttonHeight,
          ),
        ],
      ],
    );
  }
}
