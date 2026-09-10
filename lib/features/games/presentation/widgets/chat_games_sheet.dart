import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/search_text_field.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:attune/features/games/presentation/widgets/game_hub_theme.dart';
import 'package:attune/features/games/presentation/widgets/game_grid_tile.dart';

enum ChatGameDestination {
  thisOrThat,
  truthOrDare,
  thirtySixQuestions,
  paintBall,
  snakesAndLadders,
  wordHunt,
  neverHaveIEver,
  // Throwaway builds, reachable so they can actually be played and
  // judged. Neither is a game Attune offers.
  dotsAndBoxesPrototype,
  constellationPrototype,
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
    'snakes_and_ladders',
    'word_hunt',
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
    'snakes_and_ladders': ChatGameDestination.snakesAndLadders,
    'word_hunt': ChatGameDestination.wordHunt,
  };

  return byType[gameType];
}

class ChatGamesSheet extends ConsumerStatefulWidget {
  const ChatGamesSheet({
    super.key,
    required this.onSelect,
    this.onStageNewGame,
    this.onOpenPaintBallSession,
  });

  /// Opening a game that already exists -- "Continue playing". Goes
  /// straight in, because the invitation happened long ago.
  final ValueChanged<ChatGameDestination> onSelect;

  /// Picking a NEW game from the catalogue, which stages it in the
  /// composer rather than starting it.
  ///
  /// Separate from [onSelect] deliberately. The two used to be one
  /// callback and the difference was inferred downstream, which is how a
  /// glance at the catalogue ended up creating a session: there was no
  /// point in the code that knew "this is a game the player has not
  /// agreed to start yet". Falls back to [onSelect] when absent, so a
  /// caller that has no composer still works.
  final ValueChanged<ChatGameDestination>? onStageNewGame;

