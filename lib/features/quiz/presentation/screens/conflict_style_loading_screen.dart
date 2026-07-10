// lib/features/quiz/presentation/screens/conflict_style_loading_screen.dart

import '../../../../core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/conflict_style_questions.dart';
import '../../domain/models/conflict_style_result.dart';
import '../providers/quiz_providers.dart';

class ConflictStyleLoadingScreen extends ConsumerStatefulWidget {
  final ConflictStyleResult result;
  final Map<int, int?> answers;
  final Function(ConflictStyleResult) onComplete;

  const ConflictStyleLoadingScreen({
    super.key,
    required this.result,
    required this.answers,
    required this.onComplete,
  });

  @override
  ConsumerState<ConflictStyleLoadingScreen> createState() =>
      _ConflictStyleLoadingScreenState();
}

class _ConflictStyleLoadingScreenState
    extends ConsumerState<ConflictStyleLoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late final String _idempotencyKey;
  bool _isSaving = false;

  String get _progressKey {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    return 'conflict_style_quiz_progress_${ConflictStyleQuestions.instrumentVersion}_$userId';
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    _idempotencyKey =
        'conflict_${DateTime.now().microsecondsSinceEpoch}_$userId';

    _saveResult();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _saveResult() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final savedResult = await ref.read(
        saveConflictQuizResultProvider((
          quizType: 'conflict',
          answers: widget.answers,
          result: widget.result,
          idempotencyKey: _idempotencyKey,
        )).future,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_progressKey);

      if (mounted) {
        widget.onComplete(savedResult);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
                title: const Text('Could not save your result'),
                content: const Text(
                  'Your answers are still saved on this device. You can try again now or go back and resume later.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
                    child: const Text('Back'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _saveResult();
                    },
                    child: const Text('Try again'),
                  ),
                ],
              ),
        );
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
                      color: colorScheme.primary.withValues(alpha: 0.2),
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
            Semantics(
              label: 'Saving your conflict style result',
              child: Text(
                'Analysing your answers...',
                style: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'Understanding how you respond to conflict',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
