// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_completion_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart'
    show
        inviteToChapterProvider,
        thirtySixQuestionRepositoryProvider,
        supabaseClientProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThirtySixChapterCompletionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final int chapter;

  const ThirtySixChapterCompletionScreen({
    super.key,
    required this.sessionId,
    required this.chapter,
  });

  @override
  ConsumerState<ThirtySixChapterCompletionScreen> createState() =>
      _ThirtySixChapterCompletionScreenState();
}

class _ThirtySixChapterCompletionScreenState
    extends ConsumerState<ThirtySixChapterCompletionScreen> {
  bool _isLoading = false;
  String? _reflection;
  bool _isLastChapter = false;

  final Map<int, String> _chapterNames = {
    1: 'Warm Up',
    2: 'Deeper',
    3: 'Vulnerable',
  };

  @override
  void initState() {
    super.initState();
    _loadChapterData();
  }

  Future<void> _loadChapterData() async {
    final repository = ref.read(thirtySixQuestionRepositoryProvider);

    await repository.completeChapter(widget.sessionId);

    final session =
        await ref
            .read(supabaseClientProvider)
            .from('game_sessions')
            .select('journey_id')
            .eq('id', widget.sessionId)
            .single();

    final journey = await repository.getJourney(session['journey_id']);
    if (journey != null) {
      setState(() {
        _isLastChapter = widget.chapter == 3 && journey.isFullyCompleted;
      });
    }

    // Load chapter reflection (if any)
    var reflection = await repository.getChapterReflection(
      journeyId: session['journey_id'],
      chapter: widget.chapter,
    );

    reflection ??= await repository.generateChapterReflection(
      journeyId: session['journey_id'],
      chapter: widget.chapter,
    );

    final observation = reflection['observation'] as String?;
    if (observation != null && observation.isNotEmpty) {
      setState(() {
        _reflection = observation;
      });
    }
  }

  Future<void> _handleContinue() async {
    if (_isLastChapter) {
      // Journey complete — show final journey reflection
      context.pushReplacementNamed(
        'thirtySixJourneyCompletion',
        extra: widget.sessionId,
      );
      return;
    }

    // Show continuation dialog
    final continueNow = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Continue the journey?'),
            content: Text(
              'Chapter ${widget.chapter + 1}: ${_chapterNames[widget.chapter + 1] ?? ''}'
              '\n\nGo deeper when you\'re both ready.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Maybe later'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue →'),
              ),
            ],
          ),
    );

    if (continueNow == true && mounted) {
      setState(() => _isLoading = true);

      try {
        // Get journey ID
        final session =
            await ref
                .read(supabaseClientProvider)
                .from('game_sessions')
                .select('journey_id')
                .eq('id', widget.sessionId)
                .single();

        final journeyId = session['journey_id'] as String;

        // Invite to next chapter
        final chapter = await ref.read(
          inviteToChapterProvider((
            journeyId: journeyId,
            chapter: widget.chapter + 1,
          )).future,
        );

        if (mounted) {
          context.pushReplacementNamed(
            'thirtySixChapterInvitation',
            extra: (
              sessionId: chapter.sessionId,
              chapter: chapter.chapterNumber,
              isInitiator: true,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to continue: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final chapterName =
        _chapterNames[widget.chapter] ?? 'Chapter ${widget.chapter}';

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
            const Icon(Icons.emoji_events, size: 64),
            Gap(Spacing.md.h),
            Text(
              'Chapter $widget.chapter complete',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.md.h),
            Text(
              'You both showed up for $chapterName.',
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (_reflection != null) ...[
              Gap(Spacing.xl.h),
              Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'One thread in your answers:',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Gap(Spacing.sm.h),
                    Text(_reflection!, style: textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
            const Spacer(),
            if (!_isLastChapter)
              Text(
                'Chapter ${widget.chapter + 1} goes deeper.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            Gap(Spacing.sm.h),
            Text(
              _isLastChapter
                  ? 'All 3 chapters complete!'
                  : 'Continue now, or leave it for another day.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.md.h),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Back to games',
                    onPressed: () {
                      context.goNamed('gamesHub');
                    },
                    size: ButtonSize.medium,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.onSurface,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label:
                        _isLastChapter
                            ? 'See journey reflection ✨'
                            : 'Continue →',
                    onPressed: _isLoading ? null : _handleContinue,
                    size: ButtonSize.medium,
                    isLoading: _isLoading,
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
