// lib/core/widgets/app_text_form_field.dart
import 'dart:async';
import 'package:debounce_throttle/debounce_throttle.dart';
import 'package:flutter/services.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

/// A comprehensive, production-ready text input field component with extensive customization.
///
/// This widget provides a fully-featured text form field that integrates with Flutter's
/// Form validation system, supports Material Design guidelines, and includes advanced
/// features like autofill, input formatting, and responsive sizing.
///
/// ## Key Features
/// - **Complete Flutter Form integration**: Full validator support with error states
/// - **Material Design compliance**: Proper focus states, borders, and visual feedback
/// - **Advanced input handling**: Input formatters, autofill hints, and keyboard controls
/// - **Responsive design**: Uses `ScreenUtil` for consistent sizing across devices
/// - **Accessibility**: Proper labels, hints, and focus management
/// - **Theme integration**: Adapts to light/dark themes with appropriate colors
///
/// ## Visual States
/// | State | Border Color | Border Width | Background |
/// |-------|-------------|--------------|------------|
/// | **Normal** | Outline with 30% opacity | 1.0 | Surface color |
/// | **Focused** | Primary color | 2.0 | Surface color |
/// | **Error** | Red | 2.0 | Surface color |
/// | **Disabled** | Outline with 10% opacity | 1.0 | Surface color |
///
/// ## Usage Examples
/// ```dart
/// // Basic email input
/// AppTextFormField(
///   label: 'Email',
///   hintText: 'Enter your email',
///   prefixIcon: Icons.email,
///   keyboardType: TextInputType.emailAddress,
///   validator: (value) {
///     if (value == null || value.isEmpty) return 'Email is required';
///     if (!EmailValidator.validate(value)) return 'Invalid email';
///     return null;
///   },
/// )
///
/// // Password field with visibility toggle
/// AppTextFormField(
///   label: 'Password',
///   obscureText: !_passwordVisible,
///   suffixIcon: IconButton(
///     icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off),
///     onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
///   ),
///   validator: ValidationUtils.validatePassword,
/// )
///
/// // Search field with custom styling
/// AppTextFormField(
///   label: 'Search',
///   prefixIcon: Icons.search,
///   isSmall: true,
///   showBorder: false,
///   fillColor: Colors.grey[100],
///   borderRadius: BorderRadius.circular(30),
/// )
/// ```
class AppTextFormField extends StatefulWidget {
  /// Controls the text being edited in the field.
  ///
  /// If not provided, the field creates its own internal controller.
  /// For form integration, provide a controller to manage state externally.
  final TextEditingController? controller;

  /// Descriptive label displayed above the input field.
  ///
  /// Required for accessibility and user understanding. Should clearly describe
  /// what information should be entered (e.g., "Email", "Password", "Search").
  final String label;

  /// Overrides the label's font size, which otherwise defaults to
  /// `isSmall ? 12.safeSp : 14.safeSp`. Null (the default) keeps that
  /// default. Lets a caller using [label] to carry real content — e.g. a
  /// full prompt/question rather than a short field name like "Email" —
  /// size it up to read as a heading instead of a compact form label.
  final double? labelFontSize;

  /// Example text displayed inside the field when it's empty.
  ///
  /// Provides additional guidance or formatting examples (e.g., "name@example.com").
  /// Displayed in a lighter color to distinguish from user-entered text.
  final String? hintText;

  /// Icon displayed at the start of the input field.
  ///
  /// Typically used to indicate the type of input expected (e.g., mail icon for email).
  /// Size adapts based on `isSmall` parameter for consistent visual hierarchy.
  final IconData? prefixIcon;

  /// Widget displayed at the end of the input field.
  ///
  /// Commonly used for action buttons like password visibility toggles, clear buttons,
  /// or validation indicators. Provides full customization for trailing controls.
  final Widget? suffixIcon;

  /// Type of keyboard to display for this field.
  ///
  /// Defaults to `TextInputType.text`. Use specialized types like `emailAddress`,
  /// `phone`, `number`, or `multiline` for appropriate keyboard layouts.
  final TextInputType keyboardType;

  /// Action button on the software keyboard.
  ///
  /// Defaults to `TextInputAction.next` for form navigation. Use `done` or `go`
  /// for final actions, or `search` for search fields.
  final TextInputAction textInputAction;

