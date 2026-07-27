// lib/core/widgets/tag_chip_row.dart

import 'package:attune/core/utils/exports/export_screens.dart';

/// The row of tag chips under an opinion or forum topic card
/// (ATTUNE_MASTER_SPEC.md §8.11 "Tags", FORUM.md §7).
///
/// Shared by OpinionCard and ForumTopicCard because a tag renders identically
/// on either — same vocabulary, same browse destination.
///
/// Renders NOTHING when there are no tags: most posts carry none, so this must
/// not reserve height or leave an empty gap on the majority of cards. That is
/// why callers can drop it in unconditionally.
///
/// Chips are quiet by design — they read as metadata rather than as buttons —
/// but each IS tappable and opens the tag browse for that slug. Tapping only
/// ever filters by tag, never by author: there is no "this author's posts
/// tagged X" destination anywhere, deliberately (§8.11 "Tag browsing").
class TagChipRow extends StatelessWidget {
  final List<String> tags;

  /// Called with the tapped slug. Callers route this to TagBrowseScreen.
  final ValueChanged<String> onTagTap;

  const TagChipRow({super.key, required this.tags, required this.onTagTap});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: Wrap(
        spacing: Spacing.xs,
        runSpacing: Spacing.xs,
        children: [
          for (final slug in tags)
            InkWell(
              onTap: () => onTagTap(slug),
              borderRadius: BorderRadiusTokens.smAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm,
                  vertical: 2,
                ),
                child: Text(
                  // The leading # marks these as tags at a glance and keeps
                  // multi-word slugs ("long distance", "red flags") reading as
                  // one chip rather than two loose words next to the body text.
                  '#$slug',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
