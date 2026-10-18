import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/conflict_toolkit/data/toolkit_texts.dart';
import 'package:attune/features/conflict_toolkit/presentation/toolkit_overflow.dart';
import 'package:uuid/uuid.dart';

/// Spec 8 (B3 (a); plan review M3): pick one of the three fixed messages.
/// "Take a pause", never "Pause", so it is never confused with pausing the
/// relationship. True when it was sent.
Future<bool?> showPauseSheet(
  BuildContext context, {
  required Future<void> Function(int variant, String clientMessageId) onSend,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  builder: (context) => PauseSheet(onSend: onSend),
);

class PauseSheet extends StatefulWidget {
  const PauseSheet({super.key, required this.onSend});

  final Future<void> Function(int variant, String clientMessageId) onSend;

  @override
  State<PauseSheet> createState() => _PauseSheetState();
}

class _PauseSheetState extends State<PauseSheet> {
  // One id for every try, so a retry never sends twice.
  final _clientId = const Uuid().v4();
  int _variant = 1;
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await widget.onSend(_variant, _clientId);
      if (mounted) Navigator.pop(context, true);
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ToolkitSheetTitle(
              title: 'Take a pause',
              subtitle: 'Only you see the timer.',
            ),
            Gap(Spacing.sm.h),
            _PauseChoices(
              value: _variant,
              onChanged: (v) => setState(() => _variant = v),
            ),
            Gap(Spacing.md.h),
            FilledButton(
              onPressed: _sending ? null : _send,
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The three messages as selectable rows.
class _PauseChoices extends StatelessWidget {
  const _PauseChoices({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final entry in kPauseTexts.entries)
          RadioListTile<int>(
            contentPadding: EdgeInsets.zero,
            value: entry.key,
            groupValue: value,
            onChanged: (v) => onChanged(v ?? 1),
            title: Text(entry.value),
          ),
      ],
    );
  }
}
