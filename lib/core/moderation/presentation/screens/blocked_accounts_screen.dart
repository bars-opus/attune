// lib/features/moderation/presentation/screens/blocked_accounts_screen.dart

import 'package:attune/core/moderation/presentation/providers/moderation_providers.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';


class BlockedAccountsScreen extends ConsumerStatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  ConsumerState<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends ConsumerState<BlockedAccountsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(blockedUsersProvider);
    });
  }

  Future<void> _unblockUser(String userId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unblock @$displayName?'),
        content: const Text('They will be able to see your posts and chat with you again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(unblockUserProvider(userId).future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unblocked @$displayName')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final blockedAsync = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked accounts'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(blockedUsersProvider);
          await ref.read(blockedUsersProvider.future);
        },
        child: blockedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => ErrorStateWidget.from(error),
          data: (blockedUsers) {
            if (blockedUsers.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.block_outlined, size: 64, color: Colors.grey),
                    Gap(Spacing.lg.h),
                    Text(
                      'No blocked accounts',
                      style: textTheme.titleMedium,
                    ),
                    Gap(Spacing.sm.h),
                    Text(
                      'When you block someone, they\'ll appear here.',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: EdgeInsets.all(Spacing.md.w),
              itemCount: blockedUsers.length,
              itemBuilder: (context, index) {
                final blocked = blockedUsers[index];
                return Container(
                  margin: EdgeInsets.only(bottom: Spacing.sm.h),
                  padding: EdgeInsets.all(Spacing.md.w),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Avatar placeholder
                      CircleAvatar(
                        backgroundColor: colorScheme.primary.withOpacity(0.1),
                        child: Text(
                          blocked.displayName.isNotEmpty
                              ? blocked.displayName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Gap(Spacing.md.w),
                      // User info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '@${blocked.displayName}',
                              style: textTheme.titleMedium,
                            ),
                            if (blocked.reason != null)
                              Text(
                                'Reason: ${blocked.reason}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            Text(
                              'Blocked ${_formatDate(blocked.blockedAt)}',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Unblock button
                      AppButton(
                        label: 'Unblock',
                        onPressed: () => _unblockUser(blocked.userId, blocked.displayName),
                        size: ButtonSize.small,
                        customColor: colorScheme.surfaceContainerHighest,
                        textColor: colorScheme.onSurface,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays} days ago';
    if (diff.inHours > 0) return '${diff.inHours} hours ago';
    return 'today';
  }
}
