import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart'
    show PlanningNewDot, planningRowDate;
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline;
import 'package:attune/features/together/domain/together_agenda.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/open_together_item.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_item_row.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many things the Upcoming card lists.
const conversationsUpcomingShown = 3;

/// The two journals, each with its latest: the reflection journal on top,
/// then (for a couple) the couples journal with the plan last worked on —
/// the top of Planning's Recent. Each row opens its journal.
class JournalsCard extends ConsumerWidget {
  const JournalsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relationshipId =
        ref.watch(timeline.currentRelationshipIdProvider).valueOrNull;
    return CardInkWell(
      borderRadius: BorderRadiusTokens.floatingNavAll,
      child: Column(
        children: [
          Gap(Spacing.sm.h),
          _ReflectionRow(divider: relationshipId != null),
          if (relationshipId != null)
            _CouplesJournalRow(relationshipId: relationshipId),
          Gap(Spacing.sm.h),
        ],
      ),
    );
  }
}

class _ReflectionRow extends ConsumerWidget {
  const _ReflectionRow({required this.divider});
  final bool divider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final latest = ref.watch(journalEntriesProvider).valueOrNull?.firstOrNull;
    return InfoRowWidget(
      title: journalRowTitle(latest),
      subtitle: MyDateFormat.join([
        'Reflection journal',
        if (latest != null) MyDateFormat.toDate(latest.updatedAt),
      ]),
      icon: Icons.edit,
      iconColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      subTitleMaxLines: 1,
      titleMaxLines: 1,
      showDivider: divider,
      showAvatar: false,
      showTrailingArrow: true,
      onTap: () => context.pushNamed('reflectionJournal'),
    );
  }
}

class _CouplesJournalRow extends ConsumerWidget {
  const _CouplesJournalRow({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final journal = coupleJournalTitle(
      ref.watch(coupleNameProvider(relationshipId)).valueOrNull,
    );
    // Keeps its last value while it refreshes, like the rows around it.
    final latest =
        ref
            .watch(planningRecentProvider(relationshipId))
            .valueOrNull
            ?.entries
            .firstOrNull;
    // Planning's own dot: a plan the partner changed since this person last
    // opened it. Hidden categories stay quiet, as they are on Planning.
    // Asked for only once there is a plan: the home RPC seeds the starter
    // categories, and with no plan nothing can be new.
    final hasNew =
        latest != null &&
        (ref
                .watch(planningHomeProvider(relationshipId))
                .valueOrNull
                ?.any((c) => c.hasNew && !c.hidden) ??
            false);
    return InfoRowWidget(
      title: latest?.entry.title ?? 'Start planning together',
      subtitle: MyDateFormat.join([
        journal,
        if (latest != null) latest.categoryName,
        if (latest != null)
          planningRowDate(latest.entry.lastActivityAt, DateTime.now()),
      ]),
      icon: Icons.checklist_outlined,
      iconColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      subTitleMaxLines: 1,
      titleMaxLines: 1,
      showDivider: false,
      showAvatar: false,
      showTrailingArrow: true,
      trailing:
          hasNew
              ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PlanningNewDot(),
                  Gap(Spacing.sm.w),
                  Icon(
                    Icons.chevron_right,
                    size: IconSizes.md.h,
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              )
              : null,
      // Back from Planning, the dot reflects the categories just opened. The
      // container, not ref: the row may be gone by the time Planning closes.
      onTap: () {
        final container = ProviderScope.containerOf(context, listen: false);
        context
            .pushNamed('planning', extra: relationshipId)
            .whenComplete(
              () => container.invalidate(planningHomeProvider(relationshipId)),
            );
      },
    );
  }
}

/// When the couple got together. A placeholder until the app asks for the
/// real date (it isn't collected yet), so the count still moves a day at a
/// time.
// TODO(together-since): replace with the couple's own start date once it
// is collected.
final togetherSincePlaceholder = DateTime(2025, 2, 14);

/// Whole days together on [now]'s calendar day (counted in UTC dates, so a
/// clock change can't skip or repeat one).
int daysTogether(DateTime now, {DateTime? since}) {
  final s = since ?? togetherSincePlaceholder;
  return DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(s.year, s.month, s.day)).inDays;
}

/// Together: how many days they've been together (the card opens the
/// calendar), then the dates they asked to be reminded of — anniversaries,
/// birthdays — at most three. Plans, to-dos and moments stay in Together.
class TogetherCard extends ConsumerWidget {
  const TogetherCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relationshipId =
        ref.watch(timeline.currentRelationshipIdProvider).valueOrNull;
    if (relationshipId == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final now = DateTime.now();
    final range = togetherUpcomingRange(now);
    final items = upcomingTogetherItems(
      [
        for (final i
            in ref
                    .watch(
                      togetherRangeProvider((
                        relationshipId: relationshipId,
                        start: range.start,
                        end: range.end,
                      )),
                    )
                    .valueOrNull ??
                const <TogetherItem>[])
          if (i.kind == TogetherItemKind.reminder) i,
      ],
      now,
      count: conversationsUpcomingShown,
    );
    final me = ref.watch(togetherMeProvider);
    final partnerName =
        ref.watch(quiz.partnerNameProvider).valueOrNull ?? 'Partner';
    final coupleName =
        ref.watch(coupleNameProvider(relationshipId)).valueOrNull;
    final days = daysTogether(now);
    return CardInkWell(
      borderRadius: BorderRadiusTokens.floatingNavAll,
      // Anywhere but an event row (which opens that event) opens the
      // calendar.
      onTap: () => context.pushNamed('together'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.md.w,
              Spacing.md,
              Spacing.xs.w,
              Spacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        '$days',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                          height: 1.1,
                        ),
                      ),
                      const Gap(Spacing.sm),
                      // "days" over "together", small and tight, left-aligned
                      // against the number.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'days',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              height: 1.0,
                            ),
                          ),
                          Text(
                            'together',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => context.pushNamed('together'),
                  child: const Text('Calendar'),
                ),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++)
            TogetherItemRow(
              item: items[i],
              me: me,
              partnerName: partnerName,
              coupleName: coupleName,
              lead: togetherCountdown(items[i].day, now),
              last: i == items.length - 1,
              onTap: () => openTogetherItem(context, items[i], relationshipId),
            ),
          Gap(Spacing.sm.h),
        ],
      ),
    );
  }
}
