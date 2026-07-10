// lib/features/settings/screens/settings_screen.dart
import 'package:attune/features/settings/utility/settings_exports.dart';

/// Main Settings screen displaying categorized user preferences and app configurations.
///
/// This screen serves as the central hub for all user-configurable settings,
/// organized into logical sections with appropriate headers and visual grouping.
/// It follows Material Design guidelines for settings interfaces and integrates
/// with the app's design system for consistent styling.
///
/// ## Screen Architecture
/// ```
/// ┌─────────────────────────────────────┐
/// │  AppBar: "Settings"                 │
/// │  ← Back Button                      │
/// ├─────────────────────────────────────┤
/// │                                     │
/// │  [Section 1 Header]                 │
/// │  • Title                            │
/// │  • Optional subtitle                │
/// │                                     │
/// │  ┌─────────────────────────────┐   │
/// │  │  CardInkWell Container      │   │
/// │  │  ┌───────────────────────┐  │   │
/// │  │  │   SettingsItem        │  │   │
/// │  │  ├───────────────────────┤  │   │
/// │  │  │   SettingsItem        │  │   │
/// │  │  └───────────────────────┘  │   │
/// │  └─────────────────────────────┘   │
/// │                                     │
/// │  [Section 2 Header]                 │
/// │  • Title                            │
/// │                                     │
/// │  ┌─────────────────────────────┐   │
/// │  │  CardInkWell Container      │   │
/// │  │  ┌───────────────────────┐  │   │
/// │  │  │   SettingsItem        │  │   │
/// │  │  └───────────────────────┘  │   │
/// │  └─────────────────────────────┘   │
/// │                                     │
/// │  [App Info Footer]                  │
/// │  • App Version 1.2.3                │
/// │  • © 2024 App Name                  │
/// │                                     │
/// └─────────────────────────────────────┘
/// ```
///
/// ## Key Design Features
/// 1. **Section-based organization**: Logical grouping of related settings
/// 2. **Visual hierarchy**: Clear headers with optional subtitles
/// 3. **Card containers**: Settings items grouped in elevated cards with subtle borders
/// 4. **App info footer**: Displays version and copyright information
/// 5. **Responsive layout**: Uses `CustomScrollView` with slivers for smooth scrolling
/// 6. **Design system integration**: Consistent spacing, typography, and colors
///
/// ## Data Flow
/// Settings structure is dynamically loaded from `SettingsDataSource.getSettingsSections(context)`,
/// which should return context-aware settings based on:
/// - User authentication state
/// - Feature flags and permissions
/// - Platform-specific settings
/// - Localization requirements
///
/// ## Usage Context
/// This screen is typically accessed from:
/// - Main navigation drawer or menu
/// - Profile screen overflow menu
/// - App information/About screen
///
/// ## Extension Points
/// ```dart
/// // Add search functionality
/// SliverPersistentHeader(
///   pinned: true,
///   delegate: _SearchHeaderDelegate(),
/// )
///
/// // Add pull-to-refresh
/// RefreshIndicator(
///   onRefresh: _refreshSettings,
///   child: CustomScrollView(...),
/// )
///
/// // Add quick actions floating button
/// FloatingActionButton.extended(
///   onPressed: () => _exportSettings(),
///   label: Text('Export'),
///   icon: Icon(Icons.save_alt),
/// )
/// ```
class SettingsScreen extends StatelessWidget {
  final String currentUserId;

  /// Creates the main Settings screen with dynamically loaded sections.
  ///
  /// The screen structure is fixed, but content is dynamically loaded from
  /// `SettingsDataSource.getSettingsSections` to support different user contexts,
  /// feature availability, and platform-specific settings.
  const SettingsScreen({super.key, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    // Access theme for consistent styling
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Dynamically load settings sections based on context
    final sections = SettingsDataSource.getSettingsSections(
      context,
      currentUserId,
    );

    // Access localization for language prefence
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      // AppBar with back navigation and transparent background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: true,
        title: Text(
          loc.settingsScreenTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ),
      // CustomScrollView enables smooth scrolling with sliver-based optimization
      body: CustomScrollView(
        slivers: [
          // Dynamically generate sliver lists for each settings section
          // Using spread operator to flatten list of SliverList widgets
          ...sections.map((section) {
            return SliverList(
              delegate: SliverChildListDelegate([
                // Section header with title and optional subtitle
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    Spacing.lg.w, // Left
                    0, // Top
                    Spacing.lg.w, // Right
                    0, // Bottom (no bottom padding)
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section title with medium opacity for visual hierarchy
                      if (section.title.isNotEmpty) ...[
                        Text(
                          section.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface.withOpacity(0.8),
                          ),
                        ),
                      ],
                      // // Optional subtitle for additional context
                      // if (section.subtitle != null) ...[
                      //   Gap(2.h), // Tiny gap between title and subtitle
                      //   Text(
                      //     section.subtitle!,
                      //     style: theme.textTheme.bodySmall?.copyWith(
                      //       color: colorScheme.onSurface.withOpacity(0.5),
                      //     ),
                      //   ),
                      // ],
                    ],
                  ),
                ),

                // Section items wrapped in CardInkWell container
                Padding(
                  padding: Spacing.allMd, // Medium padding around card
                  child: CardInkWell(
                    margin: EdgeInsets.all(
                      0,
                    ), // No external margin (handled by padding)
                    // Currently empty - could expand/collapse or show section info
                    onTap: () {
                      // Potential implementations:
                      // 1. Expand/collapse section content
                      // 2. Navigate to section details
                      // 3. Show section description
                    },
                    child: Column(
                      // Generate SettingsItem widgets for each item in the section
                      children:
                          section.items
                              .map(
                                (item) => SettingsItem(
                                  config: item,
                                  // Show dividers between items, but not after the last one
                                  showDivider:
                                      section.items.indexOf(item) <
                                      section.items.length - 1,
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ),
              ]),
            );
          }).toList(),

          // App information footer (non-scrollable box adapter)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(
                Spacing.lg.h,
              ), // Large padding around footer
              child: Column(
                children: [
                  // App version from constants (e.g., "App Version 1.2.3")
                  Text(
                    'App Version ${AppConstants.appVersion}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  // Small gap between version and copyright
                  Gap(4.h),
                  // Copyright information with dynamic year
                  Text(
                    '© ${DateTime.now().year} ${AppConstants.appDeveloper}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(
                        0.4,
                      ), // Even lower opacity
                    ),
                  ),
                  // Extra-large spacing at bottom for visual balance
                  Gap(Spacing.xl.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
