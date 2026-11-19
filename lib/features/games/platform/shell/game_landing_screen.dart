import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_backdrop.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';

/// Where the two players stand in a game.
enum GameLandingStatus {
  /// No game in progress.
  fresh,

  /// The partner started one and is waiting for this player.
  invited,

  /// A game is in progress and this player can act.
  yourTurn,

  /// A game is in progress and the partner has to act.
  waiting,

  /// The last game is over.
  finished,
}

@immutable
class GameLandingState {
  const GameLandingState({
    required this.status,
    this.partnerName,
    this.caption,
    this.canRemind = false,
  });

  final GameLandingStatus status;

  /// Named on the button while waiting. Null falls back to "your partner".
  final String? partnerName;

  /// Where the game stands, such as "Round 3 of 10". Shown under the button.
  final String? caption;

  /// Whether a reminder can be sent right now. Only read while waiting.
  final bool canRemind;
}

/// What the landing page's one button says and whether it can be pressed.
@immutable
class GameLandingAction {
  const GameLandingAction({
    required this.label,
    required this.enabled,
    this.icon,
  });

  final String label;
  final bool enabled;
  final IconData? icon;
}

/// The button for a state.
///
/// Pure, so each of the five states is checked without building a screen.
/// The button is what makes this page about two people rather than one:
/// the same game says Play, Your turn or Waiting for Ama depending on who
/// has to move.
GameLandingAction landingAction(GameLandingState state) {
  switch (state.status) {
    case GameLandingStatus.fresh:
      return const GameLandingAction(
        label: GameStrings.play,
        enabled: true,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.invited:
      return const GameLandingAction(
        label: GameStrings.join,
        enabled: true,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.yourTurn:
      return const GameLandingAction(
        label: GameStrings.yourTurn,
        enabled: true,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.waiting:
      final name = state.partnerName?.trim();
      return GameLandingAction(
        label:
            name == null || name.isEmpty
                ? GameStrings.waitingForPartner
                : GameStrings.waitingFor(name),
        // Waiting is information, not an action: there is nothing this
        // player can do in the game until the partner moves.
        enabled: false,
      );
    case GameLandingStatus.finished:
      return const GameLandingAction(
        label: GameStrings.playAgain,
        enabled: true,
        icon: Icons.replay_rounded,
      );
  }
}

/// The page every game opens on.
///
/// The game's colour and tile art, its name, one button, and the list of
/// ways to play underneath. It scrolls as a whole, so the largest text size
/// reaches everything instead of overflowing.
class GameLandingScreen extends StatelessWidget {
  const GameLandingScreen({
    super.key,
    required this.definition,
    required this.state,
    this.onPrimary,
    this.onRemind,
    this.onBack,
    this.onHowToPlay,
  });

  final GameDefinition definition;
  final GameLandingState state;

  /// Called when the button is pressed. Never called while waiting.
  final VoidCallback? onPrimary;

  final VoidCallback? onRemind;
  final VoidCallback? onBack;
  final VoidCallback? onHowToPlay;

  @override
  Widget build(BuildContext context) {
    final action = landingAction(state);
    final entries =
        definition.entriesBuilder?.call(context) ?? const <GameEntry>[];
    final showRemind =
        state.status == GameLandingStatus.waiting &&
        state.canRemind &&
        onRemind != null;

    return Scaffold(
      backgroundColor: GameTheme.ground,
      body: GameBackdrop(
        theme: definition.theme,
        child: SafeArea(
          child: AppContentWidth(
            maxWidth: ContentWidth.form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GameRoundButton(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: GameStrings.back,
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                    ),
                    if (onHowToPlay != null)
                      GameRoundButton(
                        icon: Icons.question_mark_rounded,
                        semanticLabel: GameStrings.howToPlay,
                        onTap: onHowToPlay,
                      ),
                  ],
                ),
                SizedBox(
                  height: 220,
                  child: Center(
                    child: ExcludeSemantics(
                      child: definition.heroBuilder(context, definition.theme),
                    ),
                  ),
                ),
                Text(
                  definition.collectionLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  child: Text(
                    definition.title,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  definition.tagline,
                  style: const TextStyle(
                    color: GameTheme.mutedOnGround,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 28),
                GamePrimaryButton(
                  label: action.label,
                  icon: action.icon,
                  onTap: action.enabled ? onPrimary : null,
                ),
                if (state.caption != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    state.caption!.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: GameTheme.mutedOnGround,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
                if (showRemind) ...[
                  const SizedBox(height: 12),
                  GameSecondaryButton(
                    label: GameStrings.remind,
                    onTap: onRemind,
                  ),
                ],
                if (entries.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: GameTheme.hairline),
                  for (var i = 0; i < entries.length; i++)
                    _EntryRow(number: i + 1, entry: entries[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.number, required this.entry});

  final int number;
  final GameEntry entry;

  @override
  Widget build(BuildContext context) {
    final onTap = entry.onTap;

    return Column(
      children: [
        InkWell(
          onTap: onTap == null ? null : () => onTap(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: GameTheme.tile,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 30,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: GameTheme.tileInk,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        GameStrings.entryNumber(number, entry.title),
                        style: const TextStyle(fontSize: 17),
                      ),
                      if (entry.subtitle != null)
                        Text(
                          entry.subtitle!,
                          style: const TextStyle(
                            color: GameTheme.mutedOnGround,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: GameTheme.hairline),
      ],
    );
  }
}
