import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_packages.dart';

/// A semantic content container that visually groups related information with consistent styling.
///
/// This widget creates a visually distinct container for presenting manual content,
/// documentation snippets, or informational blocks with clear visual hierarchy.
/// It uses color coordination between icon, title, and border to create semantic
/// grouping and immediate visual recognition of content type or importance level.
///
/// ## Visual Structure
/// ```
/// ┌─────────────────────────────────────┐ ← Border (semantic color)
/// │  [Icon]  Title (bold)               │
/// │                                     │
/// │  Content text spanning multiple     │
/// │  lines with appropriate opacity     │
/// │  for visual hierarchy.              │
/// └─────────────────────────────────────┘
/// ```
///
/// ## Design Characteristics
/// - **Semantic color coding**: Coordinated colors for icon, title, border, and background
/// - **Clear visual hierarchy**: Bold title, slightly transparent content text
/// - **Consistent spacing**: Uses design tokens for predictable layout
/// - **Subtle borders**: Thin borders for definition without visual weight
/// - **Icon reinforcement**: Visual icon reinforces content category
///
/// ## Color Coordination System
/// All visual elements use coordinated colors to create semantic meaning:
/// - `iconColor`: Primary semantic color (sets overall tone)
/// - `title`: Uses full `iconColor` opacity for prominence
/// - `content`: Uses `iconColor.withOpacity(0.9)` for subtle hierarchy
/// - `borderColor`: Matches semantic color for container definition
/// - `backgroundColor`: Provides contrast base (often lighter shade of semantic color)
///
/// ## Common Use Cases
/// ### 1. Information/Note Blocks
/// ```dart
/// SemanticContainerWidget(
///   title: 'Note',
///   icon: Icons.info,
///   iconColor: Colors.blue,
///   backgroundColor: Colors.blue[50],
///   borderColor: Colors.blue[200],
///   content: ManualContent(
///     content: 'This feature requires an active internet connection.',
///   ),
///   textTheme: Theme.of(context).textTheme,
/// )
/// ```
///
/// ### 2. Warning/Alert Blocks
/// ```dart
/// SemanticContainerWidget(
///   title: 'Warning',
///   icon: Icons.warning,
///   iconColor: Colors.orange,
///   backgroundColor: Colors.orange[50],
///   borderColor: Colors.orange[200],
///   content: ManualContent(
///     content: 'This action cannot be undone. Please proceed with caution.',
///   ),
///   textTheme: Theme.of(context).textTheme,
/// )
/// ```
///
/// ### 3. Success/Confirmation Blocks
/// ```dart
/// SemanticContainerWidget(
///   title: 'Success',
///   icon: Icons.check_circle,
///   iconColor: Colors.green,
///   backgroundColor: Colors.green[50],
///   borderColor: Colors.green[200],
///   content: ManualContent(
///     content: 'Your changes have been saved successfully.',
///   ),
///   textTheme: Theme.of(context).textTheme,
/// )
/// ```
///
/// ### 4. Documentation/Manual Content
/// ```dart
/// SemanticContainerWidget(
///   title: 'Documentation',
///   icon: Icons.help,
///   iconColor: Colors.purple,
///   backgroundColor: Colors.purple[50],
///   borderColor: Colors.purple[200],
///   content: ManualContent(
///     content: 'To configure this setting, navigate to Settings > Preferences.',
///   ),
///   textTheme: Theme.of(context).textTheme,
/// )
/// ```
class SemanticContainerWidget extends StatelessWidget {
  /// The text content to display within the container.
  ///
  /// Wrapped in a `ManualContent` model for potential future extensibility
  /// (could support markdown, rich text, or structured content in the future).
  /// Currently contains simple text content.
  final String content;

  /// Icon displayed beside the title for visual reinforcement.
  ///
  /// Should semantically match the content type (e.g., info, warning, help).
  /// Size is controlled by `IconSizes.md` token for consistency.
  final IconData? icon;
  final IconData? prefixIcon;


  

  /// Title text displayed prominently at the top of the container.
  ///
  /// Should be short and descriptive (e.g., "Note", "Warning", "Documentation").
  /// Uses bold weight and full opacity of `iconColor` for visual prominence.
  final String title;

  /// Background color of the container.
  ///
  /// Typically a light shade of the semantic color (e.g., blue[50], orange[50]).
  /// Provides sufficient contrast for readability while maintaining semantic grouping.
  final Color backgroundColor;

  /// Border color surrounding the container.
  ///
  /// Typically a medium shade of the semantic color (e.g., blue[200], orange[200]).
  /// Uses thin border width for subtle definition without visual weight.
  final Color borderColor;

  /// Primary semantic color that coordinates all visual elements.
  ///
  /// This color sets the semantic tone and is used for:
  /// - Icon color
  /// - Title text color
  /// - Content text color (with 90% opacity)
  /// Typically matches the container's semantic meaning (blue for info, red for error, etc.).
  final Color iconColor;

  /// Text theme for consistent typography.
  ///
  /// Required to ensure the container uses the app's established typography scale
  /// and maintains visual consistency with surrounding content.
  final TextTheme textTheme;

  final Widget? child;

  /// Creates a semantic content container with coordinated visual styling.
  ///
  /// All parameters are required to ensure complete semantic definition.
  /// The widget creates strong visual association through color coordination
  /// and consistent spacing based on the application's design tokens.
  const SemanticContainerWidget({
    super.key,
    required this.content,
     this.icon,
     this.prefixIcon,
    required this.title,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.textTheme,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Internal padding using small spacing token
      padding: EdgeInsets.all(Spacing.md.r),
      // Container styling with coordinated colors
      decoration: BoxDecoration(
        color: backgroundColor,
        // Medium border radius for balanced rounding
        borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
        // Thin border with semantic color for definition
        border: Border.all(
          color: borderColor,
          width: BorderWidthTokens.hairline.h,
        ),
      ),
      // Column layout for vertical content flow
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Semantic icon with consistent sizing
          if(icon != null)
          Icon(icon, size: IconSizes.md.r, color: iconColor),
          // Gap between icon and title
          // Gap(Spacing.sm.w),
          // Container(color: iconColor, width: .3.w, height: 30.h),
          Gap(Spacing.sm.w),
          // Title with bold weight and semantic color
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      color: iconColor,
                      fontWeight: FontWeight.w600, // Bold for prominence
                    ),
                  ), // Vertical gap between title and content
                if (content.isNotEmpty)
                  Text(
                    content,
                    style: textTheme.bodySmall?.copyWith(
                      // 90% opacity creates subtle visual hierarchy below title
                      color: iconColor.withOpacity(0.9),
                    ),
                  ),
                if (child != null) child!,
              ],
            ),
          ),

           if(prefixIcon != null)
          Icon(prefixIcon, size: IconSizes.md.r, color: iconColor),
        ],
      ),
    );
  }
}
