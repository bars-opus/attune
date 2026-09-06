import 'dart:math' as math;

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/match_indicator.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RevealScreen extends ConsumerStatefulWidget {
  const RevealScreen({
    super.key,
    required this.questionText,
    required this.userChoice,
    required this.userChoiceText,
    required this.userChoiceEmoji,
    required this.partnerChoice,
    required this.partnerChoiceText,
    required this.partnerChoiceEmoji,
    required this.partnerName,
    required this.roundNumber,
    required this.totalRounds,
    required this.isMatch,
    required this.onNext,
    this.onPrevious,
    this.hasPrevious = false,
  });

  final String questionText;
  final String userChoice;
  final String userChoiceText;
  final String userChoiceEmoji;
  final String partnerChoice;
  final String partnerChoiceText;
  final String partnerChoiceEmoji;
  final String partnerName;
  final int roundNumber;
  final int totalRounds;
  final bool isMatch;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;
  final bool hasPrevious;

  @override
  ConsumerState<RevealScreen> createState() => _RevealScreenState();
}

class _RevealScreenState extends ConsumerState<RevealScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 1180),
    vsync: this,
  );
  bool _started = false;

  Animation<double> get _questionAnimation => CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.28, curve: Curves.easeOut),
  );

  Animation<double> get _cardAnimation => CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.16, 0.68, curve: Curves.easeOutCubic),
  );

  Animation<double> get _resultAnimation => CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.62, 1, curve: Curves.easeOutBack),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isMatch) {
      ref.read(hapticsProvider).medium();
      ref.read(soundServiceProvider).play(AppSound.gameMatch);
    } else {
      ref.read(hapticsProvider).light();
      ref.read(soundServiceProvider).play(AppSound.gameReveal);
    }
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
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      bottom: Row(
        children: [
          if (widget.hasPrevious) ...[
            SizedBox(
              width: 56,
              height: 56,
              child: OutlinedButton(
                onPressed: widget.onPrevious,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: ThisOrThatPrimaryAction(
              label:
                  widget.roundNumber == widget.totalRounds
                      ? 'See our result'
                      : 'Next round',
              onPressed: widget.onNext,
              icon:
                  widget.roundNumber == widget.totalRounds
                      ? Icons.emoji_events_rounded
                      : Icons.arrow_forward_rounded,
            ),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.isMatch)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder:
                      (context, _) => CustomPaint(
                        painter: _CelebrationPainter(
                          progress: _resultAnimation.value,
                          first: palette.thisColor,
                          second: palette.thatColor,
                        ),
                      ),
                ),
              ),
            ),
          Column(
            children: [
              const SizedBox(height: 8),
              FadeTransition(
                opacity: _questionAnimation,
                child: Column(
                  children: [
                    const ThisOrThatStageLabel(
                      text: 'The reveal',
                      icon: Icons.visibility_rounded,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.questionText,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: AnimatedBuilder(
                  animation: _cardAnimation,
                  builder: (context, _) {
                    final value = _cardAnimation.value;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(-54 * (1 - value), 0),
                              child: ThisOrThatChoiceCard(
                                side: widget.userChoice == 'b' ? 'b' : 'a',
                                text: widget.userChoiceText,
                                emoji: widget.userChoiceEmoji,
                                selected: true,
                                badge: 'YOU',
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 42,
                          child: Center(
                            child: Transform.scale(
                              scale: 0.75 + (value * 0.25),
                              child: Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: palette.ink,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: palette.canvas,
                                    width: 3,
                                  ),
                                ),
                                child: Text(
                                  'VS',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(
                                    color: palette.canvas,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(54 * (1 - value), 0),
                              child: ThisOrThatChoiceCard(
                                side: widget.partnerChoice == 'b' ? 'b' : 'a',
                                text: widget.partnerChoiceText,
                                emoji: widget.partnerChoiceEmoji,
                                selected: true,
                                badge: widget.partnerName.toUpperCase(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              MatchIndicator(
                isMatch: widget.isMatch,
                animation: _resultAnimation,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  const _CelebrationPainter({
    required this.progress,
    required this.first,
    required this.second,
  });

  final double progress;
  final Color first;
  final Color second;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = Offset(size.width / 2, size.height * 0.52);
    final eased = Curves.easeOut.transform(progress.clamp(0, 1));
    for (var i = 0; i < 18; i++) {
      final angle = (math.pi * 2 / 18) * i;
      final distance = (28 + ((i % 4) * 12)) * eased;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final radius = (i.isEven ? 3.2 : 2.2) * (1 - (progress * 0.35));
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..color = (i.isEven ? first : second).withValues(
            alpha: (1 - progress).clamp(0.12, 0.75),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.first != first ||
      oldDelegate.second != second;
}
