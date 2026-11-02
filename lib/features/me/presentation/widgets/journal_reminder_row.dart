import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _clock(TimeOfDay time) =>
    MyDateFormat.toTime(DateTime(2000, 1, 1, time.hour, time.minute));

String _days(AppLocalizations loc, int isoWeekday) => switch (isoWeekday) {
  1 => loc.flow_weekdaysMon,
  2 => loc.flow_weekdaysTue,
  3 => loc.flow_weekdaysWed,
  4 => loc.flow_weekdaysThu,
  5 => loc.flow_weekdaysFri,
  6 => loc.flow_weekdaysSat,
  _ => loc.flow_weekdaysSun,
};

/// "Off" or "Mondays at 08:00 PM" (Spec 1 §3.10 J3; MyDateFormat.toTime).
String reminderSummary(AppLocalizations loc, JournalReminder reminder) {
  final day = reminder.isoWeekday;
  final time = reminder.time;
  if (!reminder.enabled || day == null || time == null) {
    return loc.flow_reminderOff;
  }
  return loc.flow_reminderWhen(_days(loc, day), _clock(time));
}

/// J3's row in Your space. An unreadable reminder shows no summary and is
/// read again when the app comes back (B7 review I-1).
class JournalReminderRow extends ConsumerStatefulWidget {
  const JournalReminderRow({super.key});

  @override
  ConsumerState<JournalReminderRow> createState() => _JournalReminderRowState();
}

class _JournalReminderRowState extends ConsumerState<JournalReminderRow>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(journalReminderProvider).hasError) {
      ref.invalidate(journalReminderProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final reminder = knownReminder(ref.watch(journalReminderProvider));
    return SpaceRow(
      title: loc.flow_reminderTitle,
      subtitle: reminder == null ? '' : reminderSummary(loc, reminder),
      icon: Icons.alarm_outlined,
      onTap: () => showJournalReminderSheet(context),
    );
  }
}

/// Settings -> Notifications -> "Remind me to write" (W3 plan P-22): the
/// same sheet, from anywhere, so the reminder can always be turned off.
SettingsConfig? journalReminderSetting(BuildContext context, WidgetRef ref) {
  if (!ref.watch(flowPathsV2Provider)) return null;
  final loc = AppLocalizations.of(context)!;
  final reminder = knownReminder(ref.watch(journalReminderProvider));
  return SettingsConfig(
    id: 'journal_reminder',
    title: loc.flow_reminderTitle,
    subtitle: reminder == null ? '' : reminderSummary(loc, reminder),
    icon: Icons.alarm_outlined,
    type: SettingsItemType.navigation,
    onTap: () => showJournalReminderSheet(context),
    iconColor: Colors.orange,
  );
}

Future<void> showJournalReminderSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const JournalReminderSheet(),
    );

/// J3's sheet: "When should we remind you?" A weekday, a time (08:00 to
/// 21:59), "Turn on"; "Turn off" when on; the contextual notification ask
/// while notifications are off.
class JournalReminderSheet extends ConsumerStatefulWidget {
  const JournalReminderSheet({super.key});

  @override
  ConsumerState<JournalReminderSheet> createState() =>
      _JournalReminderSheetState();
}

class _JournalReminderSheetState extends ConsumerState<JournalReminderSheet> {
  int? _day;
  TimeOfDay? _time;
  bool _busy = false;
  String? _error;

