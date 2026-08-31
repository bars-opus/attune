import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/community/presentation/widgets/community_questions_entry.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThisOrThatGamesHubScreen extends ConsumerWidget {
  const ThisOrThatGamesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sessionAsync = ref.watch(activeThisOrThatSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('This or That')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick picks, shared surprises, and low-pressure conversation starters.',
              style: textTheme.bodyMedium,
            ),
            Gap(Spacing.lg.h),
            // Before starting: what other couples are asking for THIS
            // game. Moved off the games hub, which is being removed —
            // and it belongs here anyway, where the questions are.
            const CommunityQuestionsEntry(typeFilter: 'This or That'),
            Gap(Spacing.lg.h),
            sessionAsync.when(
              loading:
                  () => const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              error: (_, __) => const SizedBox.shrink(),
              data: (session) {
                if (session == null) {
                  return SemanticContainerWidget(
                    title: 'Ready when you are',
                    content:
                        'Start a 10-round game with your partner. The flow stays private to your relationship workspace.',
                    icon: Icons.sports_esports_outlined,
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                    borderColor: colorScheme.primary,
                    iconColor: colorScheme.primary,
                    textTheme: textTheme,
                  );
                }

                final actionLabel =
                    session.status == 'invited'
                        ? 'Open invitation'
                        : 'Resume game';
                final statusLabel =
                    session.status == 'invited'
                        ? 'An invitation is waiting.'
                        : 'You have an active session in progress.';

                return SemanticContainerWidget(
                  title: 'Active session',
                  content: statusLabel,
                  icon: Icons.favorite,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                  borderColor: colorScheme.primary,
                  iconColor: colorScheme.primary,
                  textTheme: textTheme,
                  child: Padding(
                    padding: EdgeInsets.only(top: Spacing.md.h),
                    child: AppButton(
                      label: actionLabel,
                      onPressed: () {
                        context.pushNamed(
                          'thisOrThatSessionRouter',
                          extra: session.id,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            Gap(Spacing.lg.h),
            AppButton(
              label: 'Play',
              onPressed: () {
                context.pushNamed('thisOrThatToneSelector');
              },
              width: double.infinity,
              size: ButtonSize.large,
            ),
            Gap(Spacing.md.h),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Custom questions',
                    onPressed: () {
                      context.pushNamed('customQuestionList');
                    },
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: 'History',
                    onPressed: () {
                      context.pushNamed('thisOrThatSessionHistory');
                    },
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
