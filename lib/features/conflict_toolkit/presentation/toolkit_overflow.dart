import 'package:attune/features/safety/presentation/outside_perspective_screen.dart';
import 'package:flutter/material.dart';

/// Every toolkit tool's overflow carries the outside-perspective card
/// (research 06 B10; plan review I17).
class ToolkitOverflowButton extends StatelessWidget {
  const ToolkitOverflowButton({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: 'More',
    icon: const Icon(Icons.more_vert),
    onSelected:
        (_) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const OutsidePerspectiveScreen(),
          ),
        ),
    itemBuilder:
        (_) => const [
          PopupMenuItem(value: 0, child: Text('A trained outside perspective')),
        ],
  );
}

/// The shared top row of a toolkit sheet.
class ToolkitSheetTitle extends StatelessWidget {
  const ToolkitSheetTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const ToolkitOverflowButton(),
      ],
    );
  }
}
