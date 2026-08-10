import 'package:attune/core/utils/exports/export_screens.dart';

class NumberBadge extends StatelessWidget {
  final Color? color;
  const NumberBadge({required this.number, this.color, required this.tag});

  final int number;
  final Object tag;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(Spacing.sm.w),
      decoration: BoxDecoration(
        color: color ?? colorScheme.onSurface,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$number',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.surface,
          ),
        ),
      ),
    );
  }
}
