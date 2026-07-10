// lib/features/documentation/data/models/documentation_content.dart
import 'package:flutter/material.dart';

// models/manual_content.dart
class ManualContent {
  final String id;
  final String title;
  final String content;
  final ManualContentType type;
  // final IconData? icon;
  final String? numberPrefix; // NEW: For numbered lists (e.g., "1.", "2.")
  final List<String>? bulletPoints;
  final String? codeSnippet;
  final String? imageUrl;
  final int order;
  // final Color? iconColor;
  final Color? titleColor;
  final Color? backgroundColor;
  final Color? numberColor; // NEW: Color for number prefix

  const ManualContent({
    required this.id,
    required this.title,
    required this.content,
    this.type = ManualContentType.text,
    // this.icon,
    this.numberPrefix, // NEW
    this.bulletPoints,
    this.codeSnippet,
    this.imageUrl,
    this.order = 0,
    // this.iconColor,
    this.titleColor,
    this.backgroundColor,
    this.numberColor, // NEW
  });
}

// This is an ENUM - defines possible content types
enum ManualContentType {
  text, // Regular text content
  bulletList, // Bulleted list content
  code, // Code snippets
  image, // Images with captions
  warning, // Warning boxes
  tip, // Pro tip boxes
  important, // Important notice boxes
}
