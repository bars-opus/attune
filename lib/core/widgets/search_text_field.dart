// lib/core/widgets/search_form_field.dart
import 'package:attune/core/utils/exports/export_screens.dart';

/// Universal search field with FormField benefits (validation, form integration)
class SearchFormField extends FormField<String> {
  SearchFormField({
    super.key,
    TextEditingController? controller,
    String hintText = 'Search...',
    bool autofocus = false,
    bool showClearButton = true,
    bool showSearchIcon = true,
    bool isLoading = false,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: Spacing.md,
      vertical: Spacing.smMd,
    ),
    double borderRadius = BorderRadiusTokens.full,
    Color? backgroundColor,
    Color? iconColor,
    Color? textColor,
    Color? hintColor,
    TextStyle? textStyle,
    TextStyle? hintStyle,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onFieldSubmitted,
    VoidCallback? onCancelPressed,
    VoidCallback? onClearPressed,
    FocusNode? focusNode,
    List<String>? autofillHints,
    TextInputAction textInputAction = TextInputAction.search,
    int? maxLines = 1,
    // Localise via callsite: pass AppLocalizations.of(context).cancel
    String cancelLabel = 'Cancel',

    // FORM FIELD SPECIFIC PARAMETERS
    super.onSaved,
    super.validator,
    String? initialValue,
    super.enabled,
    super.autovalidateMode,
    InputDecoration? decoration,
  }) : super(
         initialValue: controller?.text ?? initialValue ?? '',
         builder: (FormFieldState<String> field) {
           // Do NOT create a TextEditingController here — builder runs on every
           // rebuild and would leak a new controller each time. Controller
           // lifecycle is managed entirely inside _SearchFormFieldContentState.
           return _SearchFormFieldContent(
             externalController: controller,
             initialValue: field.value ?? '',
             onFormFieldChanged: field.didChange,
             hintText: hintText,
             autofocus: autofocus,
             showClearButton: showClearButton,
             showSearchIcon: showSearchIcon,
             isLoading: isLoading,
             padding: padding,
             borderRadius: borderRadius,
             backgroundColor: backgroundColor,
             iconColor: iconColor,
             textColor: textColor,
             hintColor: hintColor,
             textStyle: textStyle,
             hintStyle: hintStyle,
             onChanged: onChanged,
             onSubmitted: onFieldSubmitted,
             onCancelPressed: onCancelPressed,
             onClearPressed: onClearPressed,
             focusNode: focusNode,
             autofillHints: autofillHints,
             textInputAction: textInputAction,
             maxLines: maxLines,
             hasError: field.hasError,
             errorText: field.errorText,
             decoration: decoration,
             cancelLabel: cancelLabel,
           );
         },
       );
}

class _SearchFormFieldContent extends StatefulWidget {
  final TextEditingController? externalController;
  final String initialValue;
  final ValueChanged<String>? onFormFieldChanged;
  final String hintText;
  final bool autofocus;
  final bool showClearButton;
  final bool showSearchIcon;
  final bool isLoading;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? textColor;
  final Color? hintColor;
  final TextStyle? textStyle;
  final TextStyle? hintStyle;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCancelPressed;
  final VoidCallback? onClearPressed;
  final FocusNode? focusNode;
  final List<String>? autofillHints;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final bool hasError;
  final String? errorText;
  final InputDecoration? decoration;
  final String cancelLabel;

  const _SearchFormFieldContent({
    this.externalController,
    required this.initialValue,
    this.onFormFieldChanged,
    required this.hintText,
    required this.autofocus,
    required this.showClearButton,
    required this.showSearchIcon,
    required this.isLoading,
    required this.padding,
    required this.borderRadius,
    this.backgroundColor,
    this.iconColor,
    this.textColor,
    this.hintColor,
    this.textStyle,
    this.hintStyle,
    this.onChanged,
    this.onSubmitted,
    this.onCancelPressed,
    this.onClearPressed,
    this.focusNode,
    this.autofillHints,
    this.textInputAction,
    this.maxLines,
    this.hasError = false,
    this.errorText,
    this.decoration,
    this.cancelLabel = 'Cancel',
  });

  @override
  State<_SearchFormFieldContent> createState() =>
      __SearchFormFieldContentState();
}

class __SearchFormFieldContentState extends State<_SearchFormFieldContent> {
  late TextEditingController _controller;
  bool _ownsController = false;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.externalController == null;
    _controller =
        widget.externalController ??
        TextEditingController(text: widget.initialValue);
    _controller.addListener(_onControllerChanged);
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void didUpdateWidget(_SearchFormFieldContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.externalController != oldWidget.externalController) {
      _controller.removeListener(_onControllerChanged);
      if (_ownsController) _controller.dispose();
      _ownsController = widget.externalController == null;
      _controller =
          widget.externalController ??
          TextEditingController(text: widget.initialValue);
      _controller.addListener(_onControllerChanged);
    } else if (_ownsController &&
        widget.initialValue != oldWidget.initialValue) {
      // Handles FormField.reset() — sync the internal controller to the reset value.
      _controller.text = widget.initialValue;
    }

