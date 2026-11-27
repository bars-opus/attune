// Development only: the liquid glass gallery on its own.
//   flutter run -t lib/core/ui/glass/preview/glass_preview_main.dart
import 'package:attune/core/ui/glass/preview/glass_gallery.dart';
import 'package:flutter/material.dart';

void main() => runApp(const GlassPreviewApp());

class GlassPreviewApp extends StatefulWidget {
  const GlassPreviewApp({super.key});

  @override
  State<GlassPreviewApp> createState() => _GlassPreviewAppState();
}

class _GlassPreviewAppState extends State<GlassPreviewApp> {
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6750A4), useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: GlassGallery(
        onToggleTheme: () => setState(
          () => _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
        ),
      ),
    );
  }
}
