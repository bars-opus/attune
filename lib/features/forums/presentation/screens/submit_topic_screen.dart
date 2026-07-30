// lib/features/forums/presentation/screens/submit_topic_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/core/widgets/poll_composer.dart';
import 'package:attune/core/widgets/tag_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class SubmitTopicScreen extends ConsumerStatefulWidget {
  /// See OpinionComposeScreen.onPosted — same rationale: shown via
  /// BottomSheetUtils.showDocumentationBottomSheet now, whose sheet has no
  /// meaningful "pop with a value" for the caller to read.
  final VoidCallback? onSubmitted;

  const SubmitTopicScreen({super.key, this.onSubmitted});

  @override
  ConsumerState<SubmitTopicScreen> createState() => _SubmitTopicScreenState();
}

class _SubmitTopicScreenState extends ConsumerState<SubmitTopicScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSubmitting = false;

  /// Non-null only when the composer holds a valid 2-4 option poll (§8.11).
  /// This is the topic's poll, which is separate from the up/down vote that
  /// decides whether the topic becomes a live debate room.
  List<String>? _pollOptions;

  /// Up to 3 slugs from the fixed vocabulary. Independent of [_pollOptions] —
  /// a topic can carry a poll and tags, either, or neither.
  List<String> _tagSlugs = const [];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Matches OpinionComposeScreen.maxContentLength's rationale, scaled to a
  /// topic's own 120-char cap (a debatable prompt, not an essay — see
  /// forum_topics.content's CHECK constraint).
  static const int maxContentLength = 120;

  /// A tap or a couple of stray characters isn't a real topic — gates the
  /// Submit button's visibility (not just its enabled state), same as
  /// OpinionComposeScreen.minContentLength.
  static const int minContentLength = 10;

  String _getRemainingCharacters() {
    final remaining = maxContentLength - _controller.text.length;
    return '$remaining characters remaining';
  }

  bool _isSubmitEnabled() {
    return _controller.text.trim().length >= minContentLength && !_isSubmitting;
  }

  Future<void> _submitTopic() async {
    if (!_isSubmitEnabled()) return;

    final content = _controller.text.trim();
    setState(() => _isSubmitting = true);

    try {
      final success = await submitTopicWithPoll(
        ref,
        content: content,
        pollOptions: _pollOptions,
        tagSlugs: _tagSlugs,
      );
      if (success && mounted) {
        widget.onSubmitted?.call();
        Navigator.maybePop(context, true);
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

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        // appBar: AppBar(
        //   title: Text('Submit a topic', style: textTheme.titleLarge),
        //   leading: IconButton(
        //     icon: const Icon(Icons.close),
        //     onPressed: () => Navigator.pop(context),
        //   ),
        // ),
        // SingleChildScrollView, not ListView: the whole form (header row,
        // text field, poll/tag rows, disclaimers) scrolls as one unit now
        // that Submit lives in the header row rather than pinned at the
        // bottom — a ListView gives its children unbounded height, which an
        // Expanded descendant further down needed a bounded parent for, so
        // that combination was hitting a RenderFlex layout error.
        body: SingleChildScrollView(
          child: Column(
            children: [
              Gap(Spacing.md.h),

              Row(
                children: [
                  Expanded(
                    child: InfoRowWidget(
                      title:
                          'Write a debatable topic as a question or statement',
                      subtitle: '',
                      iconColor: colorScheme.onBackground,
                      icon: Icons.close,
                      showAvatar: false,
                      showTrailingArrow: true,
                      showDivider: false,
                      disableTrailing: true,
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                  ),

                  if (_controller.text.trim().length >= minContentLength)
                    ShakeTransition(
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutBack,
                      child: AppButton(
                        elevation: 0,
                        animateButton: false,
                        label: 'Post',
                        isLoading: _isSubmitting,
                        onPressed: _isSubmitEnabled() ? _submitTopic : null,
                        textColor: colorScheme.surface,
                        size: ButtonSize.large,
                        width: 100,
                        padding: Spacing.horizontalMd,
                        height: 30.h,
                        borderRadius: BorderRadius.circular(100.r),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Gap(Spacing.md.h),
                  Text(
                    _getRemainingCharacters(),
                    style: textTheme.bodySmall?.copyWith(
                      color:
                          _controller.text.length > maxContentLength
                              ? colorScheme.error
                              : colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  Gap(Spacing.sm.h),

                  AppTextFormField(
                    controller: _controller,
                    focusNode: _focusNode,
                    hintText:
                        'e.g.,\n• "Is jealousy ever healthy?"\n• "Long distance never works"\n• "Should you tell your partner everything?\n• "Is it okay to keep some things private?',
                    maxLines: 4,
                    maxLength: maxContentLength,
                    autofocus: true,
                    enabled: !_isSubmitting,
                    // Drives the header row's Submit-button visibility and
                    // this field's own remaining-characters counter — both
                    // read _controller.text directly, so without this the
                    // screen only rebuilt (and caught up) whenever
                    // something else happened to trigger one, e.g.
                    // defocusing the field.
                    onChanged: (_) => setState(() {}),
                    label: '',
                  ),

                  // Optional poll (§8.11, distinct from the topic's
                  // activation vote) and tags (FORUM.md §7) — both compact
                  // icon buttons that open their own configuration sheet
                  // on tap, so they sit side by side rather than each
                  // claiming a full line.
                  Row(
                    children: [
                      PollComposerRow(
                        currentOptions: _pollOptions,
                        onChanged:
                            (options) => setState(() => _pollOptions = options),
                      ),

                      TagPickerRow(
                        currentSlugs: _tagSlugs,
                        onChanged: (slugs) => setState(() => _tagSlugs = slugs),
                      ),
                    ],
                  ),
                ],
              ),

              Gap(Spacing.md.h),

              SemanticContainerWidget(
                content:
                    'Opinions provide a space for you to discuss and express idealogies or concerns in a relationship',
                icon: Icons.info_outline,
                title: '',
                backgroundColor: Colors.grey.withOpacity(0.1),
                borderColor: Colors.grey,
                iconColor: Colors.grey,
                textTheme: textTheme,
              ),
              Gap(Spacing.md.h),
              SemanticContainerWidget(
                content:
                    'Only users who have created accounts can contribute, anonymouse users cannot contrinue',
                icon: Icons.warning_amber,
                title: '',
                backgroundColor: Colors.grey.withOpacity(0.1),
                borderColor: Colors.grey,
                iconColor: Colors.grey,
                textTheme: textTheme,
              ),
              Gap(Spacing.xl.h),
            ],
          ),
        ),
      ),
    );
  }
}
