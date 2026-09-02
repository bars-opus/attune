import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/search_text_field.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';

enum ChatGameDestination {
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

/// The destination that resumes an in-progress session of [gameType].
///
/// game_sessions rows carry a game_type; the sheet's active list has to
/// turn that back into somewhere to navigate. Every destination here
/// resumes rather than restarts: the session games' createSession returns
/// the existing session and the flow opens at the first unanswered round,
/// 36 Questions has its own resume-or-start entry, and Paint Ball's lobby
/// picks up the open match.
///
/// Returns null for a type with nowhere to go, so an unknown or retired
/// game_type renders as a non-tappable row instead of crashing on a route
/// name that does not exist.
/// The game_type behind a catalogue destination.
///
/// The catalogue is keyed by destination and the art by game_type, so one
/// of the two has to map to the other. Derived from
/// chatGameDestinationForType rather than duplicated, so a game added to
/// one is never missing from the other.
String? chatGameTypeForDestination(ChatGameDestination destination) {
  for (final gameType in const [
    'this_or_that',
    'truth_or_dare',
    '36_questions',
    'mirror',
    'sliding_scale',
    'scenario',
    'love_map',
    'paint_ball',
  ]) {
    if (chatGameDestinationForType(gameType) == destination) return gameType;
  }
  return null;
}

ChatGameDestination? chatGameDestinationForType(String gameType) {
  const byType = {
    'this_or_that': ChatGameDestination.thisOrThat,
    'truth_or_dare': ChatGameDestination.truthOrDare,
    '36_questions': ChatGameDestination.thirtySixQuestions,
    'mirror': ChatGameDestination.mirror,
    'sliding_scale': ChatGameDestination.slidingScale,
    'scenario': ChatGameDestination.scenario,
    'love_map': ChatGameDestination.loveMap,
    'paint_ball': ChatGameDestination.paintBall,
  };

  return byType[gameType];
}

class ChatGamesSheet extends ConsumerStatefulWidget {
  const ChatGamesSheet({super.key, required this.onSelect});

  final ValueChanged<ChatGameDestination> onSelect;

  @override
  ConsumerState<ChatGamesSheet> createState() => _ChatGamesSheetState();
}

class _ChatGamesSheetState extends ConsumerState<ChatGamesSheet> {
  static const _tabs = [
    AppTabItem(label: 'All', icon: Icons.apps_rounded),
    AppTabItem(label: 'Quick', icon: Icons.flash_on_outlined),
    AppTabItem(label: 'Fun', icon: Icons.celebration_outlined),
    AppTabItem(label: 'Deep', icon: Icons.favorite_border_rounded),
    AppTabItem(label: 'Slow', icon: Icons.self_improvement_outlined),
    AppTabItem(label: 'Spicy', icon: Icons.local_fire_department_outlined),
  ];

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedTabIndex = 0;

