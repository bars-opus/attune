// lib/features/settings/widgets/settings_item.dart
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

/// A specialized settings list item that adapts its behavior and appearance based on configuration.
///
/// This widget serves as a smart adapter between `SettingsConfig` data models and
/// the visual `InfoRowWidget` component. It interprets settings configuration to
/// provide appropriate interaction patterns, visual styling, and behavior for
/// different types of settings items.
///
/// ## Settings Item Types
/// | Type | Visual Cue | Behavior | Use Case |
/// |------|------------|----------|----------|
/// | **Navigation** | Chevron arrow | Navigates to route | Settings subscreens |
/// | **Toggle** | Switch control | Toggles boolean state | Feature enable/disable |
/// | **Action** | No arrow | Immediate action | Refresh, sync, clear cache |
/// | **Destructive** | Red text/icon | Destructive action | Logout, delete, reset |
/// | **Link** | External link icon | Opens URL | Terms, website, support |
/// | **Info** | Info icon | Shows modal | Documentation, guides |
///
/// ## Architecture Pattern
/// ```
/// SettingsConfig (data model)
///       ↓
///   SettingsItem (adapter/logic)
///       ↓
///  InfoRowWidget (visual component)
/// ```
///
/// ## Key Responsibilities
/// 1. **Type-specific behavior routing**: Maps `SettingsItemType` to appropriate actions
/// 2. **Visual adaptation**: Adjusts colors, icons, and trailing widgets per type
/// 3. **Interaction handling**: Manages taps, toggles, navigation, and external links
/// 4. **State management**: Handles enabled/disabled states and conditional behavior
/// 5. **External integration**: Coordinates with navigation, URL launching, and modals
///
/// ## Usage Example
/// ```dart
/// SettingsItem(
///   config: SettingsConfig(
///     id: 'notifications',
///     title: 'Push Notifications',
///     subtitle: 'Receive app notifications',
///     icon: Icons.notifications,
///     type: SettingsItemType.toggle,
///     value: _notificationsEnabled,
///     onToggle: (value) => setState(() => _notificationsEnabled = value),
///   ),
///   showDivider: true,
/// )
///
/// SettingsItem(
///   config: SettingsConfig(
///     id: 'privacy',
///     title: 'Privacy Policy',
///     subtitle: 'View our privacy practices',
///     icon: Icons.privacy_tip,
///     type: SettingsItemType.link,
///     url: 'https://example.com/privacy',
///   ),
/// )
///
/// SettingsItem(
///   config: SettingsConfig(
///     id: 'logout',
///     title: 'Log Out',
///     subtitle: 'Sign out of your account',
///     icon: Icons.logout,
///     type: SettingsItemType.destructive,
///     iconColor: Colors.red,
///     onTap: () => _confirmLogout(context),
///   ),
/// )
/// ```
class SettingsItem extends StatelessWidget {
  /// Configuration object defining the settings item's behavior and appearance.
  ///
  /// Contains all metadata needed to render and handle the item, including:
  /// - Type, title, subtitle, icon
  /// - Navigation targets or URLs
  /// - Action handlers and state values
  /// - Visual styling overrides
  /// - Enabled/disabled state
  final SettingsConfig config;

  /// Whether to show a divider line below this item when displayed in a list.
  ///
  /// Defaults to `true`. Set to `false` for the last item in a grouped section
  /// or when using alternative visual separation methods.
  final bool showDivider;

  /// Creates a settings item from configuration data.
  ///
  /// [config] is required and provides complete specification of the item's
  /// appearance and behavior. The widget adapts this configuration to produce
  /// appropriate visual representation using `InfoRowWidget`.
  
