import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/animations/animated_scale_fade.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/core/widgets/search_text_field.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum ChatGameDestination {
  gamesHub,
  thisOrThat,
  truthOrDare,
  thirtySixQuestions,
  paintBall,
  neverHaveIEver,
  mirror,
  slidingScale,
  scenario,
  loveMap,
}

class ChatGamesSheet extends StatefulWidget {
  const ChatGamesSheet({super.key, required this.onSelect});

  final ValueChanged<ChatGameDestination> onSelect;

  @override
  State<ChatGamesSheet> createState() => _ChatGamesSheetState();
}

class _ChatGamesSheetState extends State<ChatGamesSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_ChatGameCategory> get _filteredCategories {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return _chatGameCategories;

    return [
      for (final category in _chatGameCategories)
        _ChatGameCategory(
          title: category.title,
          options:
              category.options
                  .where((option) => option.matches(query, category.title))
                  .toList(),
        ),
    ].where((category) => category.options.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredCategories = _filteredCategories;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        children: [
          const BottomSheetHeader(title: 'Games'),
          SearchFormField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: false,
            hintText: 'Search games',
            onChanged: (_) => setState(() {}),
            onClearPressed: () => setState(() {}),
          ),
          SizedBox(height: Spacing.xl.h),
          Expanded(
            child:
                filteredCategories.isEmpty
                    ? EmptyStateWidget(
                      icon: Icons.search_off_rounded,
                      title: 'No games found',
                      subtitle:
                          _controller.text.trim().isEmpty
                              ? 'Try searching by game name or category.'
                              : 'No available game matches "${_controller.text.trim()}".',
                    )
                    // _EmptyGamesSearchState(query: _controller.text.trim())
                    : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.only(bottom: Spacing.xxl.h),
                      itemCount: filteredCategories.length,
                      itemBuilder: (context, categoryIndex) {
                        final category = filteredCategories[categoryIndex];
                        final precedingOptionCount = filteredCategories
                            .take(categoryIndex)
                            .fold<int>(
                              0,
                              (total, item) => total + item.options.length,
                            );

                        return _ChatGameCategorySection(
                          category: category,
                          startAnimationIndex: precedingOptionCount,
                          onSelect: widget.onSelect,
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _ChatGameCategory {
  const _ChatGameCategory({required this.title, required this.options});

  final String title;
  final List<_ChatGameOption> options;
}

class _ChatGameOption {
  const _ChatGameOption({
    required this.destination,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.showMore = false,
    this.comingSoon = false,
  });

  final ChatGameDestination destination;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool showMore;

  /// Listed but not built. The row still appears — the catalogue doubles
  /// as a roadmap — but it does not pretend to be playable.
  final bool comingSoon;

  bool matches(String query, String categoryTitle) {
    return title.toLowerCase().contains(query) ||
        subtitle.toLowerCase().contains(query) ||
        categoryTitle.toLowerCase().contains(query);
  }
}

const _chatGameCategories = <_ChatGameCategory>[
  _ChatGameCategory(
    title: 'Getting to know each other',
    options: [
      _ChatGameOption(
        destination: ChatGameDestination.thirtySixQuestions,
        title: '36 Questions',
        subtitle: 'A guided closeness journey',
        icon: Icons.favorite_border_rounded,
      ),
      _ChatGameOption(
        destination: ChatGameDestination.thisOrThat,
        title: 'This or That',
        subtitle: 'Quick choices, shared reveals',
        icon: Icons.compare_arrows_rounded,
        showMore: true,
      ),
    ],
  ),
  _ChatGameCategory(
    title: 'Understanding each other',
    options: [
      _ChatGameOption(
        destination: ChatGameDestination.mirror,
        title: 'Mirror',
        subtitle: 'How well do you read each other right now?',
        icon: Icons.psychology_outlined,
      ),
      _ChatGameOption(
        destination: ChatGameDestination.slidingScale,
        title: 'Sliding Scale',
        subtitle: 'Where you each land on what matters',
        icon: Icons.tune_rounded,
      ),
      _ChatGameOption(
        destination: ChatGameDestination.scenario,
        title: 'Scenario',
        subtitle: 'What you would each do, and why',
        icon: Icons.alt_route_rounded,
      ),
      _ChatGameOption(
        destination: ChatGameDestination.loveMap,
        title: 'Love Map',
        subtitle: 'Their inner world, a few prompts at a time',
        icon: Icons.explore_outlined,
      ),
    ],
  ),
  _ChatGameCategory(
    title: 'Fun and playful',
    options: [
      _ChatGameOption(
        destination: ChatGameDestination.truthOrDare,
        title: 'Truth or Dare',
        subtitle: 'Playful prompts for two',
        icon: Icons.casino_outlined,
        showMore: true,
      ),
      _ChatGameOption(
        destination: ChatGameDestination.neverHaveIEver,
        title: 'Never Have I Ever',
        subtitle: 'Light confessions and laughs',
        icon: Icons.waving_hand_outlined,
        // No implementation, no spec, no route. Selecting it used to push
        // the games hub, which does not offer it either — the user picked
        // a game and arrived somewhere unrelated.
        comingSoon: true,
      ),
    ],
  ),
  _ChatGameCategory(
    title: 'Arcade',
    options: [
      _ChatGameOption(
        destination: ChatGameDestination.paintBall,
        title: 'Paint Ball',
        subtitle: 'Turn-based color battle',
        icon: Icons.sports_esports_outlined,
      ),
    ],
  ),
];

class _ChatGameCategorySection extends StatelessWidget {
  const _ChatGameCategorySection({
    required this.category,
    required this.startAnimationIndex,
    required this.onSelect,
  });

  final _ChatGameCategory category;
  final int startAnimationIndex;
  final ValueChanged<ChatGameDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: Spacing.lg.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(Spacing.sm.w, 0, Spacing.sm.w, 8.h),
            child: Text(
              category.title,
              style: textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (var index = 0; index < category.options.length; index++)
            _ChatGameMenuRow(
              option: category.options[index],
              onTap:
                  category.options[index].comingSoon
                      ? null
                      : () => onSelect(category.options[index].destination),
            ),
        ],
      ),
    );
  }
}

class _ChatGameMenuRow extends StatelessWidget {
  const _ChatGameMenuRow({required this.option, required this.onTap});

  final _ChatGameOption option;

  /// Null for a coming-soon row: CardInkWell renders it inert rather than
  /// selecting a game that does not exist.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CardInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      color: colorScheme.surface,
      padding: const EdgeInsets.symmetric(
        vertical: Spacing.md,
        horizontal: Spacing.lg,
      ),
      margin: const EdgeInsets.only(bottom: Spacing.xs),
      child: InfoRowWidget(
        iconColor: colorScheme.onSurface,
        subtitle: option.subtitle,
        subTitleFontColor: Colors.grey,
        titleFontColor: colorScheme.onSurface,
        title: option.title,
        icon: option.icon,
        avatarRadius: 25.h,
        padAvatarTop: true,
        showAvatar: false,
        showDivider: false,
        trailing:
            option.comingSoon
                ? Text(
                  'Coming soon',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                )
                : option.showMore
                ? Icon(
                  Icons.more_horiz_rounded,
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  size: 28.h,
                )
                : const SizedBox.shrink(),
        showTrailingArrow: !option.comingSoon,
      ),
    );
  }
}

/// The destinations listed but not yet built.
///
/// Kept alongside the catalogue seam so a test can assert that everything
/// NOT on this list is genuinely reachable — the list must shrink as games
/// ship, and must never become a place to hide one that simply broke.
Set<ChatGameDestination> chatGameDestinationsComingSoon() => {
  for (final category in _chatGameCategories)
    for (final option in category.options)
      if (option.comingSoon) option.destination,
};

/// The destinations the catalogue actually exposes.
///
/// Exists so a test can prove every enum value has a UI entry — the
/// catalogue is a const list, so a missing entry is invisible at compile
/// time and would ship a game no one can launch.
@visibleForTesting
Set<ChatGameDestination> chatGameDestinationsInCatalogue() => {
  for (final category in _chatGameCategories)
    for (final option in category.options) option.destination,
};
