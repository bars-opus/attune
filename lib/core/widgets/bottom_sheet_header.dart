import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_text_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

const double _minTap = 44;

/// Half of what the 44 dp target adds over the label's own height.
const double _tapSlack = 10;

class BottomSheetHeader extends StatelessWidget {
  final String title;

  /// What the button does. Without it, the button closes the sheet.
  final VoidCallback? onPressed;

  /// The button's word: "Done" by default. A sheet whose button saves what
  /// was entered says "Save", so people know to tap it.
  final String actionLabel;
  const BottomSheetHeader({
    super.key,
    required this.title,
    this.onPressed,
    this.actionLabel = 'Done',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Spec 5 (R5-13, plan review I5): the action is a 44 x 44 dp target
    // (AppTextButton stays shrink-wrapped everywhere else); the vertical
    // padding gives back the difference so the header is no taller.
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.md.w,
        vertical: (Spacing.md.w - _tapSlack).clamp(0, double.infinity),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
          AppTextButton(
            text: actionLabel,
            onPressed: onPressed,
            minimumSize: const Size(_minTap, _minTap),
          ),
        ],
      ),
    );
  }
}
