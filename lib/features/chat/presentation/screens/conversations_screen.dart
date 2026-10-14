import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/buttons/app_icon_button.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/providers/chat_ui_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart'
    as planning_providers;
import 'package:attune/features/planning/presentation/planning_ui.dart'
    show planningSummaryLine;
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/presentation/screens/story_camera_screen.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline_providers;
import 'package:attune/features/together/domain/together_agenda.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:intl/intl.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/widgets/story_rings_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:attune/features/chat/domain/utils/conversation_preview.dart';
import 'package:attune/features/location/presentation/widgets/partner_distance_row.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final conversationsAsync = ref.watch(conversationsProvider);
    final filtered = ref.watch(filteredConversationsProvider);
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: colorScheme.neutral,
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Row(
          children: [
            Text(
              'Couples',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            Icon(Icons.favorite, size: 20, color: colorScheme.error),
          ],
        ),
        actions: [
          AppIconButton(
            icon: Icons.menu,
            // TEMP preview hook: pushes FeatureIntroFlowScreen directly
            // instead of RouteNames.healingJourney (FeatureIntroFlowGate
            // + SeenFeatureIntroStore), so the intro shows every tap for
            // UI iteration — the real route only shows it once per
            // device, which made it invisible after the first visit.
            // Same module/copy/launchLabel the real healingJourney route
            // passes to FeatureIntroFlowGate — see app_router.dart.
            onPressed: () {
              context.pushNamed('settings');
            },
          ),
          // IconButton(
          //   onPressed: () => _openReflections(context),
          //   icon: const Icon(Icons.self_improvement_outlined),
          //   tooltip: 'Personal reflections',
          // ),
          // IconButton(
          //   onPressed: () {
          //     ref.read(unreadOnlyProvider.notifier).state =
          //         !ref.read(unreadOnlyProvider);
          //   },
          //   icon: Icon(
          //     ref.watch(unreadOnlyProvider)
          //         ? Icons.mark_chat_unread
          //         : Icons.mark_chat_unread_outlined,
          //   ),
          // ),
        ],
      ),
      body: SafeArea(
        // conversationsAsync.value (not .when's data/loading split) so a
        // background refresh — including the one that follows an instant
        // cache paint, see ConversationsNotifier — never blanks this screen
        // back to a spinner. ChatCacheService's read is SQLite-backed and
        // therefore always async, unlike forums' SharedPreferences cache, so
        // the provider legitimately passes through AsyncLoading on every
        // build() even on a warm-cache hit; only the very first launch ever
        // (no cache written yet) has no value to fall back to here.
        child:
            conversationsAsync.hasValue
                ? ListView(
                  padding: const EdgeInsets.all(Spacing.md),
                  children: [
                    // Two story rings, above the conversation tile (spec
                    // §5.1). Needs an active relationship to know which
                    // couple's stories to show, same precondition the
                    // conversation card below already has — so this
                    // simply reuses `filtered.first`'s identifiers rather
                    // than adding a new relationship lookup. Renders
                    // nothing when there is no active relationship yet,
                    // matching the "at most one active conversation"
                    // shape the rest of this screen already assumes.
                    if (filtered.isNotEmpty)
                      StoryRingsRow(
                        relationshipId: filtered.first.relationshipId,
                        partnerId: filtered.first.partnerId,
                        partnerName: filtered.first.partnerName,
                        onCapture:
                            () => _openStoryCamera(
                              context,
                              filtered.first.relationshipId,
                            ),
                        // Mine: only meaningful once myId is known —
                        // StoryRingsRow itself only wires onTap to a
                        // ring that already has something to open
                        // (a pending capture or activeCount > 0), so
                        // there is nothing else gating this callback
                        // here.
                        onOpenMine:
                            myId == null
                                ? null
                                : () => _openStoryReel(
                                  context,
                                  relationshipId: filtered.first.relationshipId,
                                  authorId: myId,
                                  isOwnReel: true,
                                ),
                        // Partner: StoryRingsRow only ever wires this
                        // when the partner's ring is actually drawn
                        // (activeCount > 0 for filtered.first.partnerId),
                        // per this widget's own doc comment.
                        onOpenPartner:
                            () => _openStoryReel(
                              context,
                              relationshipId: filtered.first.relationshipId,
                              authorId: filtered.first.partnerId,
                              isOwnReel: false,
                            ),
                      ),
                    // The current relationship's chat, or the empty-state
                    // prompt to start one — one card, since there's at most one
                    // active conversation to show (see filteredConversationsProvider).
                    CardInkWell(
                      borderRadius: BorderRadiusTokens.floatingNavAll,
                      child:
                          filtered.isEmpty
                              ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Text(
                                    'No relationship chat is available yet.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                              : _ConversationCard(
                                conversation: filtered.first,
                                previewText: _previewText(filtered.first),
                                onTap:
                                    () => _openConversation(
                                      context,
                                      filtered.first,
                                    ),
                              ),
                    ),
                    CardInkWell(
                      borderRadius: BorderRadiusTokens.floatingNavAll,
                      child: Column(
                        children: [
                          Gap(Spacing.sm.h),
                          const _LatestReflectionRow(),
                          Gap(Spacing.sm.h),
                          const _PlanningSummaryRow(),
                          Gap(Spacing.sm.h),
                          AppDivider(),
                          Gap(Spacing.sm.h),
                          const _TogetherRow(),
                          // Ambient relationship context, beside the next
                          // event rather than in a panel of its own:
                          // "how far apart are we" belongs with "dinner
                          // on Friday", not somewhere you go to check on
                          // someone. Renders nothing at all unless both
                          // partners share and the reading is fresh.
                          const _PartnerDistanceRow(),
                          Gap(Spacing.sm.h),
                        ],
                      ),
                    ),
                  ],
                )
                : conversationsAsync.hasError
                ? Center(
                  child: TextButton(
                    onPressed:
                        () =>
                            ref
                                .read(conversationsRefreshProvider.notifier)
                                .state++,
                    child: const Text('Reload chat'),
                  ),
                )
                : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  void _openConversation(BuildContext context, Conversation conversation) {
    context.push(RouteNames.chatScreen, extra: conversation);
  }

  // No named route exists yet for the story camera — it is a freshly
  // built screen (Plan B) that this task is the first to link to, and
  // adding a full go_router route/name is out of this task's scope
  // (rings only, per the brief). A direct MaterialPageRoute push is
  // enough to make the `+` affordance functional without touching
  // app_router.dart, which is exactly the kind of shared/core file this
  // screen's regression-risk notes warn against changing casually.
  void _openStoryCamera(BuildContext context, String relationshipId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryCameraScreen(relationshipId: relationshipId),
      ),
    );
  }

  // Same reasoning as _openStoryCamera immediately above: no named route
  // exists for the reel either (Task 4 built the screen but Task 4's own
  // brief scoped routing out to avoid a file collision here, and no
  // later task picked it up — this task folds that gap in). A plain
  // MaterialPageRoute push is enough; go_router's context.pop() resolves
  // it correctly on the way back out, so this is not the Plan B Task 7
  // hazard a named route would otherwise need to route around.
  void _openStoryReel(
    BuildContext context, {
    required String relationshipId,
    required String authorId,
    required bool isOwnReel,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => StoryReelScreen(
              relationshipId: relationshipId,
              authorId: authorId,
              isOwnReel: isOwnReel,
            ),
      ),
    );
  }

  String _previewText(Conversation conversation) =>
      conversationPreviewText(conversation);
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.previewText,
    required this.onTap,
  });

  final Conversation conversation;
  final String previewText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // No Hero: the conversation row and the chat header shared a
    // `tag: conversation.name`, so opening a chat flew the row up into the
    // header. The two are different shapes (a full-width row with preview
    // text and an unread badge, versus a 40pt avatar beside a title), so
    // the flight distorted both mid-transition rather than reading as one
    // element moving. The page transition alone is cleaner.
    return InfoRowWidget(
      title: conversation.name,
      subtitle: previewText,
      imageUrl: conversation.avatarUrl,
      icon: conversation.avatarUrl == null ? Icons.person_outline : null,
      subTitleMaxLines: 2,
      showDivider: false,
      iconColor: colorScheme.background,
      backgroundColor: colorScheme.primary,
      showAvatar: true,
      disableTrailing: false,
      showTrailingArrow: false,
      trailing: Row(
        children: [
          if (conversation.unreadCount > 0) ...[
            Container(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xs,
              ),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadiusTokens.floatingNavAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  conversation.unreadCount > 99
                      // Rolling digits don't make sense once the badge is
                      // showing a capped, non-exact "99+" rather than the
                      // real count.
                      ? Text(
                        '99+',
                        style: textTheme.labelLarge?.copyWith(
                          // fontSize: 12,
                          color: colorScheme.onPrimary,
                        ),
                      )
                      : AnimatedRollingCounter(
                        count: conversation.unreadCount,
                        style: textTheme.labelLarge?.copyWith(
                          // fontSize: 12,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                ],
              ),
            ),
          ],
          // Plain status icon instead of a labelled pill — canSend (active
          // relationship) reads as an open heart; anything else (read-only,
          // archived) reads as locked/archived, mirroring the icon language
          // _LockedConversationPreview already uses for the same states.
          if (!conversation.canSend)
            Icon(
              conversation.isArchived
                  ? Icons.archive_outlined
                  : conversation.canSend
                  ? Icons.favorite
                  : Icons.lock_outline,
              size: 18,
              color:
                  conversation.canSend
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Latest personal reflection entry, if any — same feature reachable via
/// _ReflectionRow below and ChatCouplesLockedScreen's own
/// _ReflectionEntryCard (both push 'reflectionJournal'), available to
/// singles and couples alike. Always routes to the journal list rather than
/// a specific entry's detail screen, matching those two existing entry
/// points instead of adding a third navigation shape.
class _LatestReflectionRow extends ConsumerWidget {
  const _LatestReflectionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final entriesAsync = ref.watch(journalEntriesProvider);

    final latest = entriesAsync.valueOrNull?.firstOrNull;

    return InfoRowWidget(
      title: latest?.content ?? 'Start your first reflection',
      subtitle: 'Reflection Note',
      icon: Icons.edit,
      iconColor: colorScheme.onSurfaceVariant.withOpacity(.4),
      subTitleMaxLines: 1,
      titleMaxLines: 1,
      showDivider: false,
      showAvatar: false,
      disableTrailing: false,
      showTrailingArrow: true,
      onTap: () => context.pushNamed('reflectionJournal'),
    );
  }
}

/// Summary row for Planning: the single most relevant thing — an overdue
/// to-do, else the next date or to-do, else the latest plan (ranked
/// server-side by get_planning_summary, spec §16, so this widget does no
/// ranking of its own). Same "one line, tap through to the full list" shape as
/// _LatestReflectionRow/_TogetherRow.
class _PlanningSummaryRow extends ConsumerWidget {
  const _PlanningSummaryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final relationshipIdAsync = ref.watch(planning_providers.currentRelationshipIdProvider);
    final relationshipId = relationshipIdAsync.valueOrNull;

    final summaryAsync = relationshipId == null
        ? const AsyncValue<PlanningSummary?>.data(null)
        : ref.watch(planning_providers.planningSummaryProvider(relationshipId));

    // Retains its last successful value during a refresh rather than
    // flashing to a loading state — matching this card's other rows'
    // no-jump behavior (spec §6.4).
    final summary = summaryAsync.valueOrNull;

    final title = planningSummaryLine(summary);

    return InfoRowWidget(
      title: title,
      subtitle: 'Planning',
      icon: Icons.checklist_outlined,
      iconColor: colorScheme.onSurfaceVariant.withOpacity(.4),
      subTitleMaxLines: 1,
      titleMaxLines: 1,
      showDivider: false,
      showAvatar: false,
      disableTrailing: false,
      showTrailingArrow: true,
      onTap: relationshipId == null
          ? null
          : () => context.pushNamed('planning', extra: relationshipId),
    );
  }
}

/// Wraps PartnerDistanceRow with the couple this screen is showing.
///
/// Resolves the relationship from the conversation list rather than
/// taking it as a parameter, matching how the reflection and calendar
/// rows above it find their own data.
class _PartnerDistanceRow extends ConsumerWidget {
  const _PartnerDistanceRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider).valueOrNull;
    if (conversations == null || conversations.isEmpty) {
      return const SizedBox.shrink();
    }

    final conversation = conversations.first;
    return PartnerDistanceRow(
      relationshipId: conversation.relationshipId,
      partnerName: conversation.partnerName,
    );
  }
}

