// lib/features/games/truth_or_dare/presentation/screens/truth_reveal_screen.dart

import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:attune/features/games/truth_or_dare/presentation/widgets/truth_or_dare_game_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      // One RPC, and it writes only this player's column.
      //
      // This used to be a direct table update that also set the PARTNER's
      // answer column to a reveal sentinel -- so whoever answered
      // second destroyed the first person's answer, in a game whose whole
      // point is hearing what they said.
      final result = await ref
          .read(supabaseClientProvider)
          .rpc(
            'submit_truth_or_dare_answer',
            params: {'p_round_id': widget.roundId, 'p_answer': answer},
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
        context.pushReplacementNamed(
          'truthOrDareSessionRouter',
          extra: widget.sessionId,
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
    final palette = TruthOrDarePalette.of(context, tone: widget.tone);
    final textTheme = Theme.of(context).textTheme;
    final canSubmit =
        _answerController.text.trim().isNotEmpty && !_isSubmitting;

    return TruthOrDareScaffold(
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      tone: widget.tone,
      scrollable: true,
      bottom: TruthOrDarePrimaryAction(
        label: 'Send it',
        kind: 'truth',
        icon: Icons.send_rounded,
        busy: _isSubmitting,
        onPressed: canSubmit ? _submitAnswer : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TruthOrDarePromptCard(
            kind: 'truth',
            prompt: widget.questionText,
            author: widget.isCustom ? widget.partnerName : null,
          ),
          Gap(Spacing.xl.h),
          Text(
            'Your answer',
            style: textTheme.titleSmall?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          Gap(Spacing.sm.h),
          // Rebuilds on every keystroke so the action enables the moment
          // there is something to send, rather than after a blur.
          TextField(
            controller: _answerController,
            maxLines: 5,
            minLines: 3,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            style: textTheme.bodyLarge?.copyWith(color: palette.ink),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Say it how you would say it out loud...',
              hintStyle: textTheme.bodyLarge?.copyWith(color: palette.mutedInk),
              filled: true,
              fillColor: palette.panel,
              counterStyle: textTheme.bodySmall?.copyWith(
                color: palette.mutedInk,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: palette.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: palette.truth, width: 2),
              ),
              contentPadding: const EdgeInsets.all(18),
            ),
          ),
          Gap(Spacing.xs.h),
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: palette.mutedInk,
              ),
              Gap(Spacing.xs.w),
              Expanded(
                child: Text(
                  '${widget.partnerName} sees this once you send it.',
                  style: textTheme.bodySmall?.copyWith(color: palette.mutedInk),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
