import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// A labelled text field for the sign-in screens (Spec 1 §2.3).
///
/// The visible [label] sits in the field's own decoration, so a screen
/// reader reads [semanticsLabel] (or the label) as the field's name; the
/// field grows with large text instead of clipping; the label reads at
/// 4.5:1 or more in every state; and [errorText] is announced each time it
/// appears or [errorCount] goes up (one failed submit each), never shown by
/// colour alone.
class FlowTextField extends StatefulWidget {
  const FlowTextField({
    super.key,
    required this.controller,
    required this.label,
    this.semanticsLabel,
    this.errorText,
    this.errorCount = 0,
    this.hintText,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.inputFormatters,
    this.autofillHints,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
    this.labelAbove = false,
  });

  final TextEditingController controller;
  final String label;
  final String? semanticsLabel;
  final String? errorText;

  /// Raised by the screen on each failed submit, so the same message is
  /// read out again.
  final int errorCount;
  final String? hintText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  /// Spec 1 W4b: the label as a line of text above the field, for a label
  /// too long to sit inside the border at large text sizes (it wraps there
  /// instead of overlapping the border); still read as the field's name.
  final bool labelAbove;

  @override
  State<FlowTextField> createState() => _FlowTextFieldState();
}

class _FlowTextFieldState extends State<FlowTextField> {
  /// With [FlowTextField.labelAbove] and no node from the screen: the node
  /// the label above focuses (batch-4 review #3). The default field keeps
  /// its own, as before.
  FocusNode? _ownFocus;

  FocusNode? get _focusNode =>
      widget.focusNode ??
      (widget.labelAbove ? _ownFocus ??= FocusNode() : null);

  @override
  void dispose() {
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FlowTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final error = widget.errorText;
    if (error != null &&
        (error != oldWidget.errorText ||
            widget.errorCount != oldWidget.errorCount)) {
      SemanticsService.announce(error, Directionality.of(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = flowAccent(context);
    // Material's own label colours are the theme's primary when focused and
    // its error red, both under 4.5:1 on white (P-7). The error state is
    // told by the icon and the message, so its label stays on-surface.
    final labelStyle = WidgetStateTextStyle.resolveWith(
      (states) => TextStyle(
        color:
            states.contains(WidgetState.error)
                ? colorScheme.onSurface
                : states.contains(WidgetState.focused)
                ? accent
                : colorScheme.onSurfaceVariant,
      ),
    );
    final field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        label:
            widget.labelAbove
                ? null
                : Semantics(
                  label: widget.semanticsLabel ?? widget.label,
                  child: ExcludeSemantics(child: Text(widget.label)),
                ),
        labelStyle: labelStyle,
        floatingLabelStyle: labelStyle,
        hintText: widget.hintText,
        // The message in body text with an icon, so it reads at full
        // contrast and never by colour alone (§2.3).
        error:
            widget.errorText == null
                ? null
                : FlowErrorLine(text: widget.errorText!),
        // The theme's 12 dp corners in every state.
        border: const OutlineInputBorder(
          borderRadius: BorderRadiusTokens.mdAll,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadiusTokens.mdAll,
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
    );
    if (!widget.labelAbove) return field;
    // One node: the label above is the text field's name.
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: widget.semanticsLabel ?? widget.label,
            child: ExcludeSemantics(
              // Tapping the label focuses the field, as the label inside
              // the border does (the field's own node already has the tap).
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () => _focusNode?.requestFocus(),
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          field,
        ],
      ),
    );
  }
}

/// An error message on a sign-in screen (Spec 1 §2.3): an error icon, then
/// the message in body text at full contrast, so it never relies on colour
/// alone. [style] defaults to body small in `onSurface`, as under a
/// [FlowTextField]. With [liveRegion], a screen reader reads the message out
/// when it appears.
class FlowErrorLine extends StatelessWidget {
  const FlowErrorLine({
    super.key,
    required this.text,
    this.style,
    this.liveRegion = false,
  });

  final String text;
  final TextStyle? style;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = Text(
      text,
      style:
          style ??
          theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 4),
        Flexible(
          child:
              liveRegion
                  ? Semantics(liveRegion: true, child: message)
                  : message,
        ),
      ],
    );
  }
}
