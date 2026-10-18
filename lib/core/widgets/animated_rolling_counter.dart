// lib/core/widgets/animated_rolling_counter.dart

import 'package:attune/core/ui/motion/reduce_motion.dart';
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
///
/// [format] renders the figure some other way (money: "GHS 1,500.00"); as
/// with [compact], only its digits roll. [fromZero] rolls every digit up
/// from 0 when it first shows (a headline amount arriving). [settleAsText]
/// turns the rolled digits back into one plain Text once they stop, so the
/// figure lays out, scales and reads like any other text. With reduce
/// motion the figure is plain text from the start; screen readers always
/// hear the whole figure, never digit by digit.
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
    this.format,
    this.fromZero = false,
    this.settleAsText = false,
    this.textAlign = TextAlign.start,
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
  final String Function(int count)? format;
  final bool fromZero;
  final bool settleAsText;

  /// How a [settleAsText] figure lines up when it wraps (as a Text would).
  final TextAlign textAlign;

  @override
  State<AnimatedRollingCounter> createState() => _AnimatedRollingCounterState();
}

class _AnimatedRollingCounterState extends State<AnimatedRollingCounter>
    with SingleTickerProviderStateMixin {
  late int _oldCount;

  /// Every digit starts from 0: the first show of a [fromZero] figure.
  late bool _fromZero = widget.fromZero && widget.count != 0;

  /// Digits are on screen (rolling, or not yet settled back into text).
  late bool _rolling = _fromZero;

  /// Runs for one roll; when it ends a [settleAsText] figure settles.
  /// Made in initState, never lazily (a first use in dispose would look up
  /// the ticker's ancestors after the tree is gone).
  late final AnimationController _settle;
  late final CurvedAnimation _eased;

  @override
  void initState() {
    super.initState();
    _oldCount = widget.count;
    _settle = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _rolling = false);
        }
      });
    _eased = CurvedAnimation(parent: _settle, curve: widget.curve);
    if (_rolling) _settle.forward();
  }

  @override
  void didUpdateWidget(AnimatedRollingCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _oldCount = oldWidget.count;
      _fromZero = false;
      _rolling = true;
      _settle
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    _settle.dispose();
    super.dispose();
  }

  String _render(int count) =>
      widget.format?.call(count) ??
      (widget.compact ? formatCompactCount(count.abs()) : '${count.abs()}');

  /// The whole figure as it reads.
  String get _whole =>
      '${widget.prefix}${widget.format == null && widget.count < 0 ? '-' : ''}'
      '${_render(widget.count)}${widget.suffix}';

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    if (reduceMotionOf(context) || (widget.settleAsText && !_rolling)) {
      return Text(_whole, style: style, textAlign: widget.textAlign);
    }
    if (widget.settleAsText) {
      return Semantics(
        label: _whole,
        excludeSemantics: true,
        child: _overlaid(context, style),
      );
    }
    return Semantics(
      label: _whole,
      excludeSemantics: true,
      child: _digits(style),
    );
  }

  /// A [settleAsText] figure mid-roll: the settled text itself, laid out
  /// exactly as it will rest (so nothing moves when the roll ends), with
  /// each changing digit hidden and rolled over its own spot.
  Widget _overlaid(BuildContext context, TextStyle style) {
    bool isDigit(String c) => int.tryParse(c) != null;
    final whole = _whole;
    final body = _render(widget.count);
    final oldBody = _render(_oldCount);
    final bodyStart = whole.length - widget.suffix.length - body.length;
    // Position in [whole] -> the digit it rolls from. Columns line up from
    // the right, as in the digit row; a new column just appears.
    final rolls = <int, String>{};
    for (var k = 0; k < body.length; k++) {
      final c = body[k];
      if (!isDigit(c)) continue;
      final o = oldBody.length - (body.length - k);
      final from =
          _fromZero ? '0' : (o >= 0 && isDigit(oldBody[o]) ? oldBody[o] : null);
      if (from != null && from != c) rolls[bodyStart + k] = from;
    }
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final span = TextSpan(
      style: effective,
      children: [
        for (var i = 0; i < whole.length; i++)
          TextSpan(
            text: whole[i],
            style:
                rolls.containsKey(i)
                    ? const TextStyle(color: Color(0x00000000))
                    : null,
          ),
      ],
    );
    final scaler = MediaQuery.textScalerOf(context);
    return CustomPaint(
      key: const ValueKey('animated-rolling-counter-rolling'),
      foregroundPainter: _RollingDigitsPainter(
        span: span,
        whole: whole,
        rolls: rolls,
        style: effective,
        textAlign: widget.textAlign,
        textDirection: Directionality.of(context),
        textScaler: scaler,
        t: _eased,
      ),
      child: Text.rich(span, textAlign: widget.textAlign, textScaler: scaler),
    );
  }

  Widget _digits(TextStyle style) {
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
    if (widget.format == null && widget.count < 0) {
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
          // Arriving from zero, every digit rolls up from 0.
          oldDigit:
              _fromZero
                  ? '0'
                  : (oldChar != null && isDigit(oldChar)) ? oldChar : null,
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

/// Paints each rolling digit of a [AnimatedRollingCounter.settleAsText]
/// figure over its hidden place in the text below: the old digit sliding up
/// out of view, the new one up into it, clipped to that character.
class _RollingDigitsPainter extends CustomPainter {
  _RollingDigitsPainter({
    required this.span,
    required this.whole,
    required this.rolls,
    required this.style,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.t,
  }) : super(repaint: t);

  final TextSpan span;
  final String whole;
  final Map<int, String> rolls;
  final TextStyle style;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    // The same text at the width it was laid out at: the same lines and
    // the same place for every character.
    final layout = TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(minWidth: size.width, maxWidth: size.width);
    final v = t.value;
    for (final MapEntry(key: i, value: from) in rolls.entries) {
      final boxes = layout.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      if (boxes.isEmpty) continue;
      final box = boxes.first.toRect();
      canvas.save();
      canvas.clipRect(box);
      for (final (d, dy) in [(from, -box.height * v), (whole[i], box.height * (1 - v))]) {
        final glyph = TextPainter(
          text: TextSpan(text: d, style: style),
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout();
        glyph.paint(canvas, Offset(box.left, box.top + dy));
        glyph.dispose();
      }
      canvas.restore();
    }
    layout.dispose();
  }

  @override
  bool shouldRepaint(_RollingDigitsPainter old) =>
      old.whole != whole || old.rolls != rolls || old.style != style;
}
