import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';

/// A small, row-owned effect: no global overlay, timers, or layout changes.
/// Existing reactions are baselined on mount, so scrolling through history
/// never replays them. Local reactions already have a flight/landing effect.
class LiveMessageMotion extends StatefulWidget {
  const LiveMessageMotion({
    super.key,
    required this.message,
    required this.viewerId,
    required this.animateArrival,
    required this.child,
  });

  final Message message;
  final String? viewerId;
  final bool animateArrival;
  final Widget child;

  @override
  State<LiveMessageMotion> createState() => _LiveMessageMotionState();
}

class _LiveMessageMotionState extends State<LiveMessageMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: 1,
  );
  late Set<String> _partnerReactions;
  bool _arrival = false;
  bool _initialized = false;

  Set<String> _snapshot() => {
    if (widget.viewerId != null)
      for (final entry in widget.message.reactions.entries)
        for (final reactor in entry.value)
          if (reactor != widget.viewerId) '${entry.key}:$reactor',
  };

  @override
  void initState() {
    super.initState();
    _partnerReactions = _snapshot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.value = 1;
    } else if (!_initialized &&
        widget.animateArrival &&
        isAnimatedEmojiMessage(widget.message)) {
      _play(arrival: true);
    }
    _initialized = true;
  }

  void _play({required bool arrival}) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (widget.message.isDeleted ||
        reduceMotionOf(context) ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        !(ModalRoute.of(context)?.isCurrent ?? true))
      return;
    _arrival = arrival;
    _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant LiveMessageMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _snapshot();
    if (oldWidget.message.clientMessageId == widget.message.clientMessageId &&
        oldWidget.viewerId == widget.viewerId &&
        next.difference(_partnerReactions).isNotEmpty) {
      _play(arrival: false);
    }
    _partnerReactions = next;
    if (widget.message.isDeleted) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = _controller.value;
      final beat = math.sin(t * math.pi * 3) * math.pow(1 - t, 2);
      final alignment =
          _arrival
              ? Alignment.center
              : widget.message.isMine
              ? Alignment.topLeft
              : Alignment.topRight;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.scale(
            key: const ValueKey('live-message-pulse'),
            scale: 1 + beat * (_arrival ? 0.12 : 0.045),
            alignment: alignment,
            child: child,
          ),
          if (t < 1)
            Positioned(
              top: 0,
              left: widget.message.isMine ? -12 : null,
              right: widget.message.isMine ? null : -12,
              width: 48,
              height: 48,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    key: const ValueKey('live-message-sparkles'),
                    painter: _LocalSparkles(
                      progress: t,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Deliberately bounded: ordinary text, captions, and unsupported emoji stay
/// still. Grapheme clusters preserve variation selectors and joined emoji.
bool isAnimatedEmojiMessage(Message message) {
  if (message.isDeleted ||
      message.mediaType != null ||
      message.isSystemNotice ||
      message.isAttuneAssistOutput ||
      message.isImported)
    return false;
  const supported = {
    '❤',
    '❤️',
    '💕',
    '💖',
    '💗',
    '💘',
    '💞',
    '😍',
    '🥰',
    '😘',
    '😂',
    '🤣',
    '😊',
    '🥹',
    '🤗',
    '😢',
    '😭',
    '👍',
    '🎉',
    '🎊',
    '🔥',
    '👏',
  };
  final glyphs =
      message.content
          .trim()
          .characters
          .where((glyph) => glyph.trim().isNotEmpty)
          .toList();
  return glyphs.isNotEmpty &&
      glyphs.length <= 3 &&
      glyphs.every(supported.contains);
}

class _LocalSparkles extends CustomPainter {
  const _LocalSparkles({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = math.sin(math.pi * progress);
    final radius = 9 + 14 * Curves.easeOutCubic.transform(progress);
    final paint = Paint()..color = color.withValues(alpha: fade * 0.65);
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3;
      final point =
          size.center(Offset.zero) +
          Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(point, 1.8 * fade, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LocalSparkles oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