/// The next thing on Together, with a way in.
class _TogetherRow extends ConsumerWidget {
  const _TogetherRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final relationshipId =
        ref.watch(timeline_providers.currentRelationshipIdProvider).valueOrNull;
    final now = DateTime.now();
    final range = togetherUpcomingRange(now);
    final items =
        relationshipId == null
            ? const <TogetherItem>[]
            : ref
                    .watch(
                      togetherRangeProvider((
                        relationshipId: relationshipId,
                        start: range.start,
                        end: range.end,
                      )),
                    )
                    .valueOrNull ??
                const <TogetherItem>[];
    final next = nextTogetherItem(items, now);
    String title = 'Nothing planned yet';
    if (next != null) {
      final days =
          next.day.difference(DateTime(now.year, now.month, now.day)).inDays;
      final when =
          days == 0
              ? 'today'
              : days == 1
              ? 'tomorrow'
              : 'in $days days';
      final s = next.startsAt;
      title =
          s == null || next.allDay
              ? '${next.title} $when'
              : '${next.title} $when, ${DateFormat.jm().format(s)}';
    }
    return InfoRowWidget(
      title: title,
      subtitle: 'Together',
      iconColor: colorScheme.onSurfaceVariant.withOpacity(.4),
      icon: Icons.calendar_month,
      subTitleMaxLines: 1,
      titleMaxLines: 1,
      showDivider: false,
      showAvatar: false,
      disableTrailing: false,
      showTrailingArrow: true,
      onTap: () => context.pushNamed('together'),
    );
  }
}
