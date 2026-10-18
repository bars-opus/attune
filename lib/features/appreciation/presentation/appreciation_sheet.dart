import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/appreciation/data/appreciation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// "I noticed…" (Spec 7, research 06 B1): the person writes the middle; the
/// form around it is fixed. Sent as an ordinary message into the chat.
Future<bool?> showAppreciationSheet(
  BuildContext context, {
  required String relationshipId,
  required bool offerThankful,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  builder:
      (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: AppreciationSheet(
          relationshipId: relationshipId,
          offerThankful: offerThankful,
        ),
      ),
);

class AppreciationSheet extends ConsumerStatefulWidget {
  const AppreciationSheet({
    super.key,
    required this.relationshipId,
    required this.offerThankful,
  });

  final String relationshipId;

  /// Offer "Thankful for you because…" (a device setting; never sent on its
  /// own, only as the chosen words).
  final bool offerThankful;

  @override
  ConsumerState<AppreciationSheet> createState() => _AppreciationSheetState();
}

class _AppreciationSheetState extends ConsumerState<AppreciationSheet> {
  final _controller = TextEditingController();
  final _clientId = const Uuid().v4();
  bool _thankful = false;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _text =>
      composeAppreciation(_controller.text, thankful: _thankful);

  Future<void> _send() async {
    final text = _text;
    if (text == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(appreciationServiceProvider)
          .send(
            relationshipId: widget.relationshipId,
            clientMessageId: _clientId,
            text: text,
          );
      // The note arrives through the chat stream (plan review M10).
      if (mounted) Navigator.maybePop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send it. Try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final preview = _text;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.eco_outlined, color: scheme.primary),
                Gap(Spacing.sm.w),
                Text('I noticed…', style: text.titleMedium),
              ],
            ),
            Gap(Spacing.xs.h),
            Text(
              'Specific beats sweeping.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (widget.offerThankful) ...[
              Gap(Spacing.md.h),
              Wrap(
                spacing: Spacing.sm.w,
                children: [
                  ChoiceChip(
                    label: const Text('I noticed you…'),
                    selected: !_thankful,
                    onSelected: (_) => setState(() => _thankful = false),
                  ),
                  ChoiceChip(
                    label: const Text('Thankful for you because…'),
                    selected: _thankful,
                    onSelected: (_) => setState(() => _thankful = true),
                  ),
                ],
              ),
            ],
            Gap(Spacing.md.h),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.none,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                // Read out with the fixed frame (final review M-8).
                labelText: 'What you noticed',
                prefixText:
                    _thankful ? 'Thankful for you because ' : 'I noticed you ',
                hintText:
                    _thankful
                        ? 'you made the morning easy'
                        : "remembered Mum's appointment",
                helperText:
                    _controller.text.trim().isNotEmpty && preview == null
                        ? 'A little shorter, please.'
                        : null,
              ),
            ),
            if (preview != null) ...[
              Gap(Spacing.sm.h),
              Text(preview, style: text.bodyMedium),
            ],
            Gap(Spacing.md.h),
            FilledButton(
              onPressed: _sending || preview == null ? null : _send,
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}
