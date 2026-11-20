import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_complete_screen.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:attune/features/games/this_or_that/this_or_that_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// This or That's end, on the shell's completion screen.
///
/// The verdict over COMPLETE in tiles, the two players' names, the score
/// said in words and the round most worth talking about. It is a shared
/// result: nothing on it says who "got it wrong". The win sound and buzz
/// are the completion screen's, once, as it arrives.
class EndScreen extends ConsumerWidget {
  const EndScreen({
    super.key,
    required this.matchCount,
    required this.totalRounds,
    required this.mostInterestingPick,
    required this.onPlayAgain,
    required this.onTryAnotherGame,
  });

  final int matchCount;
  final int totalRounds;
  final Map<String, dynamic> mostInterestingPick;
  final VoidCallback onPlayAgain;
  final VoidCallback onTryAnotherGame;

  double get matchRatio => totalRounds == 0 ? 0 : matchCount / totalRounds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = thisOrThatPartnerLabel(
      ref.watch(gamePartnerNameProvider).valueOrNull?.trim(),
    );

    return GameCompleteScreen(
      theme: thisOrThatTheme,
      headline: _headline,
      word: 'COMPLETE',
      names: ['You', partner],
      onPlayAgain: onPlayAgain,
      onBackToGames: onTryAnotherGame,
      summary: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // On the backdrop, which is still the game's orange on a short
          // screen: white, where nothing else reads.
          Text(
            'You matched on $matchCount of $totalRounds.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameTheme.onGround,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameTheme.onGround,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          if (mostInterestingPick.isNotEmpty) ...[
            const SizedBox(height: 24),
            _PickTile(pick: mostInterestingPick, partner: partner),
          ],
        ],
      ),
    );
  }

  String get _headline {
    if (matchRatio >= 0.8) return 'Very much in sync';
    if (matchRatio >= 0.5) return 'More alike than not';
    return 'Full of surprises';
  }

  String get _subtitle {
    if (matchRatio >= 0.8) {
      return 'You found the same side $matchCount times. That deserves a rematch.';
    }
    if (matchRatio >= 0.5) {
      return 'A little alignment, a little discovery. Exactly the good stuff.';
    }
    return 'Different answers are not misses. They are invitations to know each other better.';
  }
}

/// The round worth talking about: a white tile with the question, and the
/// two picks on their options' colours, as the reveal showed them.
class _PickTile extends StatelessWidget {
  const _PickTile({required this.pick, required this.partner});

  final Map<String, dynamic> pick;
  final String partner;

  String _text(String key) => pick[key] as String? ?? '';

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    // The side each picked, where the router says; otherwise yours is
    // THIS and theirs THAT, as they always were here.
    Color face(String key, String fallback) =>
        (pick[key] as String? ?? fallback) == 'b'
            ? palette.thatColor
            : palette.thisColor;

    return GameTile(
      key: const ValueKey('this-or-that-end-pick'),
      radius: 20,
      depth: 6,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ThisOrThatStageLabel(
            text: 'Talk about this one',
            icon: Icons.chat_bubble_outline_rounded,
            color: GameTheme.tileInk,
          ),
          const SizedBox(height: 10),
          Text(
            _text('question_text'),
            style: const TextStyle(
              color: GameTheme.tileInk,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Pick(
                    key: const ValueKey('this-or-that-end-pick-you'),
                    owner: 'You',
                    text: _text('answer_a_text'),
                    emoji: _text('answer_a_emoji'),
                    face: face('answer_a', 'a'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Pick(
                    key: const ValueKey('this-or-that-end-pick-partner'),
                    owner: partner,
                    text: _text('answer_b_text'),
                    emoji: _text('answer_b_emoji'),
                    face: face('answer_b', 'b'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One player's pick, captioned with whose it is.
class _Pick extends StatelessWidget {
  const _Pick({
    super.key,
    required this.owner,
    required this.text,
    required this.emoji,
    required this.face,
  });

  final String owner;
  final String text;
  final String emoji;
  final Color face;

  @override
  Widget build(BuildContext context) {
    final ink = ThisOrThatPalette.of(context).inkOn(face);
    return Semantics(
      container: true,
      label: '$owner: $text',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: face,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                owner.toUpperCase(),
                maxLines: 2,
                style: TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              // Wraps in full: a long pick is the point of the tile.
              Text(
                '$emoji $text'.trim(),
                style: TextStyle(
                  color: ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
