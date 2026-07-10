import 'package:attune/core/utils/exports/export_screens.dart';

class HighlightContainer extends StatelessWidget {
  final Color? color;
    final double? padding;

  final Widget child;
  const HighlightContainer({super.key, this.color, required this.child, this.padding });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(padding?? Spacing.md.h),
      decoration: BoxDecoration(
        color: color ?? colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: colorScheme.primary.withOpacity(0.1)),
      ),
      child: child,
    );
  }
}