  static const _defaultTime = TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    // B7 review I-1: an unreadable reminder is read again as the sheet opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(journalReminderProvider).hasError) {
        ref.invalidate(journalReminderProvider);
      }
    });
  }

  /// B7 review I-1: while the reminder is unknown, nothing can save over it.
  List<Widget> _unknown(AppLocalizations loc, {required bool reading}) => [
    const SizedBox(height: Spacing.md),
    if (reading)
      const Center(child: CircularProgressIndicator())
    else ...[
      FlowErrorLine(text: loc.flow_reminderReadFailed, liveRegion: true),
      const SizedBox(height: Spacing.md),
      FlowSecondaryButton(
        label: loc.flow_tryAgain,
        onPressed: () => ref.invalidate(journalReminderProvider),
      ),
    ],
  ];

  void _fail(String message) {
    setState(() => _error = message);
    SemanticsService.announce(message, Directionality.of(context));
  }

  String _quietHoursMessage(AppLocalizations loc) =>
      loc.flow_reminderQuietHours(_first, _last);

  // Ruling M-2: the first and last minutes allowed (22:00 itself is not).
  String get _first => _clock(const TimeOfDay(hour: 8, minute: 0));
  String get _last => _clock(const TimeOfDay(hour: 21, minute: 59));

  Future<void> _pickTime(TimeOfDay current) async {
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null || !mounted) return;
    // Owner ruling P-20: a time outside 08:00-21:59 is never taken (the
    // server's CHECK); the last good time stays and the sheet says why.
    if (!reminderTimeAllowed(picked)) {
      _fail(_quietHoursMessage(AppLocalizations.of(context)!));
      return;
    }
    setState(() {
      _time = picked;
      _error = null;
    });
  }

  Future<void> _save(JournalReminder reminder) async {
    if (_busy) return;
    final loc = AppLocalizations.of(context)!;
    final time = reminder.time;
    if (reminder.enabled && (time == null || !reminderTimeAllowed(time))) {
      _fail(_quietHoursMessage(loc));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(journalReminderProvider.notifier).save(reminder);
      if (mounted) Navigator.of(context).pop();
    } on ReminderRefused catch (refused) {
      if (mounted) {
        _fail(
          refused.reason == ReminderRefusal.quietHours
              ? _quietHoursMessage(loc)
              : loc.flow_saveFailed,
        );
      }
    } catch (_) {
      if (mounted) _fail(loc.flow_saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final reminder = ref.watch(journalReminderProvider);
    final known = knownReminder(reminder);
    final saved = known ?? JournalReminder.off;
    final day = _day ?? saved.isoWeekday ?? 1;
    final time = _time ?? saved.time ?? _defaultTime;
    final labels = [
      loc.flow_weekdayMon,
      loc.flow_weekdayTue,
      loc.flow_weekdayWed,
      loc.flow_weekdayThu,
      loc.flow_weekdayFri,
      loc.flow_weekdaySat,
      loc.flow_weekdaySun,
    ];
    return AllowLargeText(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  loc.flow_reminderSheetTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (known == null)
                ..._unknown(loc, reading: reminder.isLoading)
              else ...[
                const SizedBox(height: Spacing.md),
                Text(
                  loc.flow_reminderDay,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Wrap(
                  spacing: Spacing.sm,
                  // B7 review M-6: rows of chips never touch at large text.
                  runSpacing: Spacing.sm,
                  children: [
                    for (var i = 0; i < 7; i++)
                      ChoiceChip(
                        label: Text(labels[i]),
                        selected: day == i + 1,
                        onSelected: (_) => setState(() => _day = i + 1),
                      ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                // "Time", then the time and its button, which wrap under each
                // other at large text sizes instead of squeezing the time.
                Text(
                  loc.flow_reminderTime,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Wrap(
                  spacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _clock(time),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _pickTime(time),
                      style: TextButton.styleFrom(
                        foregroundColor: flowAccent(context),
                        minimumSize: const Size(48, 48),
                      ),
                      child: Text(loc.flow_reminderChangeTime),
                    ),
                  ],
                ),
                PushAskRow(
                  askContext: PushAskContext.j3,
                  reason: loc.flow_reminderNeedsPush,
                  action: loc.flow_reminderTurnOnPush,
                ),
                if (_error != null) ...[
                  const SizedBox(height: Spacing.sm),
                  FlowErrorLine(text: _error!),
                ],
                const SizedBox(height: Spacing.md),
                FlowPrimaryButton(
                  label: loc.flow_reminderTurnOn,
                  busy: _busy,
                  onPressed:
                      () => _save(
                        JournalReminder(
                          enabled: true,
                          isoWeekday: day,
                          time: time,
                        ),
                      ),
                ),
                if (saved.enabled) ...[
                  const SizedBox(height: Spacing.sm),
                  FlowSecondaryButton(
                    label: loc.flow_reminderTurnOff,
                    onPressed:
                        () => _save(
                          JournalReminder(
                            enabled: false,
                            isoWeekday: saved.isoWeekday,
                            time: saved.time,
                          ),
                        ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
