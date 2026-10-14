import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../domain/calendar_feed.dart';
import '../../domain/together_overlay.dart';
import '../../domain/together_prefs.dart';
import '../together_providers.dart';
import 'calendar_feed_sheet.dart';

/// What Together may send me. Each switch saves straight away.
Future<void> showTogetherSettingsSheet(
  BuildContext context,
  String relationshipId,
) => BottomSheetUtils.showDocumentationBottomSheet<void>(
  context: context,
  backgroundColor: Theme.of(context).colorScheme.neutral,
  widget: _TogetherSettingsSheet(relationshipId: relationshipId),
);

class _TogetherSettingsSheet extends ConsumerStatefulWidget {
  const _TogetherSettingsSheet({required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<_TogetherSettingsSheet> createState() =>
      _TogetherSettingsSheetState();
}

class _TogetherSettingsSheetState
    extends ConsumerState<_TogetherSettingsSheet> {
  /// What the switches show: the saved prefs once loaded, flipped at once
  /// on a tap, and put back if the save fails.
  TogetherPrefs? _prefs;

  /// A link being made: one tap at a time.
  bool _feedBusy = false;

  /// An overlay change in flight (Phase 6): one at a time.
  bool _overlayBusy = false;

  Future<void> _save(TogetherPrefs next) async {
    final before = _prefs;
    setState(() => _prefs = next);
    try {
      final saved = await ref
          .read(togetherRepositoryProvider)
          .setPrefs(widget.relationshipId, next);
      if (mounted) setState(() => _prefs = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _prefs = before);
      context.showErrorSnackbar('Could not save that. Please try again.');
    }
  }

  Future<void> _setMirror(bool on) async {
    final ok = await ref.read(togetherMirrorEnabledProvider.notifier).set(on);
    if (!ok && mounted) {
      // iOS never shows the prompt twice: offer the way back.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Calendar access is off. You can allow it in Settings.',
          ),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: () => ref.read(deviceBusySourceProvider).openSettings(),
          ),
        ),
      );
    }
  }

  Future<void> _setOverlay(OverlayLevel next, OverlayLevel current) async {
    if (_overlayBusy || next == current) return;
    setState(() => _overlayBusy = true);
    final repo = ref.read(togetherRepositoryProvider);
    final source = ref.read(deviceBusySourceProvider);
    try {
      if (current == OverlayLevel.off && !await source.requestAccess()) {
        if (mounted) {
          // iOS never shows the prompt twice: offer the way back.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Calendar access is off. You can allow it in Settings.',
              ),
              action: SnackBarAction(
                label: 'Open Settings',
                onPressed: () => source.openSettings(),
              ),
            ),
          );
        }
        return;
      }
      await repo.setOverlay(widget.relationshipId, next);
      ref.invalidate(togetherOverlayProvider(widget.relationshipId));
      if (next != OverlayLevel.off) {
        await syncBusyTimes(
          repo,
          source,
          widget.relationshipId,
          DateTime.now(),
        );
      }
      ref.invalidate(togetherFreeWindowsProvider(widget.relationshipId));
      ref.invalidate(togetherBusyStripsProvider(widget.relationshipId));
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar('Could not save that. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _overlayBusy = false);
    }
  }

  Future<void> _newLink() async {
    if (_feedBusy) return;
    setState(() => _feedBusy = true);
    try {
      final token =
          await ref.read(togetherRepositoryProvider).createCalendarFeed();
      ref.invalidate(togetherCalendarFeedProvider);
      if (!mounted) return;
      await showCalendarFeedLinkSheet(
        context,
        calendarFeedLinks(ref.read(togetherSupabaseUrlProvider), token),
      );
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar('Could not do that. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _feedBusy = false);
    }
  }

  Future<void> _turnOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Turn off your calendar link?'),
            content: const Text(
              'Your calendar app stops getting Together. The link stops working.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Keep it'),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Turn off'),
              ),
            ],
          ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(togetherRepositoryProvider).revokeCalendarFeed();
      ref.invalidate(togetherCalendarFeedProvider);
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar('Could not do that. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final partner =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ??
        'Your partner';
    _prefs ??=
        ref.watch(togetherPrefsProvider(widget.relationshipId)).valueOrNull;
    final prefs = _prefs;
    // Only a known state offers an action: "turn on" while the status is
    // unknown would silently replace a live link (Phase 5 review #2).
    final feedAsync = ref.watch(togetherCalendarFeedProvider);
    final feed = feedAsync.valueOrNull;
    final overlay = ref.watch(togetherOverlayProvider(widget.relationshipId));
    // Only a known value gets a switch (no "off" while it's still loading).
    final widgetOn = ref.watch(togetherWidgetEnabledProvider).valueOrNull;
    // Only on phones that can show it, and only once its value is known.
    final liveSupported =
        ref.watch(togetherLiveSupportedProvider).valueOrNull ?? false;
    final liveOn = ref.watch(togetherLiveEnabledProvider).valueOrNull;
    final mirrorOn = ref.watch(togetherMirrorEnabledProvider).valueOrNull;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          const BottomSheetHeader(title: 'Together settings'),
          if (prefs == null)
            const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            InfoRowWidget(
              title: 'Morning summary',
              subtitle:
                  'One note at 8am when something involves you. Sundays: your week.',
              icon: Icons.wb_twilight_rounded,
              showAvatar: false,
              showDivider: false,
              isToggleItem: true,
              toggleValue: prefs.dailySummary,
              onToggleChanged: (v) => _save(prefs.copyWith(dailySummary: v)),
            ),
            AppDivider(),
            InfoRowWidget(
              title: "$partner's big days",
              subtitle: 'A reminder to wish them luck and ask how it went',
              icon: Icons.favorite_border_rounded,
              showAvatar: false,
              showDivider: false,
              isToggleItem: true,
              toggleValue: prefs.careNudges,
              onToggleChanged: (v) => _save(prefs.copyWith(careNudges: v)),
            ),
          ],
          AppDivider(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.md.w,
              Spacing.md,
              Spacing.md.w,
              Spacing.xs,
            ),
            child: Text(
              'Free time together',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(
              'Only when you’re busy leaves your phone — never titles, places '
              'or people. Free times show once you’ve both chosen to. Turning '
              'it off deletes your busy times straight away.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          overlay.when(
            loading:
                () => const Padding(
                  padding: EdgeInsets.all(Spacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
            error:
                (_, __) => InfoRowWidget(
                  title: "Couldn't load this",
                  subtitle: 'Tap to try again',
                  icon: Icons.refresh_rounded,
                  showAvatar: false,
                  showDivider: false,
                  disableTrailing: true,
                  onTap:
                      () => ref.invalidate(
                        togetherOverlayProvider(widget.relationshipId),
                      ),
                ),
            data:
                (level) => Column(
                  children: [
                    for (final (value, title) in [
                      (OverlayLevel.off, 'Off'),
                      (OverlayLevel.freeWindows, "Show when we're both free"),
                      (OverlayLevel.strips, 'Also show $partner my busy times'),
                    ])
                      RadioListTile<OverlayLevel>(
                        value: value,
                        groupValue: level,
                        title: Text(title),
                        onChanged:
                            _overlayBusy ? null : (v) => _setOverlay(v!, level),
                      ),
                  ],
                ),
          ),
          if (widgetOn != null) ...[
            AppDivider(),
            InfoRowWidget(
              title: 'Next plans on my home screen',
              subtitle:
                  'Off unless you turn it on. Shows your next plans’ titles and '
                  'times — no names. Anyone who sees your phone can see it; quick '
                  'exit clears it.',
              icon: Icons.widgets_outlined,
              showAvatar: false,
              showDivider: false,
              isToggleItem: true,
              toggleValue: widgetOn,
              onToggleChanged:
                  (v) =>
                      ref.read(togetherWidgetEnabledProvider.notifier).set(v),
            ),
          ],
          if (liveSupported && liveOn != null) ...[
            AppDivider(),
            InfoRowWidget(
              title: "Tonight's plan on my lock screen",
              subtitle:
                  'Off unless you turn it on. A plan you’re both in shows its '
                  'title, time and a countdown from 4 hours before — no names. '
                  'Anyone who sees your phone can see it; quick exit clears it.',
              icon: Icons.lock_clock_outlined,
              showAvatar: false,
              showDivider: false,
              isToggleItem: true,
              toggleValue: liveOn,
              onToggleChanged:
                  (v) => ref.read(togetherLiveEnabledProvider.notifier).set(v),
            ),
          ],
          if (mirrorOn != null) ...[
            AppDivider(),
            InfoRowWidget(
              title: "Copy our plans to my phone's calendar",
              subtitle:
                  'Off unless you turn it on. Adds a calendar called “Plans” '
                  'with the next 60 days of plans you’re in — titles, times and '
                  'places only, never names or notes. If your phone keeps '
                  'calendars in iCloud it may show on your other devices. '
                  'Turning it off or quick exit deletes it.',
              icon: Icons.event_available_outlined,
              showAvatar: false,
              showDivider: false,
              isToggleItem: true,
              toggleValue: mirrorOn,
              onToggleChanged: (v) => _setMirror(v),
            ),
          ],
          AppDivider(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.md.w,
              Spacing.md,
              Spacing.md.w,
              Spacing.xs,
            ),
            child: Text(
              'Your calendar app',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (feed == null && feedAsync.hasError)
            InfoRowWidget(
              title: "Couldn't check your calendar link",
              subtitle: 'Tap to try again',
              icon: Icons.refresh_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () => ref.invalidate(togetherCalendarFeedProvider),
            )
          else if (feed == null)
            const Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (feed.active) ...[
            InfoRowWidget(
              title: 'Together is in your calendar app',
              subtitle:
                  'On since ${DateFormat.MMMd().format(feed.since ?? DateTime.now())}',
              icon: Icons.event_available_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
            ),
            AppDivider(),
            InfoRowWidget(
              title: 'Get a new link',
              subtitle: 'The old one stops working',
              icon: Icons.link_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: _feedBusy ? null : _newLink,
            ),
            AppDivider(),
            InfoRowWidget(
              title: 'Turn off',
              subtitle: '',
              icon: Icons.link_off_rounded,
              iconColor: Theme.of(context).colorScheme.error,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: _turnOff,
            ),
          ] else
            InfoRowWidget(
              title: 'Show Together in my calendar app',
              subtitle: 'Google, Apple or Outlook: a private link only you use',
              icon: Icons.calendar_month_outlined,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: _feedBusy ? null : _newLink,
            ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
