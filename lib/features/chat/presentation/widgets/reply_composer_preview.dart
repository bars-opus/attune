import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:flutter/material.dart';

/// Opens a selected reply target upward from the composer's edge.
///
/// The surface arrives first, followed by its accent rail and copy, so the
/// motion explains that the message has been attached to the next send rather
/// than making the whole preview shake into place.
class ReplyComposerPreview extends StatefulWidget {
  const ReplyComposerPreview({
    super.key,
    required this.quotedText,
    required this.onClose,
  });

  final String quotedText;
  final VoidCallback onClose;

  @override
  State<ReplyComposerPreview> createState() => _ReplyComposerPreviewState();
}

class _ReplyComposerPreviewState extends State<ReplyComposerPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kMakeRoomDuration,
  );

  late final Animation<double> _room = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.82, curve: kMakeRoomCurve),
  );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.38, curve: Curves.easeOut),
  );

  late final Animation<double> _settle = Tween<double>(
    begin: 0.97,
    end: 1,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.08, 1, curve: kSettleCurve),
    ),
  );

  late final Animation<Offset> _contentOffset = Tween<Offset>(
    begin: const Offset(0, 0.18),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.86, curve: Curves.easeOutCubic),
    ),
  );

  late final Animation<double> _contentOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.18, 0.72, curve: Curves.easeOut),
  );

  late final Animation<double> _rail = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.06, 0.62, curve: Curves.easeOutCubic),
  );

  bool _started = false;
  bool _closing = false;

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

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;

    if (reduceMotionOf(context)) {
      widget.onClose();
      return;
    }

    await _controller.reverse();
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder:
              (context, child) => Align(
                alignment: Alignment.bottomCenter,
                heightFactor: _room.value.clamp(0.0, 1.0),
                child: FadeTransition(
                  opacity: _opacity,
                  child: ScaleTransition(
                    key: const ValueKey('reply-preview-surface-motion'),
                    alignment: Alignment.bottomCenter,
                    scale: _settle,
                    child: child,
                  ),
                ),
              ),
          child: CardInkWell(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            margin: EdgeInsets.zero,
            enableFeedback: false,
            child: Row(
              children: [
                SizedBox(
                  width: 3,
                  height: 38,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedBuilder(
                      animation: _rail,
                      builder:
                          (context, child) => FractionallySizedBox(
                            key: const ValueKey('reply-preview-accent-rail'),
                            heightFactor: _rail.value.clamp(0.0, 1.0),
                            child: child,
                          ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FadeTransition(
                    key: const ValueKey('reply-preview-content-opacity'),
                    opacity: _contentOpacity,
                    child: SlideTransition(
                      position: _contentOffset,
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Replying to',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '\n${widget.quotedText}',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel reply',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _close,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
