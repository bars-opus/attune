import 'package:attune/core/utils/exports/export_packages.dart';

class DocumentationItem {
  final String id;
  final String title;
  final String? subtitle;
  final String? footerText;
  final IconData? icon;
  final Color? iconColor;

  const DocumentationItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.footerText,
    this.icon,
    this.iconColor,
  });
}
