// lib/core/widgets/tag_picker.dart

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tappable summary row for the tag picker (ATTUNE_MASTER_SPEC.md §8.11
/// "Tags", FORUM.md §7), opened via
/// [BottomSheetUtils.showDocumentationBottomSheet] — same pattern as
/// PollComposerRow, so a tag is picked in its own focused sheet instead of
/// the chip Wrap expanding inline and pushing the rest of the compose form
/// down.
///
/// [currentSlugs] is owned by the parent (mirrors the picker's onChanged
/// exactly) so this row's subtitle reflects live state without duplicating
/// it.
class TagPickerRow extends StatelessWidget {
  /// Fires whenever the selection changes. Emits an empty list when nothing
  /// is selected, so the parent can pass it straight through to the
  /// repository (which treats null and empty identically).
  final List<String> currentSlugs;
  final ValueChanged<List<String>> onChanged;

  const TagPickerRow({
    super.key,
    required this.currentSlugs,
    required this.onChanged,
  });

  /// Matches attach_opinion_tags / attach_forum_topic_tags, which raise
  /// `too_many_tags` past this many DISTINCT slugs.
  static const int maxTags = 3;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppIconButton(
      icon: Icons.tag,
      onPressed: () {
        BottomSheetUtils.showDocumentationBottomSheet(
          context: context,
          backgroundColor: colorScheme.neutral,
          widget: _TagPickerSheet(
            initialSlugs: currentSlugs,
            onChanged: onChanged,
          ),
        );
      },
      iconColor: colorScheme.onBackground,
    );
  }
}

/// The sheet's content: the chip Wrap plus a Done button to close it.
/// Selection state lives here (not in the row) so re-opening the sheet
/// starts from [initialSlugs] rather than an empty selection — the same
/// "don't lose what was already picked" rule PollComposer's initialOptions
/// follows.
class _TagPickerSheet extends ConsumerStatefulWidget {
  final List<String> initialSlugs;
  final ValueChanged<List<String>> onChanged;

  const _TagPickerSheet({required this.initialSlugs, required this.onChanged});

  @override
  ConsumerState<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<_TagPickerSheet> {
  /// Insertion-ordered so the chips the user picked read back in the order
  /// they picked them. The server de-duplicates anyway, but a Set makes the
  /// cap check exact rather than depending on the UI never double-adding.
  late final Set<String> _selected = Set<String>.from(widget.initialSlugs);

  void _toggle(String slug) {
    ref.read(hapticsProvider).light();
    setState(() {
      if (_selected.contains(slug)) {
        _selected.remove(slug);
      } else {
        // Guarded rather than merely disabled: the chip's onSelected is
        // already null at the cap, so this is the belt to that braces.
        if (_selected.length >= TagPickerRow.maxTags) return;
        _selected.add(slug);
      }
    });
    widget.onChanged(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tagsAsync = ref.watch(allTagsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InfoRowWidget(
                title: 'Tags',
                subtitle: '${_selected.length}/${TagPickerRow.maxTags}',
                iconColor: colorScheme.onBackground,
                icon: Icons.close,
                showAvatar: false,
                showTrailingArrow: true,
                showDivider: false,
                disableTrailing: true,
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ),

            if (_selected.isNotEmpty) AppTextButton(),
          ],
        ),

        Gap(Spacing.md.h),
        // Tags are optional decoration on a post, so neither a slow nor a
        // failed vocabulary fetch may block composing: both collapse to
        // nothing and the user posts untagged rather than seeing an error.
        tagsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (tags) {
            if (tags.isEmpty) return const SizedBox.shrink();
            final atCap = _selected.length >= TagPickerRow.maxTags;

            return Wrap(
              spacing: Spacing.xs,
              runSpacing: Spacing.xs,
              children: [
                for (final slug in tags)
                  AppFilterChip(
                    label: slug,
                    fontSize: 12.h,
                    selectedColor: colorScheme.primary.withValues(alpha: .8),
                    selected: _selected.contains(slug),
                    onSelected:
                        (atCap && !_selected.contains(slug))
                            ? null
                            : (_) => _toggle(slug),
                  ),
              ],
            );
          },
        ),
        Gap(Spacing.xl.h),
        SemanticContainerWidget(
          content:
              'Opinions provide a space for you to discuss and express idealogies or concerns in a relationship',
          icon: Icons.info_outline,
          title: '',
          backgroundColor: Colors.grey.withOpacity(0.1),
          borderColor: Colors.grey,
          iconColor: Colors.grey,
          textTheme: textTheme,
        ),
      ],
    );
  }
}
