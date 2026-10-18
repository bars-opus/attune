import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:attune/features/wins/domain/win_card.dart';
import 'package:attune/features/wins/presentation/share_win_sheet.dart';
import 'package:attune/features/wins/presentation/win_providers.dart';
import 'package:attune/features/appreciation/data/appreciation_service.dart';
import 'package:attune/features/appreciation/data/thankful_phrasing_preference.dart';
import 'package:attune/features/appreciation/presentation/appreciation_jar_screen.dart';
import 'package:attune/features/appreciation/presentation/appreciation_sheet.dart';
import 'package:attune/features/reminders/presentation/screens/family_members_screen.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart'
    show planningRoute;
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/planning_skeletons.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline_providers;
import 'package:attune/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:attune/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show conversationsProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/together_item.dart';
import '../../domain/together_agenda.dart';
import '../../domain/together_care.dart';
import '../../domain/together_need.dart';
import '../../data/together_calendar_mirror.dart';
import '../../data/together_device_surfaces.dart';
import '../../data/together_live_activity.dart';
import '../../data/together_widget_sync.dart';
import '../../domain/together_overlay.dart';
import '../../domain/together_live.dart';
import '../../domain/together_widget.dart';
import '../../domain/together_ritual.dart';
import '../../domain/together_story.dart';
import '../open_together_item.dart';
import '../together_providers.dart';
import '../widgets/together_need_sheets.dart';
import '../widgets/couple_event_sheet.dart';
import '../widgets/free_window_sheet.dart';
import 'together_memories_screen.dart';
import '../widgets/memory_sheets.dart';
import '../widgets/ritual_sheets.dart';
import '../widgets/together_item_row.dart';
import '../widgets/together_section.dart';
import '../widgets/together_settings_sheet.dart';

enum _View { agenda, month }

/// This couple's chat: the one for [relationshipId] (preferring one we can
/// send in), else any chat we can send in. Null when there is none.
@visibleForTesting
Conversation? togetherConversationFor(
  List<Conversation> conversations,
  String relationshipId,
) {
  final ours = conversations.where((c) => c.relationshipId == relationshipId);
  for (final c in ours) {
    if (c.canSend) return c;
  }
  if (ours.isNotEmpty) return ours.first;
  for (final c in conversations) {
    if (c.canSend) return c;
  }
  return null;
}

