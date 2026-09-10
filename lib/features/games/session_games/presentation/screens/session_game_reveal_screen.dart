import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:attune/features/games/session_games/presentation/widgets/session_game_ui.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';

/// Shows both answers side by side once the gate has opened.
///
/// Takes an already-fetched [RevealedRound] rather than fetching one:
/// the caller obtained it from get_revealed_round, and a screen that
/// could fetch answers itself would be a second path to guard.
class SessionGameRevealScreen extends ConsumerStatefulWidget {
  const SessionGameRevealScreen({
    super.key,
    required this.round,
    required this.yourAnswerIsA,
    required this.onNext,
  });

  final RevealedRound round;

  /// Which slot belongs to the viewer, so the labels are right.
  final bool yourAnswerIsA;
  final VoidCallback onNext;

  @override
  ConsumerState<SessionGameRevealScreen> createState() =>
      _SessionGameRevealScreenState();
}

class _SessionGameRevealScreenState
    extends ConsumerState<SessionGameRevealScreen> {
  bool _announced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_announced) return;
    _announced = true;
    // Both answers meeting is what the round was for. It was silent.
    ref.read(soundServiceProvider).play(AppSound.gameReveal);
    ref.read(hapticsProvider).light();
  }

  @override
  Widget build(BuildContext context) {
    // Defensive: the caller should only build this once bothAnswered is
    // true, but rendering nulls as empty rather than "null" keeps a
    // mistake from displaying something that looks like an answer.
    final yours =
        (widget.yourAnswerIsA ? widget.round.answerA : widget.round.answerB) ??
        '';
    final theirs =
        (widget.yourAnswerIsA ? widget.round.answerB : widget.round.answerA) ??
        '';

    // Matching is the quiet hope of these games, so it is marked -- but
    // only marked. No score, no streak: landing on the same answer is a
    // nice moment, not a point.
    final matched =
        yours.isNotEmpty &&
        theirs.isNotEmpty &&
        yours.trim().toLowerCase() == theirs.trim().toLowerCase();

    final palette = SessionGamePalette.of(
      context,
      gameType: SessionGameTypeScope.of(context),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (matched) ...[
            Center(
              child: SessionGameStageLabel(
                text: 'you both said the same thing',
                icon: Icons.favorite_rounded,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 18),
          ],
          SessionGameAnswerCard(
            speaker: 'You',
            answer: yours,
            isYours: true,
            matched: matched,
          ),
          const SizedBox(height: 14),
          SessionGameAnswerCard(
            speaker: partnerNameOr(ref),
            answer: theirs,
            isYours: false,
            matched: matched,
          ),
          const SizedBox(height: 32),
          SessionGamePrimaryAction(
            label: 'Next',
            icon: Icons.arrow_forward_rounded,
            onPressed: widget.onNext,
          ),
        ],
      ),
    );
  }
}
