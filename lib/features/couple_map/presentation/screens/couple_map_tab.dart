import 'dart:async';
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/open_story_places.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/couple_map/presentation/widgets/couple_map_list_sheet.dart';
import 'package:attune/features/couple_map/presentation/widgets/distance_card.dart';
import 'package:attune/features/couple_map/presentation/widgets/glass_surface.dart';
import 'package:attune/features/couple_map/presentation/widgets/pin_image_renderer.dart';
import 'package:attune/features/couple_map/presentation/widgets/sharing_chip.dart';
import 'package:attune/features/couple_map/presentation/widgets/sharing_sheet.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart'
    show storyReadGatewayProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The couple map (spec §3), shown full screen by CoupleMapScreen.
/// Watching coupleMapPresenceProvider is what samples on open (only while
/// sharing) and on app resume.
class CoupleMapTab extends ConsumerStatefulWidget {
  const CoupleMapTab({super.key, required this.relationshipId, this.onBack});
  final String relationshipId;

  /// Full screen: a Back button left of the sharing chip (null: none).
  final VoidCallback? onBack;

  @override
  ConsumerState<CoupleMapTab> createState() => _CoupleMapTabState();
}

class _CoupleMapTabState extends ConsumerState<CoupleMapTab> {
  CoupleMapController? _controller;
  CoupleMapStyle _style = CoupleMapStyle.standard;
  bool _failed = false;

  /// Who the camera has been fitted to: it fits again only when someone
  /// new is on the map (the partner appearing later), never for the same
  /// people. (A partner who went stale and came back isn't re-fitted.)
  final _fittedWho = <PresenceWho>{};
  bool? _dark;
  Timer? _tick;
  late final AppLifecycleListener _lifecycle;

  /// Each push takes a number; a push that a newer one overtook (its
  /// avatars rendered slowly) doesn't draw, so a partner who has gone
  /// never comes back from a stale push.
  int _pushGen = 0;

  /// Story pins (Phase 2): the filter, the unfiltered list from the one
  /// fetch, and a generation so a slow thumbnail batch never overwrites a
  /// newer set.
  StoryFilter _filter = StoryFilter.both;
  List<StoryPlace> _allPlaces = const [];
  int _storyGen = 0;

