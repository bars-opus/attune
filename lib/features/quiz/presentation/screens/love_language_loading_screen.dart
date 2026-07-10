// lib/features/quiz/presentation/screens/love_language_loading_screen.dart

import 'dart:async';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';



class LoveLanguageLoadingScreen extends ConsumerStatefulWidget {
  final LoveLanguageResult result;
  final Map<int, int?> answers;
  final VoidCallback onComplete;

  const LoveLanguageLoadingScreen({
    super.key,
    required this.result,
    required this.answers,
    required this.onComplete,
  });

  @override
  ConsumerState<LoveLanguageLoadingScreen> createState() => _LoveLanguageLoadingScreenState();
}

class _LoveLanguageLoadingScreenState extends ConsumerState<LoveLanguageLoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _saveResult();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _saveResult() async {
    final startTime = DateTime.now();

    // Save to database
    await ref.read(saveLoveLanguageResultProvider((
      answers: widget.answers,
      result: widget.result,
    )).future);

    // Ensure minimum 2.0 second loading time (gift sequence)
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    final remaining = 2000 - elapsed;

    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }

    if (mounted) {
      widget.onComplete();
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
              'Understanding how you give and receive affection',
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
