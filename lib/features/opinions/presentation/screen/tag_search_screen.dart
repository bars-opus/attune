// lib/features/opinions/presentation/screen/tag_search_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/tag_browse_screen.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tags', style: TextStyle(fontSize: 18)),
        leading: AppIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(Spacing.md.w),
            child: TextField(
              controller: _controller,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Find a tag',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadiusTokens.mdAll,
                ),
              ),
            ),
          ),
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
                    return ListTile(
                      leading: const Icon(Icons.sell_outlined, size: 20),
                      title: Text('#$slug'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TagBrowseScreen(tagSlug: slug),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
