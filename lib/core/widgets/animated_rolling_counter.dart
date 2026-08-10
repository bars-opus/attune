// lib/core/widgets/animated_rolling_counter.dart

import 'package:attune/core/utils/exports/export_screens.dart';

/// A number that animates between values the way YouTube's view count and
/// Threads/X's like count do: each digit column that changes slides
/// vertically (bottom-to-top, like a real odometer wheel) to its new value
/// rather than a plain cross-fade or instant jump. Digits that don't change
/// between old and new value stay put — only the columns that actually
/// differ animate, same as the reference apps.
///
/// Works equally for counting up (reaction/like counts ticking up after a
/// tap) and counting down (a resend-code timer counting to zero) — every
/// roll turns the same way; only which digit ends up resting in view
/// differs.
///
/// [compact] renders large counts abbreviated ("1.2K", "3M" — see
/// formatCompactCount) instead of every digit ("1200"). Only the `0`-`9`
/// characters of the formatted string roll; the decimal point and unit
/// letter render as plain static Text, since sliding a "K" or "." through
/// an odometer motion isn't meaningful and would look broken across a
/// magnitude change (e.g. 999 -> 1K has no shared digit columns at all).
class AnimatedRollingCounter extends StatefulWidget {
  const AnimatedRollingCounter({
    super.key,
    required this.count,
    this.style,
    this.duration = const Duration(milliseconds: 450),
    this.curve = Curves.easeInOutCubic,
    this.prefix = '',
    this.suffix = '',
    this.compact = false,
  });

  final int count;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  /// e.g. '+' before a reaction count, or empty for a plain timer.
  final String prefix;

  /// e.g. 's' after a countdown ("12s").
  final String suffix;

  final bool compact;

  @override
  State<AnimatedRollingCounter> createState() => _AnimatedRollingCounterState();
}

class _AnimatedRollingCounterState extends State<AnimatedRollingCounter> {
  late int _oldCount;

  @override
  void initState() {
    super.initState();
    _oldCount = widget.count;
  }

  @override
  void didUpdateWidget(AnimatedRollingCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _oldCount = oldWidget.count;
    }
  }

  String _render(int count) =>
      widget.compact ? formatCompactCount(count.abs()) : '${count.abs()}';

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final oldChars = _render(_oldCount).split('');
    final newChars = _render(widget.count).split('');

    // Right-align both character lists so a column change (e.g. 9 -> 10, or
    // 999 -> 1.0K) rolls in new leading characters rather than misaligning
    // every existing one.
    final width =
        newChars.length > oldChars.length ? newChars.length : oldChars.length;
    final paddedOld = oldChars.reversed.toList();
    final paddedNew = newChars.reversed.toList();
    bool isDigit(String c) => int.tryParse(c) != null;

    final children = <Widget>[];
    if (widget.prefix.isNotEmpty) {
      children.add(Text(widget.prefix, style: style));
    }
    if (widget.count < 0) {
      children.add(Text('-', style: style));
    }
    for (var i = width - 1; i >= 0; i--) {
      final newChar = i < paddedNew.length ? paddedNew[i] : null;
      final oldChar = i < paddedOld.length ? paddedOld[i] : null;
      if (newChar == null) continue;
      if (!isDigit(newChar)) {
        children.add(Text(newChar, style: style));
        continue;
      }
      children.add(
        _RollingDigit(
          key: ValueKey('digit_$i'),
          oldDigit: (oldChar != null && isDigit(oldChar)) ? oldChar : null,
          newDigit: newChar,
          style: style,
          duration: widget.duration,
          curve: widget.curve,
        ),
      );
    }
    if (widget.suffix.isNotEmpty) {
      children.add(Text(widget.suffix, style: style));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

/// One digit column. Built on a raw AnimationController rather than
/// AnimatedSwitcher — AnimatedSwitcher is designed around cross-fading
/// in/out children and fights being turned into a pure slide, which is what
/// produced a fade-through look instead of a clean scroll. This drives a
/// single 0->1 animation and paints both the outgoing and incoming digit at
/// all times via Transform.translate, so nothing ever changes opacity.
class _RollingDigit extends StatefulWidget {
  const _RollingDigit({
    super.key,
    required this.oldDigit,
    required this.newDigit,
    required this.style,
    required this.duration,
    required this.curve,
  });

  final String? oldDigit;
  final String newDigit;
  final TextStyle style;
  final Duration duration;
  final Curve curve;

  @override
  State<_RollingDigit> createState() => _RollingDigitState();
}

class _RollingDigitState extends State<_RollingDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = CurvedAnimation(parent: _controller, curve: widget.curve);
    if (widget.oldDigit != null && widget.oldDigit != widget.newDigit) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(_RollingDigit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.newDigit != widget.newDigit) {
      _controller.duration = widget.duration;
      _animation = CurvedAnimation(parent: _controller, curve: widget.curve);
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oldDigit = widget.oldDigit;
    // Same fixed-height, centered slot in BOTH branches — settled digits
    // must sit in an identically-sized box to the animating one, or the
    // Stack/SizedBox in the animating branch centers its glyph slightly
    // differently than a bare Text does and every digit that isn't mid-roll
    // reads as vertically offset from the ones that are (or just settled).
    final height = (widget.style.fontSize ?? 24) * 1.2;

    if (oldDigit == null || oldDigit == widget.newDigit) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            widget.newDigit,
            style: widget.style,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Odometer effect: every roll moves bottom-to-top, like a real odometer
    // wheel or YouTube/Threads' count animation — the old digit slides
    // straight up out of view while the new digit slides up from below into
    // the same spot it vacates, both moving together as one continuous
    // strip rather than two separately-faded widgets.
    return ClipRect(
      child: SizedBox(
        height: height,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            final t = _animation.value;
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              children: [
                Transform.translate(
                  offset: Offset(0, -height * t),
                  child: Text(
                    oldDigit,
                    style: widget.style,
                    textAlign: TextAlign.center,
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, height * (1 - t)),
                  child: Text(
                    widget.newDigit,
                    style: widget.style,
                    textAlign: TextAlign.center,
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
