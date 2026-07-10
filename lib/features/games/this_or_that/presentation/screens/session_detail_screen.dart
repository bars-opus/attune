// lib/features/games/this_or_that/presentation/screens/session_detail_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionDetailScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(sessionRoundsProvider(widget.sessionId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sessionAsync = ref.watch(sessionProvider(widget.sessionId));
    final roundsAsync = ref.watch(sessionRoundsProvider(widget.sessionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Session details')),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (session) {
          if (session == null) {
            return const Center(child: Text('Session not found'));
          }

          final matchPercentage = session.matchPercentage;
          final showMatchBar = matchPercentage >= 60;

          return Column(
            children: [
              // Header stats
              Container(
                padding: EdgeInsets.all(Spacing.md.w),
                margin: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat(
                          '${session.matchCount}',
                          'Matches',
                          colorScheme,
                          textTheme,
                        ),
                        _buildStat(
                          '${session.totalRoundsCompleted}',
                          'Rounds',
                          colorScheme,
                          textTheme,
                        ),
                        _buildStat(
                          '${matchPercentage.toStringAsFixed(0)}%',
                          'Match rate',
                          colorScheme,
                          textTheme,
                        ),
                      ],
                    ),
                    if (showMatchBar) ...[
                      Gap(Spacing.md.h),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.sm.r,
                        ),
                        child: LinearProgressIndicator(
                          value: matchPercentage / 100,
                          minHeight: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                    if (!showMatchBar)
                      Padding(
                        padding: EdgeInsets.only(top: Spacing.md.h),
                        child: Text(
                          'You see things differently — that\'s what makes it interesting.',
                          style: textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              // Rounds list
              Expanded(
                child: roundsAsync.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('Error: $error')),
                  data: (rounds) {
                    if (rounds.isEmpty) {
                      return const Center(child: Text('No rounds found'));
                    }

                    return ListView.builder(
                      padding: EdgeInsets.all(Spacing.md.w),
                      itemCount: rounds.length,
                      itemBuilder: (context, index) {
                        final round = rounds[index];
                        final isMatch =
                            round.answerA != null &&
                            round.answerB != null &&
                            round.answerA == round.answerB;
                        return Container(
                          margin: EdgeInsets.only(bottom: Spacing.md.h),
                          padding: EdgeInsets.all(Spacing.md.w),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(
                              BorderRadiusTokens.md.r,
                            ),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Round ${round.roundNumber}',
                                    style: textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isMatch)
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: Spacing.sm.w,
                                        vertical: Spacing.xs.h,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withOpacity(
                                          0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          BorderRadiusTokens.sm.r,
                                        ),
                                      ),
                                      child: Text(
                                        'Matched',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Gap(Spacing.md.h),
                              Text(
                                round.displayQuestionText,
                                style: textTheme.bodyLarge,
                              ),
                              Gap(Spacing.md.h),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildAnswerChip(
                                      'You',
                                      round.answerAText,
                                      colorScheme,
                                      textTheme,
                                    ),
                                  ),
                                  Gap(Spacing.md.w),
                                  Expanded(
                                    child: _buildAnswerChip(
                                      'Partner',
                                      round.answerBText,
                                      colorScheme,
                                      textTheme,
                                    ),
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
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStat(
    String value,
    String label,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
        Text(label, style: textTheme.bodySmall),
      ],
    );
  }

  Widget _buildAnswerChip(
    String label,
    String? answer,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Container(
      padding: EdgeInsets.all(Spacing.sm.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Column(
        children: [
          Text(label, style: textTheme.labelSmall),
          Gap(Spacing.xs.h),
          Text(
            answer ?? 'Not answered',
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color:
                  answer != null
                      ? null
                      : colorScheme.onSurface.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
