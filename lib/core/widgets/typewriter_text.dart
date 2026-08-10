// lib/core/widgets/typewriter_text.dart

import 'package:flutter/material.dart';

/// Reveals [text] one character at a time, like it's being typed —
/// restarts from empty whenever [text] itself changes (a fresh key/value),
/// which is what makes re-expanding a collapsed FAQ answer replay the
/// effect instead of only playing once ever.
class TypewriterText extends StatefulWidget {
  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 30),
  });

  final String text;
  final TextStyle? style;

  /// Time per character, not total duration — a long answer takes
  /// proportionally longer to type out rather than always finishing in the
  /// same fixed time regardless of length.
  final Duration duration;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _charCount;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration * widget.text.length,
    );
    _charCount = StepTween(
      begin: 0,
      end: widget.text.length,
    ).animate(_controller);
    _controller.forward();
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.duration = widget.duration * widget.text.length;
      _charCount = StepTween(
        begin: 0,
        end: widget.text.length,
      ).animate(_controller);
      _controller
        ..reset()
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
    return AnimatedBuilder(
      animation: _charCount,
      builder: (context, _) {
        return Text(widget.text.substring(0, _charCount.value), style: widget.style);
      },
    );
  }
}
