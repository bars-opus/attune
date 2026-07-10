// lib/features/games/truth_or_dare/presentation/screens/truth_or_dare_history_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TruthOrDareHistoryScreen extends ConsumerStatefulWidget {
  const TruthOrDareHistoryScreen({super.key});

  @override
  ConsumerState<TruthOrDareHistoryScreen> createState() =>
      _TruthOrDareHistoryScreenState();
}

class _TruthOrDareHistoryScreenState
    extends ConsumerState<TruthOrDareHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(truthOrDareSessionHistoryProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final historyAsync = ref.watch(truthOrDareSessionHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game history'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(truthOrDareSessionHistoryProvider);
          await ref.read(truthOrDareSessionHistoryProvider.future);
        },
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('Error: $error')),
          data: (sessions) {
            if (sessions.isEmpty) {
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
                    Text(
                      'No game history yet',
                      style: textTheme.titleMedium,
                    ),
                    Gap(Spacing.sm.h),
                    Text(
                      'Play a game of Truth or Dare to see your history here.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: EdgeInsets.all(Spacing.md.w),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final date = DateTime.parse(session['created_at']);
                final tone = session['tone'] as String;
                final truthsCount = session['truths_count'] ?? 0;
                final daresCount = session['dares_count'] ?? 0;
                final totalRounds = truthsCount + daresCount;

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
                          // Game icon
                          const Text('🎲', style: TextStyle(fontSize: 16)),
                          Gap(Spacing.sm.w),
                          Text(
                            'Truth or Dare',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          // Tone badge
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: Spacing.sm.w,
                              vertical: Spacing.xs.h,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(
                                BorderRadiusTokens.sm.r,
                              ),
                            ),
                            child: Text(
                              _getToneDisplay(tone),
                              style: textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Gap(Spacing.sm.h),
                      // Date
                      Text(
                        '${date.day} ${_getMonth(date.month)} ${date.year}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      Gap(Spacing.md.h),
                      // Stats
                      Row(
                        children: [
                          _buildStatChip(
                            'Truths: $truthsCount',
                            Colors.green,
                            colorScheme,
                          ),
                          Gap(Spacing.sm.w),
                          _buildStatChip(
                            'Dares: $daresCount',
                            Colors.orange,
                            colorScheme,
                          ),
                          Gap(Spacing.sm.w),
                          _buildStatChip(
                            'Rounds: $totalRounds',
                            colorScheme.primary,
                            colorScheme,
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
    );
  }

  Widget _buildStatChip(String label, Color color, ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w, vertical: Spacing.xs.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  String _getToneDisplay(String tone) {
    switch (tone) {
      case 'connecting':
        return 'Connecting';
      case 'romantic':
        return 'Romantic';
      case 'playful':
        return 'Playful';
      case 'spicy':
        return 'Spicy';
      case 'intimate':
        return 'Intimate';
      default:
        return tone;
    }
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
      'Dec'
    ];
    return months[month - 1];
  }
}