  /// Whether the text should be obscured (for passwords, sensitive data).
  ///
  /// When `true`, replaces characters with dots (•). Typically used with a
  /// `suffixIcon` toggle to allow users to show/hide the text.
  final bool obscureText;

  /// Whether to enable automatic text correction.
  ///
  /// Defaults to `true`. Set to `false` for fields where autocorrect is undesirable
  /// (e.g., email addresses, usernames, codes).
  final bool autocorrect;

  /// Whether to show text input suggestions.
  ///
  /// Defaults to `true`. Set to `false` for sensitive fields where suggestions
  /// might reveal private information.
  final bool enableSuggestions;

  /// Maximum number of lines for the text to span.
  ///
  /// Defaults to `1` for single-line fields. Set to `null` or higher values
  /// for multi-line text areas. When `maxLines` is 1, height is controlled
  /// responsively; otherwise height expands to content.
  final int? maxLines;

  /// Minimum number of lines for the text to span.
  ///
  /// Only relevant when `maxLines > 1`. Controls the initial height of multi-line
  /// fields before text is entered.
  final int? minLines;

  /// Maximum number of characters allowed in the field.
  ///
  /// When set, displays a character counter below the field. Use for fields
  /// with specific length requirements (e.g., passwords, codes, tweets).
  final int? maxLength;

  /// Validation function called when the form is submitted or field loses focus.
  ///
  /// Returns an error message string if the input is invalid, or `null` if valid.
  /// Integrates with Flutter's `Form` widget for comprehensive form validation.
  final String? Function(String?)? validator;

  /// Called when the text changes in the field.
  ///
  /// Useful for real-time validation, search-as-you-type, or state updates.
  /// Receives the current text value after each change.
  final void Function(String)? onChanged;

  /// Called when the user submits the field (presses "done", "next", etc.).
  ///
  /// Typically used to move focus to the next field or trigger form submission.
  /// Receives the final text value.
  final void Function(String)? onFieldSubmitted;

  /// Called when the field is tapped.
  ///
  /// Use for custom tap behavior beyond focusing the field (e.g., showing a date picker).
  final void Function()? onTap;

  /// Whether the field is read-only (can be focused but not edited).
  ///
  /// When `true`, text cannot be modified but can be selected/copied.
  /// Useful for displaying pre-filled information that shouldn't be changed.
  final bool readOnly;

  /// Whether the field is interactive.
  ///
  /// When `false`, the field appears visually disabled and ignores all interactions.
  /// Use for conditional field availability in forms.
  final bool enabled;

  /// List of input formatters to validate or format input as it's typed.
  ///
  /// Use for enforcing patterns like phone numbers, currency, or custom masks.
  /// Example: `[FilteringTextInputFormatter.digitsOnly]` for numeric-only fields.
  final List<TextInputFormatter>? inputFormatters;

  /// Hints for the autofill system about what type of information is expected.
  ///
  /// Helps browsers and password managers autofill the field correctly.
  /// Example: `[AutofillHints.email]` for email fields.
  final Iterable<String>? autofillHints;

  /// Optional focus node to control focus behavior programmatically.
  ///
  /// Use for advanced focus management, like moving focus between fields
  /// or listening to focus changes.
  final FocusNode? focusNode;

  /// Padding inside the input field, around the text content.
  ///
  /// Defaults to medium horizontal spacing with small vertical spacing.
  /// Adjust for different visual densities or to accommodate custom icons.
  final EdgeInsetsGeometry? contentPadding;

  /// Background color of the input field.
  ///
  /// Defaults to theme's surface color with opacity adjustments for dark mode.
  /// Use to match surrounding UI or create visual emphasis.
  final Color? fillColor;

  /// Whether to display a border around the field.
  ///
  /// Defaults to `true`. Set to `false` for minimal, borderless designs.
  /// Even when false, the field still shows focus/error states appropriately.
  final bool showBorder;

  /// Whether to use compact styling for tighter layouts.
  ///
  /// When `true`:
  /// - Smaller label font
  /// - Uses [FormTokens.compactFieldHeight] for single-line fields
  /// - Smaller prefix icons
  /// Useful for dense interfaces like tables or search bars.
  final bool isSmall;

  /// Border radius for the input field.
  ///
  /// Defaults to `20.r` (20 responsive pixels) for pill-shaped fields.
  /// Use `BorderRadius.circular()` for custom rounding, or set to 0 for square fields.
  final BorderRadius? borderRadius;

