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
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    show bothPartnersSharedProvider;
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

                          Gap(Spacing.md.h),
                          Text(
                            'Relationship Center',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Gap(Spacing.sm.h),
                          const _RelationshipCenterPanel(),
                          Gap(Spacing.md.h),

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

/// "Relationship Center" panel — the couple's Pulse at a glance, plus the
/// two actions that most directly improve it.
///
/// Moved here from the old ChatIdentityCard (deleted — its identity row
/// moved to _ChatSettingsRowsTab, its photo strip was removed entirely).
/// This panel now sits inside PulseScreen itself, right after the Score
/// card, rather than in a header shared across every PulseTab tab.
///
/// ## What is deliberately NOT here
///
/// The three stat tiles were originally dummy ("7d streak", "Response
/// rate", "Shared goals"). Two of those three can never ship:
///
/// - **Streaks are a permanent product ban.** PULSE.md §6 states verbatim:
///   "Do not implement streak tracking for check-ins. Do not show 'X week
///   streak' anywhere... This is a permanent constraint from
///   ATTUNE_SOUL.md." A missed week must carry no visible penalty.
/// - **Response rate is chat-derived, per-partner attribution.** The
///   chat→Pulse integration spec's Privacy section forbids surfacing
///   chat-derived signal on any client surface, and permanent constraint
///   #2 forbids per-partner behavioural attribution entirely ("Jordan
///   tends to withdraw" must never exist). A response-rate number is
///   exactly that, just numeric.
///
/// So the tiles show Pulse itself instead: the score, its week-over-week
/// movement, and how much data it is standing on. All three are already
/// computed by `compute-pulse`, are relationship-level (never
/// per-partner), and are explicitly designed to be seen by both partners.
class _RelationshipCenterPanel extends ConsumerWidget {
  const _RelationshipCenterPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final pulseAsync = ref.watch(currentPulseScoreProvider);
    final bothSharedQuizAsync = ref.watch(bothPartnersSharedProvider);

    return CardInkWell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Gap(Spacing.md.h),
          _PulseStatRow(pulseAsync: pulseAsync),
          Gap(Spacing.xl.h),
          InfoRowWidget(
            title: 'Weekly check-in',
            subtitle: 'Five quick questions. Takes about 60 seconds.',
            icon: Icons.checklist_rtl_outlined,
            iconColor: colorScheme.info,
            circularRadius: 10,
            backgroundColor: colorScheme.info.withValues(alpha: .2),
            showAvatar: true,
            showTrailingArrow: true,
            showDivider: true,
            onTap: () => context.pushNamed('weeklyCheckin'),
          ),
          // Attachment quiz — the one other real, already-built input to
          // Pulse (PULSE.md §5: both partners completing it adds +20 to
          // Alignment, one partner only adds +5). bothPartnersSharedProvider
          // is mutual by construction (it checks BOTH directions of
          // quiz_shares), so this states a shared fact about the couple
          // rather than reporting on either partner individually.
          bothSharedQuizAsync.when(
            loading: () => _quizRow(context, colorScheme, bothShared: null),
            error: (_, _) => _quizRow(context, colorScheme, bothShared: null),
            data:
                (bothShared) =>
                    _quizRow(context, colorScheme, bothShared: bothShared),
          ),
          InfoRowWidget(
            title: 'Relationship tips',
            subtitle: 'Ideas curated for you two',
            icon: Icons.lightbulb_outline,
            iconColor: colorScheme.warning,
            circularRadius: 10,
            backgroundColor: colorScheme.warning.withValues(alpha: .2),
            showAvatar: true,
            showTrailingArrow: true,
            showDivider: false,
            // Intentionally non-tappable: no backing feature exists yet.
            // Kept as a deliberate placeholder for a spec'd-and-built
            // follow-up rather than wired to a dead route.
          ),
          Gap(Spacing.md.h),
        ],
      ),
    );
  }

  /// The attachment-quiz row. [bothShared] null means "still resolving or
  /// unavailable" — the row still renders with its real title/icon (same
  /// convention ChatSettingsStaticRows uses for a not-yet-loaded
  /// conversation) rather than flashing a spinner into the list.
  Widget _quizRow(
    BuildContext context,
    ColorScheme colorScheme, {
    required bool? bothShared,
  }) {
    return InfoRowWidget(
      title: 'Attachment styles',
      subtitle: switch (bothShared) {
        true => 'You have both shared your results',
        false => 'Take it together to strengthen your Pulse',
        null => 'See how your styles fit together',
      },
      icon: Icons.favorite_outline,
      iconColor: colorScheme.primary,
      circularRadius: 10,
      backgroundColor: colorScheme.primary.withValues(alpha: .2),
      showAvatar: true,
      showTrailingArrow: true,
      showDivider: true,
      onTap: () => context.pushNamed('quizEntry'),
    );
  }
}

/// The three Pulse stat tiles. Renders real values once
/// [currentPulseScoreProvider] resolves; an em-dash placeholder before
/// then, and for a couple with no Pulse score computed yet (a brand-new
/// relationship, which is a normal state rather than an error).
class _PulseStatRow extends StatelessWidget {
  const _PulseStatRow({required this.pulseAsync});

  final AsyncValue<PulseScore?> pulseAsync;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pulse = pulseAsync.valueOrNull;

    final overallDelta = pulse?.getDeltaForDimension('overall');

    Widget divider() => Container(
      width: .3,
      height: 50.h,
      color: colorScheme.onSurface.withValues(alpha: .5),
    );

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            value: pulse == null ? '—' : '${pulse.overallScore}',
            label: 'Pulse',
          ),
        ),
        divider(),
        Expanded(
          child: _StatTile(
            // No previous week to compare against yet is a real, common
            // state (first computed score) — distinct from "no movement",
            // so it shows the placeholder rather than a misleading "0".
            value: overallDelta == null ? '—' : _signed(overallDelta),
            label: 'This week',
            valueColor: switch (overallDelta) {
              null => null,
              > 0 => colorScheme.success,
              < 0 => colorScheme.error,
              _ => null,
            },
          ),
        ),
        divider(),
        Expanded(
          child: _StatTile(
            value: pulse == null ? '—' : _confidenceLabel(pulse.dataConfidence),
            label: 'Confidence',
          ),
        ),
      ],
    );
  }

  static String _signed(int delta) => delta > 0 ? '+$delta' : '$delta';

  /// PULSE.md §7's four levels, title-cased for a compact tile. 'none' is
  /// rendered as "Early" rather than "None" — the spec's own copy for that
  /// state is encouraging ("Not enough data yet — keep using Attune"), and
  /// a bare "None" reads as a failure the couple caused.
  static String _confidenceLabel(String confidence) => switch (confidence) {
    'high' => 'High',
    'medium' => 'Medium',
    'low' => 'Low',
    _ => 'Early',
  };
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, this.valueColor});

  final String value;
  final String label;

  /// Tints the value only — used by the week-over-week delta tile to show
  /// direction. Null keeps the default text colour, which is what every
  /// non-directional tile wants.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      // Centered rather than left-aligned: each tile sits in an Expanded
      // slot with a divider at the boundary between slots, so a
      // left-aligned tile's text hugs one side and the divider ends up
      // nowhere near the visual midpoint between two stats. Centering the
      // text is what makes the divider actually read as splitting the two
      // neighboring stats down the middle.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