  final ValueChanged<String>? onOpenPaintBallSession;

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
            onStageNewGame: widget.onStageNewGame ?? widget.onSelect,
            onOpenPaintBallSession: widget.onOpenPaintBallSession,
          ),
        ),
    ];

    // DARK, WHATEVER THE APP THEME IS. Every tile carries a saturated
    // gradient chosen against near-black; on a white sheet the same
    // colours read as highlighter. Rather than maintain two palettes,
    // the hub declares one surface -- the same call the Arcade games
    // already made for their boards.
    return GameHubTheme.wrap(
      child: GestureDetector(
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
    required this.onStageNewGame,
    required this.onOpenPaintBallSession,
  });

  final String query;
  final String? mood;
  final List<_ChatGameCategory> categories;
  final ValueChanged<ChatGameDestination> onSelect;
  final ValueChanged<ChatGameDestination> onStageNewGame;
  final ValueChanged<String>? onOpenPaintBallSession;

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
          return _ChatGamesInProgress(
            onSelect: onSelect,
            onOpenPaintBallSession: onOpenPaintBallSession,
          );
        }

        final categoryIndex = showInProgress ? index - 1 : index;
        final category = categories[categoryIndex];

        // The catalogue stages; only "Continue playing" above opens.
        return _ChatGameCategorySection(
          category: category,
          onSelect: onStageNewGame,
        );
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
      _ChatGameOption(
        destination: ChatGameDestination.snakesAndLadders,
        title: 'Snakes and Ladders',
        // Says plainly what it is FOR. Every other game here promises
        // something to learn; this one promises the opposite, and a
        // couple reaching for it after a hard conversation should be
        // able to tell at a glance.
        subtitle: 'No questions, just a die',
        icon: Icons.casino_outlined,
        tags: {'Quick', 'Fun'},
      ),
      _ChatGameOption(
        destination: ChatGameDestination.wordHunt,
        title: 'Word Hunt',
        // Thirty seconds, next to Snakes' ten minutes. Says what it costs
        // rather than what it teaches, because it teaches nothing.
        subtitle: 'One hidden word, who spots it first',
        icon: Icons.grid_on_outlined,
        tags: {'Quick', 'Fun'},
      ),
    ],
  ),
  // PROTOTYPES — deliberately their own category, and deliberately last.
  //
  // Both are throwaway builds that exist to answer a question a spec
  // cannot, and both are pass-and-play on one device rather than real
  // asynchronous games. They are here so they can be PLAYED and judged;
  // mixing them into the Arcade would imply Attune offers them.
  _ChatGameCategory(
    title: 'Prototypes',
    options: [
      _ChatGameOption(
        destination: ChatGameDestination.dotsAndBoxesPrototype,
        title: 'Dots and Boxes',
        // The question: does a skill-dominant game ruin a cooldown slot?
        subtitle: 'Prototype · pass the phone · does one of you always win?',
        icon: Icons.grid_4x4_outlined,
        tags: {'Prototype'},
      ),
      _ChatGameOption(
        destination: ChatGameDestination.constellationPrototype,
        title: 'Constellation',
        // The question: is a game with no stakes worth opening at all?
        subtitle: 'Prototype · pass the phone · no winner, nothing to lose',
        icon: Icons.auto_awesome_outlined,
        tags: {'Prototype'},
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: Spacing.xxl.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
          child: Text(
            category.title,
            style: const TextStyle(
              color: GameHubTheme.primaryText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(height: Spacing.sm.h),
        // TWO across. The card carries its own name and description now
        // rather than captioning below, so it needs the width -- three
        // across truncated every subtitle to a word and a half.
        LayoutBuilder(
          builder: (context, constraints) {
            const columns = 2;
            final gap = Spacing.sm.w;
            final tileWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
              child: Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final option in category.options)
                    SizedBox(
                      width: tileWidth - 10.w,
                      child: GameGridTile(
                        gameType:
                            chatGameTypeForDestination(option.destination) ??
                            'prototype',
                        title: option.title,
                        subtitle: option.subtitle,
                        comingSoon: option.comingSoon,
                        onTap: () => onSelect(option.destination),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
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
  const _ChatGamesInProgress({
    required this.onSelect,
    required this.onOpenPaintBallSession,
  });

  final ValueChanged<ChatGameDestination> onSelect;
  final ValueChanged<String>? onOpenPaintBallSession;

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
          // The same row as Recently played, deliberately. A horizontal
          // rail put in-progress games in a different visual language
          // from finished ones, which made the sheet read as two
          // unrelated lists rather than one history with a live top.
          for (final game in active)
            _ChatGameSessionRow(game: game, onSelect: onSelect),
          Gap(Spacing.lg.h),
        ],
        if (recent.isNotEmpty) ...[
          Gap(Spacing.md.h),
          _ChatGamesSectionLabel(label: 'Recently played'),
          Gap(Spacing.sm.h),
          for (final game in recent)
            _ChatGameSessionRow(
              game: game,
              onOpenPaintBallSession: onOpenPaintBallSession,
            ),
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
/// Used only by the recently-played list now: in-progress games moved to
/// the horizontal rail above. A completed session cannot be resumed, so
/// there is no destination to open -- Paint Ball is the one game with a
/// full recap, which is what [onOpenPaintBallSession] is for.
class _ChatGameSessionRow extends StatelessWidget {
  const _ChatGameSessionRow({
    required this.game,
    this.onSelect,
    this.onOpenPaintBallSession,
  });

  final Map<String, dynamic> game;

  /// Non-null for "Continue playing": an unfinished session has somewhere
  /// to go. Null for "Recently played", where a finished session does
  /// not -- Paint Ball's recap is the one exception, which is what
  /// [onOpenPaintBallSession] is for.
  final ValueChanged<ChatGameDestination>? onSelect;

  final ValueChanged<String>? onOpenPaintBallSession;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gameType = game['game_type'] as String? ?? '';

    // Falls back to the raw-type title-caser rather than assuming the
    // display field was computed: recentGamesProvider returns rows
    // straight from the table, without game_type_display.
    final title =
        game['game_type_display'] as String? ?? gameTypeDisplayName(gameType);

    final status = game['status'] as String? ?? '';
    final sessionId = game['id'] as String?;
    final canOpenPaintBallRecap =
        status == 'completed' &&
        gameType == 'paint_ball' &&
        sessionId != null &&
        onOpenPaintBallSession != null;
    final destination =
        onSelect == null ? null : chatGameDestinationForType(gameType);
    final VoidCallback? rowOnTap =
        destination != null
            ? () => onSelect!(destination)
            : canOpenPaintBallRecap
            ? () => onOpenPaintBallSession!(sessionId)
            : null;
    final subtitle = switch (status) {
      'invited' => 'Invitation waiting for your partner',
      'completed' => 'Recently played together',
      _ => 'Pick up where you left off',
    };

    return CardInkWell(
      onTap: rowOnTap,
      borderRadius: BorderRadius.circular(24),
      color: Colors.grey.withValues(alpha: 0.1),
      padding: EdgeInsets.all(Spacing.md.w),
      margin: EdgeInsets.only(bottom: Spacing.sm.h),
      // elevation: 0,
      borderColor: colorScheme.outline.withValues(alpha: 0.08),
      child: InfoRowWidget(
        pinAvatar: true,
        title: title,
        subtitle: subtitle,
        // The game's colour and glyph handed straight to the row rather
        // than wrapped in a GameIcon. InfoRowWidget puts a leadingWidget
        // inside a SizedBox of avatarRadius and centres it, so an 80px
        // tile in a 45px box overflowed and sat off-centre. Going through
        // the row's own IconAvatar means one widget owns the sizing.
        icon: gameGlyphFor(gameType),
        iconColor: Colors.white,
        backgroundColor: GamePalette.of(gameType).end,
        avatarRadius: 52.h,
        iconSize: 26.h,
        circularRadius: 14.r,
        // TRUE, or IconAvatar renders a bare glyph and skips its
        // coloured container entirely -- which is what made the game's
        // colour vanish from the row.
        showAvatar: true,
        showDivider: false,
        showTrailingArrow: rowOnTap != null,
        padAvatarTop: true,
        onTap: rowOnTap,
      ),
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
