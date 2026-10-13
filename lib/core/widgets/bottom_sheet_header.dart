import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/buttons/app_text_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class BottomSheetHeader extends StatelessWidget {
  final String title;

  /// What Done does. Without it, Done closes the sheet.
  final VoidCallback? onPressed;
  const BottomSheetHeader({super.key, required this.title, this.onPressed});

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

          AppTextButton(onPressed: onPressed),
        ],
      ),
    );
  }
}
