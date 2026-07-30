// lib/features/opinions/presentation/screen/edit_opinion_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Edits an existing opinion inside its 15-minute window
/// (ATTUNE_MASTER_SPEC.md §8.11 "Editing").
///
/// Mirrors [QuoteComposeScreen] / OpinionComposeScreen — same field,
/// same remaining-characters counter, same `Navigator.pop(context, true)`
/// success contract — because an edit runs the same validation a new post
/// does, and should feel like writing one. The differences are all in what is
/// NOT here: no poll composer (a poll is attached at creation and editing
/// text does not touch it) and no relationship-status line (status is captured
/// at post time and an edit must not restate it as though it were current).
///
/// The window is enforced by the RPC, not by this screen. The card only offers
/// Edit while there is time left, but a user can sit on this screen until the
/// window closes — so a submit can still come back `not_editable`, which is
/// surfaced as a snackbar rather than treated as a crash.
class EditOpinionScreen extends ConsumerStatefulWidget {
  final OpinionModel opinion;

  const EditOpinionScreen({super.key, required this.opinion});

  @override
  ConsumerState<EditOpinionScreen> createState() => _EditOpinionScreenState();
}

class _EditOpinionScreenState extends ConsumerState<EditOpinionScreen> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-filled with the current text: an edit is a revision, not a rewrite
    // from blank, so the existing content is the starting point.
    _controller = TextEditingController(text: widget.opinion.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Matches OpinionComposeScreen's ceiling — an edit runs the same
  /// validation a new post does (§8.11 "Editing").
  static const int maxContentLength = 5000;

  String _getRemainingCharacters() {
    final remaining = maxContentLength - _controller.text.length;
    return '$remaining characters remaining';
  }

  /// Also requires the text to have actually CHANGED, unlike the compose
  /// screens' equivalent: submitting an identical edit would stamp an
  /// "(edited)" marker on a post nobody edited, which is exactly the thing the
  /// marker is supposed to tell readers about.
  bool _isSaveEnabled() {
    final text = _controller.text.trim();
    return text.isNotEmpty &&
        text != widget.opinion.content.trim() &&
        !_isSubmitting;
  }

  Future<void> _save() async {
    if (!_isSaveEnabled()) return;

    final content = _controller.text.trim();
    setState(() => _isSubmitting = true);

    try {
      await editOpinion(ref, opinionId: widget.opinion.id, content: content);
      if (mounted) {
        // Same success signal the compose screens return, so a caller can
        // react (or ignore it — editOpinion has already patched the feeds in
        // place, so unlike posting there is nothing the caller must do).
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        context.showInfoSnackbar(_editErrorMessage(error));
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

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: true,
          title: Text(
            'Edit opinion',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: Spacing.md.w),
              child: AppButton(
                label: 'Save',
                onPressed: _isSaveEnabled() ? _save : null,
                size: ButtonSize.medium,
                width: 90.w,
                isLoading: _isSubmitting,
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(Spacing.lg.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextFormField(
                controller: _controller,
                focusNode: _focusNode,
                hintText: 'Say what you mean…',
                maxLines: 6,
                minLines: 3,
                maxLength: maxContentLength,
                onChanged: (_) => setState(() {}),
                enabled: !_isSubmitting,
                label: '',
              ),
              Gap(Spacing.sm.h),
              Text(
                _getRemainingCharacters(),
                style: textTheme.bodySmall?.copyWith(
                  color:
                      _controller.text.length > maxContentLength
                          ? colorScheme.error
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Gap(Spacing.md.h),
              // Sets expectations before the RPC has to: the window is the
              // one rule of this screen, and finding out it closed only on a
              // rejected Save would be a worse way to learn it.
              Text(
                'Edits are allowed within 15 minutes of posting. '
                'Edited posts show an "edited" label.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Maps the edit RPC's two rejections onto messages that say what the user can
/// do about it, rather than surfacing a raw PostgrestException.
///
/// `not_editable` deliberately covers three server-side cases (not owner,
/// removed, window closed) with one message — the window is the only one a
/// user acting through this screen can actually hit, so that is what it names.
String _editErrorMessage(Object error) {
  final text = error.toString();
  if (text.contains('not_editable')) {
    return 'That post can no longer be edited — the 15-minute window has closed.';
  }
  if (text.contains('invalid_content')) {
    return 'Your opinion must be between 1 and 5000 characters.';
  }
  return 'Could not save that edit.';
}
