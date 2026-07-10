// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_journey_completion_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/presentation/screens/games_hub_screen.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class ThirtySixJourneyCompletionScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const ThirtySixJourneyCompletionScreen({super.key, required this.sessionId});

  @override
  ConsumerState<ThirtySixJourneyCompletionScreen> createState() =>
      _ThirtySixJourneyCompletionScreenState();
}

class _ThirtySixJourneyCompletionScreenState
    extends ConsumerState<ThirtySixJourneyCompletionScreen> {
  bool _isLoading = true;
  String? _journeyObservation;
  bool _hasJourneyReflection = false;

  @override
  void initState() {
    super.initState();
    _loadJourneyReflection();
  }

  Future<void> _loadJourneyReflection() async {
    final supabase = ref.read(supabaseClientProvider);

    // Get journey ID
    final session =
        await supabase
            .from('game_sessions')
            .select('journey_id')
            .eq('id', widget.sessionId)
            .single();

    final journeyId = session['journey_id'] as String;

    // Check if journey reflection exists
    final repository = ref.read(thirtySixQuestionRepositoryProvider);
    final reflection = await repository.getJourneyReflection(
      journeyId: journeyId,
    );

    if (mounted) {
      setState(() {
        _journeyObservation = reflection['observation'];
        _hasJourneyReflection =
            reflection['observation'] != null &&
            reflection['observation'].isNotEmpty &&
            reflection['is_hidden'] == false;
        _isLoading = false;
      });
    }

    // If no reflection exists, generate one
    if (!_hasJourneyReflection && mounted) {
      await _generateJourneyReflection(journeyId);
    }
  }

  Future<void> _generateJourneyReflection(String journeyId) async {
    final repository = ref.read(thirtySixQuestionRepositoryProvider);
    final result = await repository.generateJourneyReflection(
      journeyId: journeyId,
    );

    if (mounted) {
      setState(() {
        _journeyObservation = result['observation'];
        _hasJourneyReflection =
            result['observation'] != null && result['observation'].isNotEmpty;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('36 Questions Journey'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          children: [
            const Icon(Icons.emoji_events, size: 80),
            Gap(Spacing.md.h),
            Text(
              '✨ Journey complete!',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.md.h),
            Text(
              '36 questions. 3 chapters.',
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.sm.h),
            Text(
              'You both showed up for all of it.',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (_hasJourneyReflection) ...[
              Gap(Spacing.xl.h),
              Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withOpacity(0.05),
                      colorScheme.primary.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your journey reflection:',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Gap(Spacing.md.h),
                    Text(_journeyObservation!, style: textTheme.bodyLarge),
                  ],
                ),
              ),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Play again',
                    onPressed: () {
                      // Start a new journey
                      // This will navigate to journey start flow
                    },
                    size: ButtonSize.medium,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: 'Back to games',
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GamesHubScreen(),
                        ),
                        (route) => route.isFirst,
                      );
                    },
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
}
