// lib/core/widgets/profile_info_row.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/image_container.dart';
import 'package:attune/core/widgets/profile_avatar.dart';

/// A versatile row widget for displaying informational items with multiple interaction patterns.
///
/// This highly flexible component displays title/subtitle text pairs with optional icons,
/// avatars, trailing widgets, and supports three distinct interaction modes:
/// 1. **Tappable rows**: Navigate to details (common for settings, documentation)
/// 2. **Toggle rows**: Switch controls for boolean settings
/// 3. **Display-only rows**: Information display without interaction
///
/// ## Features
/// - **Multiple interaction modes**: Tap, toggle, or display-only configurations
/// - **Visual customization**: Icons, colors, typography, spacing, and dividers
/// - **Avatar support**: Circular icon backgrounds or custom image URLs
/// - **Flexible trailing widgets**: Custom trailing content or auto-generated arrows/switches
/// - **Design system integration**: Uses tokens for spacing, icons, borders, and opacity
/// - **Accessibility**: Proper touch targets, clear visual feedback, and semantic labeling
///
/// ## Interaction Patterns
/// | Type | Visual Cue | Use Case | Trailing |
/// |------|------------|----------|----------|
/// | **Tappable** | InkWell ripple | Navigation (details, docs) | Chevron arrow |
/// | **Toggle** | Switch control | Boolean settings | Toggle switch |
/// | **Display** | No feedback | Information display | Custom or none |
///
/// ## Usage Examples
/// ```dart
/// // Tappable documentation row (original use case)
/// InfoRowWidget(
///   title: "Architecture Docs",
///   subtitle: "Project structure and patterns",
///   icon: Icons.architecture,
///   onTap: () => showDocumentationModal(context),
///   showTrailingArrow: true,
/// )
///
/// // Toggle row for settings
/// InfoRowWidget(
///   title: "Dark Mode",
///   subtitle: "Use dark theme interface",
///   icon: Icons.dark_mode,
///   isToggleItem: true,
///   toggleValue: _isDarkMode,
///   onToggleChanged: (value) => setState(() => _isDarkMode = value),
/// )
///
/// // Display-only row with custom avatar
/// InfoRowWidget(
///   title: "John Doe",
///   subtitle: "Product Manager",
///   imageUrl: "https://example.com/avatar.jpg",
///   showAvatar: true,
///   disableTrailing: true, // No interaction
/// )
///
/// // Row with custom trailing widget
/// InfoRowWidget(
///   title: "Storage Usage",
///   subtitle: "1.2 GB of 5 GB used",
///   icon: Icons.storage,
///   trailing: Chip(label: Text("24%")),
///   onTap: () => navigateToStorage(),
/// )
/// ```
class InfoRowWidget extends StatelessWidget {
  /// Primary text displayed in the row.
  ///
  /// Should be concise and descriptive (e.g., "Dark Mode", "Architecture Docs").
  /// Uses medium font weight for visual prominence. Limited to 2 lines maximum.
  final String title;

  /// Secondary text providing additional context or description.
  ///
  /// Use for explanations, details, or metadata (e.g., "Project structure and patterns").
  /// Displayed in a smaller, lower-contrast style. Limited to 3 lines maximum.
  final String subtitle;

  /// Material icon displayed in the leading position.
  ///
  /// Either [icon] or [imageUrl] must be provided. The icon is displayed within
  /// a circular avatar background when [showAvatar] is `true`.
  final IconData? icon;

  /// URL of an image to display in the leading position.
  ///
  /// Alternative to [icon] - displays an image instead of an icon.
  /// When both are provided, takes precedence over [icon].
  final String? imageUrl;

  /// Color of the leading icon (or image overlay).
  ///
  /// Defaults to the theme's primary color. Only applies to icons, not image URLs.
  final Color? iconColor;

  /// Background color of the avatar circle (when [showAvatar] is `true`).
  ///
  /// Defaults to primary color with 10% opacity for subtle contrast.
  final Color? backgroundColor;

  /// Radius of the avatar circle when [showAvatar] is enabled.
  ///
  /// If not provided, uses responsive sizing based on [iconSize].
  final double? avatarRadius;

