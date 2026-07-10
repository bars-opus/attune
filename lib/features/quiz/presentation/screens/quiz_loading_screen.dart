// lib/features/quiz/presentation/screens/quiz_loading_screen.dart

import 'dart:async';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/domain/services/attachment_scoring_service.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class QuizLoadingScreen extends ConsumerStatefulWidget {
  final Map<int, int?> answers;
  final String quizType;
  final Function(AttachmentResult) onComplete;

  const QuizLoadingScreen({
    super.key,
    required this.answers,
    required this.quizType,
    required this.onComplete,
  });

  @override
  ConsumerState<QuizLoadingScreen> createState() => _QuizLoadingScreenState();
}

class _QuizLoadingScreenState extends ConsumerState<QuizLoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isComplete = false;
  AttachmentResult? _result;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _processQuiz();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _processQuiz() async {
    // Start timing
    final startTime = DateTime.now();

    // Step 1: Calculate score (client-side)
    final result = AttachmentScoringService.calculateScore(widget.answers);
    _result = result;

    // Step 2: Save to database
    await ref.read(saveQuizResultProvider((
      quizType: widget.quizType,
      answers: widget.answers,
      result: result,
    )).future);

    // Step 3: Ensure minimum 2.5 second loading time (gift sequence anticipation)
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    final remaining = 2500 - elapsed;
    
    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }

    if (mounted) {
      setState(() {
        _isComplete = true;
      });
      
      // Small delay for fade out/in transition
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (mounted) {
        widget.onComplete(_result!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing green circle (gift sequence anticipation)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 0.8 + (_pulseController.value * 0.4);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary.withOpacity(0.2),
                    ),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 40,
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
            Gap(Spacing.xl.h),
            Text(
              'Analysing your answers...',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'Understanding how you show up in relationships',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
