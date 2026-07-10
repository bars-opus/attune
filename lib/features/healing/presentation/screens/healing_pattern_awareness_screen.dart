// lib/features/healing/presentation/screens/healing_pattern_awareness_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/healing_providers.dart';

class HealingPatternAwarenessScreen extends ConsumerStatefulWidget {
  final HealingJourney journey;

  const HealingPatternAwarenessScreen({super.key, required this.journey});

  @override
  ConsumerState<HealingPatternAwarenessScreen> createState() =>
      _HealingPatternAwarenessScreenState();
}

class _HealingPatternAwarenessScreenState
    extends ConsumerState<HealingPatternAwarenessScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  Map<String, DateTime> _completionDates = const {};

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);

    try {
      final supabase = ref.read(supabaseClientProvider);
      final profile =
          await supabase
              .from('psych_profiles')
              .select('*')
              .eq('user_id', widget.journey.userId)
              .maybeSingle();

      if (profile != null) {
        final completedQuizzes =
            (profile['completed_quizzes'] as List?)
                ?.whereType<String>()
                .toList() ??
            const <String>[];
        final quizDates = await _loadQuizDates(completedQuizzes);
        setState(() {
          _profileData = profile;
          _completionDates = quizDates;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, DateTime>> _loadQuizDates(List<String> quizTypes) async {
    if (quizTypes.isEmpty) {
      return const {};
    }

    final supabase = ref.read(supabaseClientProvider);
    final response = await supabase
        .from('quiz_responses')
        .select('quiz_type, completed_at')
        .eq('user_id', widget.journey.userId)
        .inFilter('quiz_type', quizTypes)
        .order('completed_at', ascending: false);

    final dates = <String, DateTime>{};
    for (final row in response) {
      final quizType = row['quiz_type'] as String?;
      final completedAt = row['completed_at'] as String?;
      if (quizType == null ||
          completedAt == null ||
          dates.containsKey(quizType)) {
        continue;
      }
      dates[quizType] = DateTime.parse(completedAt);
    }
    return dates;
  }

  Future<void> _completeStage() async {
    await ref.read(completePatternAwarenessProvider(widget.journey.id).future);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  String _getAttachmentDisplay(dynamic attachment) {
    if (attachment == null) return 'Not taken yet';
    if (attachment is Map<String, dynamic>) {
      final primary = attachment['primary'];
      final secondary = attachment['secondary'];
      if (primary is String && secondary is String && secondary.isNotEmpty) {
        return '${_titleCase(primary)} with ${_titleCase(secondary)} traits';
      }
      if (primary is String) {
        return '${_titleCase(primary)} tendency';
      }
      return attachment['display_name'] ?? 'Not taken yet';
    }
    return 'Not taken yet';
  }

  String _getCommunicationDisplay(dynamic communication) {
    if (communication == null) return 'Not taken yet';
    if (communication is Map<String, dynamic>) {
      final primary =
          communication['primary_style'] ?? communication['primary'];
      if (primary is String) {
        return '${_titleCase(primary)} tendency';
      }
      return communication['display_name'] ?? 'Not taken yet';
    }
    return 'Not taken yet';
  }

  String _getConflictDisplay(dynamic conflict) {
    if (conflict == null) return 'Not taken yet';
    if (conflict is Map<String, dynamic>) {
      final primary = conflict['primary'];
      final secondary = conflict['secondary'];
      if (primary is String && secondary is String && secondary.isNotEmpty) {
        return '${_titleCase(primary)} with ${_titleCase(secondary)} support';
      }
      if (primary is String) {
        return '${_titleCase(primary)} tendency';
      }
      return conflict['display_name'] ?? 'Not taken yet';
    }
    return 'Not taken yet';
  }

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String? _formatCompletedAt(String quizType) {
    final value = _completionDates[quizType];
    if (value == null) {
      return null;
    }

    final local = value.toLocal();
    const monthNames = [
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
    return '${monthNames[local.month - 1]} ${local.day}, ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final attachment = _profileData?['attachment_style'];
    final communication = _profileData?['communication_style'];
    final conflict = _profileData?['conflict_style'];

    return Scaffold(
      appBar: AppBar(title: const Text('Pattern awareness'), centerTitle: true),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stage 3 of 5',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            Text(
              'Here is what to watch for next time:',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'These are patterns, not labels. You can grow and change.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Gap(Spacing.xl.h),

            // Attachment style
            _buildPatternCard(
              label: 'Attachment style',
              value: _getAttachmentDisplay(attachment),
              source:
                  attachment != null
                      ? 'Based on your attachment quiz${_formatCompletedAt('attachment') != null ? ' • ${_formatCompletedAt('attachment')}' : ''}'
                      : 'Complete your attachment quiz for insights',
              colorScheme: colorScheme,
              textTheme: textTheme,
              isMissing: attachment == null,
            ),
            Gap(Spacing.md.h),

            // Communication style
            _buildPatternCard(
              label: 'Communication tendency',
              value: _getCommunicationDisplay(communication),
              source:
                  communication != null
                      ? 'Based on your communication quiz${_formatCompletedAt('communication') != null ? ' • ${_formatCompletedAt('communication')}' : ''}'
                      : 'Complete your communication quiz for insights',
              colorScheme: colorScheme,
              textTheme: textTheme,
              isMissing: communication == null,
            ),
            Gap(Spacing.md.h),

            // Conflict style
            _buildPatternCard(
              label: 'In conflict, you tend to:',
              value: _getConflictDisplay(conflict),
              source:
                  conflict != null
                      ? 'Based on your conflict quiz${_formatCompletedAt('conflict') != null ? ' • ${_formatCompletedAt('conflict')}' : ''}'
                      : 'Complete your conflict quiz for insights',
              colorScheme: colorScheme,
              textTheme: textTheme,
              isMissing: conflict == null,
            ),

            const Spacer(),

            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Skip for now',
                    onPressed: () => Navigator.pop(context),
                    size: ButtonSize.medium,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: 'Continue →',
                    onPressed: _completeStage,
                    size: ButtonSize.medium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatternCard({
    required String label,
    required String value,
    required String source,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    bool isMissing = false,
  }) {
    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color:
            isMissing
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                : colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(
          color:
              isMissing
                  ? colorScheme.outline.withValues(alpha: 0.1)
                  : colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color:
                  isMissing
                      ? colorScheme.onSurface.withValues(alpha: 0.5)
                      : colorScheme.primary,
            ),
          ),
          Gap(Spacing.xs.h),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color:
                  isMissing
                      ? colorScheme.onSurface.withValues(alpha: 0.5)
                      : null,
            ),
          ),
          Gap(Spacing.xs.h),
          Text(
            source,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
