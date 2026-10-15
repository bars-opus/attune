import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/together_repository.dart';
import '../../domain/calendar_export.dart';
import '../../domain/couple_event_draft.dart';
import '../../domain/shared_capture.dart';
import '../../domain/together_ai.dart';
import '../../domain/together_item.dart';
import '../../domain/together_need.dart';
import '../together_providers.dart';
import 'memory_sheets.dart' show canAddMemory, showAddMemorySheet;
import 'ritual_sheets.dart' show confirmRitualSkip;

/// Opens the event editor: empty to plan something, or with [item] to edit
/// it. The sheet closes with its confirmation, shown on the screen behind.
Future<void> showCoupleEventSheet(
  BuildContext context, {
  required String relationshipId,
  TogetherItem? item,
  ({DateTime start, DateTime end})? proposeWindow,
  String? proposeTitle,
  String? proposeNote,
  String? initialText,
}) async {
  final message = await BottomSheetUtils.showDocumentationBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: _CoupleEventSheet(
      relationshipId: relationshipId,
      item: item,
      proposeWindow: proposeWindow,
      proposeTitle: proposeTitle,
      proposeNote: proposeNote,
      initialText: initialText,
    ),
  );
  if (message != null && context.mounted) context.showSuccessSnackbar(message);
}

enum _Who { both, me, partner }

const _remindChoices = <int?, String>{
  null: 'No reminder',
  0: 'At the time',
  60: '1 hour before',
  1440: '1 day before',
};

const _repeatLabels = {
  TogetherRepeat.none: 'Does not repeat',
  TogetherRepeat.daily: 'Every day',
  TogetherRepeat.weekly: 'Every week',
  TogetherRepeat.monthly: 'Every month',
  TogetherRepeat.yearly: 'Every year',
};

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _errorCopy(String code) => switch (code) {
  'not_found' => 'This event is no longer here.',
  'owner_handoff' => 'Ask your partner to take it on instead.',
  'forbidden' => 'Only the person who made it can change who sees it.',
  _ => 'Could not save that. Please try again.',
};

class _CoupleEventSheet extends ConsumerStatefulWidget {
  const _CoupleEventSheet({
    required this.relationshipId,
    this.item,
    this.proposeWindow,
    this.proposeTitle,
    this.proposeNote,
    this.initialText,
  });
  final String relationshipId;
  final TogetherItem? item;

  /// A free window to suggest (Phase 6): opens in propose mode at its start.
  final ({DateTime start, DateTime end})? proposeWindow;

  /// An idea picked for that window (Phase 7 R5): prefills the suggestion.
  final String? proposeTitle;
  final String? proposeNote;

  /// Text shared from another app (Phase 8b): waits in "Describe it", or
  /// becomes the title and note when AI help isn't available.
  final String? initialText;

  @override
  ConsumerState<_CoupleEventSheet> createState() => _CoupleEventSheetState();
}