  /// Overrides the focused-state border color, which otherwise defaults to
  /// colorScheme.primary. Null (the default) keeps that default. Lets a
  /// caller with its own notion of "which color represents this field right
  /// now" (e.g. DebateRoomScreen's composer, tinted by FOR/AGAINST) carry
  /// that into the border too, instead of it staying primary regardless.
  /// Ignored when [showBorder] is false or the field isn't focused.
  final Color? focusedBorderColor;

  /// Explicit height override for the field container.
  ///
  /// When not provided, height is calculated responsively:
  /// - [FormTokens.compactFieldHeight] for small single-line fields
  /// - [FormTokens.defaultFieldHeight] for regular single-line fields
  /// - `null` (auto) for multi-line fields
  final double? height;
  final String? errorText;

  /// Debounce duration for onChanged events
  /// Default is 500ms - set to null to disable debouncing
  final Duration? debounceDuration;

  /// Callback that receives debounced value
  final ValueChanged<String>? onDebouncedChanged;

  /// Whether this field should request focus (and open the keyboard) as soon
  /// as it is built. Use for the single input on a screen where typing is the
  /// obvious next action (e.g. "what should we call you?").
  final bool autofocus;

  /// Creates a comprehensive text form field with extensive customization.
  ///
  /// [label] is required. All other parameters have sensible defaults following
  /// Material Design guidelines and accessibility best practices.
  const AppTextFormField({
    super.key,
    this.controller,
    required this.label,
    this.labelFontSize,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.onTap,
    this.readOnly = false,
    this.enabled = true,
    this.inputFormatters,
    this.autofillHints,
    this.focusNode,
    this.contentPadding,
    this.fillColor,
    this.showBorder = true,
    this.borderRadius,
    this.focusedBorderColor,
    this.height,
    this.isSmall = false,
    this.errorText,
    this.onDebouncedChanged,
    this.debounceDuration = const Duration(milliseconds: 500),
    this.autofocus = false,
  });

  @override
  State<AppTextFormField> createState() => _AppTextFormFieldState();
}

/// ScreenUtil's `.sp`/`.h`/`.w` extensions throw a LateInitializationError
/// when ScreenUtil hasn't been initialised. That's fine for screens built
/// under ScreenUtilInit, but this widget is shared — it gets rendered by
/// widget tests and by callers that never set ScreenUtil up (chat's
/// composer is one). Falling back to the unscaled value keeps the field
/// rendering instead of taking the whole subtree down.
extension _SafeScale on num {
  double get safeSp {
    try {
      return sp;
    } catch (_) {
      return toDouble();
    }
  }

  double get safeH {
    try {
      return h;
    } catch (_) {
      return toDouble();
    }
  }

  double get safeW {
    try {
      return w;
    } catch (_) {
      return toDouble();
    }
  }

  double get safeR {
    try {
      return r;
    } catch (_) {
      return toDouble();
    }
  }
}

class _AppTextFormFieldState extends State<AppTextFormField> {
  late TextEditingController _controller;
  bool _ownsController = false;

  // Internal node created only when no external focusNode is provided.
  FocusNode? _ownedFocusNode;
  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  Debouncer<String>? _debouncer;
  StreamSubscription<String>? _debouncerSub;
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();

    if (widget.debounceDuration != null && widget.onDebouncedChanged != null) {
      _debouncer = Debouncer<String>(
        widget.debounceDuration!,
        initialValue: _controller.text,
      );
      _debouncerSub = _debouncer!.values.listen((value) {
        if (mounted) widget.onDebouncedChanged?.call(value);
        _hasChanged = false;
      });
    }

    _effectiveFocusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(AppTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      if (_ownsController) _controller.dispose();
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? TextEditingController();
      _hasChanged = false;
    }

