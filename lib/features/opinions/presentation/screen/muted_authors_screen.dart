// lib/features/opinions/presentation/screen/muted_authors_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/data/models/muted_author_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The people this viewer has muted, newest mute first (§8.11 "Muting and
/// hiding") — the one place a mute can be undone.
///
/// Deliberately much plainer than SavedOpinionsScreen/RepostedOpinionsScreen:
/// those render OpinionCards and paginate, whereas a mute list is a short list
/// of opaque handles with nothing to expand into. There is no profile to link
/// to and no post to preview — anonymity means the handle IS the whole
/// identity available here (FORUM.md §3) — so each row is just the handle,
/// when it was muted, and an Unmute action.
///
/// A standalone pushed route with its own Scaffold + AppBar, so like
/// SavedOpinionsScreen it has NO SliverOverlapInjector: there is no enclosing
/// SliverOverlapAbsorber outside OpinionsTab's NestedScrollView to find.
class MutedAuthorsScreen extends ConsumerWidget {
  const MutedAuthorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mutedAsync = ref.watch(mutedAuthorsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Muted', style: TextStyle(fontSize: 18)),
        leading: AppIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        // The list only changes through mute/unmute (both of which invalidate
        // this provider), so pull-to-refresh is a convenience rather than the
        // primary path — but it costs one line and matches the other screens.
        onRefresh: () async => ref.invalidate(mutedAuthorsProvider),
        child: mutedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => ErrorStateWidget.from(error),
          data: (muted) => _buildList(context, ref, muted),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<MutedAuthor> muted,
  ) {
    if (muted.isEmpty) {
      // Always-scrollable so pull-to-refresh still works on an empty list —
      // same reason the feed screens use these physics.
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EmptyStateWidget(
                icon: Icons.volume_off_outlined,
                title: 'No one muted',
                subtitle:
                    'Mute someone from the menu on their opinion to stop '
                    'seeing their posts in your feeds.',
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: muted.length,
      itemBuilder: (context, index) {
        final author = muted[index];
        return ListTile(
          title: Text(author.authorHandle),
          subtitle: Text('Muted ${_formatMutedAt(author.mutedAt)}'),
          trailing: TextButton(
            onPressed: () => _unmute(context, ref, author.authorHandle),
            child: const Text('Unmute'),
          ),
        );
      },
    );
  }

  Future<void> _unmute(
    BuildContext context,
    WidgetRef ref,
    String authorHandle,
  ) async {
    try {
      await unmuteAuthor(ref, authorHandle: authorHandle);
      if (!context.mounted) return;
      context.showInfoSnackbar('Unmuted. Their posts can appear again.');
    } catch (_) {
      if (!context.mounted) return;
      context.showInfoSnackbar('Could not unmute that person.');
    }
  }

  /// Same relative-time shape OpinionCard uses for post timestamps, so a mute
  /// date reads the same way a post date does elsewhere in this feature.
  String _formatMutedAt(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
