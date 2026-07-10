// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_waiting_screen.dart

import 'dart:async';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/thirty_six_question_providers.dart';
import 'thirty_six_reveal_screen.dart';

class ThirtySixWaitingScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String roundId;
  final int roundNumber;
  final int totalRounds;
  final int chapter;
  final String questionText;
  final String answerText;

  const ThirtySixWaitingScreen({
    super.key,
    required this.sessionId,
    required this.roundId,
    required this.roundNumber,
    required this.totalRounds,
    required this.chapter,
    required this.questionText,
    required this.answerText,
  });

  @override
  ConsumerState<ThirtySixWaitingScreen> createState() =>
      _ThirtySixWaitingScreenState();
}

class _ThirtySixWaitingScreenState
    extends ConsumerState<ThirtySixWaitingScreen> {
  late Timer _pollTimer;
  RealtimeChannel? _roundChannel;
  bool _isRevealReady = false;

  @override
  void initState() {
    super.initState();
    _subscribeToReveal();
  }

  @override
  void dispose() {
    _pollTimer.cancel();
    final channel = _roundChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  void _subscribeToReveal() {
    final supabase = ref.read(supabaseClientProvider);

    // Listen for reveal_triggered_at
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final round =
          await supabase
              .from('game_session_rounds')
              .select('both_answered, reveal_triggered_at')
              .eq('id', widget.roundId)
              .single();

      if (round['both_answered'] == true &&
          round['reveal_triggered_at'] != null) {
        setState(() {
          _isRevealReady = true;
        });
        _pollTimer.cancel();

        // Wait 500ms grace window before navigating to reveal
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _navigateToReveal();
          }
        });
      }
    });

    // Also listen to real-time updates (fallback to polling)
    _roundChannel =
        supabase
            .channel('36q_round_${widget.roundId}')
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: 'game_session_rounds',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: widget.roundId,
              ),
              callback: (payload) {
                final data = payload.newRecord;
                if (data['both_answered'] == true) {
                  setState(() {
                    _isRevealReady = true;
                  });
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) _navigateToReveal();
                  });
                }
              },
            )
            .subscribe();
  }

  void _navigateToReveal() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (_) => ThirtySixRevealScreen(
              sessionId: widget.sessionId,
              roundId: widget.roundId,
              roundNumber: widget.roundNumber,
              totalRounds: widget.totalRounds,
              chapter: widget.chapter,
              questionText: widget.questionText,
              userAnswer: widget.answerText,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final partnerName = ref.watch(partnerNameProvider).valueOrNull ?? 'Partner';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Chapter ${widget.chapter} · Q${widget.roundNumber}/${widget.totalRounds}',
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
            // Your answer
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your answer:',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  Gap(Spacing.sm.h),
                  Text(widget.answerText, style: textTheme.bodyLarge),
                ],
              ),
            ),
            const Spacer(),
            // Waiting animation
            Container(
              padding: EdgeInsets.all(Spacing.lg.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 1500),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: 0.8 + (value * 0.4),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary.withOpacity(0.2),
                          ),
                          child: Center(
                            child: Container(
                              width: 25,
                              height: 25,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Gap(Spacing.md.h),
                  Text(
                    'Waiting for $partnerName...',
                    style: textTheme.titleMedium,
                  ),
                  Gap(Spacing.sm.h),
                  Text(
                    'They will see your answer after they submit.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.md.h),
            // Manual reveal button (after polling timeout)
            if (_isRevealReady)
              AppButton(
                label: 'Reveal ready — tap to continue 👀',
                onPressed: _navigateToReveal,
                size: ButtonSize.medium,
              ),
          ],
        ),
      ),
    );
  }
}
