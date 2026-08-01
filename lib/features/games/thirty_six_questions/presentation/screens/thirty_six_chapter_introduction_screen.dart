// lib/features/games/thirty_six_questions/presentation/screens/thirty_six_chapter_introduction_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class ThirtySixChapterIntroductionScreen extends ConsumerWidget {
  final String sessionId;
  final int chapter;

  ThirtySixChapterIntroductionScreen({
    super.key,
    required this.sessionId,
    required this.chapter,
  });

  final Map<int, String> _chapterNames = {
    1: 'Warm Up',
    2: 'Deeper',
    3: 'Vulnerable',
  };

  final Map<int, String> _chapterDescriptions = {
    1: 'The conversation starts here.\nLet\'s get comfortable together.',
    2: 'You have warmed up together.\nLevel 2 goes deeper.',
    3: 'You have gone deeper than most couples do.\nLevel 3 is the most vulnerable.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final chapterName = _chapterNames[chapter] ?? 'Chapter $chapter';
    final description = _chapterDescriptions[chapter] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('36 Questions Journey'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Chapter $chapter — $chapterName',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            const Icon(Icons.emoji_people, size: 80),
            Gap(Spacing.xl.h),
            Text(
              description,
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.md.h),
            Text(
              '12 questions · ~20 minutes',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const Spacer(),
            AppButton(
              label: 'Begin →',
              onPressed: () {
                context.pushReplacementNamed(
                  'thirtySixQuestion',
                  extra: (sessionId: sessionId, chapter: chapter),
                );
              },
              size: ButtonSize.large,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
