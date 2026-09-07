// lib/features/games/truth_or_dare/presentation/screens/dare_reveal_screen.dart

import 'dart:convert';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:attune/features/games/truth_or_dare/presentation/widgets/truth_or_dare_game_ui.dart';
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
    // The dare lands — a reveal sound as the card content appears.
    ref.read(soundServiceProvider).play(AppSound.gameReveal);
    _checkSkipStatus();
  }

  Future<void> _checkSkipStatus() async {
    final sessionId = widget.sessionId;
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    // Get session to check skip status
    final session =
        await ref
            .read(supabaseClientProvider)
            .from('game_sessions')
            .select('skips_used_a, skips_used_b')
            .eq('id', sessionId)
            .single();

    final skipsUsed =
        widget.isPartnerA
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

    ref.read(hapticsProvider).selection();
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
      final relationshipId = await ref.read(
        currentRelationshipIdProvider.future,
      );
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
      await ref
          .read(supabaseClientProvider)
          .from('game_session_rounds')
          .update({
            'question_id': questionData['question_id'],
            'chosen_type': 'truth',
            'is_skip': true,
            'skip_replaced_type': 'dare',
            'is_custom': questionData['is_custom'],
            'custom_question_data':
                questionData['custom_question_data'] != null
                    ? jsonEncode(questionData['custom_question_data'])
                    : null,
          })
          .eq('id', widget.roundId);

      // Mark skip used in session
      // Note: The skip count is already incremented via useSkip()

      // Navigate to Truth reveal with the new question
      if (mounted) {
        context.pushReplacementNamed(
          'truthReveal',
          extra: (
            sessionId: widget.sessionId,
            roundId: widget.roundId,
            roundNumber: widget.roundNumber,
            totalRounds: widget.totalRounds,
            tone: widget.tone,
            isPartnerA: widget.isPartnerA,
            partnerName: widget.partnerName,
            questionText: questionData['question_text'] as String,
            isCustom: questionData['is_custom'] as bool,
            customQuestionId:
                questionData['is_custom'] as bool
                    ? questionData['question_id'] as String?
                    : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to skip: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _completeDare() async {
    setState(() => _isLoading = true);

    try {
      // One RPC, writing only this player's column.
      //
      // The direct update this replaces also set the PARTNER's answer
      // column to a reveal sentinel, so whoever finished second
      // destroyed what the first person had said. The RPC derives the
      // column from auth.uid() and marks the round complete itself.
      final result = await ref
          .read(supabaseClientProvider)
          .rpc(
            'submit_truth_or_dare_answer',
            params: {'p_round_id': widget.roundId, 'p_answer': 'completed'},
          );

      final data = Map<String, dynamic>.from(result as Map);
      if (data['error'] == true) {
        throw StateError(data['code']?.toString() ?? 'unknown');
      }

      // Mark question as seen (preset only)
      if (!widget.isCustom) {
        final relationshipId = await ref.read(
          currentRelationshipIdProvider.future,
        );
        if (relationshipId != null) {
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
        context.pushReplacementNamed(
          'truthOrDareSessionRouter',
          extra: widget.sessionId,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to complete dare: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = TruthOrDarePalette.of(context, tone: widget.tone);
    final textTheme = Theme.of(context).textTheme;

    return TruthOrDareScaffold(
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      tone: widget.tone,
      scrollable: true,
      bottom: TruthOrDarePrimaryAction(
        label: 'Done — I did it',
        kind: 'dare',
        icon: Icons.check_circle_outline_rounded,
        busy: _isLoading,
        onPressed: _isLoading ? null : _completeDare,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TruthOrDarePromptCard(
            kind: 'dare',
            prompt: widget.dareText,
            author: widget.isCustom ? widget.partnerName : null,
          ),
          Gap(Spacing.lg.h),
          Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 14,
                color: palette.mutedInk,
              ),
              Gap(Spacing.xs.w),
              Expanded(
                child: Text(
                  '${widget.partnerName} will see which dare you got.',
                  style: textTheme.bodySmall?.copyWith(color: palette.mutedInk),
                ),
              ),
            ],
          ),
          Gap(Spacing.xl.h),
          // Skipping is a first-class action, not a hidden escape hatch.
          // A dare you do not want to do must always have a way out that
          // costs nothing socially -- so it is a visible, plainly worded
          // button rather than something to hunt for.
          if (!_isSkipUsed)
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _useSkip,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Swap this for a truth'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.ink,
                side: BorderSide(color: palette.line),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: palette.panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.line),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: palette.mutedInk,
                  ),
                  Gap(Spacing.sm.w),
                  Expanded(
                    child: Text(
                      'You have used your swap for this game.',
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.mutedInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
