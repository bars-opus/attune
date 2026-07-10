// lib/features/conflict_translator/presentation/screens/translator_sheet.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/conflict_translator/data/models/translator_response.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/translator_providers.dart';

class TranslatorSheet extends ConsumerWidget {
  final String originalMessage;
  final VoidCallback onSendOriginal;
  final Function(String) onSendRewrite;
  final Function(String) onEditRewrite;

  const TranslatorSheet({
    super.key,
    required this.originalMessage,
    required this.onSendOriginal,
    required this.onSendRewrite,
    required this.onEditRewrite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(translatorNotifierProvider);

    return Container(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg.w,
        Spacing.lg.h,
        Spacing.lg.w,
        MediaQuery.of(context).viewInsets.bottom + Spacing.lg.h,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  ref.read(translatorNotifierProvider.notifier).closeSheet();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          Gap(Spacing.md.h),

          // Side-by-side content
          if (state.isLoading) ...[
            _buildLoadingState(colorScheme, textTheme),
          ] else if (state.error != null) ...[
            _buildErrorState(context, textTheme),
          ] else if (state.response != null) ...[
            _buildTranslatorContent(
              context,
              ref,
              originalMessage,
              state.response!,
              colorScheme,
              textTheme,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 1500),
          builder: (context, value, child) {
            return Transform.scale(
              scale: 0.8 + (value * 0.4),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withValues(alpha: 0.2),
                ),
                child: Center(
                  child: Container(
                    width: 20,
                    height: 20,
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
        Gap(Spacing.md.h),
        Text(
          'Finding a better way to say this...',
          style: textTheme.titleMedium,
        ),
        Gap(Spacing.sm.h),
        Text(
          'This usually takes a moment.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    TextTheme textTheme,
  ) {
    return Column(
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        Gap(Spacing.md.h),
        Text(
          'Couldn\'t rewrite. Please try again.',
          style: textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        Gap(Spacing.md.h),
        AppButton(
          label: 'Try again',
          onPressed: () {
            // Retry logic will be handled by parent
            Navigator.pop(context);
          },
          size: ButtonSize.medium,
        ),
      ],
    );
  }

  Widget _buildTranslatorContent(
    BuildContext context,
    WidgetRef ref,
    String originalMessage,
    TranslatorResponse response,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final needsCaveat = response.isLowConfidence;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two columns
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildMessageCard(
                label: 'What you wrote',
                message: originalMessage,
                color: colorScheme.surfaceContainerHighest,
                textTheme: textTheme,
              ),
            ),
            Gap(Spacing.md.w),
            Expanded(
              child: _buildMessageCard(
                label: 'One way to say this',
                message: response.rewrite,
                color: colorScheme.primary.withValues(alpha: 0.05),
                textTheme: textTheme,
              ),
            ),
          ],
        ),
        Gap(Spacing.md.h),

        // Framing note
        Container(
          padding: EdgeInsets.all(Spacing.sm.w),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: colorScheme.primary,
              ),
              Gap(Spacing.sm.w),
              Expanded(
                child: Text(
                  'Underlying need: ${response.framingNote}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Low confidence caveat
        if (needsCaveat) ...[
          Gap(Spacing.sm.h),
          Container(
            padding: EdgeInsets.all(Spacing.sm.w),
            decoration: BoxDecoration(
              color: colorScheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_outlined,
                  size: 16,
                  color: Colors.orange,
                ),
                Gap(Spacing.sm.w),
                Expanded(
                  child: Text(
                    'This rewrite is a suggestion — it may not capture your exact meaning. Trust your instinct.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        Gap(Spacing.lg.h),

        // Buttons
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Send mine',
                onPressed: () async {
                  await ref
                      .read(translatorNotifierProvider.notifier)
                      .logUsage(
                        choseRewrite: false,
                        coreNeedIdentified: response.coreNeedIdentified,
                        rewriteConfidence: response.rewriteConfidence,
                        originalLength: originalMessage.length,
                        rewriteLength: response.rewrite.length,
                      );
                  onSendOriginal();
                },
                size: ButtonSize.medium,
                customColor: colorScheme.surfaceContainerHighest,
                textColor: colorScheme.onSurface,
              ),
            ),
            Gap(Spacing.sm.w),
            Expanded(
              child: AppButton(
                label: 'Send this',
                onPressed: () async {
                  await ref
                      .read(translatorNotifierProvider.notifier)
                      .logUsage(
                        choseRewrite: true,
                        coreNeedIdentified: response.coreNeedIdentified,
                        rewriteConfidence: response.rewriteConfidence,
                        originalLength: originalMessage.length,
                        rewriteLength: response.rewrite.length,
                      );
                  onSendRewrite(response.rewrite);
                },
                size: ButtonSize.medium,
              ),
            ),
            Gap(Spacing.sm.w),
            Expanded(
              child: AppButton(
                label: 'Edit this',
                onPressed: () async {
                  await ref
                      .read(translatorNotifierProvider.notifier)
                      .logUsage(
                        choseRewrite: true,
                        coreNeedIdentified: response.coreNeedIdentified,
                        rewriteConfidence: response.rewriteConfidence,
                        originalLength: originalMessage.length,
                        rewriteLength: response.rewrite.length,
                      );
                  onEditRewrite(response.rewrite);
                },
                size: ButtonSize.medium,
                customColor: colorScheme.surfaceContainerHighest,
                textColor: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageCard({
    required String label,
    required String message,
    required Color color,
    required TextTheme textTheme,
  }) {
    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelSmall),
          Gap(Spacing.sm.h),
          Text(message, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