  /// Callback function triggered when the row is tapped.
  ///
  /// Only used when [isToggleItem] is `false`. For toggle items, use [onToggleChanged].
  /// When provided, wraps the row in an InkWell with Material Design ripple feedback.
  final VoidCallback? onTap;

  /// Optional callback triggered when only the leading icon/avatar is tapped.
  ///
  /// When provided, the leading icon/avatar becomes its own tap target
  /// (e.g. to open a profile) separate from [onTap] on the rest of the row.
  /// When `null`, the avatar has no tap behavior of its own and taps
  /// fall through to [onTap] as before.
  final VoidCallback? onAvatarTap;

  /// Custom widget displayed at the trailing edge of the row.
  ///
  /// Overrides automatic trailing generation (arrows, toggles). Use for badges,
  /// chips, status indicators, or custom actions. When `null`, appropriate
  /// trailing content is generated based on other parameters.
  final Widget? trailing;

  /// Whether to automatically show a chevron arrow (›) at the trailing edge.
  ///
  /// Only applies when [trailing] is `null` and [isToggleItem] is `false`.
  /// Defaults to `false`. Set to `true` for tappable rows that navigate forward.
  final bool showTrailingArrow;

  /// Whether to display the leading icon/image within a circular avatar.
  ///
  /// When `true` (default), the icon/image appears within a circular background.
  /// When `false`, displays the icon/image alone without background decoration.
  final bool showAvatar;

  /// Whether to hide all trailing content.
  ///
  /// When `true`, suppresses both custom [trailing] widgets and auto-generated
  /// trailing content (arrows, toggles, open-in-new icons). Useful for minimal,
  /// display-only rows.
  final bool disableTrailing;

  /// Padding applied inside the row, around all content.
  ///
  /// Use to control the row's internal spacing or adjust for specific layout needs.
  final EdgeInsetsGeometry? padding;

  /// Horizontal alignment of the title and subtitle text.
  ///
  /// Defaults to `CrossAxisAlignment.start` (left-aligned for LTR languages).
  /// Change to `center` or `end` for different visual arrangements.
  final CrossAxisAlignment titleAlignment;

  /// Vertical packing of the title/subtitle text block within the row's
  /// height.
  ///
  /// Defaults to `MainAxisAlignment.start` (text packs to the top — correct
  /// when a trailing [showDivider] should hug the row's bottom edge, as in
  /// most settings/list rows). Set to `MainAxisAlignment.center` when the
  /// leading avatar/image is much taller than the text (e.g. product grid
  /// cards) and the text should sit vertically centered against it instead.
  final MainAxisAlignment textMainAxisAlignment;

  /// Complete text style override for the title.
  ///
  /// When provided, completely replaces the default title typography.
  /// Use for custom fonts, colors, or other typographic treatments.
  final TextStyle? titleStyle;

  /// Complete text style override for the subtitle.
  ///
  /// When provided, completely replaces the default subtitle typography.
  /// Typically uses smaller, lower-contrast styling than the title.
  final TextStyle? subtitleStyle;

  /// Size of the leading icon or avatar in logical pixels.
  ///
  /// Defaults to `20.h` (20 responsive pixels) when [showAvatar] is `true`,
  /// or `24.h` when [showAvatar] is `false`. Uses `ScreenUtil` for scaling.
  final double? iconSize;

  /// Whether to show a divider line below the row.
  ///
  /// Defaults to `true`. Set to `false` for seamless rows in grouped lists
  /// or when using alternative visual separation methods.
  final bool showDivider;
  final double titleFontSize;
  final double subTitleFontSize;

  final Color? titleFontColor;
  final Color? subTitleFontColor;

  // NEW: Add support for toggle items

  /// Whether this row represents a toggle/setting control.
  ///
  /// When `true`:
  /// - Requires [toggleValue] and [onToggleChanged] parameters
  /// - Shows a switch control at the trailing edge
  /// - Disables [onTap] functionality
  /// - Prevents InkWell wrapping (switch handles interaction)
  /// Defaults to `false` (standard tappable/display row).
  final bool isToggleItem;

  /// Current boolean value for toggle rows.
  ///
  /// Required when [isToggleItem] is `true`. Represents the current state
  /// of the toggle (checked/unchecked, on/off).
  final bool? toggleValue;
  final bool? pinAvatar;

