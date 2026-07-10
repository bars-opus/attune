import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:glass_kit/glass_kit.dart';

/// A specialized container for modal documentation content with distinctive rounded corners.
///
/// This widget creates a visually distinct container optimized for displaying
/// documentation content in modal sheets, typically with a top-only rounded design
/// that distinguishes it from the main app interface. It's specifically designed
/// to work with `InfoRowWidget` and documentation modal patterns established
/// in previous implementations.
///
/// ## Design Characteristics
/// - **Top-only rounding**: Only the top-left and top-right corners are rounded,
///   creating a "sheet" appearance that emerges from the bottom of the screen
/// - **Theme integration**: Uses the theme's background color for consistency
/// - **Responsive padding**: Default padding scales with screen size via `ScreenUtil`
/// - **Modal optimization**: Designed for use with `showModalBottomSheet`
///
/// ## Typical Usage Pattern
/// This component is commonly used within modal bottom sheets to present
/// documentation content in a visually distinct container:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   backgroundColor: Colors.transparent, // Let container provide background
///   builder: (context) => CircularDocumentationContainer(
///     padding: 20, // Optional custom padding
///     child: DocumentationTabView(
///       documentation: architectureDocs,
///       faqs: architectureFAQs,
///     ),
///   ),
/// )
/// ```
///
/// ## Visual Structure
/// ```
/// ┌─────────────────────────────────────────────┐
/// │                                             │  ← Top rounded corners only
/// │          XL Padding (default)               │
/// │  ┌─────────────────────────────────────┐   │
/// │  │                                     │   │
/// │  │          Child Content              │   │
/// │  │        (Documentation, FAQs)        │   │
/// │  │                                     │   │
/// │  └─────────────────────────────────────┘   │
/// │                                             │  ← Bottom corners remain square
/// └─────────────────────────────────────────────┘
/// ```
///
/// ## Usage Examples
/// ```dart
/// // Basic documentation modal container
/// CircularDocumentationContainer(
///   child: DocumentationTabView(
///     documentation: allSections,
///     faqs: allFAQs,
///     showDocumentationFirst: true,
///   ),
/// )
///
/// // Custom padding for dense content
/// CircularDocumentationContainer(
///   padding: 16, // Reduced from default XL spacing
///   child: MarkdownViewer(
///     content: apiDocumentation,
///   ),
/// )
///
/// // Integration with existing modal sheet pattern
/// InfoRowWidget(
///   title: "Architecture Docs",
///   subtitle: "Project structure and patterns",
///   icon: Icons.architecture,
///   onTap: () => showModalBottomSheet(
///     context: context,
///     isScrollControlled: true,
///     backgroundColor: Colors.transparent,
///     constraints: BoxConstraints(
///       maxHeight: MediaQuery.of(context).size.height * 0.9,
///     ),
///     builder: (context) => CircularDocumentationContainer(
///       child: DocumentationTabView(...),
///     ),
///   ),
/// )
/// ```
class CircularDocumentationContainer extends StatelessWidget {
  /// The content widget to display inside the container.
  ///
  /// Typically a `DocumentationTabView`, `MarkdownViewer`, or other documentation
  /// presentation widget. This child receives the container's padding and
  /// background styling.
  final Widget child;

  /// Padding applied inside the container, between the border and child content.
  ///
  /// Defaults to `Spacing.xl.h` (extra-large responsive spacing from design tokens).
  /// Use custom values to control visual density - smaller values for compact
  /// content, larger values for spacious, readable layouts.
  final double? padding;
  final bool? allRadius;
  final Color? color;

  /// Creates a circular-top container optimized for documentation modal content.
  ///
  /// [child] is required and contains the documentation content to display.
  /// [padding] is optional and defaults to extra-large spacing for optimal readability.
  const CircularDocumentationContainer({
    super.key,
    required this.child,
    this.padding,
     this.color,
    this.allRadius,
  });

  @override
  Widget build(BuildContext context) {
    // Extract color scheme for theme-aware background
    final colorScheme = Theme.of(context).colorScheme;

    return
    // GlassContainer(
    //   // Dimensions & Shape
    //   width: double.infinity, // Takes full width
    //   borderRadius: BorderRadius.only(
        // topLeft: Radius.circular(BorderRadiusTokens.xl),
        // topRight: Radius.circular(BorderRadiusTokens.xl),
    //   ),
    //   // Glass Effect Properties
    //   blur: 20, // Intensity of the background blur (10-30 is typical)
    //   color: colorScheme.background.withOpacity(
    //     0.15,
    //   ), // Your theme color, made translucent
    //   borderColor: Colors.white.withOpacity(
    //     0.1,
    //   ), // A subtle light border for the "glass edge"
    //   borderWidth: 0.5,
    //   // Shadow for depth
    //   shadowColor: Colors.black.withOpacity(0.2),
    //   // Your existing content
    //   child: Container(
    //     padding: EdgeInsets.all(padding ?? Spacing.xl.h),
    //     child: child,
    //   ),
    // );
    Container(
      // Container decoration with distinctive top-only rounding
      decoration: BoxDecoration(
        // Use theme background for consistent appearance with rest of app
        color: color?? colorScheme.background,
        // Top-only rounding creates "emerging sheet" visual metaphor
        borderRadius:
            allRadius == true
                ? BorderRadius.circular(BorderRadiusTokens.xl)
                : BorderRadius.only(
                  topLeft: Radius.circular(BorderRadiusTokens.xl),
                  topRight: Radius.circular(BorderRadiusTokens.xl),
                ),
      ),
      // Responsive internal padding (defaults to extra-large spacing)
      padding: EdgeInsets.all(padding ?? Spacing.xl.h),
      // Child content receives container styling
      child: child,
    );
  }
}
