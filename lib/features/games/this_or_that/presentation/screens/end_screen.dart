import 'dart:math' as math;

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EndScreen extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<EndScreen> createState() => _EndScreenState();
}

class _EndScreenState extends ConsumerState<EndScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _started = false;

  double get matchRatio =>
      widget.totalRounds == 0 ? 0 : widget.matchCount / widget.totalRounds;

  @override
  void initState() {
    super.initState();
    ref.read(soundServiceProvider).play(AppSound.gameComplete);
    ref.read(hapticsProvider).medium();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotionOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return ThisOrThatGameScaffold(
      title: 'Game complete',
      scrollable: true,
      bottom: Row(
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: OutlinedButton(
              onPressed: widget.onTryAnotherGame,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Icon(Icons.grid_view_rounded, size: 21),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ThisOrThatPrimaryAction(
              label: 'Play again',
              onPressed: widget.onPlayAgain,
              icon: Icons.replay_rounded,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          ScaleTransition(
            scale: CurvedAnimation(
              parent: _controller,
              curve: const Interval(0, 0.45, curve: Curves.easeOutBack),
            ),
            child: const GameIcon(gameType: 'this_or_that', size: 82),
          ),
          const SizedBox(height: 14),
          Text(
            _headline,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w900,
              height: 1.08,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              height: 1.4,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 22),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = Curves.easeOutCubic.transform(
                const Interval(0.18, 0.82).transform(_controller.value),
              );
              return Semantics(
                label:
                    '${widget.matchCount} matches out of ${widget.totalRounds} rounds',
                child: SizedBox.square(
                  dimension: 164,
                  child: CustomPaint(
                    painter: _ScoreRingPainter(
                      value: matchRatio * progress,
                      track: palette.line,
                      first: palette.thisColor,
                      second: palette.thatColor,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(matchRatio * progress * 100).round()}%',
                            style: Theme.of(
                              context,
                            ).textTheme.headlineMedium?.copyWith(
                              color: palette.ink,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                          Text(
                            '${widget.matchCount} matched',
                            style: Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(
                              color: palette.mutedInk,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (widget.mostInterestingPick.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.panel.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ThisOrThatStageLabel(
                    text: 'Talk about this one',
                    icon: Icons.chat_bubble_outline_rounded,
                    color: palette.thisColor,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.mostInterestingPick['question_text'] as String? ??
                        '',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _ResultPick(
                          label: 'YOU',
                          text:
                              widget.mostInterestingPick['answer_a_text']
                                  as String? ??
                              '',
                          emoji:
                              widget.mostInterestingPick['answer_a_emoji']
                                  as String? ??
                              '',
                          color: palette.thisColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ResultPick(
                          label: 'PARTNER',
                          text:
                              widget.mostInterestingPick['answer_b_text']
                                  as String? ??
                              '',
                          emoji:
                              widget.mostInterestingPick['answer_b_emoji']
                                  as String? ??
                              '',
                          color: palette.thatColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
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
      return 'You found the same side ${widget.matchCount} times. That deserves a rematch.';
    }
    if (matchRatio >= 0.5) {
      return 'A little alignment, a little discovery. Exactly the good stuff.';
    }
    return 'Different answers are not misses. They are invitations to know each other better.';
  }
}

class _ResultPick extends StatelessWidget {
  const _ResultPick({
    required this.label,
    required this.text,
    required this.emoji,
    required this.color,
  });

  final String label;
  final String text;
  final String emoji;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '$emoji $text'.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({
    required this.value,
    required this.track,
    required this.first,
    required this.second,
  });

  final double value;
  final Color track;
  final Color first;
  final Color second;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ringRect = rect.deflate(11);
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      ringRect,
      -math.pi / 2,
      math.pi * 2,
      false,
      paint..color = track,
    );
    paint.shader = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: math.pi * 1.5,
      colors: [first, second],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(ringRect);
    canvas.drawArc(
      ringRect,
      -math.pi / 2,
      math.pi * 2 * value.clamp(0, 1),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.track != track ||
      oldDelegate.first != first ||
      oldDelegate.second != second;
}
