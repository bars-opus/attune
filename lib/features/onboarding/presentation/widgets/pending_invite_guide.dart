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
//
// Spec 1 W4b (§3.8 R3, Q7): with [v2] (R3 under flow_couples_v2) the words
// are the spec's, the partner is named, and day 7 offers "Send a new
// invite" (withdraws the old code, mints a new one, opens the share step)
// instead of "Invite someone else". Without it, nothing changes.

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
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
    this.v2 = false,
    this.partnerName,
    this.onSendNewInvite,
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

  /// R3's words and day 7 (Spec 1 W4b).
  final bool v2;

  /// The invited partner's first name (R1's, this phone only), or null.
  final String? partnerName;

  /// Day 7's "Send a new invite" (v2 only).
  final VoidCallback? onSendNewInvite;

  @override
  Widget build(BuildContext context) {
    if (v2) return _buildV2(context);
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

  Widget _buildV2(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final text = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final title = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final waited = age ?? Duration.zero;
    final name = partnerName?.trim();
    final named = name != null && name.isNotEmpty;

    if (waited >= pivotAfter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(loc.flow_guideWeekTitle, style: title),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            named
                ? loc.flow_guideWeekBody(name)
                : loc.flow_guideWeekBodyUnnamed,
            style: text,
          ),
          const SizedBox(height: Spacing.smMd),
          FlowSecondaryButton(
            label: loc.flow_guideKeepWaiting,
            onPressed: busy ? null : onKeepWaiting,
          ),
          const SizedBox(height: Spacing.sm),
          FlowPrimaryButton(
            label: loc.flow_guideSendNew,
            busy: busy,
            onPressed: onSendNewInvite ?? onInviteSomeoneElse,
          ),
          const SizedBox(height: Spacing.xs),
          Text(loc.flow_guideSendNewHelper, style: text),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_guideOnMyOwn,
            onPressed: busy ? null : onUseAlone,
          ),
        ],
      );
    }

    if (waited >= reflectAfter) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(loc.flow_guideReflectTitle, style: title),
          ),
          const SizedBox(height: Spacing.xs),
          Text(loc.flow_guideReflectBody, style: text),
          const SizedBox(height: Spacing.smMd),
          FlowSecondaryButton(
            label: loc.flow_guideOpenJournal,
            onPressed: onReflect,
          ),
        ],
      );
    }

    return Text(loc.flow_guideWaitLine, style: text);
  }
}
