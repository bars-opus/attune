// lib/features/opinions/presentation/screens/opinion_compose_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/core/widgets/poll_composer.dart';
import 'package:attune/core/widgets/tag_picker.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class OpinionComposeScreen extends ConsumerStatefulWidget {
  /// Called after a successful post. Pushed screens instead pop with `true`
  /// for the caller to detect (see the old Navigator.push call sites this
  /// replaced), but this screen is now shown via
  /// BottomSheetUtils.showDocumentationBottomSheet, whose modal sheet has no
  /// meaningful "pop with a value" — showModalBottomSheet's result is
  /// discarded by that helper. A callback lets the sheet's caller react
  /// (invalidate feeds, scroll to top) the same way onboarding_flow.dart's
  /// _confirmMoveOn captures a tap via callback instead of a pop value.
  final VoidCallback? onPosted;

  const OpinionComposeScreen({super.key, this.onPosted});

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

  /// Matches the RPC's 5000-char ceiling (§8.11) — long enough for a real
  /// relationship story, not a tweet-length cap.
  static const int maxContentLength = 5000;

  /// A tap or a couple of stray characters isn't a real opinion — this
  /// gates the Post button's visibility (not just its enabled state) so an
  /// empty/near-empty draft doesn't offer a button that would just 22023
  /// from the RPC's own blank-content check.
  static const int minContentLength = 10;

  bool _isPostEnabled() {
    return _controller.text.trim().length >= minContentLength && !_isSubmitting;
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
        widget.onPosted?.call();
        // Still pop for the (now unused by in-app callers, but harmless)
        // case of this screen being reached via a plain Navigator.push.
        Navigator.maybePop(context, true);
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

    final statusDisplay = statusDisplayFor(status);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        // Scrollable rather than a fixed Column: the tag picker wraps up to 20
        // chips over several rows, which on a short screen (or with the
        // keyboard up) would overflow the viewport the plain Column assumed.
        body: ListView(
          children: [
            Gap(Spacing.md.h),

            Row(
              children: [
                Expanded(
                  child: InfoRowWidget(
                    title: statusDisplay,
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
                      onPressed: _isPostEnabled() ? _postOpinion : null,
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
            Gap(Spacing.lg.h),
            // Status display (blank name, just status)

            // Text input
            AppTextFormField(
              controller: _controller,
              focusNode: _focusNode,
              hintText: "What's on your mind?",
              maxLines: 12,
              minLines: 5,
              maxLength: maxContentLength,
              autofocus: true,
              // buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null, // Custom counter
              onChanged: (_) => setState(() {}),
              enabled: !_isSubmitting,
              label: '',
            ),

            // Optional tags (§8.11) and poll — both compact icon buttons
            // that open their own configuration sheet on tap, rather than
            // full-width rows, so the two sit side by side here instead of
            // each claiming the whole line.
            Row(
              children: [
                TagPickerRow(
                  currentSlugs: _tagSlugs,
                  onChanged: (slugs) => setState(() => _tagSlugs = slugs),
                ),
                PollComposerRow(
                  currentOptions: _pollOptions,
                  onChanged:
                      (options) => setState(() => _pollOptions = options),
                ),
              ],
            ),

            // Was a Spacer, which needs bounded height and cannot live
            // inside a scroll view — a plain trailing gap does the same job
            // here, since Post lives on the AppBar rather than at the
            // bottom of this column.
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
    );
  }
}