    if (widget.focusNode != oldWidget.focusNode) {
      if (oldWidget.focusNode == null) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  // Single listener covers both user typing and programmatic changes
  // (e.g. controller.clear(), controller.text = '...'). Calling setState
  // here keeps the clear button visibility in sync without a separate flag.
  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
      widget.onFormFieldChanged?.call(_controller.text);
    }
  }

  void _clearSearch() {
    _controller.clear(); // triggers _onControllerChanged → field.didChange('')
    widget.onClearPressed?.call();
    _focusNode.requestFocus();
  }

  void _cancelSearch() {
    _controller.clear();
    widget.onCancelPressed?.call();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final errorColor = colorScheme.error;
    final effectiveBackgroundColor =
        widget.hasError
            ? errorColor.withValues(alpha: 0.1)
            : widget.backgroundColor ?? colorScheme.surfaceContainerHighest;
    final effectiveIconColor =
        widget.hasError
            ? errorColor
            : widget.iconColor ?? colorScheme.onSurface.withValues(alpha: 0.5);
    final effectiveHintColor =
        widget.hasError
            ? errorColor.withValues(alpha: 0.7)
            : widget.hintColor ?? colorScheme.onSurface.withValues(alpha: 0.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: effectiveBackgroundColor,
                  borderRadius: BorderRadius.circular(widget.borderRadius.r),
                  border: Border.all(
                    color: widget.hasError ? errorColor : colorScheme.outline,
                    width: .3,
                  ),
                ),
                padding: widget.padding,
                child: Row(
                  children: [
                    if (widget.showSearchIcon) ...[
                      widget.isLoading
                          ? const CircularLoadingIndicator()
                          : Icon(
                            Icons.search,
                            size: IconSizes.sm.r,
                            color: effectiveIconColor,
                          ),
                      SizedBox(width: Spacing.sm.w),
                    ],

                    Expanded(
                      child: TextFormField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: widget.autofocus,
                        maxLines: widget.maxLines,
                        textInputAction: widget.textInputAction,
                        autofillHints: widget.autofillHints,
                        decoration: (widget.decoration ??
                                InputDecoration(
                                  hintText: widget.hintText,
                                  hintStyle:
                                      widget.hintStyle ??
                                      theme.textTheme.bodyMedium?.copyWith(
                                        color: effectiveHintColor,
                                      ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                  errorBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                ))
                            .copyWith(errorText: null),
                        style:
                            widget.textStyle ??
                            theme.textTheme.bodyMedium?.copyWith(
                              color: widget.textColor ?? colorScheme.onSurface,
                            ),
                        onChanged: widget.onChanged,
                        onFieldSubmitted: widget.onSubmitted,
                      ),
                    ),

                    if (widget.showClearButton &&
                        _controller.text.isNotEmpty &&
                        !widget.isLoading)
                      IconButton(
                        onPressed: _clearSearch,
                        icon: Icon(
                          Icons.clear,
                          size: IconSizes.sm.r,
                          color: effectiveIconColor,
                        ),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            if (widget.onCancelPressed != null) ...[
              SizedBox(width: Spacing.xs.w),
              TextButton(
                onPressed: _cancelSearch,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.md.w,
                    vertical: Spacing.sm.h,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  widget.cancelLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),

        if (widget.hasError && widget.errorText != null)
          Padding(
            padding: EdgeInsets.only(left: Spacing.md.w, top: Spacing.xs.h),
            child: Text(
              widget.errorText!,
              style: theme.textTheme.bodySmall?.copyWith(color: errorColor),
            ),
          ),
      ],
    );
  }
}

// ========== ENHANCED FILTERABLE VERSION ==========

class FilterableSearchFormField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final List<String> filterChips;
  final List<String> selectedFilters;
  final ValueChanged<List<String>> onFiltersChanged;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final Map<String, IconData>? filterIcons;
  final FormFieldSetter<String>? onSaved;
  final FormFieldValidator<String>? validator;
  final String? initialValue;
  final bool enabled;
  final AutovalidateMode? autovalidateMode;
  final VoidCallback? onCancelPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool isLoading;
  final String cancelLabel;

  const FilterableSearchFormField({
    super.key,
    this.controller,
    this.hintText = 'Search and filter...',
    required this.filterChips,
    required this.selectedFilters,
    required this.onFiltersChanged,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onSaved,
    this.validator,
    this.initialValue,
    this.onCancelPressed,
    this.enabled = true,
    this.autovalidateMode,
    this.focusNode,
    this.autofocus = false,
    this.filterIcons,
    this.isLoading = false,
    this.cancelLabel = 'Cancel',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchFormField(
          controller: controller,
          onCancelPressed: onCancelPressed,
          hintText: hintText,
          onChanged: onSearchChanged,
          onFieldSubmitted: onSearchSubmitted,
          onSaved: onSaved,
          validator: validator,
          initialValue: initialValue,
          enabled: enabled,
          autovalidateMode: autovalidateMode,
          autofocus: autofocus,
          focusNode: focusNode,
          isLoading: isLoading,
          cancelLabel: cancelLabel,
        ),

        if (filterChips.isNotEmpty) ...[
          SizedBox(height: Spacing.sm.h),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  filterChips.map((filter) {
                    final isSelected = selectedFilters.contains(filter);
                    final icon = filterIcons?[filter];
                    return Padding(
                      padding: EdgeInsets.only(right: Spacing.xs.w),
                      child: AppFilterChip(
                        avatarIcon: icon,
                        label: filter,
                        borderWidth: 0.3,
                        selected: isSelected,
                        onSelected: (selected) {
                          final newFilters = List<String>.from(selectedFilters);
                          if (selected) {
                            newFilters.add(filter);
                          } else {
                            newFilters.remove(filter);
                          }
                          onFiltersChanged(newFilters);
                        },
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
