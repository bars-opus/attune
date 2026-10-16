import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_preview.dart';
import 'package:attune/features/location/data/presence_repository.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const sharingErrorCopy = "Couldn't update your area. Try again.";

Future<void> showSharingSheet(
  BuildContext context, {
  required String relationshipId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  // Neutral, like the app's pages: never M3's primary-tinted sheet surface.
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  builder: (_) => SharingSheet(relationshipId: relationshipId),
);

/// Share on or off, and pause or resume (spec §3.1). Pause is symmetric
/// and silent: nobody is told, and you can't see them while it lasts.
class SharingSheet extends ConsumerStatefulWidget {
  const SharingSheet({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<SharingSheet> createState() => _SharingSheetState();
}

class _SharingSheetState extends ConsumerState<SharingSheet> {
  bool _busy = false;

  /// The device-only home area (spec §3.3); null until read.
  HomeArea? _home;
  bool _homeLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      readHomeArea(ref.read(coupleMapLocalStoreProvider)).then((h) {
        if (mounted) {
          setState(() {
            _home = h;
            _homeLoaded = true;
          });
        }
      }),
    );
  }

  /// Sets the home area from the presence sampler's coarse fix: the same
  /// medium-accuracy reading presence uses, never a precise one. The
  /// sampler never prompts; without permission the sample is null.
  Future<void> _setHome() async {
    // It records where you are NOW: ask first, so tapping it at work or a
    // friend's never quietly misplaces the one safety warning.
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Use where you are right now as your home area?'),
            content: const Text(
              'It stays on this phone. Pins near it start off.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Use here'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    final sample = await ref.read(presenceSamplerProvider).sample();
    if (!mounted) return;
    if (sample == null) {
      context.showErrorSnackbar("Couldn't find where you are. Try again.");
      return;
    }
    final home = HomeArea(lat: sample.lat, lng: sample.lng);
    await writeHomeArea(ref.read(coupleMapLocalStoreProvider), home);
    if (mounted) setState(() => _home = home);
  }

  Future<void> _clearHome() async {
    await writeHomeArea(ref.read(coupleMapLocalStoreProvider), null);
    if (mounted) setState(() => _home = null);
  }

  Future<void> _removeAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _confirmAndRemoveAll();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndRemoveAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Remove all your places?'),
            content: const Text('Your stories stay.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Remove all'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    final container = ProviderScope.containerOf(context);
    try {
      final n = await container
          .read(storyPlacesRepositoryProvider)
          .clearMine(widget.relationshipId);
      if (mounted) {
        context.showSuccessSnackbar(switch (n) {
          0 => 'No places to remove',
          1 => 'Removed 1 place',
          _ => 'Removed $n places',
        });
      }
    } catch (_) {
      if (mounted) context.showErrorSnackbar(sharingErrorCopy);
    } finally {
      container.invalidate(storyPlacesProvider);
    }
  }

  /// The switch's value while a change is in flight, until the read agrees
  /// (so it never snaps back on the refetch frame), or the call failed.
  bool? _pendingOn;

  Future<void> _run(
    Future<void> Function(PresenceRepository r) action, {
    VoidCallback? onError,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Captured now: the sheet may be dismissed before the call returns, and
    // the map must still re-read (ref can't be used after dispose).
    final container = ProviderScope.containerOf(context);
    try {
      await action(container.read(presenceRepositoryProvider));
    } catch (_) {
      if (mounted) {
        onError?.call();
        context.showErrorSnackbar(sharingErrorCopy);
      }
    } finally {
      container.invalidate(coupleMapPresenceProvider(widget.relationshipId));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.relationshipId;
    final theme = Theme.of(context);
    final state =
        ref.watch(presenceStateProvider(rel)).valueOrNull ??
        const PresenceState(PresenceStatus.off);
    final presenceAsync = ref.watch(coupleMapPresenceProvider(rel));
    final widgetOn =
        ref.watch(coupleWidgetEnabledProvider).valueOrNull ?? false;
    if (_pendingOn != null &&
        !_busy &&
        !presenceAsync.isRefreshing &&
        !presenceAsync.isLoading &&
        state.isOn == _pendingOn) {
      _pendingOn = null; // the read caught up
    }
    final until = state.pausedUntil;
    final left = until?.difference(DateTime.now());
    Widget pauseRow(String title, Duration? d, {required bool last}) =>
        MergeSemantics(
          child: InfoRowWidget(
            // M3's secondary-text colour: meets WCAG AA at 12 sp.
            subTitleFontColor: theme.colorScheme.onSurfaceVariant,
            title: title,
            subtitle:
                d == null
                    ? 'Until you turn it back on'
                    : 'Then back at your next open',
            icon: Icons.pause_outlined,
            showAvatar: false,
            showTrailingArrow: false,
            // Without this InfoRowWidget adds an "open in new" glyph.
            disableTrailing: true,
            showDivider: !last,
            // The home-screen widget's distance goes first (widget §4.3).
            onTap:
                _busy
                    ? null
                    : () => _run((r) async {
                      await CoupleWidgetSync.hideDistanceNow();
                      await r.pause(rel, d);
                    }),
          ),
        );
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BottomSheetHeader(title: 'Sharing'),
            CardInkWell(
              child: Column(
                children: [
                  // One labelled switch for screen readers (InfoRowWidget doesn't merge
                  // a toggle row's semantics; SwitchListTile does the same).
                  MergeSemantics(
                    child: InfoRowWidget(
                      // M3's secondary-text colour: meets WCAG AA at 12 sp.
                      subTitleFontColor: theme.colorScheme.onSurfaceVariant,
                      title: 'Share my approximate area',
                      subtitle:
                          'Your neighbourhood, never your address. Updates when you open Attune.',
                      icon: Icons.location_on_outlined,
                      isToggleItem: true,
                      toggleValue: _pendingOn ?? state.isOn,
                      showAvatar: false,
                      showDivider: state.isOn,
                      onToggleChanged: (v) {
                        if (_busy) return;
                        setState(() => _pendingOn = v);
                        _run(
                          (r) async {
                            if (!v) await CoupleWidgetSync.hideDistanceNow();
                            await (v
                                ? r.startSharing(rel)
                                : r.stopSharing(rel));
                          },
                          onError: () => setState(() => _pendingOn = null),
                        );
                      },
                    ),
                  ),
                  if (state.status == PresenceStatus.sharing) ...[
                    pauseRow(
                      'Pause for 1 hour',
                      const Duration(hours: 1),
                      last: false,
                    ),
                    pauseRow(
                      'Pause for 8 hours',
                      const Duration(hours: 8),
                      last: false,
                    ),
                    pauseRow('Pause until I resume', null, last: true),
                  ],
                  if (state.status == PresenceStatus.paused)
                    MergeSemantics(
                      child: InfoRowWidget(
                        // M3's secondary-text colour: meets WCAG AA at 12 sp.
                        subTitleFontColor: theme.colorScheme.onSurfaceVariant,
                        title: 'Resume',
                        subtitle:
                            left == null || left.isNegative
                                ? 'Paused until you resume'
                                : 'Paused · ${pauseRemainingLabel(left)} left',
                        icon: Icons.play_arrow_rounded,
                        showAvatar: false,
                        showTrailingArrow: false,
                        disableTrailing: true,
                        showDivider: false,
                        onTap: _busy ? null : () => _run((r) => r.resume(rel)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm,
                Spacing.lg,
                Spacing.md,
              ),
              child: Text(
                'Pausing hides you from each other. Nobody is told.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // The home-screen distance widget (widget spec §3.4).
            CardInkWell(
              child: Column(
                children: [
                  MergeSemantics(
                    child: InfoRowWidget(
                      // M3's secondary-text colour: meets WCAG AA at 12 sp.
                      subTitleFontColor: theme.colorScheme.onSurfaceVariant,
                      title: widgetToggleTitle,
                      subtitle: widgetToggleSubtitle,
                      icon: Icons.widgets_outlined,
                      isToggleItem: true,
                      toggleValue: widgetOn,
                      showAvatar: false,
                      showDivider: false,
                      onToggleChanged:
                          (v) => ref
                              .read(coupleWidgetEnabledProvider.notifier)
                              .set(v),
                    ),
                  ),
                  if (widgetOn) const CoupleWidgetPreviewCard(),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
            // Story places (Phase 2): the home-area warning (device only)
            // and removing every place I pinned.
            CardInkWell(
              child: Column(
                children: [
                  if (_homeLoaded && _home == null)
                    MergeSemantics(
                      child: InfoRowWidget(
                        // M3's secondary-text colour: meets WCAG AA at 12 sp.
                        subTitleFontColor: theme.colorScheme.onSurfaceVariant,
                        title: 'Warn me near home',
                        subtitle:
                            'Uses where you are now. Kept on this phone only.',
                        icon: Icons.home_outlined,
                        showAvatar: false,
                        showTrailingArrow: false,
                        disableTrailing: true,
                        showDivider: true,
                        onTap: _setHome,
                      ),
                    ),
                  if (_home != null) ...[
                    InfoRowWidget(
                      // M3's secondary-text colour: meets WCAG AA at 12 sp.
                      subTitleFontColor: theme.colorScheme.onSurfaceVariant,
                      title: 'Home area set',
                      subtitle: 'Pins near it start off',
                      icon: Icons.home_outlined,
                      showAvatar: false,
                      showTrailingArrow: false,
                      disableTrailing: true,
                      showDivider: true,
                    ),
                    MergeSemantics(
                      child: InfoRowWidget(
                        // M3's secondary-text colour: meets WCAG AA at 12 sp.
                        subTitleFontColor: theme.colorScheme.onSurfaceVariant,
                        title: 'Clear home area',
                        subtitle: 'Forget it on this phone',
                        icon: Icons.home_work_outlined,
                        showAvatar: false,
                        showTrailingArrow: false,
                        disableTrailing: true,
                        showDivider: true,
                        onTap: _clearHome,
                      ),
                    ),
                  ],
                  MergeSemantics(
                    child: InfoRowWidget(
                      // M3's secondary-text colour: meets WCAG AA at 12 sp.
                      subTitleFontColor: theme.colorScheme.onSurfaceVariant,
                      title: 'Remove all my places',
                      subtitle: 'Your stories stay',
                      icon: Icons.wrong_location_outlined,
                      showAvatar: false,
                      showTrailingArrow: false,
                      disableTrailing: true,
                      showDivider: false,
                      onTap: _removeAll,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
        ),
      ),
    );
  }
}
