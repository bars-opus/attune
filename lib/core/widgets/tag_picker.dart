// lib/core/widgets/tag_picker.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Attach-tags control for the opinion and topic compose screens
/// (ATTUNE_MASTER_SPEC.md §8.11 "Tags", FORUM.md §7).
///
/// Lives in core/widgets beside PollComposer because opinions and forum topics
/// share it verbatim — a tag behaves identically on either surface.
///
/// The vocabulary is FIXED and app-controlled: this renders the 20 seeded
/// slugs as selectable chips and offers no way to type a new one. That is the
/// whole point — a user-invented tag would be an author fingerprint, so the
/// composer cannot mint one.
///
/// Like PollComposer, tags are immutable after posting, so this is the only
/// place they can be chosen, and it enforces the same 3-tag cap the RPC does
/// so the limit is felt in the form rather than as a `too_many_tags` error
/// after the post already exists.
class TagPicker extends ConsumerStatefulWidget {
  /// Fires whenever the selection changes. Emits an empty list when nothing is
  /// selected, so the parent can pass it straight through to the repository
  /// (which treats null and empty identically).
  final ValueChanged<List<String>> onChanged;

  const TagPicker({super.key, required this.onChanged});

  /// Matches attach_opinion_tags / attach_forum_topic_tags, which raise
  /// `too_many_tags` past this many DISTINCT slugs.
  static const int maxTags = 3;

  @override
  ConsumerState<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends ConsumerState<TagPicker> {
  /// Insertion-ordered so the chips the user picked read back in the order
  /// they picked them. The server de-duplicates anyway, but a Set makes the
  /// cap check exact rather than depending on the UI never double-adding.
  final Set<String> _selected = <String>{};

  void _toggle(String slug) {
    setState(() {
      if (_selected.contains(slug)) {
        _selected.remove(slug);
      } else {
        // Guarded rather than merely disabled: the chip's onSelected is
        // already null at the cap, so this is the belt to that braces.
        if (_selected.length >= TagPicker.maxTags) return;
        _selected.add(slug);
      }
    });
    widget.onChanged(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final tagsAsync = ref.watch(allTagsProvider);

    return tagsAsync.when(
      // Tags are optional decoration on a post, so neither a slow nor a failed
      // vocabulary fetch may block composing: both collapse to nothing and the
      // user posts untagged rather than seeing an error on the compose screen.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (tags) {
        if (tags.isEmpty) return const SizedBox.shrink();
        final atCap = _selected.length >= TagPicker.maxTags;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Tags (optional)', style: textTheme.titleSmall),
                const Gap(Spacing.sm),
                Text(
                  '${_selected.length}/${TagPicker.maxTags}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Gap(Spacing.xs),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                for (final slug in tags)
                  FilterChip(
                    label: Text(slug),
                    selected: _selected.contains(slug),
                    // Null at the cap disables the chip outright (greyed, not
                    // tappable) rather than letting the tap silently no-op,
                    // so the 3-tag limit is visible instead of mysterious.
                    onSelected:
                        (atCap && !_selected.contains(slug))
                            ? null
                            : (_) => _toggle(slug),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
