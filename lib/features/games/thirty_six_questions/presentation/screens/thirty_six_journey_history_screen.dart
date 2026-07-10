// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_journey_history_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'thirty_six_chapter_history_screen.dart';

class ThirtySixJourneyHistoryScreen extends ConsumerWidget {
  const ThirtySixJourneyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final journeysAsync = ref.watch(thirtySixJourneysProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey history'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: journeysAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (journeys) {
          if (journeys.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_outlined,
                    size: 64,
                    color: colorScheme.onSurface.withOpacity(0.3),
                  ),
                  Gap(Spacing.md.h),
                  Text('No journey history yet', style: textTheme.titleMedium),
                  Gap(Spacing.sm.h),
                  Text(
                    'Complete a 36 Questions Journey to see your history here.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(Spacing.md.w),
            itemCount: journeys.length,
            itemBuilder: (context, index) {
              final journey = journeys[index];
              final chapterCount = journey.completedChapters;

              return Container(
                margin: EdgeInsets.only(bottom: Spacing.md.h),
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('💬', style: TextStyle(fontSize: 20)),
                        Gap(Spacing.sm.w),
                        Text(
                          '36 Questions Journey',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: Spacing.sm.w,
                            vertical: Spacing.xs.h,
                          ),
                          decoration: BoxDecoration(
                            color:
                                journey.isCompleted
                                    ? colorScheme.primary.withOpacity(0.1)
                                    : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              BorderRadiusTokens.sm.r,
                            ),
                          ),
                          child: Text(
                            journey.isCompleted ? 'Complete' : 'In progress',
                            style: textTheme.labelSmall?.copyWith(
                              color:
                                  journey.isCompleted
                                      ? colorScheme.primary
                                      : colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Gap(Spacing.sm.h),
                    Text(
                      '${_formatDate(journey.createdAt)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                    Gap(Spacing.md.h),
                    Row(
                      children: List.generate(3, (index) {
                        final isCompleted = index < chapterCount;
                        return Container(
                          margin: EdgeInsets.only(right: Spacing.sm.w),
                          padding: EdgeInsets.symmetric(
                            horizontal: Spacing.sm.w,
                            vertical: Spacing.xs.h,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isCompleted
                                    ? colorScheme.primary.withOpacity(0.1)
                                    : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              BorderRadiusTokens.sm.r,
                            ),
                          ),
                          child: Text(
                            'Ch${index + 1}',
                            style: textTheme.labelSmall?.copyWith(
                              color:
                                  isCompleted
                                      ? colorScheme.primary
                                      : colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        );
                      }),
                    ),
                    Gap(Spacing.md.h),
                    if (journey.isCompleted)
                      Row(
                        children: [
                          if (journey.hasFinalObservation)
                            Text(
                              '✨ Has reflection',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              // Navigate to journey chapters
                              _showJourneyChapters(context, ref, journey.id);
                            },
                            child: const Text('View chapters →'),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_getMonth(date.month)} ${date.year}';
  }

  String _getMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  void _showJourneyChapters(
    BuildContext context,
    WidgetRef ref,
    String journeyId,
  ) {
    final chaptersAsync = ref.watch(journeyChaptersProvider(journeyId));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.8,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder:
                (context, scrollController) => chaptersAsync.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('Error: $error')),
                  data: (chapters) {
                    if (chapters.isEmpty) {
                      return const Center(child: Text('No chapters found'));
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.all(Spacing.md.w),
                      itemCount: chapters.length,
                      itemBuilder: (context, index) {
                        final chapter = chapters[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text('${chapter.chapterNumber}'),
                          ),
                          title: Text(_getChapterName(chapter.chapterNumber)),
                          subtitle: Text(
                            chapter.isCompleted ? 'Completed' : 'In progress',
                          ),
                          trailing:
                              chapter.isCompleted
                                  ? TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) =>
                                                  ThirtySixChapterHistoryScreen(
                                                    sessionId:
                                                        chapter.sessionId,
                                                    chapter:
                                                        chapter.chapterNumber,
                                                  ),
                                        ),
                                      );
                                    },
                                    child: const Text('View'),
                                  )
                                  : null,
                        );
                      },
                    );
                  },
                ),
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
}
