import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/buttons/app_icon_button.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/providers/chat_ui_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final conversationsAsync = ref.watch(conversationsProvider);
    final filtered = ref.watch(filteredConversationsProvider);

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
        child: conversationsAsync.when(
          data: (_) {
            return ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [
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
                                () =>
                                    _openConversation(context, filtered.first),
                          ),
                ),
                CardInkWell(
                  borderRadius: BorderRadiusTokens.floatingNavAll,
                  child: Column(
                    children: [
                      Gap(Spacing.sm.h),
                      const _LatestReflectionRow(),
                      Gap(Spacing.sm.h),
                      AppDivider(),
                      Gap(Spacing.sm.h),
                      const _NextCalendarEventRow(),
                      Gap(Spacing.sm.h),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (_, __) => Center(
                child: TextButton(
                  onPressed:
                      () =>
                          ref
                              .read(conversationsRefreshProvider.notifier)
                              .state++,
                  child: const Text('Reload chat'),
                ),
              ),
        ),
      ),
    );
  }

  void _openConversation(BuildContext context, Conversation conversation) {
    context.push(RouteNames.chatScreen, extra: conversation);
  }

  String _previewText(Conversation conversation) {
    final message = conversation.lastMessage;
    if (message == null) return 'No messages yet';
    if (message.mediaType == 'image' && message.content.trim().isEmpty) {
      return 'Photo';
    }
    if (message.mediaType == 'image' && message.content.trim().isNotEmpty) {
      return 'Photo: ${message.content}';
    }
    return message.content;
  }
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

/// Next upcoming reminder, if any — same source CouplesCalendarScreen
/// itself reads (remindersListProvider), same "Today"/"Tomorrow"/"In N
/// days" countdown language.
class _NextCalendarEventRow extends ConsumerWidget {
  const _NextCalendarEventRow();

  DateTime _nextOccurrence(ReminderModel reminder) {
    if (!reminder.isRecurring) return reminder.remindAt;
    final now = DateTime.now();
    var next = DateTime(
      now.year,
      reminder.remindAt.month,
      reminder.remindAt.day,
    );
    if (next.isBefore(DateTime(now.year, now.month, now.day))) {
      next = DateTime(
        now.year + 1,
        reminder.remindAt.month,
        reminder.remindAt.day,
      );
    }
    return next;
  }

  String _countdownLabel(DateTime occurrence) {
    final today = DateTime.now();
    final days =
        DateTime(
          occurrence.year,
          occurrence.month,
          occurrence.day,
        ).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return 'In $days days';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final remindersAsync = ref.watch(remindersListProvider);

    final reminders = remindersAsync.valueOrNull ?? const [];
    ReminderModel? next;
    DateTime? nextOccurrence;
    for (final reminder in reminders) {
      final occurrence = _nextOccurrence(reminder);
      if (nextOccurrence == null || occurrence.isBefore(nextOccurrence)) {
        next = reminder;
        nextOccurrence = occurrence;
      }
    }

    final title =
        next == null
            ? 'No upcoming events'
            : '${next.title} ${_countdownLabel(nextOccurrence!).toLowerCase()}';

    return InfoRowWidget(
      title: title,
      subtitle: 'Calendar',
      iconColor: colorScheme.onSurfaceVariant.withOpacity(.4),
      icon: Icons.calendar_month,
      subTitleMaxLines: 1,
      titleMaxLines: 1,
      showDivider: false,
      showAvatar: false,
      disableTrailing: false,
      showTrailingArrow: true,
      onTap: () => context.pushNamed('couplesCalendar'),
    );
  }
}
