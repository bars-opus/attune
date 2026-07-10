// lib/features/healing/presentation/screens/healing_post_mortem_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/services/healing_generation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/healing_providers.dart';

class HealingPostMortemScreen extends ConsumerStatefulWidget {
  final HealingJourney journey;

  const HealingPostMortemScreen({super.key, required this.journey});

  @override
  ConsumerState<HealingPostMortemScreen> createState() =>
      _HealingPostMortemScreenState();
}

class _HealingPostMortemScreenState
    extends ConsumerState<HealingPostMortemScreen> {
  bool _isGenerating = false;
  String? _observation;
  String? _confidence;
  String? _reflectionPrompt;
  bool _isComplete = false;
  bool _hasSkipped = false;

  @override
  void initState() {
    super.initState();
    _checkExistingStatus();
  }

  void _checkExistingStatus() {
    if (widget.journey.postMortemStatus == 'completed') {
      setState(() {
        _observation = widget.journey.postMortemObservation;
        _confidence = widget.journey.postMortemConfidence;
        _reflectionPrompt = widget.journey.postMortemReflectionPrompt;
        _isComplete = true;
      });
    } else if (widget.journey.postMortemStatus == 'skipped' ||
        widget.journey.postMortemStatus == 'insufficient_evidence') {
      setState(() {
        _hasSkipped = true;
        _isComplete = true;
      });
    }
  }

  Future<void> _generatePostMortem() async {
    setState(() => _isGenerating = true);

    try {
      final service = HealingGenerationService(
        supabase: ref.read(supabaseClientProvider),
      );

      final result = await service.generatePostMortem(
        journeyId: widget.journey.id,
      );

      if (result != null && result['status'] == 'completed') {
        setState(() {
          _observation = result['observation'];
          _confidence = result['confidence'];
          _reflectionPrompt = result['reflection_prompt'] as String?;
          _isComplete = true;
          _isGenerating = false;
        });

        // Save to database
        await ref.read(
          completePostMortemProvider((
            journeyId: widget.journey.id,
            status: 'completed',
            observation: _observation,
            confidence: _confidence,
            reflectionPrompt: _reflectionPrompt,
          )).future,
        );
      } else {
        await ref.read(
          completePostMortemProvider((
            journeyId: widget.journey.id,
            status: 'insufficient_evidence',
            observation: null,
            confidence: null,
            reflectionPrompt: null,
          )).future,
        );

        setState(() {
          _isComplete = true;
          _hasSkipped = true;
          _isGenerating = false;
        });
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to generate: $e')));
      }
    }
  }

  Future<void> _skipStage() async {
    await ref.read(
      completePostMortemProvider((
        journeyId: widget.journey.id,
        status: 'skipped',
        observation: null,
        confidence: null,
        reflectionPrompt: null,
      )).future,
    );

    if (mounted) {
      setState(() {
        _hasSkipped = true;
        _isComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relationship reflection'),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stage 2 of 5',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            Text(
              'Relationship reflection',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),

            if (_isGenerating) ...[
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    Gap(Spacing.md.h),
                    Text(
                      'Generating a grounded reflection...',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ] else if (_isComplete && _observation != null) ...[
              Gap(Spacing.xl.h),
              Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'One pattern that surfaced:',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Gap(Spacing.md.h),
                    Text(_observation!, style: textTheme.bodyLarge),
                    if (_reflectionPrompt != null &&
                        _reflectionPrompt!.trim().isNotEmpty) ...[
                      Gap(Spacing.md.h),
                      Text(
                        _reflectionPrompt!,
                        style: textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    Gap(Spacing.sm.h),
                    Text(
                      _confidence != null && _confidence != 'none'
                          ? 'Confidence: ${_confidence?.toUpperCase()}'
                          : 'Based on available data',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Gap(Spacing.md.h),
              Text(
                'This is based on shared data. It is not a judgment.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ] else if (_isComplete && _hasSkipped) ...[
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 48,
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    Gap(Spacing.md.h),
                    Text(
                      'There is not enough information for a grounded reflection yet.',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ] else ...[
              const Spacer(),
              Center(
                child: Column(
                  children: [
                    Text(
                      'Ready for a grounded reflection on the relationship dynamic?',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    Gap(Spacing.md.h),
                    Text(
                      'This analysis is private and based on shared data.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],

            Gap(Spacing.md.h),

            Row(
              children: [
                if (!_isComplete)
                  Expanded(
                    child: AppButton(
                      label: 'Skip',
                      onPressed: _isGenerating ? null : _skipStage,
                      size: ButtonSize.medium,
                      customColor: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                if (!_isComplete) Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: _isComplete ? 'Continue →' : 'Generate reflection',
                    onPressed:
                        _isGenerating
                            ? null
                            : _isComplete
                            ? () => Navigator.pop(context, true)
                            : _generatePostMortem,
                    size: ButtonSize.medium,
                    isLoading: _isGenerating,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
