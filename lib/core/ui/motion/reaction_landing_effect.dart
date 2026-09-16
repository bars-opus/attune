import 'dart:async';
import 'dart:math' as math;

import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

/// Gives the receiving bubble the same expand-compress-settle beat as the
/// reaction drawn at its edge. [trigger] is deliberately just a revision:
/// reaction data may update before or after the flight, while the screen can
/// increment this value at the exact visual landing moment.
class ReactionImpactScale extends StatefulWidget {
  const ReactionImpactScale({
    super.key,
    required this.trigger,
    required this.child,
    this.alignment = Alignment.center,
    this.duration = kReactionLandingDuration,
  });

  final Object trigger;
  final Widget child;
  final Alignment alignment;
  final Duration duration;

  @override
  State<ReactionImpactScale> createState() => _ReactionImpactScaleState();
}

class _ReactionImpactScaleState extends State<ReactionImpactScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.045,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.045,
        end: 0.985,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 34,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.985,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 36,
    ),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant ReactionImpactScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && !reduceMotionOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    key: const ValueKey('reaction-bubble-impact'),
    scale: _scale,
    alignment: widget.alignment,
    child: widget.child,
  );
}

/// Continues a reaction flight with a small impact at its landing point.
///
/// The overlay returns to exactly 1x before disappearing, so the handoff to
/// the real reaction badge is visually quiet. It never changes bubble layout.
Future<void> showReactionLandingEffect({
  required BuildContext context,
  required Offset center,
  required String emoji,
  Duration duration = kReactionLandingDuration,
}) {
  if (reduceMotionOf(context)) return Future<void>.value();

  final overlay = Overlay.of(context, rootOverlay: true);
  final completed = Completer<void>();
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder:
        (context) => _ReactionLandingEffect(
          center: center,
          emoji: emoji,
          duration: duration,
          onCompleted: () {
            entry.remove();
            if (!completed.isCompleted) completed.complete();
          },
        ),
  );
  overlay.insert(entry);
  return completed.future;
}

class _ReactionLandingEffect extends StatefulWidget {
  const _ReactionLandingEffect({
    required this.center,
    required this.emoji,
    required this.duration,
    required this.onCompleted,
  });

  final Offset center;
  final String emoji;
  final Duration duration;
  final VoidCallback onCompleted;

  @override
  State<_ReactionLandingEffect> createState() => _ReactionLandingEffectState();
}

class _ReactionLandingEffectState extends State<_ReactionLandingEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener(_onStatusChanged);

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.26,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.26,
        end: 0.94,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 34,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.94,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 36,
    ),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onCompleted();
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value;
            return Stack(
              children: [
                Positioned(
                  left: widget.center.dx - 38,
                  top: widget.center.dy - 38,
                  width: 76,
                  height: 76,
                  child: CustomPaint(
                    key: const ValueKey('reaction-landing-splash'),
                    painter: _ReactionSplashPainter(
                      progress: progress,
                      color: accent,
                    ),
                  ),
                ),
                Positioned(
                  left: widget.center.dx - 22,
                  top: widget.center.dy - 22,
                  width: 44,
                  height: 44,
                  child: Transform.scale(
                    key: const ValueKey('reaction-landing-emoji'),
                    scale: _scale.value,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Center(
                        child: Text(
                          widget.emoji,
                          style: const TextStyle(
                            fontSize: 22,
                            shadows: [
                              Shadow(
                                color: Color(0x24000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReactionSplashPainter extends CustomPainter {
  const _ReactionSplashPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final burst = Curves.easeOutCubic.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);

    final ringPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * fade
          ..color = color.withValues(alpha: 0.32 * fade);
    canvas.drawCircle(center, 13 + (19 * burst), ringPaint);

    final particlePaint =
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withValues(alpha: 0.46 * fade);
    for (var index = 0; index < 6; index++) {
      final angle = (math.pi * 2 * index / 6) - (math.pi / 2);
      final radius = 15 + (18 * burst);
      final particleCenter = Offset(
        center.dx + (math.cos(angle) * radius),
        center.dy + (math.sin(angle) * radius),
      );
      canvas.drawCircle(particleCenter, 2.2 * fade, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReactionSplashPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
