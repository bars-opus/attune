// lib/features/opinions/presentation/screens/opinion_compose_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/core/widgets/poll_composer.dart';
import 'package:attune/core/widgets/tag_picker.dart';
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

  /// Non-null only when the composer holds a valid 2-4 option poll (§8.11).
  List<String>? _pollOptions;

  /// Up to 3 slugs from the fixed vocabulary. Independent of [_pollOptions] —
  /// a post can carry a poll and tags, either, or neither.
  List<String> _tagSlugs = const [];

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
      final success = await postOpinionWithPoll(
        ref,
        content: content,
        pollOptions: _pollOptions,
        tagSlugs: _tagSlugs,
      );
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final status =
        ref.watch(userRelationshipStatusProvider).valueOrNull ?? 'single';

    final statusDisplay = _getStatusDisplay(status);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: true,
          title: Text(
            'New opinion',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            AppButton(
              label: 'Post',
              onPressed: _isPostEnabled() ? _postOpinion : null,
              size: ButtonSize.medium,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
          ],
        ),
        // Scrollable rather than a fixed Column: the tag picker wraps up to 20
        // chips over several rows, which on a short screen (or with the
        // keyboard up) would overflow the viewport the plain Column assumed.
        body: SingleChildScrollView(
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
              Gap(Spacing.md.h),
              // Optional poll (§8.11) — starts collapsed behind "Add poll".
              PollComposer(
                onChanged: (options) => setState(() => _pollOptions = options),
              ),
              Gap(Spacing.md.h),
              // Optional tags (§8.11) — a fixed vocabulary, max 3.
              TagPicker(
                onChanged: (slugs) => setState(() => _tagSlugs = slugs),
              ),
              // Was a Spacer, which needs bounded height and cannot live
              // inside a scroll view — a plain trailing gap does the same job
              // here, since Post lives on the AppBar rather than at the
              // bottom of this column.
              Gap(Spacing.xl.h),
            ],
          ),
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
