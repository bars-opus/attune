// lib/core/widgets/create_content_fab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/create_content_chooser.dart';

/// The "+" FAB shared by the Opinions sub-tabs (Following, Discover): one
/// shared button and behaviour instead of each feed owning its own.
///
/// Always visible, on every tab, regardless of auth state — tapping it as a
/// guest shows the sign-in snackbar instead of the tap silently doing
/// nothing.
///
/// Opens [CreateContentChooser], which goes straight to the opinion
/// composer, with the caller's feed-invalidation callback wired through.
class CreateContentFab extends StatelessWidget {
  const CreateContentFab({
    super.key,
    required this.isAuthenticated,
    required this.heroTag,
    this.onOpinionPosted,
  });

  final bool isAuthenticated;

  /// Required, not defaulted: Hero tags must be unique across the whole
  /// mounted subtree, not just the visible page, and the home shell keeps
  /// several tabs alive at once. Each caller passes its own distinct tag.
  final Object heroTag;

  /// Mirrors CreateContentChooser.show's own callback exactly — plug in the
  /// caller's existing feed-invalidation/scroll-to-top logic unchanged.
  final VoidCallback? onOpinionPosted;

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
        );
      },
    );
  }
}
