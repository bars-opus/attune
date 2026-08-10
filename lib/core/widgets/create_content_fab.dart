// lib/core/widgets/create_content_fab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/create_content_chooser.dart';

/// The single "+" FAB shared by all four Opinions/Forums sub-tabs (Following,
/// Discover, Contributing, Explore) — one shared button/behavior instead of
/// each section owning its own differently-gated, differently-scoped FAB.
///
/// Always visible, on every tab, regardless of auth state — tapping it as a
/// guest shows the sign-in snackbar instead of the tap silently doing
/// nothing (the previous Opinions FAB) or the button being altogether absent
/// on some tabs (the previous Forums FAB, hidden outside Explore).
///
/// Opens [CreateContentChooser] with BOTH feed-invalidation callbacks wired,
/// not just the one relevant to whichever screen the FAB happened to be
/// declared on — a guest (well, signed-in user) picking "Start a forum
/// topic" from a FAB physically sitting on the Opinions tab still needs
/// votingTopicsProvider invalidated, not just the opinion feeds.
class CreateContentFab extends StatelessWidget {
  const CreateContentFab({
    super.key,
    required this.isAuthenticated,
    required this.heroTag,
    this.onOpinionPosted,
    this.onTopicSubmitted,
  });

  final bool isAuthenticated;

  /// Required, not defaulted: _OpinionsSection and ForumsSection each mount
  /// their own CreateContentFab, and both are kept alive simultaneously by
  /// OpinionsTab's IndexedStack (Opinions/Forums are sibling pages, not
  /// swapped out) — a single shared literal tag threw "multiple heroes share
  /// the same tag" the moment both were on screen at once, since Hero
  /// uniqueness is checked across the whole mounted subtree, not just the
  /// visible page. Each caller passes its own distinct tag.
  final Object heroTag;

  /// Mirrors CreateContentChooser.show's own callbacks exactly — plug in
  /// each caller's existing feed-invalidation/scroll-to-top logic unchanged.
  final VoidCallback? onOpinionPosted;
  final VoidCallback? onTopicSubmitted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppFab(
      scrollAware: true,
      heroTag: heroTag,
      icon: Icons.add,
      onPressed: () {
        if (!isAuthenticated) {
          context.showErrorSnackbar('Sign in to perform this action');
          return;
        }
        CreateContentChooser.show(
          context: context,
          backgroundColor: colorScheme.neutral,
          onOpinionPosted: onOpinionPosted,
          onTopicSubmitted: onTopicSubmitted,
        );
      },
    );
  }
}
