import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:flutter/material.dart';

/// A section title over one card of rows, as Planning's lists are laid out.
class TogetherSection extends StatelessWidget {
  const TogetherSection({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.md,
            Spacing.lg,
            0,
          ),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        Padding(
          padding: Spacing.allMd,
          child: CardInkWell(
            margin: EdgeInsets.zero,
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}
