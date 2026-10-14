import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/together_ai.dart';
import '../../domain/together_overlay.dart';
import '../together_providers.dart';
import 'couple_event_sheet.dart';

/// A free window: suggest a time, or (with AI on) three ideas to suggest.
Future<void> showFreeWindowSheet(
  BuildContext context, {
  required String relationshipId,
  required FreeWindow window,
  required String partnerName,
}) => BottomSheetUtils.showDocumentationBottomSheet<void>(
  context: context,
  backgroundColor: Theme.of(context).colorScheme.neutral,
  widget: _FreeWindowSheet(
    relationshipId: relationshipId,
    window: window,
    partnerName: partnerName,
  ),
);

class _FreeWindowSheet extends ConsumerStatefulWidget {
  const _FreeWindowSheet({
    required this.relationshipId,
    required this.window,
    required this.partnerName,
  });
  final String relationshipId;
  final FreeWindow window;
  final String partnerName;

  @override
  ConsumerState<_FreeWindowSheet> createState() => _FreeWindowSheetState();
}

class _FreeWindowSheetState extends ConsumerState<_FreeWindowSheet> {
  List<DateIdea>? _ideas;
  bool _loading = false;

  Future<void> _getIdeas() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final ideas = await ref
          .read(togetherAiRepositoryProvider)
          .ideas(widget.relationshipId, widget.window.start, widget.window.end);
      if (mounted) setState(() => _ideas = ideas);
    } on TogetherAiException catch (e) {
      if (!mounted) return;
      final off = e.code == 'CONSENT_REQUIRED' || e.code == 'FEATURE_DISABLED';
      if (off) {
        ref.invalidate(togetherAiAvailableProvider(widget.relationshipId));
      }
      context.showErrorSnackbar(switch (e.code) {
        _ when off => "AI help isn't available for you two right now.",
        'RATE_LIMITED' => "You've used today's AI help. Try again later.",
        _ => "Couldn't get ideas just now. Try again.",
      });
    } catch (_) {
      if (mounted) context.showErrorSnackbar("Couldn't get ideas just now.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _suggest({String? title, String? note}) {
    final navigator = Navigator.of(context);
    final host = navigator.context;
    navigator.pop();
    showCoupleEventSheet(
      host,
      relationshipId: widget.relationshipId,
      proposeWindow: (start: widget.window.start, end: widget.window.end),
      proposeTitle: title,
      proposeNote: note,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.window;
    final ai =
        ref
            .watch(togetherAiAvailableProvider(widget.relationshipId))
            .valueOrNull ??
        false;
    final ideas = _ideas;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(
            title:
                'Both free ${DateFormat.MMMEd().format(w.start)}, '
                '${DateFormat.jm().format(w.start)}–${DateFormat.jm().format(w.end)}',
          ),
          if (w.partnerDiffers)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Text(
                "That's ${w.partnerFrom}–${w.partnerTo} for ${widget.partnerName}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          InfoRowWidget(
            title: 'Suggest something for this time',
            subtitle: '${widget.partnerName} picks yes or no',
            icon: Icons.event_available_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () => _suggest(),
          ),
          if (ai && ideas == null) ...[
            AppDivider(),
            InfoRowWidget(
              title: 'Get 3 ideas',
              subtitle: 'Suggestions only; nothing is sent until you choose',
              icon: Icons.auto_awesome_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: _loading ? null : _getIdeas,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
          if (ideas != null)
            for (final i in ideas) ...[
              AppDivider(),
              InfoRowWidget(
                title: i.title,
                subtitle: i.blurb,
                icon: Icons.lightbulb_outline_rounded,
                showAvatar: false,
                showDivider: false,
                titleMaxLines: 1,
                subTitleMaxLines: 2,
                showTrailingArrow: true,
                onTap: () => _suggest(title: i.title, note: i.blurb),
              ),
            ],
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
