// lib/core/widgets/create_content_chooser.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/screens/submit_topic_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';

/// Shown from any "+" entry point shared by Opinions and Forums — an
/// opinion post and a forum topic are different actions (different fields,
/// different validation, a topic's poll means something different from an
/// opinion's), not two views of one form, so this is a type picker in
/// front of their existing separate compose sheets rather than a merged
/// tabbed compose screen. Matches how Instagram/Twitter's "+" works: pick
/// what you're making, then land in that type's own dedicated flow.
class CreateContentChooser {
  /// Opens the chooser, then (on a row tap) the chosen type's compose
  /// sheet. [onOpinionPosted]/[onTopicSubmitted] mirror
  /// OpinionComposeScreen.onPosted / SubmitTopicScreen.onSubmitted exactly
  /// — the caller's existing feed-invalidation/scroll-to-top logic for
  /// each type plugs in unchanged.
  static Future<void> show({
    required BuildContext context,
    required Color backgroundColor,
    VoidCallback? onOpinionPosted,
    VoidCallback? onTopicSubmitted,
  }) async {
    // Wait for the chooser sheet to fully close before opening the next
    // one — two showModalBottomSheet calls in flight at once (pop this,
    // immediately push that) race against the same Navigator.
    await BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      maxHeight: 250.h,
      backgroundColor: backgroundColor,
      widget: _CreateContentChooserSheet(),
    );
    if (!context.mounted) return;

    switch (_lastChoice) {
      case _CreateChoice.opinion:
        await BottomSheetUtils.showDocumentationBottomSheet(
          context: context,
          backgroundColor: backgroundColor,
          widget: OpinionComposeScreen(onPosted: onOpinionPosted),
        );
      case _CreateChoice.topic:
        await BottomSheetUtils.showDocumentationBottomSheet(
          context: context,
          backgroundColor: backgroundColor,
          widget: SubmitTopicScreen(onSubmitted: onTopicSubmitted),
        );
      case null:
        return; // Dismissed without picking either.
    }
    _lastChoice = null;
  }

  // BottomSheetUtils.showDocumentationBottomSheet returns Future<void> (see
  // PollComposerRow/TagPickerRow for the same limitation) — it never
  // surfaces what the user tapped, so the row's onTap stashes the choice
  // here for show() to read once the sheet's own Future resolves. Reset to
  // null after every use so a later dismiss-without-choosing can't replay
  // a stale pick.
  static _CreateChoice? _lastChoice;
}

enum _CreateChoice { opinion, topic }

class _CreateContentChooserSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Plain static content (no scrollable) gives DraggableScrollableSheet
    // (inside BottomSheetUtils.showDocumentationBottomSheet) nothing to
    // detect a drag gesture on — it collapses to dismiss by watching scroll
    // notifications bubble from a scrollable descendant, so without one,
    // dragging on the sheet does nothing. SingleChildScrollView is that
    // scrollable, even though this content never actually needs to scroll.
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Gap(Spacing.lg),
          InfoRowWidget(
            title: 'Share an opinion',
            subtitle: 'A post readers react to, comment on, and vote on',
            icon: Icons.rate_review_outlined,
            showAvatar: false,
            showTrailingArrow: true,
            trailing: Icon(
              Icons.add,
              color: colorScheme.onBackground,
              size: 20.h,
            ),
            onTap: () {
              CreateContentChooser._lastChoice = _CreateChoice.opinion;
              Navigator.pop(context);
            },
          ),
          InfoRowWidget(
            title: 'Start a forum topic',
            subtitle: 'A debatable prompt others vote to activate and argue',
            icon: Icons.forum_outlined,
            showAvatar: false,
            showTrailingArrow: true,
            trailing: Icon(
              Icons.add,
              color: colorScheme.onBackground,
              size: 20.h,
            ),
            onTap: () {
              CreateContentChooser._lastChoice = _CreateChoice.topic;
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
