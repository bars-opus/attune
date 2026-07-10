// lib/features/games/truth_or_dare/presentation/screens/truth_or_dare_end_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';

class TruthOrDareEndScreen extends StatelessWidget {
  final int userTruths;
  final int userDares;
  final int partnerTruths;
  final int partnerDares;
  final Map<String, dynamic> mostInterestingPick;
  final VoidCallback onPlayAgain;
  final VoidCallback onTryAnotherGame;

  const TruthOrDareEndScreen({
    super.key,
    required this.userTruths,
    required this.userDares,
    required this.partnerTruths,
    required this.partnerDares,
    required this.mostInterestingPick,
    required this.onPlayAgain,
    required this.onTryAnotherGame,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game over!'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          children: [
            Text(
              'Session complete!',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.xl.h),
            // Stats
            _buildStatRow('You', userTruths, userDares, colorScheme, textTheme),
            Gap(Spacing.md.h),
            _buildStatRow('Partner', partnerTruths, partnerDares, colorScheme, textTheme),
            Gap(Spacing.xl.h),
            // Most interesting pick
            if (mostInterestingPick.isNotEmpty) ...[
              const Divider(),
              Gap(Spacing.md.h),
              Text(
                'Most interesting:',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Gap(Spacing.sm.h),
              Text(
                mostInterestingPick['text'] ?? '',
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (mostInterestingPick['answer'] != null) ...[
                Gap(Spacing.sm.h),
                Text(
                  mostInterestingPick['answer'],
                  style: textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
            const Spacer(),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Play again',
                    onPressed: onPlayAgain,
                    size: ButtonSize.medium,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: 'Try another game',
                    onPressed: onTryAnotherGame,
                    size: ButtonSize.medium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int truths, int dares, ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(Icons.question_answer, size: 16, color: Colors.green),
              Gap(Spacing.xs.w),
              Text('$truths Truths'),
            ],
          ),
          Gap(Spacing.md.w),
          Row(
            children: [
              Icon(Icons.flash_on, size: 16, color: Colors.orange),
              Gap(Spacing.xs.w),
              Text('$dares Dares'),
            ],
          ),
        ],
      ),
    );
  }
}
