import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notes/note_date_sections.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../data/models/journal_note.dart';
import '../providers/reflection_journal_providers.dart';

enum _RowAction { pin, delete }

/// One entry in the list, as a notes row. Swipe RIGHT deletes (with Undo);
/// swipe LEFT pins or unpins. Long-press and screen-reader actions offer the
/// same, since swipes are neither discoverable nor available to assistive
/// technology.
class JournalEntryRow extends ConsumerWidget {
  const JournalEntryRow({super.key, required this.entry, required this.now, required this.last, required this.onTap});
  final JournalEntrySummary entry;
  final DateTime now;
  final bool last;
  final VoidCallback onTap;

  /// How long Undo is offered before the entry is gone for good.
  static const undoWindow = Duration(seconds: 6);

  String get _pinLabel => entry.pinned ? 'Unpin' : 'Pin';

  Future<void> _togglePin(BuildContext context, WidgetRef ref) async {
    final host = Navigator.of(context).context;
    try {
      await ref.read(journalListProvider.notifier).togglePin(entry);
    } catch (_) {
      host.showErrorSnackbar("Couldn't do that. Please try again.");
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final list = ref.read(journalListProvider.notifier);
    final host = Navigator.of(context).context;
    try {
      await list.delete(entry);
    } catch (_) {
      host.showErrorSnackbar("Couldn't delete that. Please try again.");
      return;
    }
    var undone = false;
    host.showInfoSnackbar('Entry deleted', actionLabel: 'Undo', onAction: () async {
      undone = true;
      try {
        await list.restore(entry.id);
      } catch (_) {
        host.showErrorSnackbar("Couldn't bring it back.");
      }
    });
    // After the Undo window it goes for good; if the app closes first, the
    // next visit's sweep finishes it.
    Future.delayed(undoWindow, () {
      if (!undone) list.purge(entry.id);
    });
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<_RowAction>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(entry.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(_pinLabel),
            onTap: () => Navigator.pop(c, _RowAction.pin),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Theme.of(c).colorScheme.error),
            title: const Text('Delete'),
            onTap: () => Navigator.pop(c, _RowAction.delete),
          ),
        ]),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _RowAction.pin:
        await _togglePin(context, ref);
      case _RowAction.delete:
        await _delete(context, ref);
    }
  }

  Widget _swipeBackground(BuildContext context, {required bool delete}) {
    final scheme = Theme.of(context).colorScheme;
    final fg = delete ? scheme.onErrorContainer : scheme.onPrimaryContainer;
    return Container(
      padding: Spacing.horizontalMd,
      color: delete ? scheme.errorContainer : scheme.primaryContainer,
      alignment: delete ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(delete ? Icons.delete_outline_rounded : (entry.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded), color: fg),
        const Gap(Spacing.xs),
        Text(delete ? 'Delete' : _pinLabel, style: TextStyle(color: fg)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('journal-${entry.id}'),
      background: _swipeBackground(context, delete: true),
      secondaryBackground: _swipeBackground(context, delete: false),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          await _togglePin(context, ref);
        } else {
          await _delete(context, ref);
        }
        return false; // the list itself removes or moves the row
      },
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: _pinLabel): () => _togglePin(context, ref),
          const CustomSemanticsAction(label: 'Delete'): () => _delete(context, ref),
        },
        child: GestureDetector(
          onLongPress: () => _menu(context, ref),
          child: InfoRowWidget(
            leadingWidget: const SizedBox.shrink(),
            avatarRadius: 0,
            iconSize: 0,
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
            // Title on top, one date underneath — as a note's row.
            title: entry.displayTitle,
            subtitle: noteRowDate(entry.createdAt, now),
            titleMaxLines: 1,
            subTitleMaxLines: 1,
            showDivider: !last,
            disableTrailing: !entry.hasPhoto,
            trailing: entry.hasPhoto
                ? Semantics(label: 'Has a photo', child: Icon(Icons.photo_outlined, size: 18, color: Theme.of(context).colorScheme.outline))
                : null,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
