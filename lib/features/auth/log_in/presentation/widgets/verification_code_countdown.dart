import 'package:attune/core/utils/exports/export_screens.dart';

class VerificationCodeCountdown extends StatelessWidget {
  final double? fontSize;
  const VerificationCodeCountdown({
    super.key,
    this.fontSize,
    required this.secondsRemaining,
  });

  final int secondsRemaining;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: AnimatedRollingCounter(
        count: secondsRemaining,
        suffix: 's',
        style: textTheme.bodyLarge?.copyWith(
          color: colorScheme.primary, 
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
