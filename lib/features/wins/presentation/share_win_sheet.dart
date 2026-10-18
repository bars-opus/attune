import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Share a win" (Spec 7, research 06 B2): a shared highlight; the partner
/// sees an in-app card to ask about it. Nothing is pushed.
Future<bool?> showShareWinSheet(
  BuildContext context, {
  required String relationshipId,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  builder:
      (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ShareWinSheet(relationshipId: relationshipId),
      ),
);

class ShareWinSheet extends ConsumerStatefulWidget {
  const ShareWinSheet({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  ConsumerState<ShareWinSheet> createState() => _ShareWinSheetState();
}

class _ShareWinSheetState extends ConsumerState<ShareWinSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(togetherRepositoryProvider)
          .shareAWin(
            widget.relationshipId,
            title: _title.text.trim(),
            note: _note.text.trim(),
          );
      if (mounted) Navigator.maybePop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't share it. Try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ready = _title.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_outlined, color: scheme.primary),
                Gap(Spacing.sm.w),
                Text('Share a win', style: text.titleMedium),
              ],
            ),
            Gap(Spacing.xs.h),
            Text(
              'It goes on your timeline, and they can ask you about it.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Gap(Spacing.md.h),
            TextField(
              key: const ValueKey('win-title'),
              controller: _title,
              autofocus: true,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'What happened?'),
            ),
            TextField(
              key: const ValueKey('win-note'),
              controller: _note,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Anything to add? (optional)',
              ),
            ),
            Gap(Spacing.md.h),
            FilledButton(
              onPressed: _sending || !ready ? null : _share,
              child: const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }
}
