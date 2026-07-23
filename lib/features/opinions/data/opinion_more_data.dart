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
  }) {
    final isOwnPost = opinion.isMine;

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
            order: 2,
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
              order: 3,
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
