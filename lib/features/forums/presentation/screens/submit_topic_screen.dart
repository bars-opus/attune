// lib/features/forums/presentation/screens/submit_topic_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class SubmitTopicScreen extends ConsumerStatefulWidget {
  const SubmitTopicScreen({super.key});

  @override
  ConsumerState<SubmitTopicScreen> createState() => _SubmitTopicScreenState();
}

class _SubmitTopicScreenState extends ConsumerState<SubmitTopicScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _getRemainingCharacters() {
    final remaining = 120 - _controller.text.length;
    return '$remaining characters remaining';
  }

  bool _isSubmitEnabled() {
    return _controller.text.trim().isNotEmpty && !_isSubmitting;
  }

  Future<void> _submitTopic() async {
    if (!_isSubmitEnabled()) return;

    final content = _controller.text.trim();
    setState(() => _isSubmitting = true);

    try {
      final success = await ref.read(submitTopicProvider(content).future);
      if (success && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit topic: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Submit a topic', style: textTheme.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Write a debatable topic as a question or statement',
              style: textTheme.bodyMedium,
            ),
            Gap(Spacing.md.h),
            AppTextFormField(
              controller: _controller,
              focusNode: _focusNode,
              hintText: 'e.g., Is jealousy ever healthy?',
              maxLines: 4,
              maxLength: 120,
              enabled: !_isSubmitting,
              label: '',
            ),
            Gap(Spacing.sm.h),
            Text(
              _getRemainingCharacters(),
              style: textTheme.bodySmall?.copyWith(
                color:
                    _controller.text.length > 120
                        ? colorScheme.error
                        : colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            Gap(Spacing.lg.h),
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Good topics invite two sides.',
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Gap(Spacing.xs.h),
                  Text(
                    '• "Long distance never works"',
                    style: textTheme.bodySmall,
                  ),
                  Text(
                    '• "Should you tell your partner everything?"',
                    style: textTheme.bodySmall,
                  ),
                  Text(
                    '• "Is it okay to keep some things private?"',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Spacer(),
            AppButton(
              label: 'Submit',
              onPressed: _isSubmitEnabled() ? _submitTopic : null,
              size: ButtonSize.medium,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }
}
