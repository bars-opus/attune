import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/together_item.dart';
import '../../domain/together_story.dart';
import '../together_providers.dart';

/// "Add a line about Saturday?" (spec §6.3).
String memoryPromptQuestion(MemoryPrompt p, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final ago = today.difference(p.day).inDays;
  final when = switch (ago) {
    <= 0 => 'today',
    1 => 'yesterday',
    < 7 => DateFormat.EEEE().format(p.day),
    _ => DateFormat.MMMd().format(p.day),
  };
  return 'Add a line about $when?';
}

/// A confirmed, shared event of both of ours that I'm in, once it has
/// started (the server checks the same, plan R4).
bool canAddMemory(TogetherItem item, DateTime now, String? me) {
  if (item.kind != TogetherItemKind.event || me == null) return false;
  if (item.status != 'confirmed') return false;
  // A repeating event has no single day to remember (the server refuses too).
  if (item.sourceRef['rrule'] != null) return false;
  if (item.visibility != TogetherVisibility.shared) return false;
  if (item.participantIds.length != 2 || !item.participantIds.contains(me)) {
    return false;
  }
  final start = item.startsAt;
  return start != null ? !start.isAfter(now) : !item.day.isAfter(now);
}

Future<void> showAddMemorySheet(
  BuildContext context, {
  required String eventId,
  required String title,
}) async {
  final message = await BottomSheetUtils.showDocumentationBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: _AddMemorySheet(eventId: eventId, title: title),
  );
  if (message != null && context.mounted) context.showSuccessSnackbar(message);
}

class _AddMemorySheet extends ConsumerStatefulWidget {
  const _AddMemorySheet({required this.eventId, required this.title});
  final String eventId;
  final String title;

  @override
  ConsumerState<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends ConsumerState<_AddMemorySheet> {
  final _line = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final line = _line.text.trim();
    if (line.isEmpty) {
      context.showErrorSnackbar('Write a line first');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(togetherRepositoryProvider)
          .addEventMemory(widget.eventId, line);
      ref.invalidate(togetherMemoryPromptsProvider);
      ref.invalidate(togetherOnThisDayProvider);
      ref.invalidate(togetherRangeProvider);
      if (mounted) Navigator.of(context).pop('Added to your story.');
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar('Could not save that. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(
            title: 'Add a memory',
            actionLabel: 'Save',
            onPressed: _busy ? null : _save,
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Gap(Spacing.sm),
          AppTextFormField(
            controller: _line,
            label: 'A line to remember it by',
            maxLines: 3,
            maxLength: 300,
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