class _CoupleEventSheetState extends ConsumerState<_CoupleEventSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _location = TextEditingController();

  /// A typed note the AI turns into this form (Phase 7 R4); never saved itself.
  final _describe = TextEditingController();
  bool _reading = false;

  /// The shared text has been put into the title/note (no-AI path), once.
  bool _sharedApplied = false;
  late bool _allDay;
  late DateTime _start;
  DateTime? _end;
  TogetherRepeat _repeat = TogetherRepeat.none;
  Set<int> _weekdays = {};
  _Who _who = _Who.both;
  TogetherVisibility _visibility = TogetherVisibility.shared;
  int? _remind;
  String? _ownerId;
  String _kind = 'event';
  int _interval = 1;
  DateTime? _repeatUntil;
  bool _busy = false;

  /// Propose mode: ask the partner to pick one of these times (2a).
  bool _propose = false;
  List<({DateTime start, DateTime? end})> _times = [];

  /// Who's holding it: 'nobody', 'me' or 'partner' (a hand-off proposal).
  String _holder = 'nobody';

  /// The partner was already asked to hold it and hasn't answered.
  bool _handoffPending = false;

  /// Propose mode only counts while its toggle is showing: a new event,
  /// shared, that includes the partner.
  bool get _proposing =>
      _propose &&
      !_editing &&
      _visibility == TogetherVisibility.shared &&
      _who != _Who.me;

  bool get _editing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item == null) {
      final now = DateTime.now();
      _allDay = false;
      _start = DateTime(now.year, now.month, now.day, now.hour + 1);
      _end = _start.add(const Duration(hours: 1));
      final w = widget.proposeWindow;
      if (w != null) {
        // A free window (Phase 6): suggest its start, for up to two hours.
        final length = w.end.difference(w.start);
        _start = w.start;
        _end = w.start.add(
          length > const Duration(hours: 2) ? const Duration(hours: 2) : length,
        );
        _propose = true;
        _times = [(start: _start, end: _end)];
        if (widget.proposeTitle != null) _title.text = widget.proposeTitle!;
        if (widget.proposeNote != null) _note.text = widget.proposeNote!;
      }
      if (widget.initialText != null) _describe.text = widget.initialText!;
      return;
    }
    final d = CoupleEventDraft.fromItem(item);
    _title.text = d.title;
    _note.text = d.note ?? '';
    _location.text = d.locationName ?? '';
    _allDay = d.allDay;
    _start = d.start;
    _end = d.end;
    _repeat = d.repeat;
    _weekdays = {...d.weekdays};
    _interval = d.interval;
    _repeatUntil = d.repeatUntil;
    _visibility = d.visibility;
    _remind = d.remindOffsetsMin.isEmpty ? null : d.remindOffsetsMin.first;
    _ownerId = d.ownerId;
    _kind = d.kind;
    final me = ref.read(togetherMeProvider);
    final askedTo = item.sourceRef['owner_proposed_to'] as String?;
    _handoffPending = askedTo != null && askedTo != me;
    _holder =
        d.ownerId == null
            ? (_handoffPending ? 'partner' : 'nobody')
            : (d.ownerId == me ? 'me' : 'partner');
    _who =
        d.participantIds.length > 1
            ? _Who.both
            : (d.participantIds.contains(me) ? _Who.me : _Who.partner);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _location.dispose();
    _describe.dispose();
    super.dispose();
  }

  List<String> _participants(String? me, String? partner) {
    if (_visibility != TogetherVisibility.shared) return [if (me != null) me];
    return switch (_who) {
      _Who.both => [if (me != null) me, if (partner != null) partner],
      _Who.me => [if (me != null) me],
      _Who.partner => [if (partner != null) partner],
    };
  }

  /// Edits one of the proposed times, keeping its length.
  Future<void> _pickTime(int i) {
    final t = _times[i];
    return showCupertinoDateTimeSheet(
      context: context,
      mode:
          _allDay
              ? CupertinoDatePickerMode.date
              : CupertinoDatePickerMode.dateAndTime,
      initialDateTime: t.start,
      sheetHeight: 350.h,
      onChanged:
          (v) => setState(() {
            final length = t.end?.difference(t.start);
            _times[i] = (start: v, end: length == null ? null : v.add(length));
          }),
    );
  }

  Future<void> _pick({required bool end}) {
    final initial =
        end ? (_end ?? _start.add(const Duration(hours: 1))) : _start;
    return showCupertinoDateTimeSheet(
      context: context,
      mode:
          _allDay
              ? CupertinoDatePickerMode.date
              : CupertinoDatePickerMode.dateAndTime,
      initialDateTime: initial,
      sheetHeight: 350.h,
      onChanged:
          (v) => setState(() {
            if (end) {
              _end = v;
            } else {
              final length = _end?.difference(_start);
              _start = v;
              if (length != null) _end = v.add(length);
            }
          }),
    );
  }

  Future<T?> _choose<T>(String title, Map<T, String> options) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder:
          (c) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in options.entries)
                  ListTile(
                    title: Text(e.value),
                    onTap: () => Navigator.of(c).pop(e.key),
                  ),
              ],
            ),
          ),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final me = ref.read(togetherMeProvider);
    final String? partner;
    final String tz;
    try {
      partner = await ref.read(togetherPartnerIdProvider.future);
      tz = await ref.read(togetherDeviceTimezoneProvider.future);
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar('Could not save that. Please try again.');
      }
      return;
    }
    // A big day is a shared event just for its creator (plan 2b R5). My own
    // stops being one if I switch it to both of us or to private; my
    // partner's stays theirs (and the server keeps the creator's kind).
    final mine = widget.item == null || widget.item!.createdBy == me;
    final demote =
        mine &&
        _kind == 'big_day' &&
        !(_visibility == TogetherVisibility.shared && _who == _Who.me);
    final draft = CoupleEventDraft(
      title: _title.text,
      allDay: _allDay,
      start: _allDay ? DateTime(_start.year, _start.month, _start.day) : _start,
      end:
          _end == null
              ? null
              : (_allDay ? DateTime(_end!.year, _end!.month, _end!.day) : _end),
      timezone: widget.item?.tz ?? tz,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      locationName:
          _location.text.trim().isEmpty ? null : _location.text.trim(),
      kind: demote ? 'event' : _kind,
      repeat: _repeat,
      interval: _interval,
      weekdays: _repeat == TogetherRepeat.weekly ? _weekdays : const {},
      repeatUntil: _repeat == TogetherRepeat.none ? null : _repeatUntil,
      participantIds: _participants(me, partner),
      ownerId: switch (_holder) {
        'me' => me,
        // Asking the partner keeps whoever holds it now until they say yes.
        'partner' => _ownerId,
        _ => null,
      },
      visibility: _visibility,
      remindOffsetsMin: [if (_remind != null) _remind!],
    );
    if (!mounted) return;
    final problem = draft.validate();
    if (problem != null) {
      context.showErrorSnackbar(problem);
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(togetherRepositoryProvider);
    try {
      final partnerName =
          ref.read(quiz_providers.partnerNameProvider).valueOrNull ??
          'your partner';
      if (_proposing) {
        await repo.proposeEvent(widget.relationshipId, draft, [
          for (final t in _times) ProposalTime(start: t.start, end: t.end),
        ]);
        ref.invalidate(togetherNeedsProvider);
        if (!mounted) return;
        Navigator.of(context).pop('Sent to $partnerName.');
        return;
      }
      final String id;
      if (_editing) {
        id = widget.item!.id;
        await repo.updateEvent(id, draft);
      } else {
        id = await repo.createEvent(widget.relationshipId, draft);
      }
      final partnerOwns = _ownerId != null && _ownerId != me;
      var asked = true;
      if (_visibility == TogetherVisibility.shared &&
          _holder == 'partner' &&
          !partnerOwns &&
          !_handoffPending) {
        // The event is saved either way; a failed ask must not invite a
        // second Save (and a second event).
        try {
          await repo.proposeHandoff(id);
        } catch (_) {
          asked = false;
        }
      }
      // Refetch now rather than waiting on the realtime signal.
      ref.invalidate(togetherRangeProvider);
      ref.invalidate(togetherNeedsProvider);
      if (!mounted) return;
      final done = _editing ? 'Saved' : 'Added';
      Navigator.of(
        context,
      ).pop(asked ? '$done.' : "$done, but couldn't ask $partnerName.");
    } on TogetherException catch (e) {
      if (!mounted) return;
      context.showErrorSnackbar(_errorCopy(e.code));
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not save that. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Delete this event?'),
            content: const Text('It will be removed for both of you.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => ref.read(togetherRepositoryProvider).deleteEvent(widget.item!.id),
      'Deleted.',
    );
  }

  Future<void> _skipWeek() async {
    if (!await confirmRitualSkip(context) || !mounted) return;
    await _run(
      () => ref
          .read(togetherRepositoryProvider)
          .skipRitualOccurrence(widget.item!.id),
      'Skipped this week.',
    );
  }

  Future<void> _leave() => _run(
    () => ref.read(togetherRepositoryProvider).leaveEvent(widget.item!.id),
    'You left it.',
  );

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(togetherRangeProvider);
      if (!mounted) return;
      Navigator.of(context).pop(done);
    } on TogetherException catch (e) {
      if (!mounted) return;
      context.showErrorSnackbar(_errorCopy(e.code));
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not do that. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _format(DateTime d) =>
      _allDay
          ? DateFormat.yMMMEd().format(d)
          : DateFormat.yMMMEd().add_jm().format(d);

  Future<void> _fillIn() async {
    final text = _describe.text.trim();
    if (text.isEmpty || _reading) return;
    setState(() => _reading = true);
    try {
      final d = await ref
          .read(togetherAiRepositoryProvider)
          .capture(widget.relationshipId, text, DateTime.now());
      if (!mounted) return;
      setState(() {
        _title.text = d.title;
        _allDay = d.allDay;
        _start = d.start;
        // An all-day draft may span days (a trip); a timed one gets an hour.
        _end =
            d.end ?? (d.allDay ? null : d.start.add(const Duration(hours: 1)));
        // In a suggestion the times on offer are what gets sent: use the one read.
        if (_times.isNotEmpty) _times = [(start: _start, end: _end)];
        _who = d.withPartner ? _Who.both : _Who.me;
        if (d.location != null) _location.text = d.location!;
        if (d.note != null) _note.text = d.note!;
      });
      context.showSuccessSnackbar('Filled in. Check it, then save.');
    } on TogetherAiException catch (e) {
      if (!mounted) return;
      if (e.code == 'CONSENT_REQUIRED' || e.code == 'FEATURE_DISABLED') {
        ref.invalidate(togetherAiAvailableProvider(widget.relationshipId));
      }
      context.showErrorSnackbar(switch (e.code) {
        'CONSENT_REQUIRED' ||
        'FEATURE_DISABLED' => "AI help isn't available for you two right now.",
        'RATE_LIMITED' =>
          "You've used today's AI help. Try again in ${((e.retryAfterSeconds ?? 3600) / 3600).ceil()} hours.",
        _ => "Couldn't read that. Try again, or fill it in yourself.",
      });
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar(
          "Couldn't read that. Try again, or fill it in yourself.",
        );
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final me = ref.watch(togetherMeProvider);
    final aiAsync = ref.watch(
      togetherAiAvailableProvider(widget.relationshipId),
    );
    final aiOn = widget.item == null && (aiAsync.valueOrNull ?? false);
    // No AI help (known, or failed to check): a shared note fills the title
    // and note instead, once, without overwriting anything typed.
    final sharedText = widget.initialText;
    if (sharedText != null &&
        !_sharedApplied &&
        widget.item == null &&
        (aiAsync.valueOrNull == false || aiAsync.hasError)) {
      _sharedApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final f = sharedCaptureFallback(sharedText);
        setState(() {
          if (_title.text.trim().isEmpty) _title.text = f.title;
          if (_note.text.trim().isEmpty && f.note != null) _note.text = f.note!;
        });
      });
    }
    final partnerName =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Partner';
    final coupleName = coupleLabel(
      ref.watch(coupleNameProvider(widget.relationshipId)).valueOrNull,
    );
    final item = widget.item;
    final mine = item == null || item.createdBy == me;
    // A ritual's week is skipped rather than deleted or left (Phase 3
    // review #2): a deleted week would be laid out again by the next run.
    final ritualWeek = item?.sourceRef['kind'] == 'ritual_occurrence';
    final export = item == null ? null : calendarExportFor(item, me);
    final memorable =
        item != null &&
        canAddMemory(item, ref.watch(togetherClockProvider)(), me);
    final canDelete =
        item != null &&
        !ritualWeek &&
        (mine || item.visibility == TogetherVisibility.shared);
    final canLeave =
        item != null &&
        !ritualWeek &&
        !mine &&
        item.participantIds.contains(me) &&
        item.participantIds.length > 1;
    final shared = _visibility == TogetherVisibility.shared;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          children: [
            BottomSheetHeader(
              title: _editing ? 'Edit event' : 'New event',
              actionLabel: 'Save',
              onPressed: _busy ? null : _save,
            ),
            if (aiOn) ...[
              AppTextFormField(
                controller: _describe,
                label: 'Describe it',
                hintText: 'e.g. dinner with Kofi Sat 7pm',
                maxLength: 300,
              ),
              // Full-width field above, the action under it: at 320pt a
              // side-by-side button squeezed the field to a sliver.
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: Spacing.sm.w),
                  child:
                      _reading
                          ? const Padding(
                            padding: EdgeInsets.all(Spacing.sm),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                          : TextButton.icon(
                            onPressed: _fillIn,
                            icon: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                            ),
                            label: const Text('Fill in'),
                          ),
                ),
              ),
            ],
            AppTextFormField(
              controller: _title,
              label: 'Title',
              hintText: 'Dinner, a trip, the dentist…',
              autofocus: !_editing,
              textCapitalization: TextCapitalization.sentences,
            ),
            Gap(Spacing.sm),
            AppDivider(),
            InfoRowWidget(
              title: 'All day',
              subtitle: '',
              icon: Icons.wb_sunny_outlined,
              showAvatar: false,
              showDivider: false,
              isToggleItem: true,
              toggleValue: _allDay,
              onToggleChanged: (v) => setState(() => _allDay = v),
            ),
            AppDivider(),
            if (!_proposing) ...[
              InfoRowWidget(
                title: _format(_start),
                subtitle: 'Starts',
                icon: Icons.schedule_rounded,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: () => _pick(end: false),
              ),
              AppDivider(),
              InfoRowWidget(
                title: _end == null ? 'Add an end' : _format(_end!),
                subtitle: 'Ends',
                icon: Icons.schedule_outlined,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: () => _pick(end: true),
              ),
            ],
            AppDivider(),
            InfoRowWidget(
              title: _repeatLabels[_repeat]!,
              subtitle: 'Repeats',
              icon: Icons.repeat_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap:
                  _propose
                      ? null
                      : () async {
                        final r = await _choose('Repeats', _repeatLabels);
                        if (r != null) {
                          setState(() {
                            _repeat = r;
                            if (r == TogetherRepeat.weekly &&
                                _weekdays.isEmpty) {
                              _weekdays = {_start.weekday};
                            }
                          });
                        }
                      },
            ),
            if (_repeat == TogetherRepeat.weekly)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                child: Wrap(
                  spacing: Spacing.xs,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(_weekdayShort[d - 1]),
                        selected: _weekdays.contains(d),
                        onSelected:
                            (on) => setState(() {
                              on ? _weekdays.add(d) : _weekdays.remove(d);
                            }),
                      ),
                  ],
                ),
              ),
            AppDivider(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.md.w,
                Spacing.md,
                Spacing.md.w,
                0,
              ),
              child: Text(
                'Who it’s for',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Padding(
              padding: Spacing.allMd,
              child: SegmentedButton<_Who>(
                showSelectedIcon: false,
                segments: [
                  // The couple by their chosen name ("Couples" until then).
                  ButtonSegment(
                    value: _Who.both,
                    label: Text(coupleName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const ButtonSegment(value: _Who.me, label: Text('Me')),
                  ButtonSegment(value: _Who.partner, label: Text(partnerName)),
                ],
                selected: {shared ? _who : _Who.me},
                onSelectionChanged:
                    shared ? (s) => setState(() => _who = s.first) : null,
              ),
            ),
            if (shared && _who == _Who.me && !_proposing) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'A big day for me',
                subtitle: '$partnerName will be reminded to wish you luck',
                icon: Icons.star_outline_rounded,
                showAvatar: false,
                showDivider: false,
                isToggleItem: true,
                toggleValue: _kind == 'big_day',
                onToggleChanged:
                    (v) => setState(() => _kind = v ? 'big_day' : 'event'),
              ),
            ],
            if (widget.item == null && shared && _who != _Who.me) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Ask $partnerName to pick',
                subtitle: 'Offer up to three times',
                icon: Icons.how_to_vote_outlined,
                showAvatar: false,
                showDivider: false,
                isToggleItem: true,
                toggleValue: _propose,
                onToggleChanged:
                    (v) => setState(() {
                      _propose = v;
                      if (v) {
                        _repeat = TogetherRepeat.none;
                        if (_times.isEmpty) {
                          _times = [(start: _start, end: _end)];
                        }
                      }
                    }),
              ),
              if (_proposing) ...[
                for (var i = 0; i < _times.length; i++)
                  InfoRowWidget(
                    title: _format(_times[i].start),
                    subtitle: 'Option ${i + 1}',
                    icon: Icons.schedule_rounded,
                    showAvatar: false,
                    showDivider: false,
                    disableTrailing: true,
                    onTap: () => _pickTime(i),
                  ),
                if (_times.length < 3)
                  InfoRowWidget(
                    title: 'Add another time',
                    subtitle: '',
                    icon: Icons.add_rounded,
                    showAvatar: false,
                    showDivider: false,
                    disableTrailing: true,
                    onTap:
                        () => setState(() {
                          final last = _times.last;
                          _times = [
                            ..._times,
                            (
                              start: last.start.add(const Duration(days: 1)),
                              end: last.end?.add(const Duration(days: 1)),
                            ),
                          ];
                        }),
                  ),
              ],
            ],
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Text(
                'Who can see it',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Padding(
              padding: Spacing.allMd,
              child: SegmentedButton<TogetherVisibility>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: TogetherVisibility.shared,
                    label: Text('Both'),
                  ),
                  ButtonSegment(
                    value: TogetherVisibility.busyOnly,
                    label: Text('Busy only'),
                  ),
                  ButtonSegment(
                    value: TogetherVisibility.private,
                    label: Text('Just me'),
                  ),
                ],
                selected: {_visibility},
                onSelectionChanged:
                    mine ? (s) => setState(() => _visibility = s.first) : null,
              ),
            ),
            if (shared) ...[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                child: Text(
                  "Who's holding it",
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Padding(
                padding: Spacing.allMd,
                child: SegmentedButton<String>(
                  key: const Key('owner-picker'),
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: 'nobody', label: Text('Nobody')),
                    const ButtonSegment(value: 'me', label: Text('Me')),
                    ButtonSegment(value: 'partner', label: Text(partnerName)),
                  ],
                  selected: {_holder},
                  onSelectionChanged: (s) => setState(() => _holder = s.first),
                ),
              ),
            ],
            AppDivider(),
            InfoRowWidget(
              title: _remindChoices[_remind] ?? 'No reminder',
              subtitle: 'Remind',
              icon: Icons.notifications_none_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () async {
                final picked = await _choose('Remind', {
                  for (final e in _remindChoices.entries)
                    (e.key ?? -1): e.value,
                });
                if (picked != null) {
                  setState(() => _remind = picked == -1 ? null : picked);
                }
              },
            ),
            AppDivider(),
            AppTextFormField(
              controller: _location,
              label: 'Where (optional)',
              maxLength: 120,
            ),
            AppTextFormField(
              controller: _note,
              label: 'Note (optional)',
              maxLines: 3,
              maxLength: 500,
            ),
            if (canLeave) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Leave event',
                subtitle: '',
                icon: Icons.logout_rounded,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: _busy ? null : _leave,
              ),
            ],
            if (export != null) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Add to my calendar',
                subtitle:
                    export.onlyThisTime
                        ? 'This time only: your calendar can’t repeat it the same way'
                        : 'Opens your calendar app, ready to save',
                icon: Icons.event_available_rounded,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: () async {
                  try {
                    await ref.read(calendarExporterProvider).add(export);
                  } catch (_) {
                    if (context.mounted) {
                      context.showErrorSnackbar(
                        'Your calendar app could not be opened.',
                      );
                    }
                  }
                },
              ),
            ],
            if (memorable) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Add a memory',
                subtitle: 'A line about how it went',
                icon: Icons.edit_note_rounded,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap:
                    _busy
                        ? null
                        : () {
                          final navigator = Navigator.of(context);
                          final host = navigator.context;
                          navigator.pop();
                          showAddMemorySheet(
                            host,
                            eventId: item.id,
                            title: item.title,
                          );
                        },
              ),
            ],
            if (ritualWeek) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Skip this week',
                subtitle: 'No problem — it’ll be back the week after',
                icon: Icons.redo_rounded,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: _busy ? null : _skipWeek,
              ),
            ],
            if (canDelete) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Delete event',
                subtitle: '',
                icon: Icons.delete_outline_rounded,
                iconColor: colorScheme.error,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: _busy ? null : _delete,
              ),
            ],
            Gap(Spacing.xl),
          ],
        ),
      ),
    );
  }
}
