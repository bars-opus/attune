// lib/features/moderation/presentation/widgets/block_confirmation_sheet.dart

import 'package:attune/core/moderation/presentation/providers/moderation_providers.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';


class BlockConfirmationSheet extends ConsumerStatefulWidget {
  final String targetUserId;
  final String targetDisplayName;

  const BlockConfirmationSheet({
    super.key,
    required this.targetUserId,
    required this.targetDisplayName,
  });

  @override
  ConsumerState<BlockConfirmationSheet> createState() => _BlockConfirmationSheetState();
}

class _BlockConfirmationSheetState extends ConsumerState<BlockConfirmationSheet> {
  final TextEditingController _reasonController = TextEditingController();
  bool _isBlocking = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _blockUser() async {
    setState(() => _isBlocking = true);

    try {
      await ref.read(blockUserProvider((
        blockedId: widget.targetUserId,
        reason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
      )).future);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to block user: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg.w,
        Spacing.lg.h,
        Spacing.lg.w,
        MediaQuery.of(context).viewInsets.bottom + Spacing.lg.h,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Block @${widget.targetDisplayName}?',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Gap(Spacing.md.h),
          Text(
            'You won\'t see each other\'s posts or be able to chat. '
            'This can be undone in Settings.',
            style: textTheme.bodyMedium,
          ),
          Gap(Spacing.md.h),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              hintText: 'Optional reason (only visible to you)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            maxLength: 200,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
          ),
          Gap(Spacing.lg.h),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(context, false),
                  size: ButtonSize.medium,
                  customColor: colorScheme.surfaceContainerHighest,
                  textColor: colorScheme.onSurface,
                ),
              ),
              Gap(Spacing.md.w),
              Expanded(
                child: AppButton(
                  label: 'Block',
                  onPressed: _blockUser,
                  size: ButtonSize.medium,
                  isLoading: _isBlocking,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