  /// The one-time "Stories you pin…" hint: null until read from the store.
  bool? _hintSeen;
  bool _hintThisVisit = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(coupleMapLocalStoreProvider)
          .read(CoupleMapLocalKeys.storiesHintSeen)
          .then((v) {
            if (mounted) setState(() => _hintSeen = v == 'true');
          }),
    );
    // Keeps "Paused · 42 min" counting down.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // Back from airplane mode or Settings: give the map another go.
    _lifecycle = AppLifecycleListener(onResume: _retryMap);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  /// Opens the reel over tapped story pins, oldest first.
  void _openStories(List<String> storyIds) => openStoryPlaces(
    context,
    relationshipId: widget.relationshipId,
    places: _allPlaces,
    storyIds: storyIds,
  );

  /// Mine / Partner's are filtered here from the one Both fetch, so the
  /// Stories button's visibility always reflects every pinned story.
  List<StoryPlace> _filtered(List<StoryPlace> all) {
    final me = ref.read(currentUserProvider)?.id;
    return switch (_filter) {
      StoryFilter.both => all,
      StoryFilter.mine => [
        for (final p in all)
          if (p.authorId == me) p,
      ],
      StoryFilter.partner => [
        for (final p in all)
          if (p.authorId != me) p,
      ],
    };
  }

  void _cycleFilter() {
    setState(() => _filter = _filter.next);
    unawaited(_pushStories(_filtered(_allPlaces)));
  }

  /// Pins at once, then thumbnails in parallel batches of 16, redrawing
  /// after each (spec §7: thumbnail volume). A null signature skips a pin.
  Future<void> _pushStories(List<StoryPlace> places) async {
    final gen = ++_storyGen;
    final c = _controller;
    if (c == null || !mounted) return;
    final pins = storyScenePins(places);
    final images = <String, RawPin>{};
    await c.setStories(pins, Map.of(images));
    if (!mounted || gen != _storyGen) return;
    final cs = Theme.of(context).colorScheme;
    final px =
        (CoupleMapConfig.storyPinSize * MediaQuery.devicePixelRatioOf(context))
            .round();
    final gateway = ref.read(storyReadGatewayProvider);
    final renderer = ref.read(pinImageRendererProvider);
    for (var start = 0; start < places.length; start += 16) {
      final chunk = places.skip(start).take(16);
      await Future.wait(
        chunk.map((p) async {
          PinSpec spec(String? url) => PinSpec(
            imageUrl: url,
            cacheKey: p.story.thumbnailKey,
            initials: '',
            ring: Colors.white,
            fill: cs.surfaceContainerHighest,
            onFill: cs.onSurface,
            sizePx: px,
          );
          // Already rendered (keyed by thumbnail): no signing round trip.
          final cached = renderer.peekRaw(spec(null));
          if (cached != null) {
            images[p.storyItemId] = await cached;
            return;
          }
          final signed = await gateway.signMediaUrl(p.story.thumbnailKey);
          if (signed == null) return;
          images[p.storyItemId] = await renderer.renderRaw(spec(signed));
        }),
      );
      if (!mounted || gen != _storyGen || _controller != c) return;
      if (images.isNotEmpty) await c.setStories(pins, Map.of(images));
    }
  }

  void _retryMap() {
    if (mounted && _failed) setState(() => _failed = false);
  }

  void _retry() {
    _retryMap();
    ref.invalidate(coupleMapPresenceProvider(widget.relationshipId));
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  int get _pinSizePx =>
      (CoupleMapConfig.pinSize * MediaQuery.devicePixelRatioOf(context))
          .round();

  void _onReady(CoupleMapController c) {
    _controller = c;
    final p =
        ref.read(coupleMapPresenceProvider(widget.relationshipId)).valueOrNull;
    if (p != null) unawaited(_push(p));
    if (_allPlaces.isNotEmpty) unawaited(_pushStories(_filtered(_allPlaces)));
  }

  Future<void> _push(CoupleMapPresence p) async {
    final gen = ++_pushGen;
    final c = _controller;
    if (c == null || !mounted) return;
    final areas = sceneAreas(p);
    final avatars = await _avatars(areas);
    if (!mounted || _controller != c || gen != _pushGen) return;
    await c.setPresence(
      areas,
      avatars,
      areaColor: Theme.of(context).colorScheme.primary,
      together: p.together,
      pinSizePx: _pinSizePx,
    );
    final who = {for (final a in areas) a.who};
    if (areas.isNotEmpty && !who.every(_fittedWho.contains)) {
      final first = _fittedWho.isEmpty;
      _fittedWho.addAll(who);
      await c.fitTo([
        for (final a in areas) a.centre,
      ], animate: !first && !_reduceMotion);
    }
  }

  Future<Map<PresenceWho, Uint8List>> _avatars(List<SceneArea> areas) async {
    final people = await ref.read(
      coupleMapPeopleProvider(widget.relationshipId).future,
    );
    if (!mounted) return const {};
    final cs = Theme.of(context).colorScheme;
    final px = _pinSizePx;
    final renderer = ref.read(pinImageRendererProvider);
    PinSpec spec(String? url, String initials) => PinSpec(
      imageUrl: url,
      initials: initials,
      ring: cs.surface,
      fill: cs.primaryContainer,
      onFill: cs.onPrimaryContainer,
      sizePx: px,
    );
    return {
      for (final a in areas)
        a.who: await renderer.render(
          a.who == PresenceWho.self
              ? spec(people.selfUrl, people.selfInitials)
              : spec(people.partnerUrl, people.partnerInitials),
        ),
    };
  }

  Future<void> _fit() async {
    final p =
        ref.read(coupleMapPresenceProvider(widget.relationshipId)).valueOrNull;
    final areas = p == null ? const <SceneArea>[] : sceneAreas(p);
    // Spec §3.1: both areas and the visible stories.
    await _controller?.fitTo([
      for (final a in areas) a.centre,
      for (final s in _filtered(_allPlaces)) MapPoint(s.lat, s.lng),
    ], animate: !_reduceMotion);
  }

  void _toggleStyle(bool dark) {
    final next =
        _style == CoupleMapStyle.standard
            ? CoupleMapStyle.satellite
            : CoupleMapStyle.standard;
    setState(() => _style = next);
    unawaited(_controller?.setStyle(next, dark: dark));
  }

  void _onNoticeTap(CoupleMapNotice n) {
    switch (n) {
      case CoupleMapNotice.notSharing:
        showSharingSheet(context, relationshipId: widget.relationshipId);
      case CoupleMapNotice.locationOff:
        ref.read(presenceSamplerProvider).openSettings();
      case CoupleMapNotice.justYou:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.relationshipId;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    if (_dark != null && _dark != dark) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller?.setStyle(_style, dark: dark);
        // Areas and pin rings take theme colours: redraw them too.
        final p = ref.read(coupleMapPresenceProvider(rel)).valueOrNull;
        if (p != null) unawaited(_push(p));
        // Story pins' fallback fills take theme colours too.
        unawaited(_pushStories(_filtered(_allPlaces)));
      });
    }
    _dark = dark;

    ref.listen(coupleMapPresenceProvider(rel), (_, next) {
      final p = next.valueOrNull;
      if (p != null) unawaited(_push(p));
    });
    final placesKey = StoryPlacesKey(rel);
    ref.listen(storyPlacesProvider(placesKey), (_, next) {
      final v = next.valueOrNull;
      if (v == null) return;
      _allPlaces = v;
      unawaited(_pushStories(_filtered(v)));
    });
    final placesAsync = ref.watch(storyPlacesProvider(placesKey));
    final allPlaces = placesAsync.valueOrNull ?? _allPlaces;
    final showStories = allPlaces.isNotEmpty;

    final presenceAsync = ref.watch(coupleMapPresenceProvider(rel));
    final presence = presenceAsync.valueOrNull;
    // Unknown access must not claim "off".
    final access =
        ref.watch(locationAccessProvider).valueOrNull ?? LocationAccess.granted;
    final people = ref.watch(coupleMapPeopleProvider(rel)).valueOrNull;
    final partnerName = people?.partnerName ?? 'your partner';
    final distance = ref.watch(partnerDistanceWithReunionProvider(rel));
    final now = DateTime.now();
    final state = presence?.state;
    final notice = presence == null ? null : coupleMapNotice(presence, access);
    // A failed first read with nothing to fall back on: say so, offer a
    // retry, and never claim "Off" for a state we haven't read (1.3).
    final loadFailed = presence == null && presenceAsync.hasError;
    final mapAvailable =
        !_failed && ref.watch(coupleMapTokenProvider).isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom + Spacing.md;
    // Full screen, the map draws under the status bar: controls start below it.
    final topInset = MediaQuery.paddingOf(context).top;

    // The one-time hint: first visit with nothing pinned yet (§3.4).
    if (_hintSeen == false &&
        !_hintThisVisit &&
        placesAsync.hasValue &&
        allPlaces.isEmpty) {
      _hintThisVisit = true;
      unawaited(
        ref
            .read(coupleMapLocalStoreProvider)
            .write(CoupleMapLocalKeys.storiesHintSeen, 'true'),
      );
    }
    final showHint = _hintThisVisit && allPlaces.isEmpty;

    final Widget bottom;
    if (loadFailed) {
      bottom = RetryCard(onTap: _retry);
    } else if (presence == null) {
      bottom = const LoadingCard();
    } else if (notice != null) {
      bottom = NoticeCard(
        notice: notice,
        onTap:
            notice == CoupleMapNotice.justYou
                ? null
                : () => _onNoticeTap(notice),
      );
    } else if (distance != null) {
      bottom = DistanceCard(
        copy: distanceCardCopy(
          distance,
          partnerName: partnerName,
          myUtcOffsetMinutes: now.timeZoneOffset.inMinutes,
          now: now,
        ),
        people:
            people ??
            const CoupleMapPeople(
              selfInitials: '?',
              partnerInitials: '?',
              partnerName: 'your partner',
            ),
      );
    } else {
      bottom = const SizedBox.shrink();
    }

    final chip = SharingChip(
      // Unread state: a neutral word, never "Off".
      label:
          state == null
              ? 'Sharing'
              : sharingChipLabel(
                state,
                access: access,
                partnerName: partnerName,
                now: now,
              ),
      status: state?.status,
      locationOff: access != LocationAccess.granted,
      onTap: () => showSharingSheet(context, relationshipId: rel),
    );

    final onBack = widget.onBack;
    final back =
        onBack == null
            ? null
            : GlassIconButton(
              icon: Icons.adaptive.arrow_back,
              tooltip: 'Back',
              onPressed: onBack,
            );
    final topLeft = Row(
      children: [
        if (back != null) ...[back, const SizedBox(width: Spacing.sm)],
        Flexible(child: chip),
      ],
    );

    if (!mapAvailable) {
      return ColoredBox(
        color: theme.colorScheme.surface,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Spacing.md,
            topInset + Spacing.md,
            Spacing.md,
            Spacing.md,
          ),
          children: [
            topLeft,
            const SizedBox(height: Spacing.md),
            // Nothing read yet (or the read failed): say so here too, with
            // the retry that also brings the map back.
            if (presence == null) ...[
              bottom,
              const SizedBox(height: Spacing.md),
            ],
            CoupleMapListContent(
              presence: presence ?? CoupleMapPresence.none,
              partnerName: partnerName,
              notice: notice,
              now: now,
              onNoticeTap:
                  notice == null || notice == CoupleMapNotice.justYou
                      ? null
                      : () => _onNoticeTap(notice),
              places: _filtered(allPlaces),
              onPlaceTap: (p) => _openStories([p.storyItemId]),
            ),
          ],
        ),
      );
    }

    final build = ref.watch(coupleMapViewBuilderProvider);
    return Stack(
      children: [
        Positioned.fill(
          child: build(
            style: _style,
            dark: dark,
            onReady: _onReady,
            ornamentTop:
                CoupleMapConfig.rightColumnBottom(stories: showStories) +
                topInset,
            onStoriesTapped: _openStories,
            ornamentBottom:
                bottomInset + CoupleMapConfig.cardMaxHeight + Spacing.sm,
            onLoadError: () {
              if (!mounted) return;
              // The map's State is going away: stop calling it.
              _controller = null;
              _fittedWho.clear();
              setState(() => _failed = true);
            },
          ),
        ),
        Positioned(
          top: topInset + Spacing.md,
          left: Spacing.md,
          right: Spacing.md + CoupleMapConfig.glassTarget + Spacing.sm,
          child: topLeft,
        ),
        // One right-hand column, so nothing overlaps on short screens; the
        // compass sits below it (CoupleMapConfig.rightColumnBottom).
        Positioned(
          top: topInset + Spacing.md,
          right: Spacing.md,
          child: Column(
            children: [
              GlassIconButton(
                icon:
                    _style == CoupleMapStyle.standard
                        ? Icons.satellite_alt_outlined
                        : Icons.map_outlined,
                tooltip:
                    _style == CoupleMapStyle.standard
                        ? 'Satellite view'
                        : 'Map view',
                onPressed: () => _toggleStyle(dark),
              ),
              const SizedBox(height: CoupleMapConfig.glassGap),
              // Hidden while nothing is pinned (spec §3.1).
              if (showStories) ...[
                GlassIconButton(
                  icon: switch (_filter) {
                    StoryFilter.both => Icons.people_outline,
                    StoryFilter.mine => Icons.person_outline,
                    StoryFilter.partner => Icons.person_pin_circle_outlined,
                  },
                  tooltip: switch (_filter) {
                    StoryFilter.both => 'Stories: both of you',
                    StoryFilter.mine => 'Stories: mine',
                    StoryFilter.partner => "Stories: $partnerName's",
                  },
                  onPressed: _cycleFilter,
                ),
                const SizedBox(height: CoupleMapConfig.glassGap),
              ],
              GlassIconButton(
                icon: Icons.center_focus_strong_outlined,
                tooltip: 'Recentre on us',
                onPressed: _fit,
              ),
              const SizedBox(height: CoupleMapConfig.glassGap),
              GlassIconButton(
                icon: Icons.list_alt_rounded,
                tooltip: 'List',
                onPressed:
                    () => showCoupleMapListSheet(context, relationshipId: rel),
              ),
              const SizedBox(height: CoupleMapConfig.glassGroupGap),
              GlassIconButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onPressed:
                    () => _controller?.zoomBy(1, animate: !_reduceMotion),
              ),
              const SizedBox(height: CoupleMapConfig.glassGap),
              GlassIconButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onPressed:
                    () => _controller?.zoomBy(-1, animate: !_reduceMotion),
              ),
            ],
          ),
        ),
        Positioned(
          left: Spacing.md,
          right: Spacing.md,
          bottom: bottomInset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHint) ...[
                GlassPanel(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Row(
                    children: [
                      Icon(
                        Icons.photo_camera_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Text(
                          'Stories you pin from the camera appear here',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),
              ],
              AnimatedSwitcher(
                duration:
                    _reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(bottom.runtimeType),
                  child: bottom,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
