import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_text_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
    return Padding(
      padding: EdgeInsets.all(Spacing.md.w),
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

          AppTextButton(text: actionLabel, onPressed: onPressed),
        ],
      ),
    );
  }
}
