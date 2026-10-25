import 'dart:math' as math;

import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A4's code field (Spec 1 §3.3): ONE text field, drawn as six boxes, so
/// the system's one-time-code autofill (AutofillHints.oneTimeCode, and the
/// Android SMS listener in W2c) fills it in one go. Digits only, at most six;
/// [onCompleted] fires once per complete code. An error about the code
/// turns the boxes red and is read out; only a wrong code ([shakeCount])
/// also shakes them, twice, when motion is allowed. An accepted code shows a
/// check that fades in over 150 ms.
class OneTimeCodeField extends StatefulWidget {
  const OneTimeCodeField({
    super.key,
    required this.controller,
    required this.semanticsLabel,
    required this.onCompleted,
    this.focusNode,
    this.enabled = true,
    this.errorText,
    this.errorCount = 0,
    this.shakeCount = 0,
    this.accepted = false,
    this.autofocus = true,
  });

  static const length = 6;

  final TextEditingController controller;

  /// "Verification code, 6 digits".
  final String semanticsLabel;
  final ValueChanged<String> onCompleted;
  final FocusNode? focusNode;
  final bool enabled;

  /// What is wrong with the code ("didn't work", "expired"): shown under
  /// the boxes, which turn red, and read out when it appears or changes.
  final String? errorText;

  /// Raise on each failed check, so the same message is read out again.
  final int errorCount;

  /// Raise for a wrong code only (§3.3 A4): the boxes shake. Nothing else
  /// shakes them (review B4 I-2).
  final int shakeCount;
  final bool accepted;
  final bool autofocus;

  @override
  State<OneTimeCodeField> createState() => _OneTimeCodeFieldState();
}

class _OneTimeCodeFieldState extends State<OneTimeCodeField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  String? _lastCompleted;
  FocusNode? _ownFocus;

  /// Focused when checking a code (or sending one) disabled the field: the
  /// focus, and so the keyboard, comes back with it for the next try.
  bool _refocus = false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant OneTimeCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    final error = widget.errorText;
    if (error != null &&
        (error != oldWidget.errorText ||
            widget.errorCount != oldWidget.errorCount)) {
      SemanticsService.announce(error, Directionality.of(context));
      _lastCompleted = null;
    }
    if (widget.shakeCount != oldWidget.shakeCount && !reduceMotionOf(context)) {
      _shake.forward(from: 0);
    }
    if (oldWidget.enabled && !widget.enabled) {
      _refocus = _focus.hasFocus;
    } else if (!oldWidget.enabled && widget.enabled && _refocus) {
      _refocus = false;
      // After the frame: the field takes focus only once it is enabled.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.enabled) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _shake.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _changed() {
    final code = widget.controller.text;
    setState(() {});
    if (code.length == OneTimeCodeField.length && code != _lastCompleted) {
      _lastCompleted = code;
      widget.onCompleted(code);
    } else if (code.length < OneTimeCodeField.length) {
      _lastCompleted = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final code = widget.controller.text;
    final hasError = widget.errorText != null;
    final boxHeight =
        52 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);

    Widget box(int index) {
      final filled = index < code.length;
      final active = index == code.length && widget.enabled;
      final color =
          hasError
              ? colorScheme.error
              : active
              ? flowAccent(context)
              : colorScheme.outline;
      return Expanded(
        child: Container(
          height: boxHeight,
          margin: const EdgeInsetsDirectional.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: active || hasError ? 2 : 1),
          ),
          child: Text(
            filled ? code[index] : '',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = math.sin(t * math.pi * 4) * 8 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Stack(
            children: [
              ExcludeSemantics(
                child: Directionality(
                  // Digits read left to right in every language.
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      for (var i = 0; i < OneTimeCodeField.length; i++) box(i),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Semantics(
                  label: widget.semanticsLabel,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(OneTimeCodeField.length),
                    ],
                    showCursor: false,
                    enableInteractiveSelection: false,
                    style: const TextStyle(color: Colors.transparent),
                    // The boxes behind are the field's look: the theme's
                    // borders and fill must not draw over them.
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      isCollapsed: true,
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AnimatedOpacity(
          opacity: widget.accepted ? 1 : 0,
          duration: kSelectionDuration,
          child: Icon(Icons.check_circle, color: flowAccent(context), size: 32),
        ),
        if (hasError)
          FlowErrorLine(
            text: widget.errorText!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
      ],
    );
  }
}
