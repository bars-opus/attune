// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_journey_overview_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/community/presentation/widgets/community_questions_entry.dart';
import 'package:attune/features/games/thirty_six_questions/data/models/thirty_six_question_chapter.dart';
import 'package:attune/features/games/thirty_six_questions/data/models/thirty_six_question_journey.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../providers/thirty_six_question_providers.dart';
import '../widgets/thirty_six_continuation_banner.dart';

class ThirtySixJourneyOverviewScreen extends ConsumerWidget {
  final String journeyId;

  const ThirtySixJourneyOverviewScreen({super.key, required this.journeyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final journeyAsync = ref.watch(thirtySixJourneyProvider(journeyId));
    final chaptersAsync = ref.watch(journeyChaptersProvider(journeyId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('36 Questions Journey'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'abandon') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('End this journey?'),
                        content: const Text(
                          'Completed chapters will stay in your history, '
                          'but you won\'t continue to the next chapter.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('End journey'),
                          ),
                        ],
                      ),
                );
                if (confirm == true) {
                  final repository = ref.read(
                    thirtySixQuestionRepositoryProvider,
                  );
                  await repository.abandonJourney(journeyId: journeyId);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                }
              }
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(value: 'abandon', child: Text('End journey')),
                ],
          ),
        ],
      ),
      body: journeyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (journey) {
          if (journey == null) {
            return const Center(child: Text('Journey not found'));
          }

          return chaptersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(child: Text('Error: $error')),
            data: (chapters) {
              final nextChapter = journey.nextChapter;

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(Spacing.lg.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Progress
                          Container(
                            padding: EdgeInsets.all(Spacing.md.w),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(
                                BorderRadiusTokens.md.r,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildChapterProgress(
                                      number: 1,
                                      label: 'Warm Up',
                                      isCompleted:
                                          journey.chapter1CompletedAt != null,
                                      isActive: nextChapter == 1,
                                      colorScheme: colorScheme,
                                      textTheme: textTheme,
                                    ),
                                    Icon(
                                      Icons.arrow_forward,
                                      size: 16,
                                      color: colorScheme.onSurface.withOpacity(
                                        0.3,
                                      ),
                                    ),
                                    _buildChapterProgress(
                                      number: 2,
                                      label: 'Deeper',
                                      isCompleted:
                                          journey.chapter2CompletedAt != null,
                                      isActive: nextChapter == 2,
                                      colorScheme: colorScheme,
                                      textTheme: textTheme,
                                    ),
                                    Icon(
                                      Icons.arrow_forward,
                                      size: 16,
                                      color: colorScheme.onSurface.withOpacity(
                                        0.3,
                                      ),
                                    ),
                                    _buildChapterProgress(
                                      number: 3,
                                      label: 'Vulnerable',
                                      isCompleted:
                                          journey.chapter3CompletedAt != null,
                                      isActive: nextChapter == 3,
                                      colorScheme: colorScheme,
                                      textTheme: textTheme,
                                    ),
                                  ],
                                ),
                                Gap(Spacing.md.h),
                                Text(
                                  journey.isFullyCompleted
                                      ? '✨ Journey complete!'
                                      : 'Chapter ${journey.nextChapter} of 3',
                                  style: textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          Gap(Spacing.xl.h),
                          // Chapter list
                          Text(
                            'Chapters',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Gap(Spacing.md.h),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final chapterNumber = index + 1;
                      final isCompleted = chapters.any(
                        (c) =>
                            c.chapterNumber == chapterNumber && c.isCompleted,
                      );
                      final isActive = chapterNumber == nextChapter;

                      final chapter = _chapterForNumber(
                        chapters,
                        chapterNumber,
                      );
                      return _buildChapterTile(
                        context: context,
                        number: chapterNumber,
                        name: _getChapterName(chapterNumber),
                        isCompleted: isCompleted,
                        isActive: isActive,
                        journey: journey,
                        chapter: chapter,
                      );
                    }, childCount: 3),
                  ),
                  // Continuation banner
                  if (!journey.isFullyCompleted && nextChapter <= 3)
                    SliverToBoxAdapter(
                      child: ThirtySixContinuationBanner(
                        journeyId: journeyId,
                        nextChapter: nextChapter,
                      ),
                    ),
                  // What other couples are asking. Moved off the games
                  // hub, which is being removed — and it belongs beside
                  // the questions rather than on a generic list of games.
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
                    sliver: const SliverToBoxAdapter(
                      child: CommunityQuestionsEntry(),
                    ),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: Spacing.xl.h)),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildChapterProgress({
    required int number,
    required String label,
    required bool isCompleted,
    required bool isActive,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                isCompleted
                    ? colorScheme.primary
                    : isActive
                    ? colorScheme.primary.withOpacity(0.2)
                    : colorScheme.surfaceContainerHighest,
            border: Border.all(
              color:
                  isActive
                      ? colorScheme.primary
                      : colorScheme.outline.withOpacity(0.2),
              width: isActive ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              isCompleted ? '✓' : '$number',
              style: TextStyle(
                color:
                    isCompleted
                        ? colorScheme.onPrimary
                        : isActive
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.5),
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
        Gap(Spacing.xs.h),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color:
                isCompleted
                    ? colorScheme.primary
                    : colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildChapterTile({
    required BuildContext context,
    required int number,
    required String name,
    required bool isCompleted,
    required bool isActive,
    required ThirtySixQuestionJourney journey,
    required ThirtySixQuestionChapter? chapter,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: Spacing.lg.w,
        vertical: Spacing.xs.h,
      ),
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(
          color:
              isCompleted
                  ? colorScheme.primary.withOpacity(0.2)
                  : isActive
                  ? colorScheme.primary.withOpacity(0.3)
                  : colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isCompleted
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
          child: Text(
            isCompleted ? '✓' : '$number',
            style: TextStyle(color: isCompleted ? colorScheme.onPrimary : null),
          ),
        ),
        title: Text(name, style: textTheme.titleMedium),
        subtitle: Text(
          isCompleted
              ? 'Completed'
              : isActive
              ? 'Ready to start'
              : 'Locked',
          style: textTheme.bodySmall?.copyWith(
            color:
                isCompleted
                    ? colorScheme.primary
                    : isActive
                    ? colorScheme.primary
                    : colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        trailing:
            isCompleted
                ? TextButton(
                  onPressed: () {
                    // Show chapter history
                  },
                  child: const Text('View'),
                )
                : isActive
                ? TextButton(
                  onPressed: () {
                    // Start chapter
                    if (chapter != null) {
                      context.pushNamed(
                        'thirtySixChapterIntroduction',
                        extra: (
                          sessionId: chapter.sessionId,
                          chapter: chapter.chapterNumber,
                        ),
                      );
                    }
                  },
                  child: const Text('Start'),
                )
                : const Icon(Icons.lock_outline, size: 16),
      ),
    );
  }

  String _getChapterName(int chapter) {
    switch (chapter) {
      case 1:
        return 'Warm Up';
      case 2:
        return 'Deeper';
      case 3:
        return 'Vulnerable';
      default:
        return 'Chapter $chapter';
    }
  }

  ThirtySixQuestionChapter? _chapterForNumber(
    List<ThirtySixQuestionChapter> chapters,
    int chapterNumber,
  ) {
    for (final chapter in chapters) {
      if (chapter.chapterNumber == chapterNumber) return chapter;
    }
    return null;
  }
}
