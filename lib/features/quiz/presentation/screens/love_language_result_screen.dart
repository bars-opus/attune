// lib/features/quiz/presentation/screens/love_language_result_screen.dart
//
// Spec 5 (R5-5): what feels loving right now, grouped by how much. No type,
// no primary; it can be changed, and shared only by the explicit share.
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:attune/features/quiz/presentation/widgets/share_quiz_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoveLanguageResultScreen extends ConsumerWidget {
  const LoveLanguageResultScreen({super.key, required this.result});

  final LoveLanguageResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isInCouplesMode =
        ref.watch(userRelationshipModeProvider).valueOrNull == 'couples';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          // Back to wherever it was opened from (final review M-3).
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(Spacing.lg.w),
          children: [
            Text(
              'What feels loving to me right now',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              LoveLanguageResult.frameworkNote,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (result.fromEarlierVersion) ...[
              Gap(Spacing.sm.h),
              Text(
                'From your earlier answers. Change them any time.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            Gap(Spacing.lg.h),
            ...LovingWayGroups(result: result).build(context),
            if (result.moments.isNotEmpty) ...[
              Text('Especially', style: textTheme.titleMedium),
              Gap(Spacing.sm.h),
              Wrap(
                spacing: Spacing.sm.w,
                runSpacing: Spacing.sm.h,
                children: [
                  for (final m in LovingMoment.values)
                    if (result.moments.contains(m)) Chip(label: Text(m.label)),
                ],
              ),
              Gap(Spacing.lg.h),
            ],
            Gap(Spacing.md.h),
            if (isInCouplesMode) ...[
              ShareQuizButton(quizType: 'love_language', result: result),
              Gap(Spacing.md.h),
            ],
            AppButton(
              label: 'Change',
              onPressed:
                  () => context.pushReplacementNamed(
                    'loveLanguageQuiz',
                    extra: result,
                  ),
              size: ButtonSize.medium,
              customColor: colorScheme.surfaceContainerHighest,
              textColor: colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

/// "A lot / A little / Not really" with the ways under each; shared with the
/// partner's view of a share.
class LovingWayGroups {
  const LovingWayGroups({required this.result});

  final LoveLanguageResult result;

  List<Widget> build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return [
      for (final rating in LovingRating.values.reversed)
        if (result.rated(rating).isNotEmpty) ...[
          Text(rating.label, style: textTheme.titleMedium),
          Gap(Spacing.xs.h),
          Text(
            result.rated(rating).map((w) => w.label).join(', '),
            style: textTheme.bodyLarge,
          ),
          Gap(Spacing.lg.h),
        ],
    ];
  }
}
