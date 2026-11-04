import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/opinions/presentation/widgets/need_support_link.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export '../providers/journal_support_providers.dart';

/// The writer's card (Spec 1 §8 W9c), shown instead of a reflection. Only
/// the writer sees it; never animated (§2.2); large text let through.
class JournalSupportCard extends ConsumerWidget {
  const JournalSupportCard({super.key, required this.onNotNow});

  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AllowLargeText(
      // A live region: the card arrives after the writer leaves the entry,
      // so a screen reader is told (W9 final M-7).
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          margin: const EdgeInsets.only(top: Spacing.md),
          padding: Spacing.allMd,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadiusTokens.mdAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.journal_supportCardBody,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Spacing.sm,
                runSpacing: Spacing.xs,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: theme.colorScheme.onSurface,
                    ),
                    onPressed: onNotNow,
                    child: Text(loc.journal_supportNotNow),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed:
                        () => openSupportNow(
                          context,
                          ref,
                          SupportLinkSource.journal,
                        ),
                    child: Text(loc.journal_supportSeeSupport),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
