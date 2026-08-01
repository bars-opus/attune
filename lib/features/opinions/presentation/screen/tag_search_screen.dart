// lib/features/opinions/presentation/screen/tag_search_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/search_text_field.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Browse/search the fixed tag vocabulary, landing on the same filtered feed a
/// chip tap would (ATTUNE_MASTER_SPEC.md §8.11: "Tags are also searchable
/// directly — type/browse the fixed vocabulary, not a search-any-text field").
///
/// The field filters an IN-MEMORY list of the 20 seeded slugs; it never queries
/// the server and can never produce a tag that does not exist. That is the
/// point — a freeform tag search would be a text search over posts, which is a
/// different (and deliberately absent) feature.
class TagSearchScreen extends ConsumerStatefulWidget {
  const TagSearchScreen({super.key});

  @override
  ConsumerState<TagSearchScreen> createState() => _TagSearchScreenState();
}

class _TagSearchScreenState extends ConsumerState<TagSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(allTagsProvider);

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: false,
          backgroundColor: Colors.transparent,
          title: BottomSheetHeader(title: 'Tags'),
        ),
        body: Column(
          children: [
            Gap(Spacing.md),
            SearchFormField(
              controller: _controller,
              // focusNode: _searchFocusNode,
              autofocus: false,

              hintText: 'Find opinions and forums using a tag',
              showClearButton: true,
              onChanged: (value) => setState(() => _query = value),
            ),
            Gap(Spacing.lg),
            Expanded(
              child: tagsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => ErrorStateWidget.from(error),
                data: (tags) {
                  final query = _query.trim().toLowerCase();
                  final filtered =
                      query.isEmpty
                          ? tags
                          : [
                            for (final slug in tags)
                              if (slug.toLowerCase().contains(query)) slug,
                          ];

                  if (filtered.isEmpty) {
                    return const Center(
                      child: EmptyStateWidget(
                        icon: Icons.sell_outlined,
                        title: 'No matching tag',
                        subtitle:
                            'Tags are a fixed list, so only these topics exist.',
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final slug = filtered[index];
                      return InfoRowWidget(
                        subtitle: '',
                        iconColor: Colors.grey,
                        title: slug,
                        icon: Icons.tag,
                        avatarRadius: 25.h,
                        onTap: () {
                          context.pushNamed('tagBrowse', extra: slug);
                        },
                        disableTrailing: true,
                        showAvatar: false,
                        showTrailingArrow: false,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
