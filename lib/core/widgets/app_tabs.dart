import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/app/theme/design_tokens.dart';

/// Represents a single tab item within a tabbed interface.
///
/// This model class defines the content and appearance of an individual tab,
/// supporting both traditional icon+label combinations and fully custom tab widgets.
/// Used in conjunction with `SimpleTabs` to create tabbed navigation interfaces.
///
/// ## Configuration Options
/// - **Label**: Required text label for the tab
/// - **Icon**: Optional Material icon displayed alongside the label
/// - **Custom Child**: Fully custom widget to replace the default icon+label layout
/// - **Content**: The widget to display when this tab is active (typically a screen/page)
///
/// ## Usage Example
/// ```dart
/// // Traditional icon + label tab
/// AppTabItem(
///   label: 'Home',
///   icon: Icons.home,
///   content: HomeScreen(),
/// )
///
/// // Label-only tab
/// AppTabItem(
///   label: 'Profile',
///   content: ProfileScreen(),
/// )
///
/// // Fully custom tab design
/// AppTabItem(
///   customChild: Badge(
///     label: Text('3'),
///     child: Text('Notifications'),
///   ),
///   content: NotificationsScreen(),
/// )
/// ```
class AppTabItem {
  /// The text label displayed on the tab.
  ///
  /// Required for accessibility and clarity. Even when using `customChild`,
  /// consider providing a label for screen readers.
  final String label;

  /// Optional Material icon displayed to the left of the label.
  ///
  /// Uses Material Icons with default sizing (`IconSizes.md`).
  /// When both `icon` and `customChild` are provided, `customChild` takes precedence.
  final IconData? icon;

  /// Fully custom widget to use as the tab's visual representation.
  ///
  /// When provided, this completely replaces the default icon+label layout.
  /// Use for advanced tab designs like badges, avatars, or custom indicators.
  final Widget? customChild;

  /// The content widget displayed when this tab is active.
  ///
  /// Typically a `Widget` representing a screen, page, or content section.
  /// This is not used directly by `SimpleTabs` but is commonly stored with
  /// the tab definition for convenience in tab controller patterns.
  final Widget? content;

  /// Creates a tab item definition.
  ///
  /// [label] is required for all tab items. [icon] and [customChild] are optional,
  /// with [customChild] taking precedence when both are provided.
  const AppTabItem({
    required this.label,
    this.icon,
    this.customChild,
    this.content,
  });
}

/// Simple Tab Style Configuration
///
/// Defines the visual appearance and styling parameters for a tab bar.
/// Provides a centralized way to customize tab colors, typography, indicators,
/// and spacing while maintaining consistency across the application.
///
/// ## Design Token Integration
/// This class works with the application's design token system:
/// - `BorderRadiusTokens.md` for default border radius
/// - Responsive scaling via `ScreenUtil` for measurements
/// - Theme color scheme integration for sensible defaults
///
/// ## Style Customization Examples
/// ```dart
/// // Minimal tabs with subtle indicator
/// AppTabsStyle(
///   indicatorHeight: 1.5,
///   showIndicator: true,
///   tabPadding: 12.0,
/// )
///
/// // Bold, pill-shaped tabs
/// AppTabsStyle(
///   borderRadius: 24.0,
///   activeColor: Colors.blue,
///   inactiveColor: Colors.grey,
///   showIndicator: false,
///   activeTextStyle: TextStyle(fontWeight: FontWeight.bold),
/// )
///
/// // Material Design 3 style
/// AppTabsStyle(
///   indicatorColor: Colors.deepPurple,
///   indicatorHeight: 3.0,
///   tabPadding: 20.0,
/// )
/// ```
class AppTabsStyle {
  /// Color of the active (selected) tab label.
  ///
  /// Defaults to the theme's primary color (`colorScheme.primary`) when not specified.
  /// Should provide sufficient contrast against the tab bar background.
  final Color? activeColor;

  /// Color of inactive (unselected) tab labels.
  ///
  /// Defaults to `onSurface.withOpacity(0.6)` for subtle, accessible contrast.
  /// Should be noticeably less prominent than the active tab color.
  final Color? inactiveColor;

  /// Color of the selection indicator (underline).
  ///
  /// Defaults to the theme's primary color (`colorScheme.primary`).
  /// Typically matches or complements the `activeColor` for visual harmony.
  final Color? indicatorColor;

  /// Height of the selection indicator in logical pixels.
  ///
  /// Defaults to `1.0` (1 pixel). Use `ScreenUtil` for responsive scaling.
  /// Common values: 1.0 (subtle), 2.0 (standard), 3.0+ (bold).
  final double? indicatorHeight;

