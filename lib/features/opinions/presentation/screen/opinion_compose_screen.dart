// lib/features/opinions/presentation/screens/opinion_compose_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class OpinionComposeScreen extends ConsumerStatefulWidget {
  const OpinionComposeScreen({super.key});

  @override
  ConsumerState<OpinionComposeScreen> createState() =>
      _OpinionComposeScreenState();
}

class _OpinionComposeScreenState extends ConsumerState<OpinionComposeScreen> {
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
    final remaining = 280 - _controller.text.length;
    return '$remaining characters remaining';
  }

  bool _isPostEnabled() {
    return _controller.text.trim().isNotEmpty && !_isSubmitting;
  }

  Future<void> _postOpinion() async {
    if (!_isPostEnabled()) return;
    if (ref.read(currentUserIdProvider) == null) {
      context.showInfoSnackbar(
        'Continue with phone number from Chat to post an opinion.',
      );
      return;
    }

    final content = _controller.text.trim();
    setState(() => _isSubmitting = true);

    try {
      final success = await ref.read(postOpinionProvider(content).future);
      if (success && mounted) {
        Navigator.pop(context, true); // Return true to signal refresh needed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status =
        ref.watch(userRelationshipStatusProvider).valueOrNull ?? 'single';

    final statusDisplay = _getStatusDisplay(status);

    return Scaffold(
      appBar: AppBar(
        title: Text('New opinion', style: textTheme.titleLarge),
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
            // Status display (blank name, just status)
            Text(
              statusDisplay,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Gap(Spacing.md.h),
            // Text input
            AppTextFormField(
              controller: _controller,
              focusNode: _focusNode,
              hintText: "What's on your mind?",
              maxLines: 8,
              maxLength: 280,
              // buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null, // Custom counter
              onChanged: (_) => setState(() {}),
              enabled: !_isSubmitting,
              label: '',
            ),
            Gap(Spacing.sm.h),
            // Character counter
            Text(
              _getRemainingCharacters(),
              style: textTheme.bodySmall?.copyWith(
                color:
                    _controller.text.length > 280
                        ? colorScheme.error
                        : colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const Spacer(),
            // Post button
            AppButton(
              label: 'Post',
              onPressed: _isPostEnabled() ? _postOpinion : null,
              size: ButtonSize.medium,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusDisplay(String status) {
    switch (status) {
      case 'single':
        return 'Single';
      case 'taken':
        return 'Taken';
      case 'figuring_it_out':
        return 'Figuring it out';
      case 'open':
        return 'Open';
      default:
        return '';
    }
  }
}
