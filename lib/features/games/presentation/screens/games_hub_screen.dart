// lib/features/games/presentation/screens/games_hub_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart'
    as thirty_six;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class GamesHubScreen extends ConsumerStatefulWidget {
  const GamesHubScreen({super.key});

  @override
  ConsumerState<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends ConsumerState<GamesHubScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(activeGamesProvider);
      ref.read(recentGamesProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Play together'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // Active games section
          SliverToBoxAdapter(child: _buildActiveGamesSection(context)),
          // Choose a game section
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.lg.w,
              vertical: Spacing.md.h,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Choose a game',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildGameCard(
                  context,
                  gameType: 'this_or_that',
                  icon: '🔀',
                  title: 'This or That',
                  description: 'Quick picks · Any tone · ~5 min',
                  onTap: () => _startGame('this_or_that'),
                ),
                Gap(Spacing.md.h),
                _buildGameCard(
                  context,
                  gameType: 'truth_or_dare',
                  icon: '🎲',
                  title: 'Truth or Dare',
                  description: 'Classic · All tones · ~15 min',
                  onTap: () => _startGame('truth_or_dare'),
                ),
                Gap(Spacing.md.h),
                _buildGameCard(
                  context,
                  gameType: 'paint_ball',
                  icon: '🎯',
                  title: 'Paint Ball',
                  description: 'Timing tap · 3 lives · ~5 min',
                  onTap: () => _startGame('paint_ball'),
                ),
                Gap(Spacing.md.h),
                _buildThirtySixQuestionsCard(context, ref),
                Gap(Spacing.xl.h),
              ]),
            ),
          ),
          // Community questions entry
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
            sliver: SliverToBoxAdapter(child: _buildCommunityEntry(context)),
          ),
          // Past games section
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.lg.w,
              vertical: Spacing.md.h,
            ),
            sliver: SliverToBoxAdapter(child: _buildPastGamesSection(context)),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Container(
                  margin: EdgeInsets.only(bottom: Spacing.sm.h),
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
                  child: Row(
                    children: [
                      const Text('🎲', style: TextStyle(fontSize: 20)),
                      Gap(Spacing.md.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Truth or Dare',
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Playful · Jun 3',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(onPressed: () {}, child: const Text('View')),
                    ],
                  ),
                );
              }, childCount: 2),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.all(Spacing.lg.w),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: TextButton(
                  onPressed: () {
                    // Navigate to full history
                  },
                  child: const Text('View all past games →'),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildActiveGamesSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final activeGames = ref.watch(activeGamesProvider);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.lg.w,
        vertical: Spacing.md.h,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active games',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Gap(Spacing.sm.h),
          activeGames.when(
            loading:
                () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
            error: (error, stack) => const SizedBox.shrink(),
            data: (games) {
              if (games.isEmpty) {
                return Container(
                  padding: EdgeInsets.all(Spacing.md.w),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.md.r,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sports_esports_outlined,
                        color: colorScheme.onSurface.withOpacity(0.3),
                      ),
                      Gap(Spacing.md.w),
                      Text(
                        'No active games',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children:
                    games.map((game) {
                      return Container(
                        margin: EdgeInsets.only(bottom: Spacing.sm.h),
                        padding: EdgeInsets.all(Spacing.md.w),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(
                            BorderRadiusTokens.md.r,
                          ),
                          border: Border.all(
                            color: colorScheme.primary.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text('🎲', style: TextStyle(fontSize: 20)),
                            Gap(Spacing.md.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    game['game_type_display'] ?? 'Game',
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    game['status'] == 'invited'
                                        ? 'Waiting for partner...'
                                        : 'Your turn',
                                    style: textTheme.bodySmall?.copyWith(
                                      color:
                                          game['status'] == 'invited'
                                              ? Colors.orange
                                              : colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AppButton(
                              label: 'Resume',
                              onPressed: () {
                                // Navigate to game
                              },
                              size: ButtonSize.small,
                              width: 90.w,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(
    BuildContext context, {
    required String gameType,
    required String icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 32)),
            Gap(Spacing.md.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            AppButton(
              label: 'Play →',
              onPressed: onTap,
              size: ButtonSize.small,
              width: 90.w,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunityEntry(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () {
        context.pushNamed('communityFeed');
      },
      child: Container(
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withOpacity(0.1),
              colorScheme.primary.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.public, size: 28, color: colorScheme.primary),
            Gap(Spacing.md.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Community questions',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Browse questions from other couples',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPastGamesSection(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final recentGames = ref.watch(recentGamesProvider);

    return recentGames.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
      data: (games) {
        if (games.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Past games',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
          ],
        );
      },
    );
  }

  // Add to games_hub_screen.dart — update the 36 Questions card

  Widget _buildThirtySixQuestionsCard(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final journeyAsync = ref.watch(thirty_six.activeThirtySixJourneyProvider);

    return GestureDetector(
      onTap: () {
        // If journey exists, resume it; otherwise start new
        ref.read(thirty_six.activeThirtySixJourneyProvider.future).then((
          journey,
        ) {
          if (journey != null) {
            // Navigate to journey overview / next chapter
            context.pushNamed('thirtySixJourneyOverview', extra: journey.id);
          } else {
            // Start new journey flow
            _startNewJourney(context, ref);
          }
        });
      },
      child: Container(
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            const Text('💬', style: TextStyle(fontSize: 32)),
            Gap(Spacing.md.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '36 Questions Journey',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Deep connection · 3 chapters of 12 · ~20 min per chapter',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  journeyAsync.when(
                    data: (journey) {
                      if (journey != null) {
                        return Text(
                          'Chapter ${journey.nextChapter} of 3 in progress',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            journeyAsync.when(
              data: (journey) {
                if (journey != null) {
                  return AppButton(
                    label: 'Resume',
                    onPressed: () {
                      context.pushNamed(
                        'thirtySixJourneyOverview',
                        extra: journey.id,
                      );
                    },
                    size: ButtonSize.small,
                    width: 90.w,
                  );
                }
                return AppButton(
                  label: 'Start →',
                  onPressed: () => _startNewJourney(context, ref),
                  size: ButtonSize.small,
                  width: 90.w,
                );
              },
              loading: () => const SizedBox.shrink(),
              error:
                  (_, __) => AppButton(
                    label: 'Start →',
                    onPressed: () => _startNewJourney(context, ref),
                    size: ButtonSize.small,
                    width: 90.w,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _startNewJourney(BuildContext context, WidgetRef ref) {
    final relationshipId = ref.read(
      thirty_six.currentRelationshipIdProvider.future,
    );
    final userId = ref.read(thirty_six.currentUserIdProvider);

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to start the journey.')),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    relationshipId.then((relId) async {
      if (relId == null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active relationship found.')),
        );
        return;
      }

      try {
        final repository = ref.read(
          thirty_six.thirtySixQuestionRepositoryProvider,
        );
        final journey = await repository.createJourney(relationshipId: relId);

        if (context.mounted) {
          Navigator.pop(context); // Close loading

          // Invite to Chapter 1
          final chapter = await ref.read(
            thirty_six.inviteToChapterProvider((
              journeyId: journey.id,
              chapter: 1,
            )).future,
          );

          if (context.mounted) {
            context.pushNamed(
              'thirtySixChapterInvitation',
              extra: (
                sessionId: chapter.sessionId,
                chapter: chapter.chapterNumber,
                isInitiator: true,
              ),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start journey: $e')),
          );
        }
      }
    });
  }

  void _startGame(String gameType) {
    // Navigate to the appropriate game screen
    // This will be implemented when we wire up the game flows
    switch (gameType) {
      case 'this_or_that':
        context.pushNamed('thisOrThatGamesHub');
        break;
      case 'truth_or_dare':
        context.pushNamed('truthOrDareGame');
        break;
      case 'paint_ball':
        _startPaintBall(context, ref);
        break;
      case '36_questions':
        // Navigator.push(
        //   context,
        //   MaterialPageRoute(
        //     builder: (_) => const QuestionsGameScreen(),
        //   ),
        // );
        break;
    }
  }

  void _startPaintBall(BuildContext context, WidgetRef ref) {
    final relationshipId = ref.read(
      thirty_six.currentRelationshipIdProvider.future,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    relationshipId
        .then((relId) {
          if (!context.mounted) return;
          Navigator.pop(context);
          if (relId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No active relationship found.')),
            );
            return;
          }

          context.pushNamed(
            'paintBallLobby',
            pathParameters: {'relationshipId': relId},
          );
        })
        .catchError((error) {
          if (!context.mounted) return;
          Navigator.pop(context);
          // Never surface the raw exception to the user (project convention).
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open Paint Ball. Please try again.'),
            ),
          );
        });
  }
}
