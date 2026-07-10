import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/providers/theme_provider.dart';

// Helper widget that rebuilds when theme changes
class ThemeConsumer extends ConsumerWidget {
  final Widget Function(BuildContext context, bool isDarkMode) builder;

  const ThemeConsumer({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeProvider.notifier).isDarkMode(context);
    return builder(context, isDarkMode);
  }
}

// Example usage:
/*
ThemeConsumer(
  builder: (context, isDarkMode) {
    return Container(
      color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
      child: Text(
        'Content',
        style: TextStyle(
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
    );
  },
)
*/