    // Re-wire the focus listener if the effective node changed.
    final oldNode = oldWidget.focusNode ?? _ownedFocusNode;
    final newNode = _effectiveFocusNode;
    if (oldNode != newNode) {
      oldNode?.removeListener(_onFocusChange);
      newNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_onFocusChange);
    _ownedFocusNode?.dispose();
    _debouncerSub?.cancel();
    _debouncer?.cancel();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_effectiveFocusNode.hasFocus &&
        _hasChanged &&
        widget.onDebouncedChanged != null) {
      widget.onDebouncedChanged!(_controller.text);
      _hasChanged = false;
    }
  }

  void _handleChanged(String value) {
    _hasChanged = true;
    widget.onChanged?.call(value);
    _debouncer?.value = value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final errorText =
        widget.errorText?.isNotEmpty == true ? widget.errorText : null;

    return Padding(
      // Same rule as the label row below: nothing to space away from when
      // there's no label, so no top padding either.
      padding: EdgeInsets.only(
        top: widget.label.isNotEmpty ? Spacing.sm.safeH : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // An empty label is a real call pattern (borderless/minimal
          // fields like ChatTextField) — skip reserving a blank Text row
          // and its Gap for those, rather than showing invisible spacing.
          if (widget.label.isNotEmpty) ...[
            Text(
              widget.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
                fontSize:
                    widget.labelFontSize ??
                    (widget.isSmall ? 12.safeSp : 14.safeSp),
              ),
            ),
            Gap(Spacing.xs.safeH),
          ],

          _buildField(theme, colorScheme, isDark, errorText),
        ],
      ),
    );
  }

  // Always wrapped in a SizedBox, even when _calculateHeight() returns null
  // (multi-line). A bare multi-line TextFormField exposes its own internal
  // Scrollable to the widget tree, which breaks any test or caller relying
  // on there being a single scrollable on the screen — the SizedBox keeps
  // that contained. Multi-line height is still content-driven, because a
  // null height imposes no constraint.
  Widget _buildField(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
    String? errorText,
  ) {
    final field = TextFormField(
      controller: _controller,
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: widget.obscureText,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      validator: widget.validator,
      onChanged: _handleChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      onTap: widget.onTap,
      readOnly: widget.readOnly,
      enabled: widget.enabled,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
        fontSize: 14.safeSp,
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        alignLabelWithHint: true,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.4),
          fontSize: 12.safeSp,
        ),
        prefixIcon:
            widget.prefixIcon != null
                ? Icon(
                  widget.prefixIcon,
                  size: IconSizes.sm.safeH + 5,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                )
                : null,
        suffixIcon: widget.suffixIcon,
        filled: true,
        fillColor:
            widget.fillColor ??
            (isDark
                ? colorScheme.surface.withValues(
                  alpha: FormTokens.darkFieldFillOpacity,
                )
                : colorScheme.surface),
        contentPadding:
            widget.contentPadding ??
            EdgeInsets.symmetric(
              horizontal: Spacing.md.safeW,
              vertical: Spacing.sm.safeH,
            ),
        border: _buildBorder(colorScheme),
        errorText: errorText,
        enabledBorder: _buildBorder(colorScheme),
        focusedBorder: _buildBorder(colorScheme, isFocused: true),
        errorBorder: _buildBorder(colorScheme, isError: errorText != null),
        focusedErrorBorder: _buildBorder(
          colorScheme,
          isError: errorText != null,
          isFocused: true,
        ),
        disabledBorder: _buildBorder(colorScheme, isDisabled: true),
        errorStyle:
            errorText == null
                ? null
                : theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                  fontSize: 12.safeSp,
                ),
        errorMaxLines: 2,
        isDense: true,
        counterStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 12.safeSp),
      ),
    );

    return SizedBox(height: _calculateHeight(), child: field);
  }

  double? _calculateHeight() {
    if (widget.height != null) return widget.height;
    if (widget.errorText?.isNotEmpty == true) return null;
    if (widget.maxLines == 1) {
      return widget.isSmall
          ? FormTokens.compactFieldHeight.safeH
          : FormTokens.defaultFieldHeight.safeH;
    }
    return null;
  }

  InputBorder _buildBorder(
    ColorScheme colorScheme, {
    bool isFocused = false,
    bool isError = false,
    bool isDisabled = false,
  }) {
    if (!widget.showBorder) return InputBorder.none;

    final borderColor =
        isError
            ? colorScheme.error
            : isFocused
            ? (widget.focusedBorderColor ?? colorScheme.primary)
            : colorScheme.outline.withValues(
              alpha: FormTokens.fieldBorderOpacity,
            );

    final borderWidth =
        isFocused
            ? FormTokens.focusedFieldBorderWidth
            : FormTokens.defaultFieldBorderWidth;

    return OutlineInputBorder(
      borderRadius: widget.borderRadius ?? BorderRadius.circular(20.safeR),
      borderSide: BorderSide(
        color:
            isDisabled
                ? colorScheme.outline.withValues(
                  alpha: FormTokens.disabledFieldBorderOpacity,
                )
                : borderColor,
        width: borderWidth,
      ),
    );
  }
}