  const SettingsItem({
    super.key,
    required this.config,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    var modalIcon = Icon(
      Icons.expand_more,
      size: IconSizes.md.h,
      color: colorScheme.onBackground.withOpacity(0.3),
    );
    return InfoRowWidget(
      // Core content from configuration
      title: config.title,
      subtitle: config.subtitle,
      padding: showDivider ? null : EdgeInsets.symmetric(vertical: Spacing.sm),
      icon: config.icon,
      // Disable avatar background for cleaner settings appearance
      showAvatar: false,
      showDivider: showDivider,
      // Visual styling
      backgroundColor: Colors.transparent,
      iconColor: config.iconColor ?? Colors.grey,

      // ✅ CRITICAL: No onTap for toggle items (handled by Switch widget)
      onTap:
          config.type == SettingsItemType.toggle
              ? null // Toggles use Switch interaction, not InkWell
              : (config.isEnabled
                  ? () => _handleTap(context)
                  : null), // Only enabled items are tappable
      // Navigation items show chevron arrows, links show external icon
      showTrailingArrow: config.type != SettingsItemType.link,

      // ✅ Use new toggle parameters (added to InfoRowWidget)
      isToggleItem: config.type == SettingsItemType.toggle,
      toggleValue: config.value,
      onToggleChanged: config.onToggle,

      // Only use trailing for non-toggle custom widgets
      // Toggles use built-in Switch, others can use custom trailing widgets
      trailing:
          config.type == SettingsItemType.info
              ? modalIcon
              : config.type != SettingsItemType.toggle
              ? config.trailing
              : null,

      // Destructive items get special text styling (typically red)
      titleStyle:
          config.type == SettingsItemType.destructive
              ? TextStyle(color: config.iconColor, fontWeight: FontWeight.w500)
              : null,
    );
  }

  /// Handles tap interactions based on the settings item type.
  ///
  /// This method routes tap events to appropriate behaviors:
  /// - **Navigation**: Pushes named routes using path-based navigation
  /// - **Toggle**: No tap handling (Switch widget handles interaction)
  /// - **Action/Destructive**: Executes immediate callback functions
  /// - **Link**: Opens external URLs with feedback and error handling
  /// - **Info**: Displays documentation bottom sheets with context-aware sizing
  ///
  /// Returns early if the item is disabled (`config.isEnabled == false`).
  /// Uses async/await for operations that may complete asynchronously (URL launching).
  void _handleTap(BuildContext context) async {
    // Early exit for disabled items
    if (!config.isEnabled) return;

    // Route behavior based on item type
    switch (config.type) {
      case SettingsItemType.navigation:
        // Navigate to internal screen/route
        if (config.routeName != null) {
          // ✅ Use PATH navigation (consistent with your working example)
          // push() uses path-based navigation rather than MaterialPageRoute
          context.push(config.routeName!);
          // Alternative: context.go(config.routeName!) for go_router
        } else {
          // Fallback to direct callback if no route specified
          config.onTap?.call();
        }
        break;

      case SettingsItemType.toggle:
        // Toggles handle their own interaction via Switch widget
        // No tap handling needed - Switch provides built-in interaction
        break;

      case SettingsItemType.action:
      case SettingsItemType.destructive:
        // Immediate actions (logout, delete account, clear cache, etc.)
        // These execute synchronously and may show confirmation dialogs
        config.onTap?.call();
        break;

      case SettingsItemType.link:
        // Open external URL in browser or appropriate app
        if (config.url != null) {
          // Use utility for consistent URL launching with user feedback
          await UrlLauncherUtils.launchUrlWithFeedback(
            context: context,
            url: config.url!,
            errorMessage: 'Cannot open this link',
          );
        } else {
          // Fallback to callback if no URL specified
          config.onTap?.call();
        }
        break;

      case SettingsItemType.info:
        // Open documentation or informational modal
        BottomSheetUtils.showDocumentationBottomSheet(
          context: context,
          // Info items are typically view-only (no agree/decline)
          showButtons: false,
          // Dynamic sizing: full guide gets 90% height, others get 70%
          maxHeight:
              config.id == 'guide'
                  ? null // Use default (90%)
                  : MediaQuery.of(context).size.height * 0.7, // 70% for others
          // Dynamic content: guide shows full DocumentationScreen, others show legal docs
          widget:
              config.id == 'guide'
                  ? DocumentationScreen()
                  : AllLegalDocumentationsScreen(),
        );
        break;
    }
  }
}