  /// Whether the leading icon/avatar gets the same top padding
  /// (Spacing.md) the text column already starts with (its own leading
  /// Gap(Spacing.xs.h) plus title line height). Default true keeps every
  /// existing row unchanged. Pass false when [pinAvatar] already aligns the
  /// row to CrossAxisAlignment.start and the avatar should sit flush with
  /// the first line of text instead of getting a second, redundant nudge
  /// down from that top padding — otherwise pinning to start only to then
  /// pad the avatar back down largely cancels the pin out.
  final bool padAvatarTop;
  final bool? isNotAvatarImage;
  final int? titleMaxLines;
  final int? subTitleMaxLines;

  final double? circularRadius;
  final Widget? bottomWidget;

  /// Callback function triggered when the toggle switch changes state.
  ///
  /// Required when [isToggleItem] is `true`. Receives the new boolean value
  /// when the user toggles the switch. Use to update application state.
  final ValueChanged<bool>? onToggleChanged;

  /// Creates a versatile information row widget with multiple interaction modes.
  ///
  /// [title] and [subtitle] are required. Either [icon] or [imageUrl] must be provided.
  /// Parameters are validated with assertions to prevent invalid configurations.
  const InfoRowWidget({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.imageUrl,
    this.iconColor,
    this.backgroundColor,
    this.avatarRadius,
    this.onTap,
    this.onAvatarTap,
    this.trailing,
    this.showTrailingArrow = false,
    this.showAvatar = true,
    this.disableTrailing = false,
    this.padding,
    this.titleAlignment = CrossAxisAlignment.start,
    this.textMainAxisAlignment = MainAxisAlignment.start,
    this.titleStyle,
    this.subtitleStyle,
    this.iconSize,
    this.showDivider = true,
    // NEW parameters
    this.isToggleItem = false,
    this.toggleValue,
    this.onToggleChanged,
    this.titleMaxLines,
    this.subTitleMaxLines,
    this.circularRadius,
    this.titleFontSize = 14,
    this.subTitleFontSize = 12,
    this.titleFontColor,
    this.subTitleFontColor,
    this.isNotAvatarImage = false,
    this.pinAvatar = true,
    this.padAvatarTop = false,
    this.bottomWidget,
  }) : assert(
         // Either icon or imageUrl must be provided for visual identity
         icon != null || imageUrl != null,
         'Either icon or imageUrl must be provided',
       ),
       // Validate toggle parameters when toggle mode is enabled
       assert(
         !isToggleItem || (toggleValue != null && onToggleChanged != null),
         'For toggle items, both toggleValue and onToggleChanged must be provided',
       ),
       // Prevent conflicting interaction patterns
       assert(
         !isToggleItem || onTap == null,
         'Toggle items should not have onTap, use onToggleChanged instead',
       );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final pinRowAvatar = pinAvatar ?? false;

    // ✅ NEW: Build trailing for toggle items if not provided
    // Prioritizes custom trailing, then toggle switch, then other auto-generated content
    final effectiveTrailing =
        trailing ?? (isToggleItem ? _buildToggleSwitch(context) : null);

    // Core row content structure (shared across all interaction types)
    final rowContent = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Row(
        crossAxisAlignment:
            pinRowAvatar ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Leading icon/avatar with consistent spacing
          Padding(
            padding:
                padAvatarTop
                    ? const EdgeInsets.only(top: Spacing.md)
                    : EdgeInsets.zero,
            child: _buildIconOrAvatar(context, colorScheme),
          ),
          if (iconSize != 0) Gap(Spacing.md.w),

          // Text content area with flexible alignment.
          //
          // Deliberately NOT a SingleChildScrollView, even a
          // NeverScrollableScrollPhysics one: that registers a Scrollable
          // per row, so a screen of these (Settings is 8) ends up with many
          // scrollables and anything resolving "the" scrollable — including
          // tester.scrollUntilVisible — breaks. ClipRect contains overflow
          // without pretending to be scrollable.
          Expanded(
            child: ClipRect(
              child: SingleChildScrollView(
                physics: NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisAlignment: textMainAxisAlignment,
                  crossAxisAlignment: titleAlignment,
                  children: [
                    // Small gap for visual separation
                    Gap(Spacing.xs.h),
                    // Primary title with line limiting
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style:
                            titleStyle ??
                            textTheme.titleSmall?.copyWith(
                              color: titleFontColor ?? colorScheme.onBackground,
                              fontSize: titleFontSize.sp,
                              fontWeight: FontWeight.w500,
                            ),
                        maxLines: titleMaxLines ?? 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    // Small gap between title and subtitle
                    if (subtitle.isNotEmpty)
                      if (title.isNotEmpty) Gap(Spacing.xs.h),
                    // Optional subtitle (only if non-empty)
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style:
                            subtitleStyle ??
                            textTheme.bodyMedium?.copyWith(
                              // fontSize: subTitleFontSize.sp,
                              color:
                                  subTitleFontColor ??
                                  colorScheme.onBackground.withOpacity(
                                    OpacityTokens.medium,
                                  ),
                            ),
                        maxLines: subTitleMaxLines ?? 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (bottomWidget != null) bottomWidget!,
                    // Optional divider below content
                    if (showDivider) AppDivider(),
                  ],
                ),
              ),
            ),
          ),

