import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/games/platform/feel/game_feedback.dart';
import 'package:attune/features/games/platform/feel/game_letter_tiles.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_backdrop.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where every game ends.
///
/// A headline, one word spelled in tiles, the players' names, and whatever
/// the game wants to say about how it went. It names the two people who
/// played rather than scoring either of them.
class GameCompleteScreen extends ConsumerStatefulWidget {
  const GameCompleteScreen({
    super.key,
    required this.theme,
    required this.headline,
    required this.word,
    required this.onBackToGames,
    this.names = const [],
    this.summary,
    this.onPlayAgain,
  });

  final GameTheme theme;

  /// The line over the tiles, such as "This or That".
  final String headline;

  /// The word spelled in tiles, such as "COMPLETE".
  final String word;

  /// Who played. Joined with an ampersand.
  final List<String> names;

  /// The game's own account of the result.
  final Widget? summary;

  /// Null hides Play again.
  final VoidCallback? onPlayAgain;

  final VoidCallback onBackToGames;

  @override
  ConsumerState<GameCompleteScreen> createState() => _GameCompleteScreenState();
}

class _GameCompleteScreenState extends ConsumerState<GameCompleteScreen> {
  @override
  void initState() {
    super.initState();
    // Once, when the screen arrives -- not on every rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(gameFeedbackProvider).fire(GameEvent.complete);
    });
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.names.where((name) => name.trim().isNotEmpty).toList();

    return Scaffold(
      backgroundColor: GameTheme.ground,
      body: GameBackdrop(
        theme: widget.theme,
        child: SafeArea(
          child: AppContentWidth(
            maxWidth: ContentWidth.form,
            child: Column(
              children: [
                Expanded(
                  // Centred when it fits, scrolling when it does not.
                  child: LayoutBuilder(
                    builder:
                        (context, box) => SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: box.maxHeight,
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: _content(names),
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.onPlayAgain != null) ...[
                        GamePrimaryButton(
                          label: GameStrings.playAgain,
                          icon: Icons.replay_rounded,
                          onTap: widget.onPlayAgain,
                        ),
                        const SizedBox(height: 12),
                      ],
                      GameSecondaryButton(
                        label: GameStrings.backToGames,
                        onTap: widget.onBackToGames,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(List<String> names) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 12),
        GameLetterTiles(word: widget.word, tileSize: 36),
        if (names.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(
            names.join(' & '),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
        if (widget.summary != null) ...[
          const SizedBox(height: 20),
          widget.summary!,
        ],
      ],
    );
  }
}
