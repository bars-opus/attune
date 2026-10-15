import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/together_need.dart';
import '../../domain/together_ritual.dart';
import '../../domain/together_story.dart';
import '../together_providers.dart';

const _lengths = {20: '20 min', 45: '45 min', 60: '1 hour', 120: '2 hours'};
const _short = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> _sheet(BuildContext context, Widget child) async {
  final message = await BottomSheetUtils.showDocumentationBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: child,
  );
  if (message != null && context.mounted) context.showSuccessSnackbar(message);
}

void _refresh(WidgetRef ref) {
  ref.invalidate(togetherRitualsProvider);
  ref.invalidate(togetherRangeProvider);
  ref.invalidate(togetherNeedsProvider);
}

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
  String done,
) async {
  try {
    await action();
    _refresh(ref);
    if (context.mounted) Navigator.of(context).pop(done);
  } catch (_) {
    if (context.mounted) {
      context.showErrorSnackbar('Could not do that. Please try again.');
    }
  }
}

Future<void> showRitualTemplatesSheet(
  BuildContext context,
  String relationshipId,
) => _sheet(context, _TemplatesSheet(relationshipId: relationshipId));

Future<void> showRitualEditor(
  BuildContext context,
  String relationshipId, {
  RitualTemplate? template,
  TogetherRitual? ritual,
}) => _sheet(
  context,
  _RitualEditor(
    relationshipId: relationshipId,
    template: template,
    ritual: ritual,
  ),
);

Future<void> showRitualSheet(
  BuildContext context,
  String relationshipId,
  TogetherRitual ritual,
) => _sheet(
  context,
  _RitualSheet(relationshipId: relationshipId, ritual: ritual),
);

Future<void> showRitualProposalSheet(BuildContext context, TogetherNeed need) =>
    _sheet(context, _RitualProposalSheet(need: need));

/// My suggestion, still waiting on my partner: withdrawable.
Future<void> showSentRitualSheet(BuildContext context, TogetherRitual ritual) =>
    _sheet(context, _SentRitualSheet(ritual: ritual));

/// "Skip this week?" — one light check so a mis-tap doesn't drop a date
/// (a skipped week can't be brought back). True when confirmed.
Future<bool> confirmRitualSkip(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder:
        (c) => AlertDialog(
          title: const Text('Skip this week?'),
          content: const Text('No problem — it’ll be back the week after.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Skip it'),
            ),
          ],
        ),
  );
  return ok == true;
}

