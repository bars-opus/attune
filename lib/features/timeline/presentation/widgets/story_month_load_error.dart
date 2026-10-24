import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Under a calendar month whose story counts could not be read (04 #5):
/// the date cells then have no story avatars, which looked like a month
/// without stories. Reads the same provider key as the cells, so it costs
/// no extra call. Nothing when the counts loaded, or while they load.
class StoryMonthLoadErrorRow extends ConsumerWidget {
  const StoryMonthLoadErrorRow({
    super.key,
    required this.relationshipId,
    required this.month,
  });

  final String relationshipId;
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = StoryDayRangeKey.month(
      relationshipId: relationshipId,
      day: month,
    );
    final counts = ref.watch(storyDayCountsProvider(key));
    if (!counts.hasError || counts.hasValue) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error_outline_rounded,
                size: IconSizes.sm,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                "Couldn't load this month's stories.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // While the re-read runs: progress in Retry's place, so a tap
            // shows it landed and cannot fire twice (M-4).
            if (counts.isLoading)
              Semantics(
                label: "Loading this month's stories",
                child: const SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: SizedBox.square(
                      dimension: IconSizes.sm,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: () => ref.invalidate(storyDayCountsProvider(key)),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}
