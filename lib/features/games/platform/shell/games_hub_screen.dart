import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_session_status.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/games_catalogue.dart';
import 'package:attune/features/games/platform/legacy/legacy_game_opener.dart';
import 'package:attune/features/games/platform/shell/game_backdrop.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_content_width.dart';
import 'package:attune/features/games/platform/shell/game_hub_card.dart';
import 'package:attune/features/games/platform/shell/game_route_resume.dart';
import 'package:attune/features/games/platform/shell/game_tap_guard.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Every game, and every game in progress. Route: /games/hub.
///
/// The games in progress first, each saying whose move it is; then the
/// launch games as blocks of their colours, the first one large; then the
/// games still to come, dimmed.
class GamesHubScreen extends ConsumerStatefulWidget {
  const GamesHubScreen({super.key});

  @override
  ConsumerState<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends ConsumerState<GamesHubScreen>
    with GameRouteResume<GamesHubScreen>, GameTapGuard<GamesHubScreen> {
  /// The hub is in front again after a game or a landing page: a game may
  /// have started or ended there without an event the list heard.
  @override
  void onRouteResumed() => ref.invalidate(activeGamesProvider);

  void _openLanding(GameDefinition definition) {
    runOnce(definition.gameType, () {
      // Not awaited: the push lasts until the landing page is closed.
      unawaited(
        context.pushNamed(
          'gameLanding',
          pathParameters: {'gameType': definition.gameType},
        ),
      );
    });
  }

  void _openSession(String gameType, String sessionId) {
    runOnce(gameType, () {
      final controller =
          ref.read(gameRegistryProvider).byType(gameType)?.controller;
      if (controller != null) {
        return controller.openSession(context, ref, sessionId: sessionId);
      }
      return ref.read(legacyGameOpenerProvider)(
        context,
        gameType,
        sessionId: sessionId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // A partner inviting, moving or finishing fetches the list again.
    ref.listen<AsyncValue<void>>(gameSessionEventsProvider, (_, next) {
      if (next.hasValue) ref.invalidate(activeGamesProvider);
    });

    final registry = ref.watch(gameRegistryProvider);
    final name = ref.watch(gamePartnerNameProvider).valueOrNull?.trim();
    // Kept through a refetch; a list that failed to load shows no section.
    final sessions = [
      for (final row
          in ref.watch(activeGamesProvider).valueOrNull ??
              const <Map<String, dynamic>>[])
        if (row['id'] is String) row,
    ];
    final launch = registry.launch.toList();
    final comingSoon = registry.comingSoon.toList();
    final gridNames = [
      for (final definition in [...launch.skip(1), ...comingSoon])
        definition.title,
    ];

    return Scaffold(
      backgroundColor: GameTheme.ground,
      body: GameBackdrop(
        // No game's colour: the hub is the ground the games sit on.
        theme: const GameTheme(primary: GameTheme.ground),
        child: SafeArea(
          bottom: false,
          child: GameContentWidth(
            maxWidth: ContentWidth.list,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                Row(
                  children: [
                    GameRoundButton(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: GameStrings.back,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: const Text(
                    GameStrings.games,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ),
                // An empty line while the name is unknown: "Play together"
                // would repeat the section heading a few lines below, and
                // holding the line's height keeps the games from moving
                // down when the name arrives.
                const SizedBox(height: 4),
                Text(
                  name != null && name.isNotEmpty
                      ? GameStrings.playWith(name)
                      : '',
                  style: const TextStyle(
                    color: GameTheme.mutedOnGround,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sessions.isNotEmpty) ...[
                  const _SectionTitle(GameStrings.inPlay),
                  for (final row in sessions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SessionRow(
                        key: ValueKey('games-hub-session-${row['id']}'),
                        sessionId: row['id'] as String,
                        gameType: row['game_type'] as String? ?? '',
                        initiatorId: row['initiator_id'] as String?,
                        definition: registry.byType(
                          row['game_type'] as String?,
                        ),
                        onTap:
                            () => _openSession(
                              row['game_type'] as String? ?? '',
                              row['id'] as String,
                            ),
                      ),
                    ),
                ],
                if (launch.isNotEmpty) ...[
                  const _SectionTitle(GameStrings.playTogether),
                  GameHubCard(
                    definition: launch.first,
                    featured: true,
                    onTap: () => _openLanding(launch.first),
                  ),
                  const SizedBox(height: _gap),
                  _CardGrid(
                    names: gridNames,
                    cards: [
                      for (final definition in launch.skip(1))
                        GameHubCard(
                          definition: definition,
                          onTap: () => _openLanding(definition),
                        ),
                    ],
                  ),
                ],
                if (comingSoon.isNotEmpty) ...[
                  const _SectionTitle(GameStrings.comingSoon),
                  _CardGrid(
                    names: gridNames,
                    cards: [
                      for (final definition in comingSoon)
                        GameHubCard(definition: definition),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const double _gap = 12;

/// Cards two to a row, each row as tall as its tallest card, so a name that
/// wraps never leaves its neighbour short.
///
/// One to a row when a word of any name would not fit across a half-width
/// card at this text size: broken mid-word ("36 Ques / tions") reads worse
/// than a longer list.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.cards, required this.names});

  final List<GameHubCard> cards;

  /// Every name drawn in a grid card, so the grids on the page choose alike.
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = _twoFit(context, constraints.maxWidth) ? 2 : 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i += perRow)
              Padding(
                padding: const EdgeInsets.only(bottom: _gap),
                child:
                    perRow == 1
                        ? cards[i]
                        : IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: cards[i]),
                              const SizedBox(width: _gap),
                              Expanded(
                                child:
                                    i + 1 < cards.length
                                        ? cards[i + 1]
                                        : const SizedBox(),
                              ),
                            ],
                          ),
                        ),
              ),
          ],
        );
      },
    );
  }

  bool _twoFit(BuildContext context, double width) {
    if (!width.isFinite) return true;
    final room = (width - _gap) / 2 - 2 * GameHubCard.padding;
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(GameHubCard.titleStyle);
    final scaler = MediaQuery.textScalerOf(context);
    for (final name in names) {
      for (final word in name.split(' ')) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final fits = painter.width <= room;
        painter.dispose();
        if (!fits) return false;
      }
    }
    return true;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 12),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// A game in progress: its colour and icon, its name, and whose move it is.
class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    super.key,
    required this.sessionId,
    required this.gameType,
    required this.initiatorId,
    required this.definition,
    required this.onTap,
  });

  final String sessionId;
  final String gameType;
  final String? initiatorId;

  /// Null for a game this build has not been taught.
  final GameDefinition? definition;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = watchSessionLanding(
      ref,
      sessionId: sessionId,
      initiatorId: initiatorId,
    );
    // Nothing while the state is on its way: landingAction says Play for
    // loading, which is wrong for a game already under way.
    final action =
        state.status == GameLandingStatus.loading ? null : landingAction(state);
    final title = definition?.title ?? gameTypeDisplayName(gameType);
    final colour = definition?.theme.primary ?? GameColors.comingSoon;
    final icon = definition?.icon ?? gameGlyphFor(gameType);

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: action == null ? title : '$title, ${action.label}',
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        // Never disabled: even waiting on the partner, the game's own screen
        // shows where it stands.
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: GameTheme.raised,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 44,
                    child: Icon(icon, size: 24, color: hubCardInk(colour)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (action != null)
                        Text(
                          action.label,
                          style: TextStyle(
                            color:
                                action.enabled
                                    ? GameTheme.onGround
                                    : GameTheme.mutedOnGround,
                            fontSize: 14,
                            fontWeight:
                                action.enabled
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: GameTheme.mutedOnGround,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
