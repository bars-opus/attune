import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/opinions/domain/content_filter_error.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// The content filter's refusal, shown under the field it refused (Spec 1
/// §8 W9a, §2.3): an icon and the words, never colour alone, announced when
/// it appears. The draft stays in the field.
class ContentFilterNotice extends StatefulWidget {
  const ContentFilterNotice({
    super.key,
    required this.reason,
    this.part = ContentFilterPart.text,
  });

  final ContentFilterReason reason;

  /// Which part was refused: a reply's quote or a poll option changes the
  /// words (batch-3 review I-3).
  final ContentFilterPart part;

  @override
  State<ContentFilterNotice> createState() => _ContentFilterNoticeState();
}

class _ContentFilterNoticeState extends State<ContentFilterNotice> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
  }

  @override
  void didUpdateWidget(ContentFilterNotice old) {
    super.didUpdateWidget(old);
    if (old.reason != widget.reason || old.part != widget.part) _announce();
  }

  void _announce() {
    if (!mounted) return;
    SemanticsService.announce(
      widget.part.lines(widget.reason, AppLocalizations.of(context)!).join(' '),
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = widget.part.lines(
      widget.reason,
      AppLocalizations.of(context)!,
    );
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    return AllowLargeText(
      // No liveRegion: _announce already speaks it, and both would be read
      // twice by TalkBack (W9 final M-6).
      child: Semantics(
        container: true,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
          padding: Spacing.allSm,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            // The sheet it sits on is the same surface colour: the outline
            // shows the box there (batch-3 review M-1).
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadiusTokens.mdAll,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in lines) Text(line, style: style),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