          // Trailing content area with conditional logic
          if (!disableTrailing) ...[
            // Custom trailing widget (highest priority)
            if (effectiveTrailing != null) ...[
              Gap(Spacing.md.w),
              effectiveTrailing,
            ]
            // Auto-generated chevron for tappable rows
            else if (showTrailingArrow) ...[
              Gap(Spacing.md.w),
              Icon(
                Icons.chevron_right,
                size: IconSizes.md.h,
                color: colorScheme.onBackground.withOpacity(0.3),
              ),
            ]
            // Auto-generated "open" icon for tappable rows without custom trailing
            else if (onTap != null && !isToggleItem) ...[
              // ✅ Don't show for toggles
              Gap(Spacing.md.w),
              Icon(
                Icons.open_in_new,
                size: IconSizes.sm.h,
                color: colorScheme.onBackground.withOpacity(0.3),
              ),
            ],
          ],
        ],
      ),
    );

    // ✅ IMPORTANT: Don't wrap toggle items in InkWell - switches handle their own interaction
    return isToggleItem
        ? rowContent // Toggles handle their own interaction via Switch widget
        : (onTap != null
            ? InkWell(
              // Material Design ripple feedback for tappable rows
              onTap: onTap,
              splashColor: colorScheme.primary.withOpacity(0.12),
              highlightColor: colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
              child: rowContent,
            )
            : rowContent); // Display-only rows get no interactive wrapper
  }

  // ✅ NEW: Build toggle switch for boolean settings
  // Creates an adaptive switch that matches the platform design language
  Widget _buildToggleSwitch(BuildContext context) {
    return AppToggleSwitch(
      toggleValue: toggleValue ?? false,
      onToggleChanged: onToggleChanged ?? (bool value) {},
    );
  }

  // Builds the leading icon or avatar with consistent styling
  Widget _buildIconOrAvatar(BuildContext context, ColorScheme colorScheme) {
    final icoColor = iconColor ?? colorScheme.primary;
    final bgColor = backgroundColor ?? colorScheme.primary.withOpacity(0.1);
    final size = iconSize ?? (showAvatar ? 20.h : 24.h);
    final notAvatarImage = isNotAvatarImage ?? false;

    final avatar =
        imageUrl != null
            ? notAvatarImage
                ? SizedBox(
                  width: avatarRadius ?? 45.h,
                  height: avatarRadius ?? 45.h,
                  child: ImageContainer(
                    imageUrl: imageUrl ?? '',
                    isPreview: false,
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                )
                : ProfileAvatar(
                  avatarUrl: imageUrl ?? '',
                  currentUserId: '',
                  size: avatarRadius ?? 45.h,
                  enableHero: false,
                )
            : IconAvatar(
              icon: icon ?? Icons.person,
              iconColor: icoColor,
              size: size,
              showAvatar: showAvatar,
              backgroundColor: bgColor,
              avatarRadiusSize: avatarRadius,
              circularRadius: circularRadius ?? 100.r,
            );

    if (onAvatarTap == null) return avatar;

    // Own GestureDetector so the avatar's tap is captured before it can
    // bubble to the row-level InkWell/onTap wrapping the whole row.
    return GestureDetector(
      onTap: onAvatarTap,
      behavior: HitTestBehavior.opaque,
      child: avatar,
    );
  }
}
