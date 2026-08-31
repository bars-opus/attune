// lib/features/community/presentation/screens/community_feed_screen.dart
import 'package:attune/features/auth/utility/auth_exports.dart';
import 'package:attune/features/community/data/models/community_question.dart';
import 'package:attune/features/community/presentation/providers/community_providers.dart';
import 'package:attune/features/community/presentation/widgets/community_question_card.dart';

class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key, this.initialTypeFilter});

  /// Opens the feed already narrowed to one game's questions.
  ///
  /// A game linking here means "see what other couples are asking for
  /// THIS game"; landing on every type and making the user find the
  /// filter answers a question they did not ask. Null keeps the
  /// browse-everything behaviour the standalone entry had.
  final String? initialTypeFilter;

  @override
  ConsumerState<CommunityFeedScreen> createState() =>
      _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  String? _selectedTypeFilter;
  String? _selectedToneFilter;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _cursor;
  bool _hasMore = true;
  final List<CommunityQuestion> _questions = [];
  bool _isLoading = false;

  final List<String> _typeFilters = ['All', 'This or That', 'Truth', 'Dare'];
  final List<String> _toneFilters = [
    'All',
    'Connecting',
    'Romantic',
    'Playful',
    'Spicy',
  ];

  @override
  void initState() {
    super.initState();
    _selectedTypeFilter = widget.initialTypeFilter;
    _loadInitialFeed();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialFeed() async {
    setState(() => _isLoading = true);
    try {
      final feed = await ref.read(
        communityFeedProvider((
          typeFilter: _selectedTypeFilter == 'All' ? null : _selectedTypeFilter,
          toneFilter: _selectedToneFilter == 'All' ? null : _selectedToneFilter,
          searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
          limit: 20,
          cursor: null,
        )).future,
      );

      setState(() {
        _questions.clear();
        _questions.addAll(feed);
        _hasMore = feed.length >= 20;
        _cursor =
            feed.isNotEmpty ? feed.last.createdAt.toIso8601String() : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load community questions: $e')),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore || _cursor == null) return;

    setState(() => _isLoading = true);
    try {
      final feed = await ref.read(
        communityFeedProvider((
          typeFilter: _selectedTypeFilter == 'All' ? null : _selectedTypeFilter,
          toneFilter: _selectedToneFilter == 'All' ? null : _selectedToneFilter,
          searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
          limit: 20,
          cursor: _cursor,
        )).future,
      );

      setState(() {
        _questions.addAll(feed);
        _hasMore = feed.length >= 20;
        _cursor =
            feed.isNotEmpty ? feed.last.createdAt.toIso8601String() : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _applyFilters() {
    _loadInitialFeed();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community questions'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitialFeed,
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: EdgeInsets.all(Spacing.md.w),
              child: AppTextFormField(
                controller: _searchController,
                hintText: 'Search questions...',
                // prefixIcon: const Icon(Icons.search, size: 20),
                onChanged: (value) {
                  _searchQuery = value;
                  _applyFilters();
                },
                label: '',
              ),
            ),
            // Filters
            Container(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Column(
                children: [
                  // Type filters
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _typeFilters.length,
                      separatorBuilder: (_, __) => Gap(Spacing.sm.w),
                      itemBuilder: (context, index) {
                        final label = _typeFilters[index];
                        final isSelected =
                            _selectedTypeFilter == label ||
                            (index == 0 && _selectedTypeFilter == null);
                        return _buildFilterChip(
                          label: label,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedTypeFilter =
                                  label == 'All' ? null : label;
                            });
                            _applyFilters();
                          },
                        );
                      },
                    ),
                  ),
                  Gap(Spacing.sm.h),
                  // Tone filters
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _toneFilters.length,
                      separatorBuilder: (_, __) => Gap(Spacing.sm.w),
                      itemBuilder: (context, index) {
                        final label = _toneFilters[index];
                        final isSelected =
                            _selectedToneFilter == label ||
                            (index == 0 && _selectedToneFilter == null);
                        return _buildFilterChip(
                          label: label,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() {
                              _selectedToneFilter =
                                  label == 'All' ? null : label;
                            });
                            _applyFilters();
                          },
                          toneChip: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.md.h),
            // Feed
            Expanded(
              child:
                  _questions.isEmpty && !_isLoading
                      ? _buildEmptyState()
                      : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.all(Spacing.md.w),
                        itemCount: _questions.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _questions.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return CommunityQuestionCard(
                            question: _questions[index],
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    bool toneChip = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.md.w,
          vertical: Spacing.xs.h,
        ),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? colorScheme.primary.withOpacity(0.1)
                  : colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color:
                isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.public_outlined, size: 64),
            Gap(Spacing.md.h),
            Text('No community questions yet', style: textTheme.titleMedium),
            Gap(Spacing.sm.h),
            Text(
              'Browse our featured collection\nor share your own question.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            Gap(Spacing.lg.h),
            AppButton(
              label: 'Browse featured',
              onPressed: () {
                // Clear filters to show seeded questions
                setState(() {
                  _selectedTypeFilter = null;
                  _selectedToneFilter = null;
                  _searchQuery = '';
                  _searchController.clear();
                });
                _loadInitialFeed();
              },
              size: ButtonSize.medium,
            ),
            Gap(Spacing.md.h),
            AppButton(
              label: 'Create and share a question',
              onPressed: () {
                // Navigate to create custom question
                Navigator.pop(context);
              },
              size: ButtonSize.medium,
              customColor: colorScheme.surfaceContainerHighest,
              textColor: colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}
