import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/session_games/presentation/widgets/session_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Closes a completed session.
///
/// [yourScore] is populated for Mirror only, and is the VIEWER'S OWN
/// score. §11.1 makes it self-facing: this screen must never receive or
/// render the partner's score, and there is deliberately no parameter
/// for it. mirror_scores' RLS (USING user_id = auth.uid()) means a
/// caller could not fetch one even if this screen asked.
class SessionGameEndScreen extends ConsumerStatefulWidget {
  const SessionGameEndScreen({
    super.key,
    required this.onDone,
    this.yourScore,
    this.totalRounds,
  });

  final VoidCallback onDone;
  final int? yourScore;
  final int? totalRounds;

  @override
  ConsumerState<SessionGameEndScreen> createState() =>
      _SessionGameEndScreenState();
}

class _SessionGameEndScreenState extends ConsumerState<SessionGameEndScreen> {
  bool _announced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_announced) return;
    _announced = true;
    // A finished session was silent, which made the end of a game feel
    // like a screen you had wandered onto rather than somewhere you
    // arrived.
    ref.read(soundServiceProvider).play(AppSound.gameComplete);
    ref.read(hapticsProvider).medium();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SessionGamePalette.of(
      context,
      gameType: SessionGameTypeScope.of(context),
    );
    final textTheme = Theme.of(context).textTheme;
    final score = widget.yourScore;
    final total = widget.totalRounds;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Center(
            child: SessionGameStageLabel(
              text: 'that is the end',
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 24),
          if (score != null && total != null) ...[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: palette.panel,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.line),
              ),
              child: Column(
                children: [
                  // Counts up rather than appearing: a number that ticks
                  // reads as something being totted up.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: score.toDouble()),
                    duration:
                        reduceMotionOf(context)
                            ? Duration.zero
                            : Duration(milliseconds: 500 + (score * 130)),
                    curve: Curves.easeOutCubic,
                    builder:
                        (context, value, _) => Text(
                          '${value.round()}',
                          style: textTheme.displaySmall?.copyWith(
                            color: palette.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                  ),
                  const SizedBox(height: 6),
                  // Framed as the viewer's own reading of their partner,
                  // never as a verdict on either person (§11.1, and
                  // §8.4's "no diagnosis language").
                  Text(
                    'of $total times you read them right',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.mutedInk,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ] else ...[
            Center(
              child: Text(
                'You both showed up for that one.',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(color: palette.ink),
              ),
            ),
            const SizedBox(height: 28),
          ],
          SessionGamePrimaryAction(
            label: 'Done',
            icon: Icons.check_rounded,
            onPressed: widget.onDone,
          ),
        ],
      ),
    );
  }
}
