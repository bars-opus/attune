// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_question_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/thirty_six_question_providers.dart';

class ThirtySixQuestionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final int chapter;

  const ThirtySixQuestionScreen({
    super.key,
    required this.sessionId,
    required this.chapter,
  });

  @override
  ConsumerState<ThirtySixQuestionScreen> createState() =>
      _ThirtySixQuestionScreenState();
}

class _ThirtySixQuestionScreenState
    extends ConsumerState<ThirtySixQuestionScreen> {
  final TextEditingController _answerController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSubmitting = false;
  String? _roundId;
  int _currentRoundNumber = 0;
  final int _totalRounds = 12;
  String _questionText = '';
  bool _hasPartnerAnswered = false;
  RealtimeChannel? _roundChannel;

  @override
  void initState() {
    super.initState();
    _loadCurrentRound();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _focusNode.dispose();
    final channel = _roundChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  void _loadCurrentRound() {
    final supabase = ref.read(supabaseClientProvider);
    final sessionId = widget.sessionId;

    // Get current round
    supabase
        .from('game_session_rounds')
        .select('*')
        .eq('session_id', sessionId)
        .order('round_number', ascending: true)
        .then((response) async {
          if (response.isEmpty || !mounted) return;

          // Find first unanswered round
          for (final round in response) {
            final roundId = round['id'];
            final userId = ref.read(currentUserIdProvider);
            if (userId == null) return;

            // Check if user already answered this round
            final answer =
                await supabase
                    .from('thirty_six_question_answers')
                    .select('*')
                    .eq('round_id', roundId)
                    .eq('user_id', userId)
                    .maybeSingle();

            if (answer == null || answer['is_removed'] == true) {
              // This round needs an answer
              setState(() {
                _roundId = roundId;
                _currentRoundNumber = round['round_number'];
                _questionText = round['question_text_snapshot'] ?? '';
              });

              // Check if partner answered
              _checkPartnerAnswered(roundId);
              _subscribeToRound(roundId);
              return;
            }
          }

          // All rounds answered — check if chapter is complete
          _checkChapterComplete();
        });
  }

  Future<void> _checkPartnerAnswered(String roundId) async {
    final supabase = ref.read(supabaseClientProvider);
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

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

    final answer =
        await supabase
            .from('thirty_six_question_answers')
            .select('*')
            .eq('round_id', roundId)
            .eq('user_id', partnerId)
            .eq('is_removed', false)
            .maybeSingle();

    if (mounted) {
      setState(() {
        _hasPartnerAnswered = answer != null;
      });
    }
  }

  void _subscribeToRound(String roundId) {
    final supabase = ref.read(supabaseClientProvider);
    final oldChannel = _roundChannel;
    if (oldChannel != null) {
      supabase.removeChannel(oldChannel);
    }

    _roundChannel =
        supabase
            .channel('36q_round_$roundId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'thirty_six_question_answers',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'round_id',
                value: roundId,
              ),
              callback: (payload) {
                // Check if partner answered
                _checkPartnerAnswered(roundId);
                _checkBothAnswered(roundId);
              },
            )
            .subscribe();
  }

  Future<void> _checkBothAnswered(String roundId) async {
    final supabase = ref.read(supabaseClientProvider);

    final round =
        await supabase
            .from('game_session_rounds')
            .select('both_answered')
            .eq('id', roundId)
            .single();

    if (round['both_answered'] == true && mounted) {
      // Navigate to reveal or next round
      // This will be handled by the waiting screen or reveal screen
    }
  }

  Future<void> _checkChapterComplete() async {
    final supabase = ref.read(supabaseClientProvider);

    // Check if all rounds are complete
    final response = await supabase
        .from('game_session_rounds')
        .select('both_answered')
        .eq('session_id', widget.sessionId);

    final allComplete = response.every((r) => r['both_answered'] == true);

    if (allComplete && mounted) {
      // Chapter is complete — show completion ceremony
      context.pushReplacementNamed(
        'thirtySixChapterCompletion',
        extra: (sessionId: widget.sessionId, chapter: widget.chapter),
      );
    }
  }

  Future<void> _submitAnswer() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || _isSubmitting || _roundId == null) return;

    // Soft minimum check (20 chars suggested, but not enforced)
    if (answer.length < 20) {
      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Short answer'),
              content: const Text(
                'Your answer is quite short. A sentence or two is enough.\n\n'
                'Do you want to submit it anyway?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep writing'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Submit anyway'),
                ),
              ],
            ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repository = ref.read(thirtySixQuestionRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw Exception('Not authenticated');

      // Submit answer
      await repository.submitAnswer(
        roundId: _roundId!,
        userId: userId,
        answerText: answer,
      );

      if (mounted) {
        // Navigate to waiting screen
        context.pushReplacementNamed(
          'thirtySixWaiting',
          extra: (
            sessionId: widget.sessionId,
            roundId: _roundId!,
            roundNumber: _currentRoundNumber,
            totalRounds: _totalRounds,
            chapter: widget.chapter,
            questionText: _questionText,
            answerText: answer,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _useSkip() async {
    if (_roundId == null) return;
    if (_hasPartnerAnswered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your partner has already answered this one.'),
        ),
      );
      return;
    }

    final supabase = ref.read(supabaseClientProvider);

    // Check if skips remaining
    final session =
        await supabase
            .from('game_sessions')
            .select('skips_used')
            .eq('id', widget.sessionId)
            .single();

    final skipsUsed = session['skips_used'] as int? ?? 0;
    if (skipsUsed >= 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No skips remaining (max 2 per chapter)'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Skip this question?'),
            content: Text(
              'A replacement question will be selected. '
              'You have ${2 - skipsUsed} skip${2 - skipsUsed > 1 ? 's' : ''} remaining.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Skip'),
              ),
            ],
          ),
    );

    if (confirm != true || !mounted) return;

    final repository = ref.read(thirtySixQuestionRepositoryProvider);
    await repository.useSkip(sessionId: widget.sessionId, roundId: _roundId!);
    if (!mounted) return;

    _answerController.clear();
    _loadCurrentRound();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Question replaced')));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final partnerName = ref.watch(partnerNameProvider).valueOrNull ?? 'Partner';

    if (_roundId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Chapter ${widget.chapter} · Q$_currentRoundNumber of $_totalRounds',
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question
            Text(
              _questionText,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.xl.h),
            // Answer input
            Text(
              'Your answer',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _answerController,
              focusNode: _focusNode,
              hintText: 'A sentence or two is enough...',
              maxLines: 5,
              maxLength: 400,
              // buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
              // null,
              enabled: !_isSubmitting,
              label: '',
            ),
            Gap(Spacing.sm.h),
            Row(
              children: [
                Text(
                  '${_answerController.text.length}/400',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                Text(
                  'A sentence or two is enough.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            Gap(Spacing.md.h),
            Text(
              '$partnerName will see your answer after you both submit.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            // Partner status
            Container(
              padding: EdgeInsets.all(Spacing.sm.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasPartnerAnswered
                        ? Icons.check_circle
                        : Icons.hourglass_empty,
                    size: 16,
                    color:
                        _hasPartnerAnswered
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  Gap(Spacing.sm.w),
                  Text(
                    _hasPartnerAnswered
                        ? '$partnerName answered'
                        : '$partnerName waiting',
                    style: textTheme.bodySmall?.copyWith(
                      color:
                          _hasPartnerAnswered
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.md.h),
            // Skip and Submit buttons
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Skip question',
                    onPressed: _isSubmitting ? null : _useSkip,
                    size: ButtonSize.medium,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: 'Submit answer',
                    onPressed:
                        _answerController.text.trim().isNotEmpty &&
                                !_isSubmitting
                            ? _submitAnswer
                            : null,
                    size: ButtonSize.medium,
                    isLoading: _isSubmitting,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
