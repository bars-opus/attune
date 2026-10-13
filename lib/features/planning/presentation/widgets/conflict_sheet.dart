import 'package:attune/app/theme/design_tokens.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:flutter/material.dart';

enum ConflictChoice { keepMine, useTheirs, copyMine }

/// Spec §4 "Conflicts": the second save never silently overwrites.
Future<ConflictChoice?> showConflictSheet(BuildContext context, {required String theirs}) =>
    showModalBottomSheet<ConflictChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: Spacing.pagePadding,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Your partner just changed this', style: Theme.of(c).textTheme.titleLarge),
            const Gap(Spacing.sm),
            Text('Their version:', style: Theme.of(c).textTheme.labelLarge),
            const Gap(Spacing.xs),
            Container(
              padding: Spacing.allSm,
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadiusTokens.smAll,
              ),
              child: Text(theirs.isEmpty ? '(empty)' : theirs, maxLines: 8, overflow: TextOverflow.ellipsis),
            ),
            const Gap(Spacing.lg),
            AppButton(label: 'Keep mine', onPressed: () => Navigator.pop(c, ConflictChoice.keepMine)),
            const Gap(Spacing.sm),
            AppButton(
              label: 'Use theirs',
              variant: ButtonVariant.outline,
              onPressed: () => Navigator.pop(c, ConflictChoice.useTheirs),
            ),
            const Gap(Spacing.sm),
            AppButton(
              label: 'Copy mine, then use theirs',
              variant: ButtonVariant.text,
              onPressed: () => Navigator.pop(c, ConflictChoice.copyMine),
            ),
          ]),
        ),
      ),
    );
