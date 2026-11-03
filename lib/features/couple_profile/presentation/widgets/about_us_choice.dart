import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One answer to an About us question, as a radio card (Spec 1 §2.2 150 ms
/// selection, §2.3: 48 dp, read as one item with its helper line, the
/// radio state announced).
class AboutUsChoice extends StatelessWidget {
  const AboutUsChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.helper,
  });

  final String label;
  final String? helper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = flowAccent(context);
    final duration =
        reduceMotionOf(context) ? Duration.zero : kSelectionDuration;
    void tap() {
      if (!selected) HapticFeedback.selectionClick();
      onTap();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Semantics(
        container: true,
        button: true,
        inMutuallyExclusiveGroup: true,
        checked: selected,
        label: [label, if (helper != null) helper!].join('. '),
        // Batch-5 fix round 1 (review I-1): a screen reader can choose it.
        onTap: tap,
        child: ExcludeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: tap,
              borderRadius: BorderRadiusTokens.lgAll,
              child: AnimatedContainer(
                duration: duration,
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.smMd,
                ),
                decoration: BoxDecoration(
                  color: selected ? accent.withValues(alpha: 0.08) : null,
                  borderRadius: BorderRadiusTokens.lgAll,
                  border: Border.all(
                    color: selected ? accent : scheme.outlineVariant,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (helper != null) ...[
                            const SizedBox(height: Spacing.xs),
                            Text(
                              helper!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? accent : scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
