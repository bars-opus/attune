// lib/features/pulse/presentation/screens/pulse_screen.dart

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/pulse/data/models/pulse_score.dart';
import 'package:attune/features/pulse/presentation/widgets/dimension_row.dart';
import 'package:attune/features/pulse/presentation/widgets/number_view.dart';
import 'package:attune/features/pulse/presentation/widgets/radar_chart.dart';
import 'package:attune/features/pulse/presentation/widgets/ring_chart.dart';
import 'package:attune/features/pulse/presentation/widgets/checkin_banner.dart';
import 'package:attune/features/pulse/presentation/widgets/trend_chart.dart';
import 'package:attune/features/pulse/presentation/widgets/visualisation_switcher.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PulseScreen extends ConsumerStatefulWidget {
  const PulseScreen({super.key});

  @override
  ConsumerState<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends ConsumerState<PulseScreen>
    with AutomaticKeepAliveClientMixin {
  String _selectedVisualisation = 'ring';
  bool _isRefreshing = false;

  // Keeps this tab's state (loaded data, selected visualisation, scroll
  // position) alive when TabBarView scrolls it off-screen switching tabs,
  // instead of disposing and rebuilding from scratch every time the user
  // comes back to Pulse.
  @override
  bool get wantKeepAlive => true;

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
    super.build(context); // AutomaticKeepAliveClientMixin requirement
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pulseAsync = ref.watch(currentPulseScoreProvider);
    final historyAsync = ref.watch(pulseHistoryProvider);

    return RefreshIndicator(
      onRefresh: _refreshPulse,
      child: CustomScrollView(
        slivers: [
          // Required whenever this scrollable lives inside PulseTab's
          // NestedScrollView (its only current host — see PulseTab's own
          // doc comment) — redirects the header's layout extent here so
          // this list doesn't render as if it starts under the header while
          // its own scroll offset still reads as zero.
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(Spacing.md.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Gap(Spacing.lg.h),
                  // Header
                  InfoRowWidget(
                    title: _getLastUpdatedText(pulseAsync),
                    subtitle: 'Last updated date',
                    icon: Icons.trending_down,
                    iconSize: 0,
                    showAvatar: false,
                    showTrailingArrow: true,
                    iconColor: Colors.grey,
                    showDivider: false,
                    onTap: () {},

                    trailing:
                        _isRefreshing
                            ? SizedBox(
                              width: 40,
                              height: 40,
                              child: Center(child: CircularLoadingIndicator()),
                            )
                            : IconButton(
                              icon: Icon(
                                Icons.refresh,
                                color: colorScheme.primary,
                              ),
                              onPressed: _refreshPulse,
                            ),
                  ),

                  Gap(Spacing.md.h),

                  // Main content
                  pulseAsync.when(
                    loading:
                        () => const Center(child: CircularLoadingIndicator()),
                    error:
                        (error, stack) => Center(
                          child: ErrorStateWidget(
                            title: '',
                            subtitle: 'Error: $error',
                          ),

                          //  ErrorStateWidget(subtitle: 'Error: $error'),
                        ),
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
                          CardInkWell(
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Score',
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    GestureDetector(
                                      onTap: () {},
                                      child: Row(
                                        children: [
                                          Text(
                                            'Learn more',
                                            style: textTheme.bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme.primary,
                                                ),
                                          ),
                                          Gap(Spacing.md.w),
                                          Icon(
                                            Icons.chevron_right,
                                            size: IconSizes.md.h,
                                            color: colorScheme.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                Gap(Spacing.xl.h),
                                VisualisationSwitcher(
                                  currentVisualisation: _selectedVisualisation,
                                  onChanged: (value) {
                                    setState(
                                      () => _selectedVisualisation = value,
                                    );
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
                                Gap(Spacing.xl.h * 2),

                                // Data confidence display
                                _buildConfidenceDisplay(pulse.dataConfidence),
                                Gap(Spacing.md.h),
                              ],
                            ),
                          ),

                          // Dimensions rows
                          CardInkWell(
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Dimensions',
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    GestureDetector(
                                      onTap: () {},
                                      child: Row(
                                        children: [
                                          Text(
                                            'Learn more',
                                            style: textTheme.bodySmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: colorScheme.primary,
                                                ),
                                          ),
                                          Gap(Spacing.md.w),
                                          Icon(
                                            Icons.chevron_right,
                                            size: IconSizes.md.h,
                                            color: colorScheme.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                Gap(Spacing.xl.h),

                                ...dimensions.keys.map((key) {
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: Spacing.md.h,
                                    ),
                                    child: DimensionRow(
                                      label: key,
                                      score: dimensions[key]!,
                                      delta: deltas[key],
                                      confidence: pulse
                                          .getConfidenceForDimension(
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
                              ],
                            ),
                          ),

                          CardInkWell(
                            child: Column(
                              children: [
                                // Trend chart
                                historyAsync.when(
                                  data:
                                      (history) => TrendChart(history: history),
                                  loading: () => const SizedBox.shrink(),
                                  error: (_, __) => const SizedBox.shrink(),
                                ),

                                Gap(Spacing.xl.h),

                                // Check-in banner
                                const CheckinBanner(),
                                Gap(Spacing.lg.h),
                              ],
                            ),
                          ),
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

    return SemanticContainerWidget(
      content: message,
      icon: Icons.info_outline,
      title: 'No internet connection',
      backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
      borderColor: colorScheme.primary,
      iconColor: colorScheme.primary,
      textTheme: textScheme,
    );

    //  Container(
    //   padding: EdgeInsets.all(Spacing.md.w),
    //   decoration: BoxDecoration(
    //     color: colorScheme.primary.withOpacity(0.1),
    //     borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
    //   ),
    //   child: Row(
    //     children: [
    //       Icon(Icons.info_outline, color: colorScheme.primary),
    //       Gap(Spacing.sm.w),
    //       Expanded(child: Text(message, style: textScheme.bodySmall)),
    //     ],
    //   ),
    // );
  }

  Widget _buildNoDataState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        EmptyStateWidget(
          icon: Icons.show_chart,
          title: 'No pulse score yet',
          subtitle:
              'Complete your first weekly check-in\nto see your relationship pulse.',
        ),
        Gap(Spacing.lg.h),
        AppButton(
          label: 'Start check-in',
          onPressed: () {
            context.pushNamed('weeklyCheckin');
          },

          elevation: 0,

          textColor: colorScheme.surface,
          size: ButtonSize.small,
          width: double.infinity,
          padding: Spacing.horizontalMd,
          height: 40.h,
        ),
        Gap(Spacing.md.h), // Add spacing between buttons
        AppButton(
          label: 'Log your first moment',
          onPressed: () {
            context.pushNamed('logMomentType');
          },

          elevation: 0,

          size: ButtonSize.small,
          width: double.infinity,
          padding: Spacing.horizontalMd,
          height: 40.h,

          customColor: colorScheme.surfaceContainerHighest,
          textColor: colorScheme.onSurface,
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
                      'Limited data — this will improve with more check-ins, logged moments, and time as we learn from your conversations.',
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
      return MyDateFormat.toDate(date);

      // '${date.day}/${date.month}/${date.year}';
    }
    return 'Not yet';
  }
}