/// The couple's life hub: what's on today and this week, what's coming,
/// and the story so far. The Month view is the calendar (TimelineScreen).
class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key, this.embedded = false});

  /// Inside another screen's tab: no app bar of its own.
  final bool embedded;

  @override
  ConsumerState<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends ConsumerState<TogetherScreen> {
  _View _view = _View.agenda;

  /// Month is built the first time it's chosen, then kept.
  bool _monthOpened = false;

  /// The header and tabs tuck away while scrolling down and come back on
  /// any scroll up, so a long Agenda or Month gets the room.
  bool _headerTucked = false;

  /// Tuck on a user's scroll down, show on a scroll up or once settled at
  /// the top.
  /// Only lists long enough to fill the space the header gives back tuck
  /// it, so a short list never jumps.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    var tucked = _headerTucked;
    // A drag down announces itself while the list is still at the top.
    if (n is UserScrollNotification) {
      final room = n.metrics.maxScrollExtent - n.metrics.minScrollExtent;
      if (n.direction == ScrollDirection.reverse && room > 160) tucked = true;
      if (n.direction == ScrollDirection.forward) tucked = false;
    } else if (n is ScrollEndNotification &&
        n.metrics.pixels <= n.metrics.minScrollExtent) {
      tucked = false;
    }
    if (tucked != _headerTucked) setState(() => _headerTucked = tucked);
    return false;
  }

  /// The device zone is reported once per visit (best effort).
  bool _zoneReported = false;

  /// A share that was already waiting when Together opened is taken once.
  bool _sharedChecked = false;

  void _openShared(PendingShare share) {
    if (!mounted) return;
    final id =
        ref.read(timeline_providers.currentRelationshipIdProvider).valueOrNull;
    if (id == null) return; // waits until Together is reachable
    ref.read(pendingShareProvider.notifier).state = null;
    if (share.expiredAt(DateTime.now())) return;
    showCoupleEventSheet(context, relationshipId: id, initialText: share.text);
  }

  /// My calendar's busy times are refreshed once per visit (Phase 6 R4).
  bool _busySynced = false;

  /// The calendar copy is refreshed once per visit (Phase 8d R4).
  bool _mirrorSynced = false;

  /// With no relationship any more, its plans leave the phone (8d R5).
  bool _orphansCleared = false;

  Future<void>? _mirrorRun;

  /// One at a time: two syncs at once would both see the same gaps and copy
  /// plans (or make a calendar) twice.
  Future<void> _syncMirror(String relationshipId) {
    final repo = ref.read(togetherRepositoryProvider);
    final previous = _mirrorRun ?? Future<void>.value();
    return _mirrorRun = previous.then(
      (_) => TogetherMirror.syncIfEnabled(
        (from, to) => repo.listItems(relationshipId, start: from, end: to),
        ref.read(togetherMeProvider),
        ref.read(togetherClockProvider)(),
      ),
    );
  }

  /// Memory prompts I tapped "Not now" on this visit (Phase 4 R4).
  final Set<String> _dismissed = {};

  /// Win cards asked about or put aside this visit (Spec 7, B2).
  final Set<String> _winsAsked = {};

  Future<void> _reportZone(String relationshipId) async {
    try {
      final tz = await ref.read(togetherDeviceTimezoneProvider.future);
      await ref
          .read(togetherRepositoryProvider)
          .reportTimezone(relationshipId, tz);
    } catch (_) {
      // Best effort: Planning reports it too, and UTC is the fallback.
    }
  }

  Future<void> _add(String relationshipId) =>
      openAddFlow(context, relationshipId: relationshipId);

  void _open(TogetherItem item, String relationshipId) => openTogetherItem(
    context,
    item,
    relationshipId,
    onMoment: () => setState(() => _view = _View.month),
  );

  /// Refetch both ranges, not just the agenda built from them.
  Future<void> _reload(String relationshipId) {
    ref.invalidate(togetherRangeProvider);
    return ref.read(togetherAgendaProvider(relationshipId).future);
  }

  Widget _needRow(
    TogetherNeed n,
    String relationshipId,
    String partnerName, {
    bool last = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, subtitle) = switch (n.kind) {
      TogetherNeedKind.proposal => (
        Icons.how_to_vote_outlined,
        '$partnerName suggested · pick a time',
      ),
      TogetherNeedKind.ritualProposal => (
        Icons.event_repeat_rounded,
        '$partnerName suggested a ritual',
      ),
      TogetherNeedKind.sentProposal => (
        Icons.hourglass_empty_rounded,
        'No reply yet',
      ),
      TogetherNeedKind.handoff => (
        Icons.front_hand_outlined,
        '$partnerName asked you to take this on',
      ),
      TogetherNeedKind.unownedTodo => (
        Icons.check_box_outline_blank_rounded,
        n.dueDate == null
            ? 'Nobody has this yet'
            : MyDateFormat.join([
              'Nobody has this yet',
              'due ${DateFormat.MMMEd().format(n.dueDate!)}',
            ]),
      ),
      TogetherNeedKind.poll => (
        Icons.date_range_outlined,
        'Pick the dates that work for you',
      ),
    };
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      icon: icon,
      iconColor: colorScheme.primary,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      title: n.title.isEmpty ? 'Untitled' : n.title,
      subtitle: subtitle,
      titleMaxLines: 1,
      subTitleMaxLines: 1,
      showDivider: !last,
      disableTrailing: true,
      onTap: () => _openNeed(n, relationshipId),
    );
  }

  void _openNeed(TogetherNeed n, String relationshipId) {
    switch (n.kind) {
      case TogetherNeedKind.proposal:
        showProposalSheet(context, n);
      case TogetherNeedKind.ritualProposal:
        showRitualProposalSheet(context, n);
      case TogetherNeedKind.sentProposal:
        showSentProposalSheet(context, n);
      case TogetherNeedKind.handoff:
        showHandoffSheet(context, n);
      case TogetherNeedKind.unownedTodo:
      case TogetherNeedKind.poll:
        final entryId = n.entryId;
        if (entryId == null) return;
        Navigator.of(context).push(
          planningRoute(
            PlanningEntryScreen(
              relationshipId: relationshipId,
              entryId: entryId,
            ),
          ),
        );
    }
  }

  void _showAllNeeds(
    List<TogetherNeed> needs,
    String relationshipId,
    String partnerName,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (c) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < needs.length; i++)
                  _needRow(
                    needs[i],
                    relationshipId,
                    partnerName,
                    last: i == needs.length - 1,
                  ),
              ],
            ),
          ),
    );
  }

  /// "Add a line about Saturday?" for a lived shared event (Phase 4 R4).
  Widget _memoryPromptRow(MemoryPrompt p, DateTime now, {bool divider = true}) {
    final colorScheme = Theme.of(context).colorScheme;
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      icon: Icons.edit_note_rounded,
      iconColor: colorScheme.primary,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      title: memoryPromptQuestion(p, now),
      subtitle: p.title,
      titleMaxLines: 2,
      subTitleMaxLines: 1,
      showDivider: divider,
      trailing: TextButton(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        ),
        onPressed: () async {
          setState(() => _dismissed.add(p.eventId));
          try {
            await ref
                .read(togetherRepositoryProvider)
                .dismissMemoryPrompt(p.eventId);
          } catch (_) {
            // Best effort: it is hidden for this visit either way.
          }
        },
        child: const Text('Not now'),
      ),
      onTap:
          () => showAddMemorySheet(context, eventId: p.eventId, title: p.title),
    );
  }

  Widget _onThisDayRow(OnThisDayItem i) => InfoRowWidget(
    padding: const EdgeInsets.symmetric(
      horizontal: Spacing.md,
      vertical: Spacing.xs,
    ),
    icon: Icons.history_rounded,
    title: i.title,
    subtitle: MyDateFormat.join(['On this day', i.lead]),
    titleMaxLines: 1,
    subTitleMaxLines: 1,
    showDivider: true,
    disableTrailing: true,
  );

  /// Every moment, a page at a time (Phase 4 R8).
  void _openMemories(String relationshipId) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TogetherMemoriesScreen(relationshipId: relationshipId),
    ),
  );

  /// A time we're both free (Phase 6 R6): tap to suggest something then.
  Widget _freeWindowRow(
    FreeWindow w,
    String relationshipId,
    String partnerName, {
    bool today = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final time =
        '${DateFormat.jm().format(w.start)}–${DateFormat.jm().format(w.end)}';
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      icon: Icons.event_available_rounded,
      iconColor: colorScheme.primary,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      title:
          today
              ? 'Both free $time'
              : MyDateFormat.join([DateFormat.MMMEd().format(w.start), time]),
      subtitle:
          w.partnerDiffers
              ? "That's ${w.partnerFrom}–${w.partnerTo} for $partnerName"
              : 'Tap to suggest something',
      titleMaxLines: 1,
      subTitleMaxLines: 1,
      showDivider: true,
      disableTrailing: true,
      onTap:
          () => showFreeWindowSheet(
            context,
            relationshipId: relationshipId,
            window: w,
            partnerName: partnerName,
          ),
    );
  }

  /// A warm nudge around my partner's big day (plan 2b): fixed copy.
  Widget _careRow(CareCard c, String partnerName) {
    final colorScheme = Theme.of(context).colorScheme;
    final before = c.phase == CarePhase.before;
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      icon: Icons.favorite_rounded,
      iconColor: colorScheme.primary,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      title:
          before
              ? "$partnerName's big day: ${c.item.title}"
              : 'How did ${c.item.title} go?',
      subtitle: before ? 'Send a word of luck' : 'Ask $partnerName how it went',
      titleMaxLines: 1,
      subTitleMaxLines: 1,
      showDivider: true,
      disableTrailing: true,
      onTap: () => _openChatWith(careDraft(c), c.item),
    );
  }

  /// Opens our chat with [draft] ready to send (or edit).
  /// True when the chat opened (a win card is put aside only then; Spec 7
  /// final review M-10).
  Future<bool> _openChatWith(String draft, [TogetherItem? about]) async {
    final relationshipId =
        ref.read(timeline_providers.currentRelationshipIdProvider).valueOrNull;
    List<Conversation> conversations;
    try {
      conversations = await ref.read(conversationsProvider.future);
    } catch (_) {
      conversations = const [];
    }
    if (!mounted) return false;
    final chat =
        relationshipId == null
            ? null
            : togetherConversationFor(conversations, relationshipId);
    if (chat == null) {
      context.showErrorSnackbar('Chat isn’t available right now.');
      return false;
    }
    context.pushNamed(
      'chatScreen',
      extra: chat,
      queryParameters: {'draft': draft},
    );
    return true;
  }

  /// A ritual on the Agenda: what, and when next (never how often missed).
  Widget _ritualRow(
    TogetherRitual r,
    String relationshipId,
    String? me,
    String partnerName,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final next = r.nextStartsAt;
    final subtitle = switch (r.status) {
      RitualStatus.proposed =>
        r.createdBy == me ? 'Waiting for $partnerName' : r.when,
      RitualStatus.paused => 'Paused',
      RitualStatus.active =>
        next == null
            ? r.when
            : 'Next: ${MyDateFormat.join([DateFormat.MMMEd().format(next), DateFormat.jm().format(next)])}',
    };
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      icon: Icons.event_repeat_rounded,
      iconColor: colorScheme.primary,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      title: r.title,
      subtitle: subtitle,
      titleMaxLines: togetherRowLines(context).title,
      subTitleMaxLines: togetherRowLines(context).subtitle,
      showDivider: true,
      disableTrailing: true,
      onTap: switch (r.status) {
        RitualStatus.proposed when r.createdBy == me =>
          () => showSentRitualSheet(context, r),
        // A suggestion to me is answered from Needs you.
        RitualStatus.proposed => null,
        _ => () => showRitualSheet(context, relationshipId, r),
      },
    );
  }

  String _dayLabel(DateTime day, DateTime today) {
    final diff = day.difference(today).inDays;
    if (diff == 1) return 'Tomorrow';
    return DateFormat('EEEE d MMM').format(day);
  }

  List<Widget> _rows(
    List<TogetherItem> items,
    String relationshipId,
    String? me,
    String partnerName, {
    String? Function(TogetherItem)? lead,
  }) => [
    for (var i = 0; i < items.length; i++)
      TogetherItemRow(
        item: items[i],
        me: me,
        partnerName: partnerName,
        coupleName: ref.watch(coupleNameProvider(relationshipId)).valueOrNull,
        last: i == items.length - 1,
        lead: lead?.call(items[i]),
        onTap: () => _open(items[i], relationshipId),
      ),
  ];

  Future<void> _publishWidget(
    TogetherAgenda? agenda,
    List<FreeWindow> windows,
    String? me,
    DateTime now,
  ) async {
    if (agenda == null) return;
    if (!mounted) return;
    await TogetherWidgetSync.publishIfEnabled(
      togetherWidgetLines(
        items: [
          ...agenda.today,
          for (final d in agenda.week) ...d.items,
          ...agenda.comingUp,
        ],
        windows: windows,
        me: me,
        now: now,
      ),
    );
  }

  Future<void> _publishLive(
    TogetherAgenda? agenda,
    String? me,
    DateTime now,
  ) async {
    if (agenda == null || !mounted) return;
    await TogetherLiveActivity.showIfEnabled(
      livePlanFor(
        items: [
          ...agenda.today,
          for (final d in agenda.week) ...d.items,
          ...agenda.comingUp,
        ],
        me: me,
        now: now,
      ),
    );
  }

  /// Spec 7 (B1, B2): write an "I noticed…" note, open the jar, share a win.
  Widget _goodThingsSection(
    String relationshipId, {
    required bool appreciation,
    required bool wins,
  }) => TogetherSection(
    title: 'Good things',
    children: [
      if (appreciation) ...[
        InfoRowWidget(
          title: 'Notice something',
          subtitle: 'Specific beats sweeping.',
          icon: Icons.eco_outlined,
          showAvatar: false,
          showTrailingArrow: true,
          onTap:
              () => showAppreciationSheet(
                context,
                relationshipId: relationshipId,
                offerThankful: ref.read(thankfulPhrasingProvider),
              ),
        ),
        InfoRowWidget(
          title: 'Your appreciation jar',
          subtitle: '',
          icon: Icons.inventory_2_outlined,
          showAvatar: false,
          showDivider: wins,
          showTrailingArrow: true,
          onTap: () => context.push(AppreciationJarScreen.routeName),
        ),
      ],
      if (wins)
        InfoRowWidget(
          title: 'Share a win',
          subtitle: 'Good news, big or small',
          icon: Icons.emoji_events_outlined,
          showAvatar: false,
          showDivider: false,
          showTrailingArrow: true,
          onTap: () => showShareWinSheet(context, relationshipId: relationshipId),
        ),
    ],
  );

  /// My partner shared a win (Spec 7, B2): ask about it. Fixed copy and a
  /// fixed draft; never a push. Tapping or "Not now" puts it aside.
  Widget _winRow(WinCard w, String partnerName) {
    final colorScheme = Theme.of(context).colorScheme;
    Future<void> putAside() async {
      setState(() => _winsAsked.add(w.eventId));
      try {
        await ref.read(togetherRepositoryProvider).dismissWinCard(w.eventId);
      } catch (_) {
        // Shown again next time; nothing else depends on it.
      }
    }

    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      icon: Icons.emoji_events_outlined,
      iconColor: colorScheme.primary,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      title: '$partnerName shared a win: ${w.title}',
      subtitle: 'Ask $partnerName about it — what was the best part?',
      titleMaxLines: togetherRowLines(context).title,
      subTitleMaxLines: togetherRowLines(context).subtitle,
      showDivider: true,
      trailing: IconButton(
        tooltip: 'Not now',
        icon: const Icon(Icons.close),
        onPressed: putAside,
      ),
      onTap: () async {
        if (await _openChatWith(winDraft(w.title))) putAside();
      },
    );
  }

  Widget _agenda(String relationshipId) {
    final me = ref.watch(togetherMeProvider);
    final partnerName =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Partner';
    final now = ref.watch(togetherClockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final needs =
        ref.watch(togetherNeedsProvider(relationshipId)).valueOrNull ??
        const <TogetherNeed>[];
    final rituals =
        ref.watch(togetherRitualsProvider(relationshipId)).valueOrNull ??
        const <TogetherRitual>[];
    // Optional extras (Phase 4): a failed load just hides them.
    final prompts =
        ref.watch(togetherMemoryPromptsProvider(relationshipId)).valueOrNull ??
        const <MemoryPrompt>[];
    final prompt =
        prompts.where((p) => !_dismissed.contains(p.eventId)).firstOrNull;
    final onThisDay =
        ref.watch(togetherOnThisDayProvider(relationshipId)).valueOrNull ??
        const <OnThisDayItem>[];
    // Free time together (Phase 6): optional too, empty unless both opted in.
    final windows =
        ref.watch(togetherFreeWindowsProvider(relationshipId)).valueOrNull ??
        const <FreeWindow>[];
    final strips =
        ref.watch(togetherBusyStripsProvider(relationshipId)).valueOrNull ??
        const <BusyStrip>[];
    // Spec 7 (B1): "I noticed…" and the jar, while the feature is on.
    final appreciationOn =
        ref.watch(appreciationEnabledProvider).valueOrNull ?? false;
    // Spec 7 (B2): the partner's wins to ask about, and sharing one.
    final winsOn = ref.watch(winsEnabledProvider).valueOrNull ?? false;
    final winCards =
        (ref.watch(winCardsProvider(relationshipId)).valueOrNull ??
                const <WinCard>[])
            .where((w) => !_winsAsked.contains(w.eventId))
            .toList();
    // The home-screen card (Phase 8a) and the lock-screen plan (8c):
    // refreshed from what the hub just loaded, only where they're on.
    ref.listen<AsyncValue<TogetherAgenda>>(
      togetherAgendaProvider(relationshipId),
      (_, next) {
        _publishWidget(next.valueOrNull, windows, me, now);
        _publishLive(next.valueOrNull, me, now);
      },
    );
    // Turning the lock-screen plan on shows it now, from what the hub has.
    ref.listen<AsyncValue<bool>>(togetherLiveEnabledProvider, (prev, next) {
      if (next.valueOrNull == true && prev?.valueOrNull != true) {
        _publishLive(
          ref.read(togetherAgendaProvider(relationshipId)).valueOrNull,
          me,
          now,
        );
      }
    });
    // Turning the card on fills it now, from what the hub already has.
    ref.listen<AsyncValue<bool>>(togetherWidgetEnabledProvider, (prev, next) {
      if (next.valueOrNull == true && prev?.valueOrNull != true) {
        _publishWidget(
          ref.read(togetherAgendaProvider(relationshipId)).valueOrNull,
          windows,
          me,
          now,
        );
      }
    });
    // Spec 1b: turning plan titles on or off re-sends what the card and the
    // lock screen show, from what the hub already has.
    ref.listen<AsyncValue<bool>>(
      togetherSurfaceTitlesProvider(widgetTitlesKey),
      (prev, next) {
        if (prev?.valueOrNull != null &&
            next.valueOrNull != prev?.valueOrNull) {
          _publishWidget(
            ref.read(togetherAgendaProvider(relationshipId)).valueOrNull,
            windows,
            me,
            now,
          );
        }
      },
    );
    ref.listen<AsyncValue<bool>>(
      togetherSurfaceTitlesProvider(liveTitlesKey),
      (prev, next) {
        if (prev?.valueOrNull != null &&
            next.valueOrNull != prev?.valueOrNull) {
          _publishLive(
            ref.read(togetherAgendaProvider(relationshipId)).valueOrNull,
            me,
            now,
          );
        }
      },
    );
    DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
    final todayWindows =
        windows.where((w) => dayOf(w.start) == today).take(2).toList();
    final laterWindows =
        windows
            .where(
              (w) =>
                  dayOf(w.start).isAfter(today) &&
                  !dayOf(w.start).isAfter(today.add(const Duration(days: 6))),
            )
            .take(5)
            .toList();
    final partnerStripsToday =
        strips.where((s) => !s.isMine && dayOf(s.start) == today).toList();
    return ref
        .watch(togetherAgendaProvider(relationshipId))
        .when(
          skipLoadingOnReload: true,
          loading:
              () => const PlanningEntriesSkeleton(label: 'Loading your plans'),
          error:
              (e, _) => Center(
                child: ErrorStateWidget(
                  title: 'Could not load your plans',
                  subtitle: 'Check your connection and try again.',
                  primaryActionLabel: 'Try again',
                  onPrimaryAction: () => _reload(relationshipId),
                ),
              ),
          data:
              (agenda) => RefreshIndicator(
                onRefresh: () => _reload(relationshipId),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: Spacing.xxl * 2),
                  children: [
                    ...(agenda.isEmpty &&
                              winCards.isEmpty &&
                              needs.isEmpty &&
                              rituals.isEmpty &&
                              prompt == null &&
                              onThisDay.isEmpty &&
                              todayWindows.isEmpty &&
                              laterWindows.isEmpty &&
                              partnerStripsToday.isEmpty
                          ? [
                            _EmptyTogether(
                              onRitual:
                                  () => showRitualTemplatesSheet(
                                    context,
                                    relationshipId,
                                  ),
                            ),
                          ]
                          : [
                            if (needs.isNotEmpty)
                              TogetherSection(
                                title: 'Needs you',
                                children: [
                                  for (
                                    var i = 0;
                                    i < needs.length && i < 3;
                                    i++
                                  )
                                    _needRow(
                                      needs[i],
                                      relationshipId,
                                      partnerName,
                                      last:
                                          needs.length <= 3 &&
                                          i == needs.length - 1,
                                    ),
                                  if (needs.length > 3)
                                    InfoRowWidget(
                                      title: 'More',
                                      subtitle: '',
                                      icon: Icons.expand_more_rounded,
                                      showAvatar: false,
                                      showDivider: false,
                                      showTrailingArrow: true,
                                      onTap:
                                          () => _showAllNeeds(
                                            needs,
                                            relationshipId,
                                            partnerName,
                                          ),
                                    ),
                                ],
                              ),
                            TogetherSection(
                              title: 'Today',
                              children: [
                                for (final w in winCards)
                                  _winRow(w, partnerName),
                                for (final c in agenda.careCards)
                                  _careRow(c, partnerName),
                                if (prompt != null)
                                  _memoryPromptRow(
                                    prompt,
                                    now,
                                    divider: agenda.today.isNotEmpty,
                                  ),
                                for (final w in todayWindows)
                                  _freeWindowRow(
                                    w,
                                    relationshipId,
                                    partnerName,
                                    today: true,
                                  ),
                                if (partnerStripsToday.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: Spacing.md,
                                      vertical: Spacing.xs,
                                    ),
                                    child: Text(
                                      '$partnerName is busy ${partnerStripsToday.map((s) => '${DateFormat.jm().format(s.start)}–${DateFormat.jm().format(s.end)}').join(', ')}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.copyWith(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                if (agenda.today.isEmpty &&
                                    winCards.isEmpty &&
                                    agenda.careCards.isEmpty &&
                                    prompt == null &&
                                    todayWindows.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(Spacing.md),
                                    child: Text(
                                      'Nothing planned today.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.copyWith(
                                        color:
                                            Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ..._rows(
                                  agenda.today,
                                  relationshipId,
                                  me,
                                  partnerName,
                                ),
                              ],
                            ),
                            if (agenda.week.isNotEmpty)
                              TogetherSection(
                                title: 'This week',
                                children: [
                                  // One run of rows across the days, so dividers
                                  // sit between every row, not just within a day.
                                  ..._rows(
                                    [for (final w in agenda.week) ...w.items],
                                    relationshipId,
                                    me,
                                    partnerName,
                                    lead: (i) => _dayLabel(i.day, today),
                                  ),
                                ],
                              ),
                            if (laterWindows.isNotEmpty)
                              TogetherSection(
                                title: 'Free together',
                                children: [
                                  for (final w in laterWindows)
                                    _freeWindowRow(
                                      w,
                                      relationshipId,
                                      partnerName,
                                    ),
                                ],
                              ),
                            TogetherSection(
                              title: 'Rituals',
                              children: [
                                for (final r in rituals)
                                  _ritualRow(
                                    r,
                                    relationshipId,
                                    me,
                                    partnerName,
                                  ),
                                InfoRowWidget(
                                  title: 'Add a ritual',
                                  subtitle:
                                      rituals.isEmpty
                                          ? 'Date night, a weekly check-in…'
                                          : '',
                                  icon: Icons.add_rounded,
                                  showAvatar: false,
                                  showDivider: false,
                                  showTrailingArrow: true,
                                  onTap:
                                      () => showRitualTemplatesSheet(
                                        context,
                                        relationshipId,
                                      ),
                                ),
                              ],
                            ),
                            if (agenda.comingUp.isNotEmpty)
                              TogetherSection(
                                title: 'Coming up',
                                children: _rows(
                                  agenda.comingUp,
                                  relationshipId,
                                  me,
                                  partnerName,
                                  lead:
                                      (i) =>
                                          'In ${i.day.difference(today).inDays} days',
                                ),
                              ),
                            if (agenda.recentMoments.isNotEmpty ||
                                onThisDay.isNotEmpty)
                              TogetherSection(
                                title: 'Our story',
                                children: [
                                  for (final i in onThisDay) _onThisDayRow(i),
                                  ..._rows(
                                    agenda.recentMoments,
                                    relationshipId,
                                    me,
                                    partnerName,
                                    lead:
                                        (i) => DateFormat.MMMd().format(i.day),
                                  ),
                                  InfoRowWidget(
                                    title: 'All memories',
                                    subtitle: '',
                                    icon: Icons.photo_album_outlined,
                                    showAvatar: false,
                                    showDivider: false,
                                    showTrailingArrow: true,
                                    onTap: () => _openMemories(relationshipId),
                                  ),
                                ],
                              ),
                          ]),
                    // Spec 7 (B1): shown whether or not there is anything
                    // on the agenda yet.
                    if (appreciationOn || winsOn)
                      _goodThingsSection(
                        relationshipId,
                        appreciation: appreciationOn,
                        wins: winsOn,
                      ),
                  ],
                ),
              ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final relationshipAsync = ref.watch(
      timeline_providers.currentRelationshipIdProvider,
    );
    final relationshipId = relationshipAsync.valueOrNull;
    if (relationshipId != null && !_zoneReported) {
      _zoneReported = true;
      Future.microtask(() => _reportZone(relationshipId));
    }
    // A note shared from another app (Phase 8b R3): opened once Together is
    // reachable; a stale one is dropped quietly.
    ref.listen<PendingShare?>(pendingShareProvider, (_, share) {
      if (share != null) _openShared(share);
    });
    if (relationshipId != null && !_sharedChecked) {
      _sharedChecked = true;
      Future.microtask(() {
        final share = ref.read(pendingShareProvider);
        if (share != null) _openShared(share);
      });
    }
    if (relationshipId != null && !_busySynced) {
      _busySynced = true;
      Future.microtask(() async {
        final uploaded = await syncBusyTimes(
          ref.read(togetherRepositoryProvider),
          ref.read(deviceBusySourceProvider),
          relationshipId,
          DateTime.now(),
        );
        if (uploaded && mounted) {
          ref.invalidate(togetherFreeWindowsProvider(relationshipId));
        }
      });
    }
    if (relationshipAsync.hasValue &&
        relationshipId == null &&
        !_orphansCleared) {
      _orphansCleared = true;
      Future.microtask(clearTogetherDeviceSurfaces);
    }
    if (relationshipId != null && !_mirrorSynced) {
      _mirrorSynced = true;
      Future.microtask(() => _syncMirror(relationshipId));
    }
    // Turning the calendar copy on fills it now (a real switch from off;
    // the first load is the once-per-visit sync's job).
    ref.listen<AsyncValue<bool>>(togetherMirrorEnabledProvider, (prev, next) {
      if (relationshipId != null &&
          next.valueOrNull == true &&
          prev?.valueOrNull == false) {
        _syncMirror(relationshipId);
      }
    });
    // Spec 1b: titles on or off replaces every calendar entry.
    ref.listen<AsyncValue<bool>>(
      togetherSurfaceTitlesProvider(mirrorTitlesKey),
      (prev, next) {
        if (relationshipId != null &&
            prev?.valueOrNull != null &&
            next.valueOrNull != prev?.valueOrNull) {
          _syncMirror(relationshipId);
        }
      },
    );
    final toggle = Padding(
      padding: EdgeInsets.fromLTRB(Spacing.md.w, Spacing.sm, Spacing.xs.w, 0),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<_View>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _View.agenda,
                  label: Text('Agenda'),
                  icon: Icon(Icons.view_agenda_outlined),
                ),
                ButtonSegment(
                  value: _View.month,
                  label: Text('Month'),
                  icon: Icon(Icons.calendar_month_outlined),
                ),
              ],
              selected: {_view},
              onSelectionChanged:
                  (s) => setState(() {
                    _view = s.first;
                    _headerTucked = false;
                    if (_view == _View.month) _monthOpened = true;
                  }),
            ),
          ),
        ],
      ),
    );
    // The hub's own heading, the same on its own screen and in Planning's
    // Calendar tab: name and a line of welcome, settings and family.
    final header = _TogetherHeader(
      onSettings:
          relationshipId == null
              ? null
              : () => showTogetherSettingsSheet(context, relationshipId),
    );
    // Loading, no couple to show, or the hub itself.
    final body =
        relationshipId == null
            ? Column(
              children: [
                header,
                Expanded(
                  child:
                      relationshipAsync.isLoading
                          ? const PlanningEntriesSkeleton(
                            label: 'Loading your plans',
                          )
                          : const Center(
                            child: Text('No active relationship found'),
                          ),
                ),
              ],
            )
            : Column(
              children: [
                _Tuckable(
                  // A screen reader keeps the header where it is.
                  tucked:
                      _headerTucked &&
                      !MediaQuery.of(context).accessibleNavigation,
                  child: Column(children: [header, toggle]),
                ),
                // Both views stay alive once opened, so switching back shows
                // them as they were; Month is built the first time it's
                // chosen. Their data keeps refreshing from change signals.
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: IndexedStack(
                      index: _view == _View.agenda ? 0 : 1,
                      children: [
                        _agenda(relationshipId),
                        if (_monthOpened)
                          const TimelineScreen(
                            showAppBar: true,
                            showOwnAppBar: false,
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              ],
            );
    return Scaffold(
      appBar:
          widget.embedded
              ? null
              // Just the way back: the name and actions sit in the header.
              : AppBar(),
      floatingActionButton:
          relationshipId == null || _view == _View.month
              ? null
              : AppFab(
                heroTag: 'together-add',
                icon: Icons.add_rounded,
                onPressed: () => _add(relationshipId),
              ),
      body: body,
    );
  }
}

/// Slides [child] up out of sight (and out of reach) when [tucked], and
/// back down when not; instant when the device asks for less motion.
class _Tuckable extends StatelessWidget {
  const _Tuckable({required this.tucked, required this.child});
  final bool tucked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration =
        MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 220);
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.bottomCenter,
        heightFactor: tucked ? 0 : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: tucked,
          child: ExcludeSemantics(
            excluding: tucked,
            child: AnimatedOpacity(
              opacity: tucked ? 0 : 1,
              duration: duration,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The line under "Together" in its header.
const togetherTagline =
    'Your plans, rituals and moments, side by side. A journey through time.';

/// "Together" with its line of welcome on the left; family, then settings
/// at the far end, on the right. Sits above the Agenda/Month tabs.
class _TogetherHeader extends StatelessWidget {
  const _TogetherHeader({required this.onSettings});

  /// Null until the couple is known (settings belong to a relationship).
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.md.w, Spacing.sm, Spacing.sm.w, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Together',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const Gap(2),
                  Text(
                    togetherTagline,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(Spacing.md), // room between the words and the icons
          AppIconButton(
            icon: Icons.people_outline,
            tooltip: 'Family',
            onPressed: () => showFamilySheet(context),
          ),
          const Gap(Spacing.xs),
          AppIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Together settings',
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

/// A brand-new couple: three easy ways in.
class _EmptyTogether extends StatelessWidget {
  const _EmptyTogether({required this.onRitual});
  final VoidCallback onRitual;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Gap(Spacing.xl),
        const EmptyStateWidget(
          type: EmptyStateType.custom,
          icon: Icons.favorite_outline_rounded,
          title: 'Your life together starts here',
          subtitle: 'Add the dates that matter, then plan something.',
          compact: false,
        ),
        TogetherSection(
          title: 'Start with',
          children: [
            InfoRowWidget(
              title: 'Add your anniversary',
              subtitle: '',
              icon: Icons.favorite_border_rounded,
              showAvatar: false,
              showTrailingArrow: true,
              onTap: () => showReminderSheet(context),
            ),
            InfoRowWidget(
              title: 'Add a birthday',
              subtitle: '',
              icon: Icons.cake_outlined,
              showAvatar: false,
              showTrailingArrow: true,
              onTap: () => showReminderSheet(context),
            ),
            InfoRowWidget(
              title: 'Set up a ritual',
              subtitle: '',
              icon: Icons.event_repeat_rounded,
              showAvatar: false,
              showDivider: false,
              showTrailingArrow: true,
              onTap: onRitual,
            ),
          ],
        ),
      ],
    );
  }
}
