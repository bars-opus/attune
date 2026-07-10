// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_history_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart'
    show
        currentUserIdProvider,
        supabaseClientProvider,
        thirtySixQuestionRepositoryProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class ThirtySixChapterHistoryScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final int chapter;

  const ThirtySixChapterHistoryScreen({
    super.key,
    required this.sessionId,
    required this.chapter,
  });

  @override
  ConsumerState<ThirtySixChapterHistoryScreen> createState() =>
      _ThirtySixChapterHistoryScreenState();
}

class _ThirtySixChapterHistoryScreenState
    extends ConsumerState<ThirtySixChapterHistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _rounds = [];
  String _chapterName = '';

  final Map<int, String> _chapterNames = {
    1: 'Warm Up',
    2: 'Deeper',
    3: 'Vulnerable',
  };

  @override
  void initState() {
    super.initState();
    _loadChapterHistory();
  }

  Future<void> _loadChapterHistory() async {
    final supabase = ref.read(supabaseClientProvider);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      // Get all rounds for this chapter
      final roundsResponse = await supabase
          .from('game_session_rounds')
          .select('''
            *,
	            answers:thirty_six_question_answers!round_id(
	              id,
	              user_id,
	              answer_text,
	              is_removed,
              is_safety_triggered
            )
          ''')
          .eq('session_id', widget.sessionId)
          .order('round_number', ascending: true);

      // Get partner ID
      final session =
          await supabase
              .from('game_sessions')
              .select('relationship_id')
              .eq('id', widget.sessionId)
              .single();

      final relationship =
          await supabase
              .from('relationships')
              .select('user_a, user_b')
              .eq('id', session['relationship_id'])
              .single();

      final partnerId =
          relationship['user_a'] == userId
              ? relationship['user_b']
              : relationship['user_a'];

      // Process rounds
      final rounds = <Map<String, dynamic>>[];
      for (final round in roundsResponse) {
        final answers = round['answers'] as List? ?? [];
        final userAnswer = answers.firstWhere(
          (a) => a['user_id'] == userId,
          orElse: () => null,
        );
        final partnerAnswer = answers.firstWhere(
          (a) => a['user_id'] == partnerId,
          orElse: () => null,
        );

        rounds.add({
          'round_number': round['round_number'],
          'question_text': round['question_text_snapshot'] ?? '',
          'user_answer':
              userAnswer != null && userAnswer['is_removed'] == false
                  ? userAnswer['answer_text']
                  : null,
          'user_answer_removed':
              userAnswer != null && userAnswer['is_removed'] == true,
          'partner_answer':
              partnerAnswer != null && partnerAnswer['is_removed'] == false
                  ? partnerAnswer['answer_text']
                  : null,
          'partner_answer_removed':
              partnerAnswer != null && partnerAnswer['is_removed'] == true,
          'both_answered': round['both_answered'] ?? false,
          'user_answer_id': userAnswer?['id'] as String?,
        });
      }

      if (mounted) {
        setState(() {
          _rounds = rounds;
          _chapterName =
              _chapterNames[widget.chapter] ?? 'Chapter ${widget.chapter}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load history: $e')));
      }
    }
  }

  Future<void> _removeAnswer(String answerId, int roundNumber) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Remove your answer?'),
            content: const Text(
              'Your answer will be removed from this history view. '
              'Your partner will see "This answer was removed."',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Remove'),
              ),
            ],
          ),
    );

    if (confirm == true) {
      final repository = ref.read(thirtySixQuestionRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) return;

      try {
        await repository.removeAnswer(answerId: answerId, userId: userId);

        // Reload history
        await _loadChapterHistory();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your answer has been removed.')),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove answer: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Chapter ${widget.chapter}: $_chapterName')),
      body:
          _rounds.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.history_outlined, size: 64),
                    Gap(Spacing.md.h),
                    Text('No history available', style: textTheme.titleMedium),
                  ],
                ),
              )
              : ListView.builder(
                padding: EdgeInsets.all(Spacing.md.w),
                itemCount: _rounds.length,
                itemBuilder: (context, index) {
                  final round = _rounds[index];
                  return _buildRoundCard(
                    context,
                    round: round,
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                    onRemoveAnswer:
                        round['user_answer_id'] != null
                            ? () => _removeAnswer(
                              round['user_answer_id'],
                              round['round_number'],
                            )
                            : null,
                  );
                },
              ),
    );
  }

  Widget _buildRoundCard(
    BuildContext context, {
    required Map<String, dynamic> round,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    VoidCallback? onRemoveAnswer,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: Spacing.md.h),
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Round ${round['round_number']}',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (onRemoveAnswer != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onRemoveAnswer,
                  tooltip: 'Remove your answer',
                  color: colorScheme.error,
                ),
            ],
          ),
          Gap(Spacing.md.h),
          Text(round['question_text'], style: textTheme.bodyLarge),
          Gap(Spacing.md.h),
          Row(
            children: [
              Expanded(
                child: _buildAnswerColumn(
                  label: 'You',
                  answer: round['user_answer'],
                  isRemoved: round['user_answer_removed'],
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              ),
              Gap(Spacing.md.w),
              Expanded(
                child: _buildAnswerColumn(
                  label: 'Partner',
                  answer: round['partner_answer'],
                  isRemoved: round['partner_answer_removed'],
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerColumn({
    required String label,
    required String? answer,
    required bool isRemoved,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Container(
      padding: EdgeInsets.all(Spacing.sm.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelSmall),
          Gap(Spacing.xs.h),
          Text(
            isRemoved ? 'This answer was removed.' : answer ?? 'Not answered',
            style: textTheme.bodySmall?.copyWith(
              fontStyle: isRemoved ? FontStyle.italic : null,
              color: isRemoved ? colorScheme.onSurface.withOpacity(0.5) : null,
            ),
          ),
        ],
      ),
    );
  }
}
