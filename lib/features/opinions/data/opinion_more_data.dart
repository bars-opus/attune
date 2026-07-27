// lib/features/opinions/data/opinion_more_data.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overflow-menu actions for a single opinion, in the same
/// SettingsConfig/SettingsSection shape ProfileMoreData uses so the row is
/// rendered with the shared SettingsItem widget.
///
/// Blocking the author is intentionally not offered here: FORUM.md's
/// anonymity guarantee means opinions only ever expose `authorHandle` (an
/// opaque HMAC) to the client, never the real `user_id` that
/// ModerationRepository.blockUser requires — there is nothing to block with
/// from this screen. Report (via reportOpinionProvider) is the moderation
/// entry point for opinions today.
class OpinionMoreData {
  static List<SettingsSection> getSections({
    required BuildContext context,
    required WidgetRef ref,
    required OpinionModel opinion,
    required VoidCallback onReport,
    required VoidCallback? onDelete,
    VoidCallback? onHide,
    VoidCallback? onMute,
    VoidCallback? onEdit,
  }) {
    final isOwnPost = opinion.isMine;

    // Edit is offered only on your own post AND only while the 15-minute
    // window is open (§8.11 "Editing"). This is a UX check, not the
    // enforcement — edit_opinion re-checks ownership and the window
    // server-side and raises not_editable regardless. Its job is to avoid
    // showing an action that could only fail: the window can still lapse
    // while the edit screen is open, and that case is handled there.
    final canEdit =
        isOwnPost &&
        onEdit != null &&
        DateTime.now().difference(opinion.createdAt) < kOpinionEditWindow;

    return [
      SettingsSection(
        id: 'opinion_actions',
        title: 'Opinion',
        items: [
          // You cannot report your own post; you can delete it.
          if (!isOwnPost)
            SettingsConfig(
              id: 'report',
              title: 'Report',
              subtitle: '',
              icon: Icons.flag_outlined,
              type: SettingsItemType.destructive,
              iconColor: Colors.red,
              onTap: onReport,
              order: 1,
            ),
          // Hide is the quiet alternative to Report (§8.11 "Muting and
          // hiding"): "not for me" with no moderation implication. Offered on
          // ANY opinion including your own — the opposite gate from Report —
          // since dismissing something from your own feed carries no claim
          // about the content at all. Rendered as a plain action, not
          // destructive: nothing is deleted and no one else is affected.
          if (onHide != null)
            SettingsConfig(
              id: 'hide',
              title: 'Hide this opinion',
              subtitle: 'You will not see this in your feeds',
              icon: Icons.visibility_off_outlined,
              type: SettingsItemType.action,
              iconColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              onTap: onHide,
              order: 2,
            ),
          // Mute, unlike Hide, IS gated on isOwnPost: muting yourself would
          // empty your own posts out of your feeds to no purpose. Mirrors the
          // !isOwnPost gate the Follow button already uses on the card.
          if (!isOwnPost && onMute != null)
            SettingsConfig(
              id: 'mute',
              title: 'Mute this person',
              subtitle: 'Stop seeing their opinions',
              icon: Icons.volume_off_outlined,
              type: SettingsItemType.action,
              iconColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              onTap: onMute,
              order: 3,
            ),
          // Own-post, in-window only (see canEdit above). Sits with the other
          // authoring actions rather than the moderation ones, and is a plain
          // action — an edit changes your own text and destroys nothing.
          if (canEdit)
            SettingsConfig(
              id: 'edit',
              title: 'Edit',
              subtitle: 'Within 15 minutes of posting',
              icon: Icons.edit_outlined,
              type: SettingsItemType.action,
              iconColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              onTap: onEdit,
              order: 4,
            ),
          SettingsConfig(
            id: 'copy',
            title: 'Copy text',
            subtitle: '',
            icon: Icons.copy_outlined,
            type: SettingsItemType.action,
            iconColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: opinion.content));
              if (context.mounted) {
                context.showInfoSnackbar('Copied to clipboard');
              }
            },
            order: 4,
          ),
          if (isOwnPost)
            SettingsConfig(
              id: 'delete',
              title: 'Delete',
              subtitle: '',
              icon: Icons.delete_outline,
              type: SettingsItemType.destructive,
              iconColor: Colors.red,
              onTap: onDelete,
              order: 5,
            ),
        ],
      ),
    ];
  }

  /// Report-reason picker, shown after tapping Report. Separate from
  /// [getSections] since it needs its own bottom sheet, not a SettingsItem row.
  static void showReportReasons({
    required BuildContext context,
    required WidgetRef ref,
    required String opinionId,
  }) {
    // Reason list is the FORUM.md §8 set (matches the comment report dialog).
    const reasons = [
      'Identifies a real person',
      'Harmful or dangerous content',
      'Explicit sexual content',
      'Hate speech or discrimination',
      'Spam',
      'Other',
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(Spacing.md.w),
              child: Text(
                'Report this opinion',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final reason in reasons)
              ListTile(
                title: Text(reason),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref.read(
                    reportOpinionProvider((
                      opinionId: opinionId,
                      reason: reason,
                    )).future,
                  );
                  if (context.mounted) {
                    context.showInfoSnackbar(
                      'Thank you. We will review this within 24 hours.',
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
