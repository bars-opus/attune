// Keep the simple HomeTab model
import 'package:attune/core/utils/exports/export_packages.dart';

class HomeTab {
  final String id;
  final String label;
  final IconData icon;
  final IconData? activeIcon;
  final Widget screen;
  final Color? iconColor;
  final Color? activeIconColor;
  final Color? labelColor;
  final Color? activeLabelColor;
  final int badgeCount;

  const HomeTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.screen,
    this.activeIcon,
    this.iconColor,
    this.activeIconColor,
    this.labelColor,
    this.activeLabelColor,
    this.badgeCount = 0,
  });
}