  static String? _moodForTab(AppTabItem tab) {
    final label = tab.label;
    return label == 'All' ? null : label;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_ChatGameCategory> _filteredCategoriesFor(String? mood, String query) {
    return [
      for (final category in _chatGameCategories)
        _ChatGameCategory(
          title: category.title,
          options:
              category.options
                  .where(
                    (option) =>
                        (query.isEmpty ||
                            option.matches(query, category.title)) &&
                        (mood == null || option.tags.contains(mood)),
                  )
                  .toList(),
        ),
    ].where((category) => category.options.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final tabs = [
      for (final tab in _tabs)
        AppTabItem(
          label: tab.label,
          icon: tab.icon,
          content: _ChatGamesTabContent(
            query: query,
            mood: _moodForTab(tab),
            categories: _filteredCategoriesFor(_moodForTab(tab), query),
            onSelect: widget.onSelect,
          ),
        ),
    ];

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        children: [
          const BottomSheetHeader(title: 'Play'),

          SearchFormField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: false,
            hintText: 'Search games',
            onChanged: (_) => setState(() {}),
            onClearPressed: () => setState(() {}),
          ),
          SizedBox(height: Spacing.md.h),
          Expanded(
            child: TabsWithContent(
              tabs: tabs,
              initialIndex: _selectedTabIndex,
              onTabChanged:
                  (index) => setState(() => _selectedTabIndex = index),
              style: const AppTabsStyle(tabPadding: 18),
              padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
              showContent: true,
              scrollable: true,
              contentSpacing: Spacing.lg,
              backgroundColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatGamesTabContent extends StatelessWidget {
  const _ChatGamesTabContent({
    required this.query,
    required this.mood,
    required this.categories,
    required this.onSelect,
  });

  final String query;
  final String? mood;
  final List<_ChatGameCategory> categories;
  final ValueChanged<ChatGameDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    // Hidden while searching: a query filters the catalogue, and games
    // that merely happen to be in progress would survive it as results
    // the user did not search for. Mood tabs are for starting games, so
    // in-progress sessions stay anchored to All.
    final showInProgress = query.isEmpty && mood == null;

    if (categories.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.search_off_rounded,
        title: 'No games found',
        subtitle:
            query.isEmpty
                ? 'Try another mood or search by game name.'
                : 'No available game matches "$query".',
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(bottom: Spacing.xxl.h),
      itemCount: categories.length + (showInProgress ? 1 : 0),
      itemBuilder: (context, index) {
        if (showInProgress && index == 0) {
          return _ChatGamesInProgress(onSelect: onSelect);
        }

        final categoryIndex = showInProgress ? index - 1 : index;
        final category = categories[categoryIndex];

        return _ChatGameCategorySection(category: category, onSelect: onSelect);
      },
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
    required this.tags,
    this.showMore = false,
    this.comingSoon = false,
  });

  final ChatGameDestination destination;
  final String title;
  final String subtitle;
  final IconData icon;
  final Set<String> tags;
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
        subtitle: 'A slow, guided way to feel closer',
        icon: Icons.favorite_border_rounded,
        tags: {'Deep', 'Slow'},
      ),
      _ChatGameOption(
        destination: ChatGameDestination.thisOrThat,
        title: 'This or That',
        subtitle: 'Quick choices, shared reveals',
        icon: Icons.compare_arrows_rounded,
        tags: {'Quick', 'Fun'},
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
        tags: {'Deep'},
      ),
      _ChatGameOption(
        destination: ChatGameDestination.slidingScale,
        title: 'Sliding Scale',
        subtitle: 'Where you each land on what matters',
        icon: Icons.tune_rounded,
        tags: {'Quick', 'Deep'},
      ),
      _ChatGameOption(
        destination: ChatGameDestination.scenario,
        title: 'Scenario',
        subtitle: 'What you would each do, and why',
        icon: Icons.alt_route_rounded,
        tags: {'Fun', 'Deep'},
      ),
      _ChatGameOption(
        destination: ChatGameDestination.loveMap,
        title: 'Love Map',
        subtitle: 'Their inner world, a few prompts at a time',
        icon: Icons.explore_outlined,
        tags: {'Deep', 'Slow'},
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
        tags: {'Fun', 'Spicy'},
        showMore: true,
      ),
      _ChatGameOption(
        destination: ChatGameDestination.neverHaveIEver,
        title: 'Never Have I Ever',
        subtitle: 'Light confessions and laughs',
        icon: Icons.waving_hand_outlined,
        tags: {'Fun', 'Spicy'},
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
        tags: {'Quick', 'Fun'},
      ),
    ],
  ),
];

class _ChatGameCategorySection extends StatelessWidget {
  const _ChatGameCategorySection({
    required this.category,
    required this.onSelect,
  });

  final _ChatGameCategory category;
  final ValueChanged<ChatGameDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Gap(Spacing.lg),
        AppDivider(),
        Gap(Spacing.md),
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
        Gap(Spacing.sm.h),
        LayoutBuilder(
          builder: (context, constraints) {
            final gap = Spacing.sm.w;
            final tileWidth = (constraints.maxWidth - gap) / 2;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final option in category.options)
                  SizedBox(
                    width: tileWidth,
                    child: _ChatGameMenuRow(
                      option: option,
                      onTap:
                          option.comingSoon
                              ? null
                              : () => onSelect(option.destination),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
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
    final textTheme = Theme.of(context).textTheme;
    final enabled = onTap != null;

    return CardInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      color: colorScheme.surface,
      padding: EdgeInsets.all(Spacing.md.w),
      margin: EdgeInsets.zero,
      // elevation: 0,
      borderColor: colorScheme.outline.withValues(alpha: 0.08),
      child: Opacity(
        opacity: enabled ? 1 : 0.62,
        child: SizedBox(
          height: 142.h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // The illustration where one exists. A drawn icon
                  // carries its own tile, so the tinted disc below is only
                  // for the glyph fallback -- wrapping art in it would put
                  // a circle behind a rounded square.
                  Builder(
                    builder: (context) {
                      final gameType = chatGameTypeForDestination(
                        option.destination,
                      );
                      final asset =
                          gameType == null ? null : gameIconAsset(gameType);

                      if (asset != null) {
                        return GameIcon(gameType: gameType!, size: 50.h);
                      }

                      return Container(
                        width: 50.h,
                        height: 50.h,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          option.icon,
                          color: colorScheme.primary,
                          size: 30.h,
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  if (option.comingSoon)
                    const _ChatGamePill(label: 'Coming soon', muted: true)
                  else if (option.showMore)
                    Icon(
                      Icons.more_horiz_rounded,
                      color: colorScheme.onSurface.withValues(alpha: 0.58),
                      size: 24.h,
                    )
                  else
                    SizedBox.shrink(),
                ],
              ),
              const Spacer(),
              Text(
                option.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                option.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.62),
                  height: 1.16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatGamePill extends StatelessWidget {
  const _ChatGamePill({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        muted ? colorScheme.onSurfaceVariant : colorScheme.primary;
    final background =
        muted
            ? colorScheme.surfaceContainerHighest
            : colorScheme.primary.withValues(alpha: 0.12);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.full),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
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

/// The in-progress and just-finished games, above the catalogue.
///
/// These lists were the games hub's reason to exist. The hub is gone: the
/// sheet is the only games surface now, so what is already underway
/// belongs at the top of it, ahead of the catalogue of new games.
///
/// Both lists render nothing at all when empty — no header, no empty-state
/// card. A screen can afford "No active games"; a bottom sheet opened to
/// pick a game cannot, and a first-time player would meet two empty boxes
/// before reaching what they came for.
class _ChatGamesInProgress extends ConsumerWidget {
  const _ChatGamesInProgress({required this.onSelect});

  final ValueChanged<ChatGameDestination> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps both lists live while the sheet is open: an invite arriving,
    // or the partner finishing a round, re-renders in place.
    ref.watch(gameSessionEventsProvider);

    final active = ref.watch(activeGamesProvider).valueOrNull ?? const [];
    final recent = ref.watch(recentGamesProvider).valueOrNull ?? const [];

    if (active.isEmpty && recent.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (active.isNotEmpty) ...[
          Gap(Spacing.md.h),
          _ChatGamesSectionLabel(label: 'Continue playing'),
          Gap(Spacing.sm.h),
          for (final game in active)
            _ChatGameSessionRow(game: game, onSelect: onSelect),
          Gap(Spacing.lg.h),
        ],
        if (recent.isNotEmpty) ...[
          Gap(Spacing.md.h),
          _ChatGamesSectionLabel(label: 'Recently played'),
          Gap(Spacing.sm.h),
          for (final game in recent) _ChatGameSessionRow(game: game),
          Gap(Spacing.lg.h),
        ],
      ],
    );
  }
}

class _ChatGamesSectionLabel extends StatelessWidget {
  const _ChatGamesSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.sm.w,
        bottom: Spacing.xs.h,
        top: Spacing.xs.h,
      ),
      child: Row(
        children: [
          Icon(
            Icons.sports_esports_outlined,
            color: colorScheme.onSurface,
            size: 23.h,
          ),
          Gap(Spacing.md.w),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// One game_sessions row, styled as the catalogue's rows are.
///
/// [onSelect] is null for the recently-played list, which has nothing to
/// resume — a completed session is a record, not a destination — and the
/// row then renders without tap feedback or a trailing arrow rather than
/// looking tappable and doing nothing.
class _ChatGameSessionRow extends StatelessWidget {
  const _ChatGameSessionRow({required this.game, this.onSelect});

  final Map<String, dynamic> game;
  final ValueChanged<ChatGameDestination>? onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gameType = game['game_type'] as String? ?? '';

    // Falls back to the raw-type title-caser rather than assuming the
    // display field was computed: recentGamesProvider returns rows
    // straight from the table, without game_type_display.
    final title =
        game['game_type_display'] as String? ?? gameTypeDisplayName(gameType);

    final destination =
        onSelect == null ? null : chatGameDestinationForType(gameType);
    final icon = chatGameIconForType(gameType) ?? Icons.sports_esports_outlined;

    final status = game['status'] as String? ?? '';
    final statusLabel = switch (status) {
      'invited' => 'Invitation waiting',
      'completed' => 'Completed',
      _ => 'In progress',
    };
    final subtitle = switch (status) {
      'invited' => 'Invitation waiting for your partner',
      'completed' => 'Recently played together',
      _ => 'Pick up where you left off',
    };

    return CardInkWell(
      onTap: destination == null ? null : () => onSelect!(destination),
      borderRadius: BorderRadius.circular(24),
      color: colorScheme.surface,
      padding: EdgeInsets.all(Spacing.md.w),
      margin: EdgeInsets.only(bottom: Spacing.sm.h),
      // elevation: 0,
      borderColor: colorScheme.outline.withValues(alpha: 0.08),
      child: InfoRowWidget(
        title: title,
        subtitle: subtitle,
        // The illustration where one exists; GameIcon falls back to this
        // glyph itself for the games not yet drawn.
        leadingWidget: GameIcon(gameType: gameType, size: 34.h),
        icon: icon,
        showAvatar: false,
        showDivider: false,
        showTrailingArrow: true,
        padAvatarTop: true,
        bottomWidget: _ChatGamePill(
          label: statusLabel,
          muted: status == 'completed',
        ),

        onTap: destination == null ? null : () => onSelect!(destination),
      ),

      // Row(
      //   children: [
      //     Container(
      //       width: 46.h,
      //       height: 46.h,
      //       decoration: BoxDecoration(
      //         color: colorScheme.primary,
      //         shape: BoxShape.circle,
      //       ),
      //       child: Icon(icon, color: colorScheme.onPrimary, size: 23.h),
      //     ),
      //     SizedBox(width: Spacing.md.w),
      //     Expanded(
      //       child: Column(
      //         crossAxisAlignment: CrossAxisAlignment.start,
      //         children: [
      //           Row(
      //             children: [
      //               Expanded(
      //                 child: Text(
      //                   title,
      //                   maxLines: 1,
      //                   overflow: TextOverflow.ellipsis,
      //                   style: Theme.of(context).textTheme.titleSmall?.copyWith(
      //                     color: colorScheme.onSurface,
      //                     fontWeight: FontWeight.w800,
      //                   ),
      //                 ),
      //               ),
      // _ChatGamePill(
      //   label: statusLabel,
      //   muted: status == 'completed',
      // ),
      //             ],
      //           ),
      //           SizedBox(height: 3.h),
      //           Text(
      //             subtitle,
      //             maxLines: 1,
      //             overflow: TextOverflow.ellipsis,
      //             style: Theme.of(context).textTheme.bodySmall?.copyWith(
      //               color: colorScheme.onSurface.withValues(alpha: 0.62),
      //             ),
      //           ),
      //         ],
      //       ),
      //     ),
      //   ],
      // ),
    );
  }
}

/// The catalogue's icon for a game_type.
///
/// PLACEHOLDER ART. The chat game card currently draws this icon on a
/// tinted disc, standing in for the illustrated board each game will get
/// -- the pool table, the dartboard, the archery range that iMessage's
/// games show. When those assets exist, this is the seam to replace:
/// swap the Icon for the artwork and leave the card's layout, states and
/// tap behaviour untouched.
///
/// Sourced from the sheet's own catalogue rather than a second list, so a
/// game cannot show one icon in the picker and another in the chat.
IconData? chatGameIconForType(String gameType) {
  final destination = chatGameDestinationForType(gameType);
  if (destination == null) return null;

  for (final category in _chatGameCategories) {
    for (final option in category.options) {
      if (option.destination == destination) return option.icon;
    }
  }
  return null;
}
