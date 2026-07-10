// lib/features/settings/models/settings_config.dart
import 'package:attune/core/utils/exports/export_screens.dart';

enum SettingsItemType {
  navigation, // Navigates to another screen
  toggle, // Switch on/off
  action, // Performs immediate action
  link, // Opens external link
  info, // Display only (no interaction)
  destructive, // Dangerous action (red)
}

class SettingsConfig {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final SettingsItemType type;
  final VoidCallback? onTap;
  final bool? value; // For toggle items
  final ValueChanged<bool>? onToggle;
  final String? routeName; // For navigation
  final bool isEnabled;
  final Color? iconColor;
  final Widget? trailing;
  final int order; // For sorting
  final String? url; // For link type
  final WidgetBuilder? modalBuilder; // For modal type

  const SettingsConfig({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.type,
    this.onTap,
    this.value,
    this.onToggle,
    this.routeName,
    this.isEnabled = true,
    this.iconColor,
    this.trailing,
    this.url,
    this.modalBuilder,
    this.order = 0,
  });
}

// Group settings by sections
class SettingsSection {
  final String id;
  final String title;
  final String? subtitle;
  final List<SettingsConfig> items;
  final bool showDivider;

  const SettingsSection({
    required this.id,
    required this.title,
    required this.items,
    this.subtitle,
    this.showDivider = true,
  });
}
