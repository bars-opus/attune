// lib/features/documentation/data/models/documentation_section.dart
import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';

/// A titled group of [ManualContent] blocks. Sections render in the order
/// a module lists them; `order` and `category` are metadata only.
class ManualSection {
  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<ManualContent> contents;
  final int order;
  final String category;

  const ManualSection({
    required this.id,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.contents,
    this.order = 0,
    this.category = 'General',
  });
}

