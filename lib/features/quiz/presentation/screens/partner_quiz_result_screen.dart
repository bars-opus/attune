// lib/features/quiz/presentation/screens/partner_quiz_result_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/domain/models/communication_style_result.dart';
import 'package:attune/features/quiz/domain/models/conflict_style_result.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/domain/models/shared_quiz_result.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
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
    final partnerResultAsync = ref.watch(
      partnerQuizResultProvider((quizType, partnerId)),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (quizType) {
          'attachment' => 'Partner\'s attachment style',
          'love_language' => 'Partner\'s love languages',
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
      case 'attachment':
        return _buildAttachmentContent(
          result.attachmentResult!,
          colorScheme,
          textTheme,
        );
      case 'love_language':
        return _buildLoveLanguageContent(
          result.loveLanguageResult!,
          colorScheme,
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

  Widget _buildAttachmentContent(
    AttachmentResult result,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.displayName,
          style: textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ),
        Gap(Spacing.lg.h),
        Text(result.poeticDescription, style: textTheme.bodyLarge),
        Gap(Spacing.xl.h),
        Text(
          'Their spectrum',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.md.h),
        _buildAttachmentSpectrumSummary(result, colorScheme, textTheme),
        Gap(Spacing.xl.h),
        Text(
          'What this means in practice',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Gap(Spacing.md.h),
        ...result.practiceBullets.map(
          (bullet) => Padding(
            padding: EdgeInsets.only(bottom: Spacing.md.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                Gap(Spacing.sm.w),
                Expanded(child: Text(bullet, style: textTheme.bodyMedium)),
              ],
            ),
          ),
        ),
        Gap(Spacing.xl.h),
        _buildDisclaimer(
          colorScheme,
          textTheme,
          'Your partner shared this with you. Attachment styles are not fixed and can shift over time.',
        ),
      ],
    );
  }

  Widget _buildLoveLanguageContent(
    LoveLanguageResult result,
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
        Text(
          'Secondary: ${result.getSecondaryDisplay()}',
          style: textTheme.titleMedium,
        ),
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
        Text(
          result.getDescription(result.primary),
          style: textTheme.bodyMedium,
        ),
        Gap(Spacing.xl.h),
        _buildDisclaimer(
          colorScheme,
          textTheme,
          'Your partner shared this with you. Love languages are a reflection tool, not a fixed label.',
        ),
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

  Widget _buildAttachmentSpectrumSummary(
    AttachmentResult result,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final List<Map<String, dynamic>> percentages = [
      {
        'label': 'Secure',
        'value': result.securePercentage,
        'color': colorScheme.primary,
      },
      {
        'label': 'Anxious',
        'value': result.anxiousPercentage,
        'color': Colors.orange,
      },
      {
        'label': 'Avoidant',
        'value': result.avoidantPercentage,
        'color': Colors.blue,
      },
      {
        'label': 'Fearful',
        'value': result.fearfulPercentage,
        'color': Colors.purple,
      },
    ];

    return Column(
      children:
          percentages.map((item) {
            return Padding(
              padding: EdgeInsets.only(bottom: Spacing.sm.h),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(item['label'], style: textTheme.bodySmall),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.sm.r,
                      ),
                      child: LinearProgressIndicator(
                        value: item['value'] / 100,
                        minHeight: 8,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        color: item['color'],
                      ),
                    ),
                  ),
                  Gap(Spacing.sm.w),
                  SizedBox(
                    width: 35,
                    child: Text(
                      '${item['value']}%',
                      style: textTheme.labelSmall,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
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
