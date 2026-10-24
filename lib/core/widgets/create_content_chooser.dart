// lib/core/widgets/create_content_chooser.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';

/// The one compose entry behind every Opinions "+" (the FAB, the app-bar
/// button and the Discover empty state). Forums were retired (Spec 3,
/// 2026-10), so there is nothing left to choose between: "+" opens the
/// opinion composer straight away, in the same bottom sheet as before. The
/// class keeps its name so callers, and any later compose option, build on
/// this one entry point.
class CreateContentChooser {
  /// Opens the opinion composer. [onOpinionPosted] is passed to
  /// OpinionComposeScreen.onPosted unchanged, so the caller's
  /// feed-invalidation and scroll-to-top logic runs after a post.
  static Future<void> show({
    required BuildContext context,
    required Color backgroundColor,
    VoidCallback? onOpinionPosted,
  }) {
    return BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      backgroundColor: backgroundColor,
      widget: OpinionComposeScreen(onPosted: onOpinionPosted),
    );
  }
}
