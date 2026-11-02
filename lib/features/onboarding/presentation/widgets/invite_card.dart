import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_qr_code.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Shows a just-created or still-live partner invite: code, link, and quick
/// actions (share / copy), with a QR code encoding the deep link, so a
/// partner standing right there can scan it instead of typing the code.
///
/// Used by R1 (InvitePartnerScreen), R3 (RelationshipSpaceScreen), the
/// couples waiting step and the Chat tab's locked-couples surface
/// (chat_couples_locked_screen.dart) — any visual/behavior change here
/// applies to all of them.
///
/// Spec 1 W4b (§2.3; W3 batch-3 report): every target is at least 48 dp,
/// every text is at least 4.5:1 on the surface, and the code and link are
/// read out as one labelled item (they were selectable text, 32 and 42 dp
/// tall, at 3.31:1). The words are unchanged.
///
/// Final review #4: the code is selectable again (long-press → the
/// platform's Copy), as one item read out with its spelled label, at least
/// [minTarget] tall.
class InviteCard extends StatelessWidget {
  const InviteCard({super.key, required this.invite});

  final RelationshipInvite invite;

  /// The smallest target (§2.3), in logical pixels, never scaled down.
  static const double minTarget = 48;

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
    // The card is also on flag-off screens: when the app's words aren't
    // there (a bare host), the label is the English one.
    final spelled = invite.code.split('').join(' ');
    final codeLabel =
        AppLocalizations.of(context)?.flow_inviteCodeSemantics(spelled) ??
        'Invite code $spelled';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Gap(Spacing.md.h),
        ExcludeSemantics(child: InviteQrCode(data: invite.deepLink)),
        Gap(Spacing.xl.h),
        Center(
          child: Semantics(
            header: true,
            child: Text(
              'Partner invite',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
        Gap(Spacing.xs.h),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: InviteCard.minTarget,
              minWidth: InviteCard.minTarget,
            ),
            child: SelectableText(
              invite.code,
              semanticsLabel: codeLabel,
              textAlign: TextAlign.center,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: Spacing.xs,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
        Gap(Spacing.xs.h),
        Center(
          child: Text(
            invite.deepLink,
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
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
                height: InviteCard.minTarget,
                // The outline label in primary is 3.04:1 at 11 sp.
                textColor: colorScheme.onSurface,
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
                height: InviteCard.minTarget,
                // The outline label in primary is 3.04:1 at 11 sp.
                textColor: colorScheme.onSurface,
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
          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
          textAlign: TextAlign.center,
        ),
        Gap(Spacing.xxl.h),
      ],
    );
  }
}
