import 'package:attune/core/utils/exports/export_screens.dart';
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
    // Column(
    //   children: [

    //     // GestureDetector(
    //     //   behavior: HitTestBehavior.opaque,
    //     //   onTap: () => _showInviteSheet(context),
    //     //   child: SemanticContainerWidget(
    //     //     content: '',
    //     //     icon: Icons.qr_code,
    //     //     title: 'Partner invite',
    //     //     backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
    //     //     borderColor: colorScheme.primary,
    //     //     iconColor: colorScheme.primary,
    //     //     textTheme: textTheme,
    //     //     child: Column(
    //     //       crossAxisAlignment: CrossAxisAlignment.start,
    //     //       children: [
    //     //         Center(
    //     //           child: Container(
    //     //             padding: EdgeInsets.all(Spacing.md.w),
    //     //             decoration: BoxDecoration(
    //     //               color: colorScheme.onBackground,
    //     //               borderRadius: BorderRadius.circular(
    //     //                 BorderRadiusTokens.md.r,
    //     //               ),
    //     //               border: Border.all(
    //     //                 color: colorScheme.outline.withOpacity(0.2),
    //     //               ),
    //     //             ),
    //     //             // Encodes the deep link, not the bare code — scanning must
    //     //             // resolve straight to the invite, the same destination
    //     //             // typing/tapping invite.deepLink already opens.
    //     //             child: QrImageView(
    //     //               data: invite.deepLink,
    //     //               version: QrVersions.auto,
    //     //               size: 220.w,
    //     //               backgroundColor: colorScheme.onBackground,
    //     //               foregroundColor: colorScheme.background,
    //     //             ),
    //     //           ),
    //     //         ),
    //     //         Gap(Spacing.smMd.h),
    //     //         SelectableText(
    //     //           invite.code,
    //     //           style: textTheme.headlineSmall?.copyWith(
    //     //             fontWeight: FontWeight.w800,
    //     //             letterSpacing: Spacing.xs,
    //     //             color: colorScheme.onBackground,
    //     //           ),
    //     //         ),
    //     //         Gap(Spacing.sm.h),
    //     //         SelectableText(
    //     //           invite.deepLink,
    //     //           style: textTheme.bodyMedium?.copyWith(
    //     //             color: colorScheme.onBackground,
    //     //           ),
    //     //         ),
    //     //         Gap(Spacing.smMd.h),
    //     //         Text(
    //     //           'Tap for a QR code your partner can scan',
    //     //           style: textTheme.bodySmall?.copyWith(
    //     //             color: colorScheme.onSurface.withOpacity(0.5),
    //     //           ),
    //     //         ),
    //     //       ],
    //     //     ),
    //     //   ),
    //     // ),
    //     // Gap(Spacing.smMd.h),
    //     // Row(
    //     //   children: [
    //     //     Expanded(
    //     //       child: AppButton(
    //     //         label: 'Share',
    //     //         prefixIcon: Icons.ios_share,
    //     //         prefixIconColor: colorScheme.background,
    //     //         elevation: 0,
    //     //         size: ButtonSize.small,
    //     //         height: OnboardingTokens.actionButtonHeight.h,
    //     //         onPressed: () => _shareInvite(),
    //     //       ),
    //     //     ),
    //     //     Gap(Spacing.smMd.w),
    //     //     Expanded(
    //     //       child: AppButton(
    //     //         label: 'Copy link',
    //     //         prefixIcon: Icons.copy,
    //     //         variant: ButtonVariant.outline,
    //     //         prefixIconColor: colorScheme.primary,
    //     //         size: ButtonSize.small,
    //     //         height: OnboardingTokens.actionButtonHeight.h,
    //     //         onPressed: () => _copyLink(context),
    //     //       ),
    //     //     ),
    //     //   ],
    //     // ),
    //   ],
    // );
  }

  // void _shareInvite() {
  //   // Content, not just the bare link — mirrors ShareableLinkSection's
  //   // pattern (lib/core/link/widgets/shareable_link_section.dart), the
  //   // only other Share.share call site in the app.
  //   Share.share(
  //     'Join me on Attune: ${invite.deepLink}',
  //     subject: 'Attune invite',
  //   );
  // }

  // void _copyLink(BuildContext context) {
  //   Clipboard.setData(ClipboardData(text: invite.deepLink));
  //   context.showSuccessSnackbar('Invite link copied.');
  // }

  // void _showInviteSheet(BuildContext context) {
  //   BottomSheetUtils.showDocumentationBottomSheet(
  //     context: context,
  //     showButtons: false,
  //     maxHeight: 600.h,
  //     widget: _InviteQrSheet(invite: invite),
  //   );
  // }
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
        Center(
          child: QrImageView(
            data: invite.deepLink,
            version: QrVersions.auto,
            size: 200.w,
            backgroundColor: Colors.transparent,
            foregroundColor: colorScheme.primary,
          ),
        ),
        Gap(Spacing.xxl.h),
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
