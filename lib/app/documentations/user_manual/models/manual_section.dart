// lib/features/documentation/data/models/documentation_section.dart
import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';

// models/manual_section.dart
class ManualSection {
  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<ManualContent> contents;
  final int order;
  final String category;
  final Color? iconColor; // Use token reference
  final Color? titleColor; // Use token reference

  const ManualSection({
    required this.id,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.contents,
    this.order = 0,
    this.category = 'General',
    this.iconColor,
    this.titleColor,
  });
}