class _TemplatesSheet extends ConsumerWidget {
  const _TemplatesSheet({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: Colors.transparent,
    body: ListView(
      children: [
        // For the couple, by the name they chose ("couples" until then).
        BottomSheetHeader(
          title:
              'A ritual for ${coupleInSentence(ref.watch(coupleNameProvider(relationshipId)).valueOrNull)}',
        ),
        AppDivider(),
        for (var i = 0; i < ritualTemplates.length; i++) ...[
          InfoRowWidget(
            title: ritualTemplates[i].title,
            subtitle: ritualTemplates[i].blurb,
            icon: ritualTemplates[i].icon,
            showAvatar: false,
            showDivider: false,
            showTrailingArrow: true,
            onTap: () {
              final navigator = Navigator.of(context);
              final host = navigator.context;
              navigator.pop();
              showRitualEditor(
                host,
                relationshipId,
                template: ritualTemplates[i],
              );
            },
          ),
          if (i < ritualTemplates.length - 1) AppDivider(),
        ],
        Gap(Spacing.xl),
      ],
    ),
  );
}

class _RitualEditor extends ConsumerStatefulWidget {
  const _RitualEditor({
    required this.relationshipId,
    this.template,
    this.ritual,
  });
  final String relationshipId;
  final RitualTemplate? template;
  final TogetherRitual? ritual;
  @override
  ConsumerState<_RitualEditor> createState() => _RitualEditorState();
}

class _RitualEditorState extends ConsumerState<_RitualEditor> {
  late final TextEditingController _title;
  late RitualCadence _cadence;
  late int _weekday;
  late int _hour;
  late int _minute;
  late int _length;
  late String _templateId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final r = widget.ritual;
    final t = widget.template ?? ritualTemplates.last;
    _title = TextEditingController(
      text: r?.title ?? (t.id == 'custom' ? '' : t.title),
    );
    _cadence = r?.cadence ?? t.cadence;
    _weekday = r?.weekday ?? t.weekday;
    _hour = r?.hour ?? t.hour;
    _minute = r?.minute ?? t.minute;
    _length = r?.durationMin ?? t.durationMin;
    _templateId = r?.template ?? t.id;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save(String partner) async {
    if (_busy) return;
    if (_title.text.trim().isEmpty) {
      context.showErrorSnackbar('Give it a name');
      return;
    }
    setState(() => _busy = true);
    final existing = widget.ritual;
    final String tz =
        existing != null
            ? existing.tz
            : await ref.read(togetherDeviceTimezoneProvider.future);
    final draft = RitualDraft(
      template: _templateId,
      title: _title.text,
      cadence: _cadence,
      weekday: _weekday,
      hour: _hour,
      minute: _minute,
      durationMin: _length,
      tz: tz,
    );
    final repo = ref.read(togetherRepositoryProvider);
    if (!mounted) return;
    await _run(context, ref, () async {
      if (widget.ritual == null) {
        await repo.proposeRitual(widget.relationshipId, draft);
      } else {
        await repo.updateRitual(widget.ritual!.id, draft);
      }
    }, widget.ritual == null ? 'Sent to $partner.' : 'Saved.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final partner =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ??
        'your partner';
    final time = DateFormat.jm().format(DateTime(2000, 1, 1, _hour, _minute));
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          children: [
            BottomSheetHeader(
              title: widget.ritual == null ? 'New ritual' : 'Change ritual',
              actionLabel: widget.ritual == null ? 'Suggest' : 'Save',
              onPressed: _busy ? null : () => _save(partner),
            ),
            AppTextFormField(
              controller: _title,
              label: 'Name',
              textCapitalization: TextCapitalization.sentences,
            ),
            Padding(
              padding: Spacing.allMd,
              child: SegmentedButton<RitualCadence>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: RitualCadence.weekly,
                    label: Text('Every week'),
                  ),
                  ButtonSegment(
                    value: RitualCadence.fortnightly,
                    label: Text('Every other week'),
                  ),
                ],
                selected: {_cadence},
                onSelectionChanged: (s) => setState(() => _cadence = s.first),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Wrap(
                spacing: Spacing.xs,
                children: [
                  for (var d = 1; d <= 7; d++)
                    ChoiceChip(
                      label: Text(_short[d - 1]),
                      selected: _weekday == d,
                      onSelected: (_) => setState(() => _weekday = d),
                    ),
                ],
              ),
            ),
            Gap(Spacing.sm),
            AppDivider(),
            InfoRowWidget(
              title: time,
              subtitle: 'Time',
              icon: Icons.schedule_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap:
                  () => showCupertinoDateTimeSheet(
                    context: context,
                    mode: CupertinoDatePickerMode.time,
                    initialDateTime: DateTime(2000, 1, 1, _hour, _minute),
                    sheetHeight: 350.h,
                    onChanged:
                        (v) => setState(() {
                          _hour = v.hour;
                          _minute = v.minute;
                        }),
                  ),
            ),
            AppDivider(),
            Padding(
              padding: Spacing.allMd,
              child: Wrap(
                spacing: Spacing.xs,
                children: [
                  for (final e in _lengths.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _length == e.key,
                      onSelected: (_) => setState(() => _length = e.key),
                    ),
                ],
              ),
            ),
            Gap(Spacing.xl),
          ],
        ),
      ),
    );
  }
}

