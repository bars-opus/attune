import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_backdrop.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_content_width.dart';
import 'package:flutter/material.dart';

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
    this.entries = const <GameEntry>[],
    this.onPrimary,
    this.onRemind,
    this.onBack,
    this.onHowToPlay,
    this.busy = false,
  });

  final GameDefinition definition;
  final GameLandingState state;

  /// The rows under the button. Empty shows no list.
  final List<GameEntry> entries;

  /// Called when the button is pressed. Never called while it is disabled:
  /// waiting, loading or coming soon.
  final VoidCallback? onPrimary;

  final VoidCallback? onRemind;
  final VoidCallback? onBack;
  final VoidCallback? onHowToPlay;

  /// Something the button or a row asked for is still running: the button
  /// shows it is busy, and it, the rows and the reminder take no taps.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final action = landingAction(state);
    final showRemind =
        state.status == GameLandingStatus.waiting &&
        state.canRemind &&
        onRemind != null;

    return Scaffold(
      backgroundColor: GameTheme.ground,
      body: GameBackdrop(
        theme: definition.theme,
        child: SafeArea(
          child: GameContentWidth(
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
                  busy: busy,
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
                    onTap: busy ? null : onRemind,
                  ),
                ],
                if (entries.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: GameTheme.hairline),
                  for (var i = 0; i < entries.length; i++)
                    _EntryRow(
                      number: i + 1,
                      entry: entries[i],
                      enabled: !busy,
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

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.number,
    required this.entry,
    required this.enabled,
  });

  final int number;
  final GameEntry entry;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final onTap = enabled ? entry.onTap : null;

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
