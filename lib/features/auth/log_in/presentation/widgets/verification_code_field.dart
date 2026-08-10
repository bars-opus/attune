import 'package:flutter/services.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

/// Six individual boxes for the OTP, instead of one text field: entering a
/// digit auto-advances focus to the next box, backspace on an empty box
/// steps back to the previous one, and [onCompleted] fires the instant all
/// six are filled — the caller uses that to auto-submit rather than waiting
/// on a manual "Verify" tap.
///
/// [controller] stays the single source of truth. The six per-box
/// controllers exist only to drive TextField's own cursor/selection
/// behavior; every edit is written straight back into [controller] so the
/// parent (LoginScreen._verifyPhoneOtp reads _otpController.text) needs no
/// changes to keep working.
class VerificationCodeField extends StatefulWidget {
  const VerificationCodeField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onCompleted,
    this.length = 6,
  });

  final TextEditingController controller;

  /// Focus requested here lands on the first box — matches how a plain
  /// TextField's focusNode used to work, so LoginCodeStep's phone-number
  /// step can keep calling _otpFocusNode.requestFocus() unchanged.
  final FocusNode focusNode;
  final bool enabled;
  final ValueChanged<String> onCompleted;
  final int length;

  @override
  State<VerificationCodeField> createState() => _VerificationCodeFieldState();
}

class _VerificationCodeFieldState extends State<VerificationCodeField> {
  late final List<TextEditingController> _boxControllers;
  late final List<FocusNode> _boxFocusNodes;

  // Guards against re-firing onCompleted (and so re-triggering verification)
  // on every keystroke once already complete — e.g. editing the 3rd digit
  // after the code was full re-fills all six but should not re-submit twice.
  String? _lastCompletedValue;

  @override
  void initState() {
    super.initState();
    _boxControllers = List.generate(
      widget.length,
      (_) => TextEditingController(),
    );
    _boxFocusNodes = List.generate(widget.length, (_) => FocusNode());
    _syncFromController();
    widget.controller.addListener(_syncFromController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    for (final c in _boxControllers) {
      c.dispose();
    }
    for (final f in _boxFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  /// Mirrors an external change to [widget.controller] (e.g. the parent
  /// clearing it after a failed attempt) into the boxes. Re-entrancy-safe:
  /// _writeBack only calls controller.text = if the value actually changed,
  /// so this listener does not loop against its own writes.
  void _syncFromController() {
    final value = widget.controller.text;
    for (var i = 0; i < widget.length; i++) {
      final char = i < value.length ? value[i] : '';
      if (_boxControllers[i].text != char) {
        _boxControllers[i].text = char;
      }
    }
  }

  void _writeBack() {
    final combined = _boxControllers.map((c) => c.text).join();
    if (widget.controller.text != combined) {
      widget.controller.text = combined;
    }
    if (combined.length == widget.length && _lastCompletedValue != combined) {
      _lastCompletedValue = combined;
      widget.onCompleted(combined);
    } else if (combined.length < widget.length) {
      // Editing a completed code back down to a shorter one re-arms
      // onCompleted for the next time it fills — otherwise correcting a
      // wrong digit and refilling would never auto-submit again.
      _lastCompletedValue = null;
    }
  }

  void _onChanged(int index, String value) {
    // A paste of the full code can land in one box (e.g. long-press > Paste
    // from the keyboard suggestion bar) rather than arriving one digit at a
    // time via SMS autofill — spread it across the remaining boxes instead
    // of only keeping the first character.
    if (value.length > 1) {
      final digits = value.split('');
      for (var i = 0; i < digits.length && index + i < widget.length; i++) {
        _boxControllers[index + i].text = digits[i];
      }
      final nextEmpty = (index + digits.length).clamp(0, widget.length - 1);
      _boxFocusNodes[nextEmpty].requestFocus();
      _writeBack();
      return;
    }

    if (value.isNotEmpty && index < widget.length - 1) {
      _boxFocusNodes[index + 1].requestFocus();
    }
    _writeBack();
  }

  void _onKeyEvent(int index, KeyEvent event) {
    // Backspace on an already-empty box steps back and clears the previous
    // box, matching the standard OTP-field feel (iOS Messages, most banking
    // apps) instead of stopping dead at the first empty box.
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _boxControllers[index].text.isEmpty &&
        index > 0) {
      _boxFocusNodes[index - 1].requestFocus();
      _boxControllers[index - 1].clear();
      _writeBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Focus(
      // The externally-passed focusNode has no visual box of its own to
      // land on — requesting it focuses the first box instead, so callers
      // that do _otpFocusNode.requestFocus() (e.g. after a "code too short"
      // validation error) still land the cursor somewhere useful.
      focusNode: widget.focusNode,
      onFocusChange: (hasFocus) {
        if (hasFocus) _boxFocusNodes[0].requestFocus();
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(widget.length, (index) {
          return SizedBox(
            width: 44.w,
            height: 52.h,
            child: KeyboardListener(
              focusNode: FocusNode(skipTraversal: true),
              onKeyEvent: (event) => _onKeyEvent(index, event),
              child: TextField(
                controller: _boxControllers[index],
                focusNode: _boxFocusNodes[index],
                enabled: widget.enabled,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                // AutofillHints.oneTimeCode on every box (not just the
                // first) so iOS/Android's SMS-code autofill suggestion can
                // target this group regardless of which box has focus when
                // the code arrives.
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: widget.length, // allows a full-code paste to land
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: colorScheme.surface,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.md.r,
                    ),
                    borderSide: BorderSide(color: colorScheme.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.md.r,
                    ),
                    borderSide: BorderSide(color: colorScheme.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.md.r,
                    ),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) => _onChanged(index, value),
              ),
            ),
          );
        }),
      ),
    );
  }
}
