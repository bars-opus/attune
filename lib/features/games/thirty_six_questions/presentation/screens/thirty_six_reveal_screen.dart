// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_reveal_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'thirty_six_question_screen.dart';
import 'thirty_six_chapter_completion_screen.dart';

class ThirtySixRevealScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String roundId;
  final int roundNumber;
  final int totalRounds;
  final int chapter;
  final String questionText;
  final String userAnswer;

  const ThirtySixRevealScreen({
    super.key,
    required this.sessionId,
    required this.roundId,
    required this.roundNumber,
    required this.totalRounds,
    required this.chapter,
    required this.questionText,
    required this.userAnswer,
  });

  @override
  ConsumerState<ThirtySixRevealScreen> createState() =>
      _ThirtySixRevealScreenState();
}

class _ThirtySixRevealScreenState extends ConsumerState<ThirtySixRevealScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  String? _partnerAnswer;
  String? _partnerName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadPartnerAnswer();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadPartnerAnswer() async {
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

    // Get partner profile
    final profile =
        await supabase
            .from('profiles')
            .select('display_name')
            .eq('id', partnerId)
            .single();

    if (mounted) {
      setState(() {
        _partnerName = profile['display_name'] as String? ?? 'Partner';
      });
    }

    // Get partner answer
    final answer =
        await supabase
            .from('thirty_six_question_answers')
            .select('answer_text, is_removed')
            .eq('round_id', widget.roundId)
            .eq('user_id', partnerId)
            .eq('is_removed', false)
            .maybeSingle();

    if (mounted) {
      setState(() {
        _partnerAnswer = answer?['answer_text'];
        _isLoading = false;
      });
      _slideController.forward();
    }
  }

  Future<void> _goToNext() async {
    if (widget.roundNumber == widget.totalRounds) {
      // All rounds complete — show chapter completion
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => ThirtySixChapterCompletionScreen(
                sessionId: widget.sessionId,
                chapter: widget.chapter,
              ),
        ),
      );
    } else {
      // Next round
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (_) => ThirtySixQuestionScreen(
                sessionId: widget.sessionId,
                chapter: widget.chapter,
              ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final partnerDisplayName = _partnerName ?? 'Partner';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Q${widget.roundNumber} of ${widget.totalRounds} · Chapter ${widget.chapter}',
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          children: [
            // Question
            Text(
              widget.questionText,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            // Two columns
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User's answer (left)
                Expanded(
                  child: AnimatedBuilder(
                    animation: _slideController,
                    builder: (context, child) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(-0.3, 0),
                          end: Offset.zero,
                        ).animate(_slideController),
                        child: child,
                      );
                    },
                    child: _buildAnswerCard(
                      label: 'Your answer',
                      answer: widget.userAnswer,
                      color: colorScheme.primary,
                      isUser: true,
                    ),
                  ),
                ),
                Gap(Spacing.md.w),
                // Partner's answer (right)
                Expanded(
                  child: AnimatedBuilder(
                    animation: _slideController,
                    builder: (context, child) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.3, 0),
                          end: Offset.zero,
                        ).animate(_slideController),
                        child: child,
                      );
                    },
                    child: _buildAnswerCard(
                      label: "$partnerDisplayName's answer",
                      answer: _partnerAnswer ?? 'Not answered yet',
                      color: colorScheme.secondary,
                      isUser: false,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                if (widget.roundNumber > 1)
                  Expanded(
                    child: AppButton(
                      label: 'Previous',
                      onPressed: () {
                        // Navigate to previous round reveal
                        // Simplified: go back to question screen
                        Navigator.pop(context);
                      },
                      size: ButtonSize.medium,
                      customColor: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                if (widget.roundNumber > 1) Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label:
                        widget.roundNumber == widget.totalRounds
                            ? 'Finish chapter →'
                            : 'Next →',
                    onPressed: _goToNext,
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

  Widget _buildAnswerCard({
    required String label,
    required String answer,
    required Color color,
    required bool isUser,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color:
            isUser
                ? color.withOpacity(0.05)
                : colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(
          color: isUser ? color.withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: isUser ? color : colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          Gap(Spacing.md.h),
          Text(answer, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
