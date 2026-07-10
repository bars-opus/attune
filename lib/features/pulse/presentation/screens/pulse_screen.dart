// lib/features/pulse/presentation/screens/pulse_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/pulse/data/models/pulse_score.dart';
import 'package:attune/features/pulse/presentation/screens/weekly_checkin_screen.dart';
import 'package:attune/features/pulse/presentation/widgets/dimension_row.dart';
import 'package:attune/features/pulse/presentation/widgets/number_view.dart';
import 'package:attune/features/pulse/presentation/widgets/radar_chart.dart';
import 'package:attune/features/pulse/presentation/widgets/ring_chart.dart';
import 'package:attune/features/pulse/presentation/widgets/checkin_banner.dart';
import 'package:attune/features/pulse/presentation/widgets/trend_chart.dart';
import 'package:attune/features/pulse/presentation/widgets/visualisation_switcher.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_type_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PulseScreen extends ConsumerStatefulWidget {
  const PulseScreen({super.key});

  @override
  ConsumerState<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends ConsumerState<PulseScreen> {
  String _selectedVisualisation = 'ring';
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadUserPreference();
  }

  Future<void> _loadUserPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('pulse_visualisation');
    if (saved != null && mounted) {
      setState(() => _selectedVisualisation = saved);
    }
  }

  Future<void> _saveVisualisationPreference(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pulse_visualisation', value);
  }

  Future<void> _refreshPulse() async {
    setState(() => _isRefreshing = true);
    try {
      final relationshipId = await ref.read(
        currentRelationshipIdProvider.future,
      );
      if (relationshipId != null) {
        await ref.read(recomputePulseProvider(relationshipId).future);
        ref.invalidate(currentPulseScoreProvider);
        ref.invalidate(pulseHistoryProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pulseAsync = ref.watch(currentPulseScoreProvider);
    final historyAsync = ref.watch(pulseHistoryProvider);

    return RefreshIndicator(
      onRefresh: _refreshPulse,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(Spacing.md.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Text(
                        'Pulse',
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (!_isRefreshing)
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _refreshPulse,
                        ),
                      if (_isRefreshing)
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                  Gap(Spacing.sm.h),
                  Text(
                    'Updated ${_getLastUpdatedText(pulseAsync)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  Gap(Spacing.md.h),

                  // Main content
                  pulseAsync.when(
                    loading:
                        () => const Center(child: CircularProgressIndicator()),
                    error:
                        (error, stack) => Center(child: Text('Error: $error')),
                    data: (pulse) {
                      if (pulse == null) {
                        return _buildNoDataState();
                      }

                      // Build dimension map for visualisations
                      final dimensions = {
                        'Communication': pulse.communication,
                        'Connection': pulse.connection,
                        'Conflict Health': pulse.conflictHealth,
                        'Alignment': pulse.alignment,
                        'Emotional Safety': pulse.emotionalSafety,
                      };

                      final deltas = {
                        'Communication': pulse.getDeltaForDimension(
                          'communication',
                        ),
                        'Connection': pulse.getDeltaForDimension('connection'),
                        'Conflict Health': pulse.getDeltaForDimension(
                          'conflict_health',
                        ),
                        'Alignment': pulse.getDeltaForDimension('alignment'),
                        'Emotional Safety': pulse.getDeltaForDimension(
                          'emotional_safety',
                        ),
                      };

                      return Column(
                        children: [
                          // Visualisation switcher
                          VisualisationSwitcher(
                            currentVisualisation: _selectedVisualisation,
                            onChanged: (value) {
                              setState(() => _selectedVisualisation = value);
                              _saveVisualisationPreference(value);
                            },
                          ),
                          Gap(Spacing.lg.h),

                          // Selected visualisation
                          _buildVisualisation(
                            _selectedVisualisation,
                            pulse.overallScore,
                            dimensions,
                            deltas,
                          ),
                          Gap(Spacing.xl.h),

                          // Data confidence display
                          _buildConfidenceDisplay(pulse.dataConfidence),
                          Gap(Spacing.md.h),

                          // Dimensions rows
                          Text(
                            'Dimensions',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Gap(Spacing.md.h),

                          ...dimensions.keys.map((key) {
                            return Padding(
                              padding: EdgeInsets.only(bottom: Spacing.md.h),
                              child: DimensionRow(
                                label: key,
                                score: dimensions[key]!,
                                delta: deltas[key],
                                confidence: pulse.getConfidenceForDimension(
                                  _getDimensionKey(key),
                                ),
                                onTap:
                                    () => _showDimensionTooltip(
                                      key,
                                      dimensions[key]!,
                                      pulse.getConfidenceForDimension(
                                        _getDimensionKey(key),
                                      ),
                                    ),
                              ),
                            );
                          }),

                          Gap(Spacing.xl.h),

                          // Trend chart
                          historyAsync.when(
                            data: (history) => TrendChart(history: history),
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          ),

                          Gap(Spacing.xl.h),

                          // Check-in banner
                          const CheckinBanner(),
                          Gap(Spacing.lg.h),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualisation(
    String type,
    int score,
    Map<String, int> dimensions,
    Map<String, int?> deltas,
  ) {
    switch (type) {
      case 'ring':
        return Center(child: RingChart(score: score));
      case 'radar':
        return Center(child: RadarChart(dimensions: dimensions));
      case 'number':
        return NumberView(
          overallScore: score,
          dimensions: dimensions,
          deltas: deltas,
        );
      default:
        return Center(child: RingChart(score: score));
    }
  }

  Widget _buildConfidenceDisplay(String confidence) {
    final colorScheme = Theme.of(context).colorScheme;
    final textScheme = Theme.of(context).textTheme;

    if (confidence == 'high') return const SizedBox.shrink();

    String message;
    if (confidence == 'none') {
      message =
          'Not enough data yet — complete a check-in to see your first pulse score.';
    } else if (confidence == 'low') {
      message =
          'Based on early data. Your score gets more accurate as you log more moments and complete weekly check-ins.';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colorScheme.primary),
          Gap(Spacing.sm.w),
          Expanded(child: Text(message, style: textScheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _buildNoDataState() {
    return Column(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.show_chart, size: 64, color: Colors.grey),
        Gap(Spacing.md.h),
        Text(
          'No pulse score yet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Gap(Spacing.sm.h),
        Text(
          'Complete your first weekly check-in\nto see your relationship pulse.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Gap(Spacing.lg.h),
        AppButton(
          label: 'Start check-in',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WeeklyCheckinScreen()),
            );
          },
        ),
        Gap(Spacing.md.h), // Add spacing between buttons
        AppButton(
          label: 'Log your first moment',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogMomentTypeScreen()),
            );
          },
          customColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          textColor: Theme.of(context).colorScheme.onSurface,
        ),
      ],
    );
  }

  String _getDimensionKey(String label) {
    switch (label) {
      case 'Communication':
        return 'communication';
      case 'Connection':
        return 'connection';
      case 'Conflict Health':
        return 'conflict_health';
      case 'Alignment':
        return 'alignment';
      case 'Emotional Safety':
        return 'emotional_safety';
      default:
        return '';
    }
  }

  void _showDimensionTooltip(String label, int score, String confidence) {
    final descriptions = {
      'Communication': 'How clearly and kindly you express yourselves',
      'Connection': 'Emotional closeness and warmth',
      'Conflict Health': 'How well you navigate disagreements',
      'Alignment': 'Shared values and direction',
      'Emotional Safety': 'Feeling safe to be vulnerable',
    };

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(label),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Score: $score/100',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(descriptions[label] ?? ''),
                if (confidence == 'low')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Limited data — this will improve with more check-ins and logged moments.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  String _getLastUpdatedText(AsyncValue<PulseScore?> pulseAsync) {
    if (pulseAsync case AsyncData(:final value) when value != null) {
      final date = value.computedAt;
      return '${date.day}/${date.month}/${date.year}';
    }
    return 'Not yet';
  }
}