class _RitualSheet extends ConsumerWidget {
  const _RitualSheet({required this.relationshipId, required this.ritual});
  final String relationshipId;
  final TogetherRitual ritual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(togetherRepositoryProvider);
    final next = ritual.nextStartsAt;
    final paused = ritual.status == RitualStatus.paused;
    final deviceTz = ref.watch(togetherDeviceTimezoneProvider).valueOrNull;
    final memories =
        ref.watch(togetherRitualMemoriesProvider(ritual.id)).valueOrNull ??
        const <RitualMemory>[];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(title: ritual.title),
          InfoRowWidget(
            title: ritual.whenFor(deviceTz),
            subtitle:
                paused
                    ? 'Paused'
                    : (next == null
                        ? ''
                        : 'Next: ${DateFormat.MMMEd().format(next)}'),
            icon: Icons.event_repeat_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
          ),
          if (!paused && ritual.nextEventId != null) ...[
            AppDivider(),
            InfoRowWidget(
              title: 'Skip ${DateFormat.MMMEd().format(next!)}',
              subtitle: 'No problem — it’ll be back the week after',
              icon: Icons.redo_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () async {
                if (await confirmRitualSkip(context) && context.mounted) {
                  await _run(
                    context,
                    ref,
                    () => repo.skipRitualOccurrence(ritual.nextEventId!),
                    'Skipped this week.',
                  );
                }
              },
            ),
          ],
          AppDivider(),
          InfoRowWidget(
            title: 'Change time',
            subtitle: '',
            icon: Icons.schedule_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () {
              final navigator = Navigator.of(context);
              final host = navigator.context;
              navigator.pop();
              showRitualEditor(host, relationshipId, ritual: ritual);
            },
          ),
          AppDivider(),
          InfoRowWidget(
            title: paused ? 'Resume' : 'Pause',
            subtitle: '',
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap:
                () => _run(
                  context,
                  ref,
                  () => repo.setRitualStatus(
                    ritual.id,
                    paused ? 'active' : 'paused',
                  ),
                  paused ? 'Back on.' : 'Paused.',
                ),
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'End this ritual',
            subtitle: '',
            icon: Icons.close_rounded,
            iconColor: Theme.of(context).colorScheme.error,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder:
                    (c) => AlertDialog(
                      title: const Text('End this ritual?'),
                      content: const Text(
                        'Its future weeks come off both calendars.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(c).pop(false),
                          child: const Text('Keep it'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(c).pop(true),
                          child: const Text('End it'),
                        ),
                      ],
                    ),
              );
              if (ok == true && context.mounted) {
                await _run(
                  context,
                  ref,
                  () => repo.setRitualStatus(ritual.id, 'ended'),
                  'Ended.',
                );
              }
            },
          ),
          // Its memories, newest first — never a count (Phase 4 R9).
          AppDivider(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.md.w,
              Spacing.md,
              Spacing.md.w,
              Spacing.xs,
            ),
            child: Text(
              'Memories',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (memories.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Text(
                'After a week, add a line about it from Together.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final m in memories)
            InfoRowWidget(
              title: m.note ?? m.title,
              subtitle: DateFormat.MMMEd().format(m.day),
              icon: Icons.favorite_border_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              titleMaxLines: 2,
            ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}

class _RitualProposalSheet extends ConsumerWidget {
  const _RitualProposalSheet({required this.need});
  final TogetherNeed need;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ??
        'Your partner';
    final d = need.detail;
    final ritual = TogetherRitual.fromRow({
      'ritual_id': need.itemId,
      'template': d['template'],
      'title': need.title,
      'cadence': d['cadence'],
      'weekday': d['weekday'],
      'local_time': d['local_time'],
      'duration_min': d['duration_min'],
      'tz': d['tz'],
      'status': 'proposed',
    });
    final repo = ref.read(togetherRepositoryProvider);
    final deviceTz = ref.watch(togetherDeviceTimezoneProvider).valueOrNull;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(title: '$partner suggested a ritual'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(
              need.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          InfoRowWidget(
            title: ritual.whenFor(deviceTz),
            subtitle:
                _lengths[ritual.durationMin] ?? '${ritual.durationMin} min',
            icon: Icons.event_repeat_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
          ),
          AppDivider(),
          InfoRowWidget(
            title: "We're in",
            subtitle: 'It goes on both calendars every week',
            icon: Icons.check_circle_outline_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap:
                () => _run(
                  context,
                  ref,
                  () => repo.decideRitual(need.itemId, accept: true),
                  'On your calendars.',
                ),
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'Not now',
            subtitle: '',
            icon: Icons.close_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap:
                () => _run(
                  context,
                  ref,
                  () => repo.decideRitual(need.itemId, accept: false),
                  'Sent.',
                ),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}

class _SentRitualSheet extends ConsumerWidget {
  const _SentRitualSheet({required this.ritual});
  final TogetherRitual ritual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ??
        'your partner';
    final deviceTz = ref.watch(togetherDeviceTimezoneProvider).valueOrNull;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(title: ritual.title),
          InfoRowWidget(
            title: 'Waiting for $partner',
            subtitle: ritual.whenFor(deviceTz),
            icon: Icons.hourglass_empty_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'Withdraw',
            subtitle: '',
            icon: Icons.undo_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap:
                () => _run(
                  context,
                  ref,
                  () => ref
                      .read(togetherRepositoryProvider)
                      .setRitualStatus(ritual.id, 'ended'),
                  'Withdrawn.',
                ),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
