// lib/features/quiz/presentation/screens/quiz_result_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/data/local/quiz_progress_store.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:attune/features/quiz/presentation/screens/quiz_entry_screen.dart';
import 'package:attune/features/quiz/presentation/widgets/share_quiz_button.dart';
import 'package:attune/features/quiz/presentation/widgets/spectrum_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuizResultScreen extends ConsumerStatefulWidget {
  final AttachmentResult result;
  final String quizType;

  const QuizResultScreen({
    super.key,
    required this.result,
    required this.quizType,
  });

  @override
  ConsumerState<QuizResultScreen> createState() => _QuizResultScreenState();
}

class _QuizResultScreenState extends ConsumerState<QuizResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _revealController;
  bool _showTypeName = false;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Stage 1: Type name fades in after 100ms
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _showTypeName = true;
        });
      }
    });

    // Stage 1 holds for 1.5 seconds
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() {
          _showDetails = true;
        });
        _revealController.forward();
      }
    });
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed:
              () => Navigator.popUntil(context, (route) => route.isFirst),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Background (always visible)
            Container(
              width: double.infinity,
              height: double.infinity,
              child: SingleChildScrollView(
                physics:
                    _showDetails ? null : const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.all(Spacing.lg.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title (fades in with details)
                      if (_showDetails)
                        FadeTransition(
                          opacity: _revealController,
                          child: Text(
                            'Your attachment style',
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ),
                      if (_showDetails) Gap(Spacing.md.h),

                      // Type name (large, Attune green)
                      if (_showTypeName)
                        FadeTransition(
                          opacity: AlwaysStoppedAnimation(1.0),
                          child: Text(
                            widget.result.displayName,
                            style: textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),

                      if (_showDetails) ...[
                        Gap(Spacing.xl.h),

                        // Poetic description
                        Text(
                          widget.result.poeticDescription,
                          style: textTheme.bodyLarge,
                        ),

                        Gap(Spacing.xl.h),

                        // Spectrum section
                        Text(
                          'Your spectrum',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Gap(Spacing.md.h),

                        // Spectrum bars (animated)
                        SpectrumBar(
                          label: 'Secure',
                          percentage: widget.result.securePercentage,
                          color: _getSpectrumColor('secure'),
                          animation: _revealController,
                        ),
                        Gap(Spacing.sm.h),
                        SpectrumBar(
                          label: 'Anxious',
                          percentage: widget.result.anxiousPercentage,
                          color: _getSpectrumColor('anxious'),
                          animation: _revealController,
                        ),
                        Gap(Spacing.sm.h),
                        SpectrumBar(
                          label: 'Avoidant',
                          percentage: widget.result.avoidantPercentage,
                          color: _getSpectrumColor('avoidant'),
                          animation: _revealController,
                        ),
                        Gap(Spacing.sm.h),
                        SpectrumBar(
                          label: 'Fearful',
                          percentage: widget.result.fearfulPercentage,
                          color: _getSpectrumColor('fearful'),
                          animation: _revealController,
                        ),

                        Gap(Spacing.xl.h),

                        // What this means in practice
                        Text(
                          'What this means in practice',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Gap(Spacing.md.h),

                        // Practice bullets
                        ...widget.result.practiceBullets.map(
                          (bullet) => Padding(
                            padding: EdgeInsets.only(bottom: Spacing.md.h),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                                Gap(Spacing.sm.w),
                                Expanded(
                                  child: Text(
                                    bullet,
                                    style: textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        Gap(Spacing.xl.h),

                        // Snapshot disclaimer
                        Container(
                          padding: EdgeInsets.all(Spacing.md.w),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(
                              BorderRadiusTokens.md.r,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: colorScheme.primary,
                              ),
                              Gap(Spacing.sm.w),
                              Expanded(
                                child: Text(
                                  'This is a snapshot, not a label. Attachment styles shift with growth, therapy, and experience.',
                                  style: textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),

                        Gap(Spacing.xl.h),

                        // Action buttons
                        _buildActionButtons(context),

                        Gap(Spacing.lg.h),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Loading overlay during reveal (prevents interaction)
            if (!_showDetails)
              Container(
                color: colorScheme.surface,
                child: const Center(child: SizedBox.shrink()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isInCouplesMode =
        ref.watch(userRelationshipModeProvider).valueOrNull == 'couples';

    return Column(
      children: [
        // Share button - handles everything internally
        if (isInCouplesMode)
          ShareQuizButton(quizType: widget.quizType, result: widget.result),

        if (isInCouplesMode) Gap(Spacing.md.h),

        // Retake and Back buttons
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Retake quiz',
                onPressed: () => _retakeQuiz(),
                size: ButtonSize.medium,
                customColor: colorScheme.surfaceContainerHighest,
                textColor: colorScheme.onSurface,
              ),
            ),
            Gap(Spacing.md.w),
            Expanded(
              child: AppButton(
                label: 'Back to profile',
                onPressed:
                    () => Navigator.popUntil(context, (route) => route.isFirst),
                size: ButtonSize.medium,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showShareConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Share your result?'),
            content: Text(
              '${ref.read(partnerNameProvider)} will be able to see your attachment style result. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await ref.read(
                    shareQuizResultProvider((quizType: 'attachment')).future,
                  );
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Result shared with partner'),
                      ),
                    );
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('Yes, share it'),
              ),
            ],
          ),
    );
  }

  void _retakeQuiz() async {
    // Clear any saved progress for this quiz
    final prefs = await SharedPreferences.getInstance();
    final progressStore = QuizProgressStore(prefs);
    await progressStore.clearProgress(widget.quizType);

    // Navigate back to quiz entry
    Navigator.popUntil(context, (route) => route.isFirst);

    // Small delay then start fresh quiz
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const QuizEntryScreen(quizType: 'attachment'),
          ),
        );
      }
    });
  }

  Color _getSpectrumColor(String type) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (type) {
      case 'secure':
        return colorScheme.primary;
      case 'anxious':
        return Colors.orange;
      case 'avoidant':
        return Colors.blue;
      case 'fearful':
        return Colors.purple;
      default:
        return colorScheme.primary;
    }
  }
}
