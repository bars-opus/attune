// lib/features/games/truth_or_dare/presentation/screens/truth_reveal_screen.dart

import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_session_router_screen.dart';

class TruthRevealScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String roundId;
  final int roundNumber;
  final int totalRounds;
  final String tone;
  final bool isPartnerA;
  final String partnerName;
  final String questionText;
  final bool isCustom;
  final String? customQuestionId;

  const TruthRevealScreen({
    super.key,
    required this.sessionId,
    required this.roundId,
    required this.roundNumber,
    required this.totalRounds,
    required this.tone,
    required this.isPartnerA,
    required this.partnerName,
    required this.questionText,
    required this.isCustom,
    this.customQuestionId,
  });

  @override
  ConsumerState<TruthRevealScreen> createState() => _TruthRevealScreenState();
}

class _TruthRevealScreenState extends ConsumerState<TruthRevealScreen> {
  final TextEditingController _answerController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // The truth prompt lands — same reveal sound as the dare side.
    ref.read(soundServiceProvider).play(AppSound.gameReveal);
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _submitAnswer() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      // Submit answer
      final field = widget.isPartnerA ? 'answer_a' : 'answer_b';
      final submittedAtField =
          widget.isPartnerA ? 'answer_a_submitted_at' : 'answer_b_submitted_at';

      await ref
          .read(supabaseClientProvider)
          .from('game_session_rounds')
          .update({
            field: answer,
            widget.isPartnerA ? 'answer_b' : 'answer_a': '__revealed__',
            submittedAtField: DateTime.now().toIso8601String(),
          })
          .eq('id', widget.roundId);

      // Check if both answered
      final round =
          await ref
              .read(supabaseClientProvider)
              .from('game_session_rounds')
              .select('answer_a, answer_b, both_answered')
              .eq('id', widget.roundId)
              .single();

      final bothAnswered =
          round['answer_a'] != null && round['answer_b'] != null;

      // If both answered, mark as complete
      if (bothAnswered && !(round['both_answered'] as bool)) {
        await ref
            .read(supabaseClientProvider)
            .rpc('mark_round_complete', params: {'p_round_id': widget.roundId});
      }

      // Mark question as seen (preset only)
      if (!widget.isCustom) {
        final relationshipId = await ref.read(
          currentRelationshipIdProvider.future,
        );
        if (relationshipId != null) {
          // Get the question ID from the round
          final questionId = await ref
              .read(supabaseClientProvider)
              .from('game_session_rounds')
              .select('question_id')
              .eq('id', widget.roundId)
              .single()
              .then((data) => data['question_id'] as String);

          await ref
              .read(truthOrDareRepositoryProvider)
              .markQuestionSeen(
                relationshipId: relationshipId,
                questionId: questionId,
                isCustom: widget.isCustom,
              );
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (_) =>
                    TruthOrDareSessionRouterScreen(sessionId: widget.sessionId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit answer: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Truth or Dare • Round ${widget.roundNumber}/${widget.totalRounds}',
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Truth badge
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.sm.w,
                vertical: Spacing.xs.h,
              ),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🗣', style: TextStyle(fontSize: 16)),
                  Gap(Spacing.xs.w),
                  Text(
                    'TRUTH',
                    style: textTheme.labelSmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.md.h),
            // Question
            Text(
              widget.questionText,
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
              hintText: 'Type your answer here...',
              maxLines: 5,
              maxLength: 200,
              label: '',
              // buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
            ),
            Gap(Spacing.sm.h),
            Text(
              'Your partner will see your answer.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Gap(Spacing.xs.h),
            Text(
              'Stored in your game history.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
                fontStyle: FontStyle.italic,
              ),
            ),
            const Spacer(),
            AppButton(
              label: 'Submit answer',
              onPressed:
                  _answerController.text.trim().isNotEmpty && !_isSubmitting
                      ? _submitAnswer
                      : null,
              size: ButtonSize.large,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }
}
