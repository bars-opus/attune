// lib/core/widgets/selection/selection_tile.dart
import 'package:attune/core/utils/exports/export_screens.dart';


/// 🎯 Universal selection tile for lists (language, settings, etc.)
///
/// A highly versatile tile component for selection-based interfaces where users
/// choose one option from a list. Commonly used for language selectors, theme pickers,
/// settings options, and any scenario requiring visual selection feedback.
///
/// ## Key Features
/// - **Visual feedback**: Clear selected state with border, color, and checkmark
/// - **Loading states**: Built-in loading indicator for async operations
/// - **Flexible content**: Supports titles, subtitles, and custom leading widgets
/// - **Design system integration**: Uses tokens for consistent spacing, borders, and icons
/// - **Accessibility**: Full tap target with visual feedback and disabled states
///
/// ## Visual States
/// | State | Appearance |
/// |-------|-----------|
/// | **Default** | Transparent background, subtle border |
/// | **Selected** | Primary color tint, thicker border, checkmark icon |
/// | **Loading** | Progress indicator replaces checkmark, tap disabled |
/// | **Disabled** | Visual feedback when `isLoading` is `true` |
///
/// ## Usage Examples
/// ```dart
/// // Language selection tile
/// SelectionTile(
///   title: 'English',
///   subtitle: 'United States',
///   leading: Text('🇺🇸', style: TextStyle(fontSize: 24)),
///   isSelected: currentLanguage == 'en',
///   onTap: () => setLanguage('en'),
/// )
///
/// // Theme selection with loading state
/// SelectionTile(
///   title: 'Dark Theme',
///   isSelected: themeMode == ThemeMode.dark,
///   isLoading: themeChangeInProgress,
///   onTap: () => switchToDarkTheme(),
///   selectedColor: Colors.purple, // Custom selection color
/// )
///
/// // Simple option selection
/// SelectionTile(
///   title: 'High Quality',
///   subtitle: 'Uses more data',
///   isSelected: quality == 'high',
///   onTap: () => setQuality('high'),
/// )
/// ```
class SelectionTile extends StatelessWidget {
  /// Primary text displayed in the tile.
  ///
  /// This should clearly identify the selectable option (e.g., "English", "Dark Mode").
  /// Uses the theme's `bodyLarge` text style with increased font weight for prominence.
  final String title;

  /// Optional secondary text providing additional context.
  ///
  /// Use for descriptions, metadata, or clarifications (e.g., "United States",
  /// "Uses more data", "Recommended"). Displayed in a smaller, less prominent style.
  final String? subtitle;

  /// Optional widget displayed before the text content.
  ///
  /// Commonly used for icons, flags, avatars, or other visual identifiers.
  /// If provided, separated from the text by medium spacing (`Spacing.md.w`).
  final Widget? leading;

  /// Whether this tile represents the currently selected option.
  ///
  /// When `true`:
  /// - Applies a primary color tint to the background
  /// - Shows a thicker border with increased opacity
  /// - Displays a checkmark icon on the trailing edge
  /// - Adjusts text colors for better contrast
  final bool isSelected;

  /// Whether the tile is in a loading/processing state.
  ///
  /// When `true`:
  /// - Shows a circular progress indicator instead of the checkmark
  /// - Disables tap interactions (`onTap` is ignored)
  /// - Useful for async operations like applying settings
  final bool isLoading;

  /// Callback function triggered when the tile is tapped.
  ///
  /// This callback is ignored when `isLoading` is `true`. Required for all
  /// functional tiles - consider using an empty function for disabled/display-only tiles.
  final VoidCallback onTap;

  /// Custom color to use for the selected state visual indicators.
  ///
  /// If not provided, defaults to the theme's primary color (`colorScheme.primary`).
  /// Use this to create custom selection themes (e.g., different colors for
  /// different selection categories).
  final Color? selectedColor;

  /// Custom border radius for the tile.
  ///
  /// If not provided, uses the design token `BorderRadiusTokens.mdAll` (medium radius).
  /// Use this to match the tile's corners to surrounding UI elements or create
  /// different visual styles (sharp, rounded, pill-shaped).
  final BorderRadius? borderRadius;

  /// Creates a universal selection tile for list-based selection interfaces.
  ///
  /// [title] and [onTap] are required parameters. All others have sensible defaults
  /// that integrate with the application's design system.
  const SelectionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.isSelected = false,
    this.isLoading = false,
    required this.onTap,
    this.selectedColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    // Extract theme components for consistent styling
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Determine the color to use for selection indicators
    // Uses custom color if provided, otherwise falls back to theme primary
    final effectiveSelectedColor = selectedColor ?? colorScheme.primary;

    return Card(
      // Remove default Card margins for seamless list integration
      margin: EdgeInsets.all(0),
      // Elevation disabled (0) for flat design - selection is indicated by color/border
      elevation: isSelected ? 0 : 0,
      // Apply background tint when selected for clear visual feedback
      color:
          isSelected ? colorScheme.primary.withOpacity(.3) : Colors.transparent,
      shape: RoundedRectangleBorder(
        // Use custom or token-based border radius
        borderRadius: borderRadius ?? BorderRadiusTokens.mdAll,
        side: BorderSide(
          // Border color varies by selection state and opacity
          color: effectiveSelectedColor.withOpacity(0.3),
          // Thicker border when selected for enhanced visual hierarchy
          width: isSelected ? 1.h : .5.h,
        ),
      ),
      child: InkWell(
        // Disable tap when loading to prevent double-triggers
        onTap: isLoading ? null : onTap,
        // Match border radius to Card for consistent visual feedback
        borderRadius: borderRadius ?? BorderRadiusTokens.mdAll,
        child: Padding(
          // Consistent internal padding using design token
          padding: EdgeInsets.all(Spacing.sm.w),
          child: Row(
            children: [
              // Leading widget with proper spacing if provided
              if (leading != null) ...[leading!, SizedBox(width: Spacing.md.w)],

              // Main content area (title and optional subtitle)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary title with selection-aware color
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            isSelected
                                ? colorScheme.onBackground
                                : colorScheme.onSurface,
                      ),
                    ),
                    // Optional subtitle with conditional rendering
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      // Small vertical separation between title and subtitle
                      SizedBox(height: Spacing.xs.h),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          // Subtitle uses primary color when selected for emphasis
                          color:
                              isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Trailing indicator (loading or selection)
              if (isLoading)
                // Circular progress indicator for async operations
               CircularLoadingIndicator(
                           
                          )
              else if (isSelected)
                // Checkmark icon for confirmed selection
                Icon(
                  Icons.check_circle_rounded,
                  color: effectiveSelectedColor,
                  size: IconSizes.md.h,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