  /// Horizontal padding inside each tab.
  ///
  /// Defaults to `16.0` pixels. Affects the spacing between tab label and tab edges.
  /// Larger values create more spacious tabs; smaller values create compact tabs.
  final double? tabPadding;

  /// Border radius for tab containers.
  ///
  /// Defaults to `BorderRadiusTokens.md` (medium radius from design tokens).
  /// Set to `0` for square tabs or higher values for pill-shaped tabs.
  final double? borderRadius;

  /// Complete text style override for active tabs.
  ///
  /// When provided, completely replaces the default active tab typography.
  /// Use for custom fonts, weights, or other typographic treatments.
  final TextStyle? activeTextStyle;

  /// Complete text style override for inactive tabs.
  ///
  /// When provided, completely replaces the default inactive tab typography.
  /// Typically less prominent than the active text style.
  final TextStyle? inactiveTextStyle;

  /// Whether to display the selection indicator (underline).
  ///
  /// Defaults to `true`. Set to `false` for tab designs that use color fill,
  /// borders, or other visual cues to indicate selection.
  final bool showIndicator;
  final bool showDivider;

  /// Creates a tab bar style configuration.
  ///
  /// All parameters are optional with sensible defaults that follow Material
  /// Design guidelines and integrate with the application's design system.
  const AppTabsStyle({
    this.activeColor,
    this.inactiveColor,
    this.indicatorColor,
    this.indicatorHeight = 1.0,
    // 8, not 16: three tabs at 16 push the third one off a 390pt screen
    // entirely -- on an iPhone 14 Pro the Settings tab's centre lands at
    // x=409 on a 390pt-wide view, so it cannot be tapped at all. Callers
    // that want roomier tabs can still pass a larger value; the DEFAULT
    // has to fit the narrowest common phone.
    this.tabPadding = 8.0,
    this.borderRadius = BorderRadiusTokens.md,
    this.activeTextStyle,
    this.inactiveTextStyle,
    this.showIndicator = true,
    this.showDivider = true,
  });
}

/// Simple, Scrollable Tab Widget
///
/// A production-ready tab bar implementation that provides flexible, customizable
/// tab navigation with proper NestedScrollView compatibility and Material Design compliance.
///
/// ## Key Features
/// - **NestedScrollView compatible**: Works correctly within scrollable contexts
/// - **Flexible tab content**: Supports icons, labels, or fully custom tab widgets
/// - **Customizable styling**: Extensive visual customization via `AppTabsStyle`
/// - **Proper state management**: Uses external `TabController` for flexible integration
/// - **Responsive design**: Uses `ScreenUtil` for consistent scaling across devices
///
/// ## Integration Patterns
/// ```dart
/// // Basic integration with TabController
/// DefaultTabController(
///   length: 3,
///   child: Column(
///     children: [
///       SimpleTabs(
///         tabs: tabItems,
///         controller: DefaultTabController.of(context),
///       ),
///       Expanded(
///         child: TabBarView(
///           controller: DefaultTabController.of(context),
///           children: tabContents,
///         ),
///       ),
///     ],
///   ),
/// )
///
/// // Custom styled tabs
/// SimpleTabs(
///   tabs: myTabs,
///   controller: myController,
///   style: AppTabsStyle(
///     activeColor: Colors.purple,
///     indicatorHeight: 3.0,
///     showIndicator: true,
///   ),
///   scrollable: true,
/// )
/// ```
///
/// ## Important Notes
/// 1. **Controller required**: You must provide a `TabController` instance
/// 2. **Height fixed**: Tab bar has a fixed height of `48.h` for consistent touch targets
/// 3. **Indicator alignment**: Indicator is precisely aligned with no gaps
/// 4. **Divider control**: Optional subtle divider between tabs when indicator is shown
class SimpleTabs extends StatelessWidget {
  /// List of tab definitions to display in the tab bar.
  ///
  /// Each `AppTabItem` defines the visual representation (label, icon, custom widget)
  /// for one tab. The order of items determines left-to-right tab order.
  final List<AppTabItem> tabs;

  /// Controller for managing tab selection state.
  ///
  /// **REQUIRED** - You must provide a `TabController` instance. This allows
  /// the tab bar to be controlled from parent widgets and integrated with
  /// `TabBarView` for synchronized content switching.
  final TabController controller;

  /// Visual styling configuration for the tab bar.
  ///
  /// Uses `AppTabsStyle` to define colors, typography, indicators, and spacing.
  /// Defaults to a basic Material Design style when not specified.
  final AppTabsStyle style;

  /// External padding around the entire tab bar widget.
  ///
  /// Use this to position the tab bar within its parent container or create
  /// spacing from adjacent UI elements.
  final EdgeInsetsGeometry? padding;

