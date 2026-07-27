// lib/features/opinions/presentation/screen/quote_compose_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/widgets/quoted_opinion_preview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Composes a quote: your own opinion, with the opinion you are quoting
/// embedded beneath it (ATTUNE_MASTER_SPEC.md §8.11 "Quotes").
///
/// Mirrors [OpinionComposeScreen] — same 280-char field, counter, Post action
/// and `Navigator.pop(context, true)` success contract — because a quote goes
/// through the same posting path as any opinion and should feel like one. The
/// only differences are the embedded preview and the absence of a poll
/// composer (a quote's payload is the reference; a poll on top would be two
/// unrelated attachments on one post).
class QuoteComposeScreen extends ConsumerStatefulWidget {
  /// The opinion the user tapped Quote on. Only its id is sent to the server —
  /// the RPC re-targets to the underlying original if this is itself a quote,
  /// so no chain-walking happens on the client.
  final OpinionModel quotedOpinion;

  const QuoteComposeScreen({super.key, required this.quotedOpinion});

  @override
  ConsumerState<QuoteComposeScreen> createState() => _QuoteComposeScreenState();
}

class _QuoteComposeScreenState extends ConsumerState<QuoteComposeScreen> {
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

  Future<void> _postQuote() async {
    if (!_isPostEnabled()) return;
    // Same phone-verified gate as posting — a quote is a post (§8.11
    // "Participation gate").
    if (ref.read(currentUserIdProvider) == null) {
      context.showInfoSnackbar(
        'Continue with phone number from Chat to quote opinions.',
      );
      return;
    }

    final content = _controller.text.trim();
    setState(() => _isSubmitting = true);

    try {
      await postQuoteOpinion(
        ref,
        content: content,
        quotedOpinionId: widget.quotedOpinion.id,
      );
      if (mounted) {
        // Same signal OpinionComposeScreen returns: the call site invalidates
        // the feeds and scrolls to top so the new post is visible.
        Navigator.pop(context, true);
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

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: true,
          title: Text(
            'Quote opinion',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          actions: [
            AppButton(
              label: 'Post',
              onPressed: _isPostEnabled() ? _postQuote : null,
              size: ButtonSize.medium,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(Spacing.lg.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Your own status — the quote is attributed to you, not to the
              // author you are quoting.
              Text(
                _getStatusDisplay(status),
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Gap(Spacing.md.h),
              AppTextFormField(
                controller: _controller,
                focusNode: _focusNode,
                hintText: 'Add your take…',
                maxLines: 6,
                maxLength: 280,
                onChanged: (_) => setState(() {}),
                enabled: !_isSubmitting,
                label: '',
              ),
              Gap(Spacing.sm.h),
              Text(
                _getRemainingCharacters(),
                style: textTheme.bodySmall?.copyWith(
                  color:
                      _controller.text.length > 280
                          ? colorScheme.error
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Gap(Spacing.md.h),
              // The opinion being quoted, rendered exactly as it will appear
              // inside the posted quote's card — the same non-interactive
              // preview widget, so what you see composing is what ships.
              QuotedOpinionPreview(quotedOpinionId: widget.quotedOpinion.id),
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
