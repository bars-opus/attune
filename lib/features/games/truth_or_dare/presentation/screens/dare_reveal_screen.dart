// lib/features/games/truth_or_dare/presentation/screens/dare_reveal_screen.dart

import 'dart:convert';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_session_router_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_reveal_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';



class DareRevealScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String roundId;
  final int roundNumber;
  final int totalRounds;
  final String tone;
  final bool isPartnerA;
  final String partnerName;
  final String dareText;
  final bool isCustom;
  final String? customQuestionId;

  const DareRevealScreen({
    super.key,
    required this.sessionId,
    required this.roundId,
    required this.roundNumber,
    required this.totalRounds,
    required this.tone,
    required this.isPartnerA,
    required this.partnerName,
    required this.dareText,
    required this.isCustom,
    this.customQuestionId,
  });

  @override
  ConsumerState<DareRevealScreen> createState() => _DareRevealScreenState();
}

class _DareRevealScreenState extends ConsumerState<DareRevealScreen> {
  bool _isSkipUsed = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkSkipStatus();
  }

  Future<void> _checkSkipStatus() async {
    final sessionId = widget.sessionId;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    // Get session to check skip status
    final session = await ref.read(supabaseClientProvider)
        .from('game_sessions')
        .select('skips_used_a, skips_used_b')
        .eq('id', sessionId)
        .single();

    final skipsUsed = widget.isPartnerA
        ? (session['skips_used_a'] as int? ?? 0)
        : (session['skips_used_b'] as int? ?? 0);

    if (mounted) {
      setState(() {
        _isSkipUsed = skipsUsed >= 1;
      });
    }
  }

  Future<void> _useSkip() async {
    if (_isSkipUsed || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      // Use skip (atomic increment)
      final repository = ref.read(truthOrDareRepositoryProvider);
      await repository.useSkip(
        widget.sessionId,
        ref.read(currentUserIdProvider)!,
        widget.isPartnerA,
      );

      // Get a new Truth question (same tone)
      final relationshipId = await ref.read(currentRelationshipIdProvider.future);
      if (relationshipId == null) throw Exception('No relationship found');

      final questionData = await repository.selectQuestionForRound(
        relationshipId: relationshipId,
        userId: ref.read(currentUserIdProvider)!,
        tone: widget.tone,
        questionType: 'truth',
        sessionId: widget.sessionId,
      );

      setState(() {
        _isSkipUsed = true;
        _isLoading = false;
      });

      // Update the round with the new question
      await ref.read(supabaseClientProvider).from('game_session_rounds').update({
        'question_id': questionData['question_id'],
        'chosen_type': 'truth',
        'is_skip': true,
        'skip_replaced_type': 'dare',
        'is_custom': questionData['is_custom'],
        'custom_question_data': questionData['custom_question_data'] != null
            ? jsonEncode(questionData['custom_question_data'])
            : null,
      }).eq('id', widget.roundId);

      // Mark skip used in session
      // Note: The skip count is already incremented via useSkip()

      // Navigate to Truth reveal with the new question
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TruthRevealScreen(
              sessionId: widget.sessionId,
              roundId: widget.roundId,
              roundNumber: widget.roundNumber,
              totalRounds: widget.totalRounds,
              tone: widget.tone,
              isPartnerA: widget.isPartnerA,
              partnerName: widget.partnerName,
              questionText: questionData['question_text'],
              isCustom: questionData['is_custom'],
              customQuestionId: questionData['is_custom']
                  ? questionData['question_id']
                  : null,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to skip: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeDare() async {
    setState(() => _isLoading = true);

    try {
      // Mark dare as completed
      final field = widget.isPartnerA ? 'answer_a' : 'answer_b';
      final submittedAtField = widget.isPartnerA ? 'answer_a_submitted_at' : 'answer_b_submitted_at';

      await ref.read(supabaseClientProvider).from('game_session_rounds').update({
        field: 'completed',
        widget.isPartnerA ? 'answer_b' : 'answer_a': '__revealed__',
        submittedAtField: DateTime.now().toIso8601String(),
      }).eq('id', widget.roundId);

      // Check if both answered (partner may have also answered something)
      final round = await ref.read(supabaseClientProvider)
          .from('game_session_rounds')
          .select('answer_a, answer_b, both_answered')
          .eq('id', widget.roundId)
          .single();

      final bothAnswered = round['answer_a'] != null && round['answer_b'] != null;

      // If both answered, mark as complete
      if (bothAnswered && !(round['both_answered'] as bool)) {
        await ref.read(supabaseClientProvider).rpc('mark_round_complete', params: {
          'p_round_id': widget.roundId,
        });
      }

      // Mark question as seen (preset only)
      if (!widget.isCustom) {
        final relationshipId = await ref.read(currentRelationshipIdProvider.future);
        if (relationshipId != null) {
          final questionId = await ref.read(supabaseClientProvider)
              .from('game_session_rounds')
              .select('question_id')
              .eq('id', widget.roundId)
              .single()
              .then((data) => data['question_id'] as String);

          await ref.read(truthOrDareRepositoryProvider).markQuestionSeen(
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
                (_) => TruthOrDareSessionRouterScreen(
                  sessionId: widget.sessionId,
                ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete dare: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Truth or Dare • Round ${widget.roundNumber}/${widget.totalRounds}'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dare badge
            Container(
              padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w, vertical: Spacing.xs.h),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 16)),
                  Gap(Spacing.xs.w),
                  Text(
                    'DARE',
                    style: textTheme.labelSmall?.copyWith(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.md.h),
            // Dare text
            Text(
              widget.dareText,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.xl.h),
            // Instructions
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Complete the dare, then tap Done.',
                    style: textTheme.bodyMedium,
                  ),
                  Gap(Spacing.sm.h),
                  Text(
                    'Your partner will see what your dare was.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Skip button
            if (!_isSkipUsed)
              Padding(
                padding: EdgeInsets.only(bottom: Spacing.md.h),
                child: AppButton(
                  label: 'Skip this dare — I\'ll take another truth instead',
                  onPressed: _isLoading ? null : _useSkip,
                  size: ButtonSize.medium,
                  customColor: colorScheme.surfaceContainerHighest,
                  textColor: colorScheme.onSurface,
                  isLoading: _isLoading,
                ),
              ),
            if (_isSkipUsed)
              Padding(
                padding: EdgeInsets.only(bottom: Spacing.md.h),
                child: Text(
                  'No skips remaining',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            // Done button
            AppButton(
              label: 'Done ✓',
              onPressed: _isLoading ? null : _completeDare,
              size: ButtonSize.large,
              width: double.infinity,
              isLoading: _isLoading,
            ),
          ],
        ),
      ),
    );
  }
}