  /// Background color of the tab bar container.
  ///
  /// Defaults to transparent. Set to a specific color to create a distinct
  /// tab bar background (e.g., surface color for elevation).
  final Color? backgroundColor;

  /// Whether tabs should scroll horizontally when they exceed available width.
  ///
  /// When `true` (default), tabs scroll horizontally. When `false`, tabs
  /// distribute available width equally (not recommended for many tabs).
  final bool scrollable;
  final double? tabHeight;

  final bool Function(int index)? onTabTap;

  /// Creates a simple, scrollable tab bar widget.
  ///
  /// [tabs] and [controller] are required parameters. The [controller] must
  /// be properly initialized with a length matching the number of tabs.
  const SimpleTabs({
    super.key,
    required this.tabs,
    required this.controller,
    this.style = const AppTabsStyle(),
    this.padding,
    this.backgroundColor,
    this.scrollable = true,
    this.onTabTap,
    this.tabHeight = 48,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      children: [
        // Tabs bar using Flutter's built-in TabBar for Material Design compliance
        // Fixed height ensures consistent touch targets (48.h = 48 responsive pixels)
        SizedBox(
          height: tabHeight ?? 48.h,
          child: TabBar(
            // External controller for state management
            controller: controller,
            // Horizontal scrolling for many tabs
            isScrollable: scrollable,

            // Active tab color (defaults to primary)
            labelColor: style.activeColor ?? colors.primary,

            // Subtle divider between tabs (only shown when indicator is visible)
            // Uses low opacity for subtle separation without visual competition
            dividerColor:
                style.showDivider
                    ? (style.inactiveColor ??
                        colors.onSurface.withValues(alpha: 0.3))
                    : Colors.transparent,
            dividerHeight: 0.3,

            // Inactive tab color with reduced opacity for hierarchy
            unselectedLabelColor:
                style.inactiveColor ?? colors.onSurface.withValues(alpha: 0.6),

            // Custom underline indicator with precise positioning
            // FIX: Uses UnderlineTabIndicator for exact Material Design alignment
            indicator: UnderlineTabIndicator(
              borderSide: BorderSide(
                // Responsive height using ScreenUtil
                width: style.indicatorHeight!.h,
                color: style.indicatorColor ?? colors.primary,
              ),
            ),
            // Remove indicator padding for exact alignment
            indicatorPadding: EdgeInsets.zero,

            // Indicator spans full tab width for clear visual feedback
            indicatorSize: TabBarIndicatorSize.tab,

            // Active tab typography (bold by default)
            labelStyle:
                style.activeTextStyle ??
                theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
            // Inactive tab typography (regular weight by default)
            unselectedLabelStyle:
                style.inactiveTextStyle ??
                theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),

            // Remove all default TabBar padding for precise control
            padding: EdgeInsets.zero,
            // Fill available width when indicator is shown for balanced layout
            tabAlignment:
                scrollable
                    ? TabAlignment.start
                    : style.showIndicator
                    ? TabAlignment.fill
                    : TabAlignment.start,
            // Critical: Remove label padding for exact text positioning
            labelPadding: EdgeInsets.zero,

            // Generate Tab widgets from AppTabItem definitions
            tabs:
                tabs.map((tab) {
                  return Tab(
                    // Fixed tab height matching container
                    height: tabHeight ?? 48.h,
                    // Container provides customizable internal padding
                    child: GestureDetector(
                      // Handle taps ourselves
                      onTap:
                          onTabTap != null
                              ? () {
                                // Get index by finding which tab was tapped
                                final index = tabs.indexOf(tab);
                                final allowTap = onTabTap!(index);
                                if (allowTap) {
                                  controller.animateTo(index);
                                }
                              }
                              : null,
                      child: Container(
                        color: Colors.transparent,
                        // Horizontal padding adjustable via style.
                        padding: EdgeInsets.symmetric(
                          horizontal: (style.tabPadding ?? 8.0).w,
                        ),
                        alignment: Alignment.center,
                        // Use custom child if provided, otherwise build default label
                        child: tab.customChild ?? _buildTabLabel(tab),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  /// Builds the default tab label layout with optional icon.
  ///
  /// Creates a row with icon (if provided) and text label. Used when
  /// `AppTabItem.customChild` is not specified. Ensures consistent spacing
  /// and typography across all default-style tabs.
  Widget _buildTabLabel(AppTabItem tab) {
    return Row(
      // Minimal width to fit content
      mainAxisSize: MainAxisSize.min,
      // Center content horizontally within tab
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Icon with consistent sizing from design tokens
        if (tab.icon != null) ...[
          Icon(tab.icon, size: IconSizes.md),
          // Standard spacing between icon and text
          SizedBox(width: 10.w),
        ],
        // Flexible text container prevents overflow
        Flexible(
          child: Text(
            tab.label,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
