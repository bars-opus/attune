import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/home/widgets/semantic_container_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class ForumTopicCard extends StatelessWidget {
  const ForumTopicCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: SemanticContainerWidget(
        content: subtitle,
        icon: Icons.lock_outline,
        title: title,
        backgroundColor: colorScheme.onBackground.withOpacity(0.1),
        borderColor: colorScheme.onBackground,
        iconColor: colorScheme.onBackground,
        textTheme: textTheme,
      ),
    );
  }
}
