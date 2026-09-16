// lib/features/planning/presentation/screens/planning_notes_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/planning_note_model.dart';
import '../providers/planning_providers.dart';
import 'planning_note_editor_screen.dart';

/// Newest-`updated_at`-first, title + first body line as the preview —
/// the shared-scratchpad shape (spec §6.3). Tapping opens ONE edit
/// surface; there is no separate read-only mode, matching the "either
/// partner can edit any note at any time" decision (spec §2).
class PlanningNotesScreen extends ConsumerWidget {
  const PlanningNotesScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(planningNotesProvider(relationshipId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlanningNoteEditorScreen(relationshipId: relationshipId),
            )).then((_) {
              ref.read(planningNotesProvider(relationshipId).notifier).refresh();
            }),
          ),
        ],
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: TextButton(
            onPressed: () => ref.read(planningNotesProvider(relationshipId).notifier).refresh(),
            child: const Text('Could not load notes. Retry.'),
          ),
        ),
        data: (notes) {
          if (notes.isEmpty) {
            return const Center(child: Text('No notes yet.'));
          }
          return ListView.builder(
            padding: EdgeInsets.symmetric(vertical: Spacing.sm),
            itemCount: notes.length,
            itemBuilder: (context, index) => _NoteListTile(
              note: notes[index],
              relationshipId: relationshipId,
            ),
          );
        },
      ),
    );
  }
}

class _NoteListTile extends ConsumerWidget {
  const _NoteListTile({required this.note, required this.relationshipId});
  final PlanningNoteModel note;
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstLine = note.body.split('\n').first;
    return ListTile(
      title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(firstLine, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlanningNoteEditorScreen(
          relationshipId: relationshipId,
          existingNote: note,
        ),
      )).then((_) {
        ref.read(planningNotesProvider(relationshipId).notifier).refresh();
      }),
    );
  }
}
