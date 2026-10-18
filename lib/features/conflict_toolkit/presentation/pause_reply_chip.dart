import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/conflict_toolkit/data/pause_service.dart';
import 'package:attune/features/conflict_toolkit/data/toolkit_texts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Spec 8 (B3 (a); plan review I4; final review I-5): the one optional answer under a
/// received pause, shown only while the server says it is available.
/// Absent is the usual state, so its absence says nothing.
class PauseReplyChip extends ConsumerStatefulWidget {
  const PauseReplyChip({super.key, required this.pauseMessageId});

  final String pauseMessageId;

  @override
  ConsumerState<PauseReplyChip> createState() => _PauseReplyChipState();
}

class _PauseReplyChipState extends ConsumerState<PauseReplyChip> {
  final _clientId = const Uuid().v4();
  bool _sending = false;

  Future<void> _reply() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(pauseServiceProvider)
          .reply(
            pauseMessageId: widget.pauseMessageId,
            clientMessageId: _clientId,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send it. Try again.")),
        );
      }
    } finally {
      ref.invalidate(pauseReplyAvailableProvider(widget.pauseMessageId));
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available =
        ref
            .watch(pauseReplyAvailableProvider(widget.pauseMessageId))
            .valueOrNull ??
        false;
    if (!available) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: Spacing.xs.h),
      child: ActionChip(
        label: const Text(kPauseReplyText),
        onPressed: _sending ? null : _reply,
      ),
    );
  }
}
