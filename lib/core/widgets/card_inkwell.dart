// lib/core/widgets/card_inkwell.dart
import 'package:attune/core/utils/exports/export_packages.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

/// A Card wrapper with integrated InkWell for tappable container components.
///
/// This widget combines Material Design's Card and InkWell components to create
/// visually elevated, tappable containers with proper touch feedback. It's ideal
/// for list items, settings tiles, menu options, or any content that needs both
/// visual structure and interactive feedback.
///
/// ## Key Features
/// - **Material Design compliance**: Proper Card elevation and InkWell ripple effects
/// - **Visual feedback**: Configurable splash/highlight colors with opacity controls
/// - **Design system integration**: Uses tokens for spacing, borders, and elevation
/// - **Flexible styling**: Customizable borders, corners, padding, and margins
/// - **Accessibility**: Haptic feedback control and proper touch targets
///
/// ## Visual Hierarchy
/// ```
/// ┌─────────────────────────────────────┐
/// │          Margin (optional)          │
/// │  ┌───────────────────────────────┐  │
/// │  │         Card (elevation)      │  │
/// │  │  ┌─────────────────────────┐  │  │
/// │  │  │      Border (optional)  │  │  │
/// │  │  │  ┌───────────────────┐  │  │  │
/// │  │  │  │    InkWell (tap)  │  │  │  │
/// │  │  │  │  ┌─────────────┐  │  │  │  │
/// │  │  │  │  │   Padding   │  │  │  │  │
/// │  │  │  │  │  ┌───────┐  │  │  │  │  │
/// │  │  │  │  │  │ Child │  │  │  │  │  │
/// │  │  │  │  │  └───────┘  │  │  │  │  │
/// │  │  │  │  └─────────────┘  │  │  │  │
/// │  │  │  └───────────────────┘  │  │  │
/// │  │  └─────────────────────────┘  │  │
/// │  └───────────────────────────────┘  │
/// └─────────────────────────────────────┘
/// ```
///
/// ## Usage Examples
/// ```dart
/// // Basic tappable list item
/// CardInkWell(
///   onTap: () => navigateToDetails(),
///   child: Row(
///     children: [
///       Icon(Icons.settings),
///       SizedBox(width: 16),
///       Text('Settings'),
///       Spacer(),
///       Icon(Icons.chevron_right),
///     ],
///   ),
/// )
///
/// // Custom-styled card with border
/// CardInkWell(
///   onTap: () => selectOption(),
///   padding: EdgeInsets.all(20),
///   borderRadius: BorderRadius.circular(16),
///   borderColor: Colors.blue,
///   borderWidth: 1.5,
///   elevation: 2,
///   child: Column(
///     crossAxisAlignment: CrossAxisAlignment.start,
///     children: [
///       Text('Premium Feature', style: TextStyle(fontWeight: FontWeight.bold)),
///       Text('Tap to upgrade your plan'),
///     ],
///   ),
/// )
///
/// // Disabled feedback for non-interactive display
/// CardInkWell(
///   enableFeedback: false,
///   child: Text('This is a non-interactive card'),
/// )
/// ```
class CardInkWell extends StatelessWidget {
  /// The content widget to display inside the card.
  ///
  /// This can be any widget - commonly used patterns include:
  /// - `Row` for list items with leading/trailing content
  /// - `Column` for multi-line content
  /// - `Text` for simple labels
  /// - Custom widgets for complex layouts
  final Widget child;

  /// Callback function triggered when the card is tapped.
  ///
  /// If not provided, the card still renders but is non-interactive (no tap feedback).
  /// Use `null` for display-only cards that maintain visual consistency with tappable ones.
  final VoidCallback? onTap;

  /// Internal padding between the card border and the child content.
  ///
  /// Defaults to `Spacing.allLg` (large spacing on all sides from design tokens).
  /// Adjust to control visual density or accommodate specific content layouts.
  final EdgeInsetsGeometry? padding;

  /// External margin around the entire card.
  ///
  /// Defaults to `EdgeInsets.only(bottom: Spacing.md.h)` for stacked list layouts.
  /// Use to create spacing between cards or from parent container edges.
  final EdgeInsetsGeometry? margin;

  /// Corner radius of the card.
  ///
  /// Defaults to `BorderRadiusTokens.mdAll` (medium radius from design tokens).
  /// Set to `BorderRadius.zero` for square cards or custom values for specific designs.
  final BorderRadius? borderRadius;

  /// Elevation (shadow depth) of the card.
  ///
  /// Defaults to `ElevationTokens.xs` (extra-small elevation token).
  /// Higher values create more pronounced shadows for greater visual separation.
  final double? elevation;

  /// Color of the card's border.
  ///
  /// Defaults to `colorScheme.outline.withOpacity(0.1)` for a subtle, theme-aware border.
  /// Set to transparent (`Colors.transparent`) for borderless cards with elevation only.
  final Color? borderColor;

  /// The line `final Color? color;` in the `CardInkWell` class is declaring a nullable property named
  /// `color` of type `Color`. This property is not used within the class implementation provided, so
  /// it seems to be an unused or potentially placeholder property.
  final Color? color;

  /// Width of the card's border in logical pixels.
  ///
  /// Defaults to `BorderWidthTokens.hairline` (thinnest border from design tokens).
  /// Use `ScreenUtil` for responsive scaling if providing custom values.
  final double? borderWidth;

  /// Whether to enable haptic/vibration feedback on tap.
  ///
  /// Defaults to `true`. Set to `false` for less intrusive interactions or
  /// when the card is used primarily for visual structure rather than interaction.
  final bool enableFeedback;

  /// Creates a tappable card container with Material Design feedback.
  ///
  /// [child] is required and represents the content inside the card.
  /// All other parameters are optional with sensible defaults that follow
  /// Material Design guidelines and integrate with the application's design system.
  const CardInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.borderRadius,
    this.elevation,
    this.borderColor,
    this.borderWidth,
    this.color,
    this.enableFeedback = true,
  });

  @override
  Widget build(BuildContext context) {
    // Extract color scheme for theme-aware styling
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      // External spacing - defaults to bottom margin for stacked layouts
      margin: margin ?? EdgeInsets.only(bottom: Spacing.md.h),
      // Subtle elevation for depth without overwhelming shadows
      elevation: elevation ?? ElevationTokens.xs,
      color: color ?? colorScheme.surface,
      // Card shape with optional border
      shape: RoundedRectangleBorder(
        // Use custom or token-based border radius
        borderRadius: borderRadius ?? BorderRadiusTokens.lgAll,
        side: BorderSide(
          // Subtle border with low opacity for clean separation
          color: borderColor ?? colorScheme.outline.withOpacity(0.1),
          // Hairline border for minimal visual intrusion
          width: borderWidth ?? BorderWidthTokens.hairline,
        ),
      ),
      // InkWell provides Material Design tap feedback
      child: InkWell(
        // Only interactive if onTap callback is provided
        onTap: onTap,
        // Match InkWell ripple radius to card corners
        borderRadius: borderRadius ?? BorderRadiusTokens.lgAll,
        // Haptic feedback control
        enableFeedback: enableFeedback,
        // Ripple color with opacity for subtle feedback
        splashColor: colorScheme.primary.withOpacity(0.12),
        // Highlight color for pressed state
        highlightColor: colorScheme.primary.withOpacity(0.08),
        // Internal padding with default from design tokens
        child: Padding(padding: padding ?? Spacing.allLg, child: child),
      ),
    );
  }
}
