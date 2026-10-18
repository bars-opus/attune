// lib/features/quiz/presentation/screens/partner_quiz_result_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/communication_style_result.dart';
import 'package:attune/features/quiz/domain/models/conflict_style_result.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/domain/models/shared_quiz_result.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:attune/features/quiz/presentation/screens/love_language_result_screen.dart';
import 'package:attune/features/quiz/presentation/widgets/clinical_quiz_gate.dart';
import 'package:attune/features/quiz/presentation/widgets/spectrum_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PartnerQuizResultScreen extends ConsumerWidget {
  final String quizType;
  final String partnerId;

  const PartnerQuizResultScreen({
    super.key,
    required this.quizType,
    required this.partnerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Spec 5 (R5-6): communication and conflict wait for clinical sign-off.
    if (quizType == 'communication' || quizType == 'conflict') {
      return ClinicalQuizGate(child: _screen(context, ref));
    }
    return _screen(context, ref);
  }

  Widget _screen(BuildContext context, WidgetRef ref) {
    // Spec 5 (research 06 §3 F9 (3)): an attachment result is about the
    // person who took it, so a partner never opens one (the server holds no
    // attachment share either).
    if (quizType == 'attachment') {
      return Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: EdgeInsets.all(Spacing.lg.w),
          child: Text(
            'Attachment results stay with the person who took them.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }
    final partnerResultAsync = ref.watch(
      partnerQuizResultProvider((quizType, partnerId)),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (quizType) {
          'love_language' => 'What feels loving to them',
          'communication' => 'Partner\'s communication style',
          'conflict' => 'Partner\'s conflict style',
          _ => 'Partner\'s quiz result',
        }, style: textTheme.titleMedium),
      ),
      body: partnerResultAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (result) {
          if (result == null) {
            return const Center(child: Text('Result not available'));
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(Spacing.lg.w),
            child: _buildContent(context, result, colorScheme, textTheme),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    SharedQuizResult result,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    switch (result.quizType) {
      case 'love_language':
        return _buildLoveLanguageContent(
          context,
          result.loveLanguageResult!,
          textTheme,
        );
      case 'communication':
        return _buildCommunicationContent(
          result.communicationStyleResult!,
          colorScheme,
          textTheme,
        );
      case 'conflict':
        return _buildConflictContent(
          result.conflictStyleResult!,
          colorScheme,
          textTheme,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // Spec 5 (R5-5): what feels loving to them right now, grouped; no type.
  Widget _buildLoveLanguageContent(
    BuildContext context,
    LoveLanguageResult result,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LoveLanguageResult.frameworkNote,
          style: textTheme.bodySmall,
        ),
        Gap(Spacing.lg.h),
        ...LovingWayGroups(result: result).build(context),
        if (result.moments.isNotEmpty) ...[
          Text('Especially', style: textTheme.titleMedium),
          Gap(Spacing.sm.h),
          Wrap(
            spacing: Spacing.sm.w,
            runSpacing: Spacing.sm.h,
            children: [
              for (final m in LovingMoment.values)
                if (result.moments.contains(m)) Chip(label: Text(m.label)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCommunicationContent(
    CommunicationStyleResult result,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.getPrimaryDisplay(),
          style: textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ),
        Gap(Spacing.md.h),
        Text(result.getSummary(), style: textTheme.bodyLarge),
        Gap(Spacing.xl.h),
        Text(
          'Their spectrum',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.md.h),
        ...result.spectrumData.map(
          (item) => Padding(
            padding: EdgeInsets.only(bottom: Spacing.sm.h),
            child: SpectrumBar(
              label: item['label'] as String,
              percentage: item['value'] as int,
              color: colorScheme.primary.withValues(
                alpha: item['key'] == result.primary ? 1 : 0.45,
              ),
              animation: const AlwaysStoppedAnimation<double>(1),
            ),
          ),
        ),
        Gap(Spacing.xl.h),
        Text(
          'What this means',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.md.h),
        Text(result.getDescription(), style: textTheme.bodyMedium),
        Gap(Spacing.xl.h),
        _buildDisclaimer(
          colorScheme,
          textTheme,
          'Your partner shared this with you. This reflects how they answered that day and can change with context, safety, culture, and relationship dynamics.',
        ),
      ],
    );
  }

  Widget _buildConflictContent(
    ConflictStyleResult result,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.isTied || result.isMixed
              ? result.getMixedDisplay()
              : result.getPrimaryDisplay(),
          style: textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ),
        Gap(Spacing.md.h),
        Text(result.getSummary(), style: textTheme.bodyLarge),
        Gap(Spacing.xl.h),
        Text(
          'Their spectrum',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.md.h),
        ...result.spectrumData.map(
          (item) => Padding(
            padding: EdgeInsets.only(bottom: Spacing.sm.h),
            child: SpectrumBar(
              label: item['label'] as String,
              percentage: item['value'] as int,
              color: colorScheme.primary.withValues(
                alpha: item['key'] == result.primary ? 1 : 0.45,
              ),
              animation: const AlwaysStoppedAnimation<double>(1),
            ),
          ),
        ),
        Gap(Spacing.xl.h),
        Text(
          'What this means',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.md.h),
        Text(result.getDescription(), style: textTheme.bodyMedium),
        Gap(Spacing.xl.h),
        _buildDisclaimer(
          colorScheme,
          textTheme,
          'Your partner shared this with you. This reflects how they answered that day. Conflict responses can change with context, power, safety, culture, and relationship dynamics.',
        ),
      ],
    );
  }

  Widget _buildDisclaimer(
    ColorScheme colorScheme,
    TextTheme textTheme,
    String text,
  ) {
    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Text(
        text,
        style: textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }
}
