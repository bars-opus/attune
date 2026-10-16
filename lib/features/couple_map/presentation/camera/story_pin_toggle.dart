import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_controller.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds the controller (seam for tests).
final storyPinControllerFactoryProvider =
    Provider<StoryPinController Function({required Future<bool> pausedCheck})>((
      ref,
    ) {
      return ({required Future<bool> pausedCheck}) => StoryPinController(
        store: ref.read(coupleMapLocalStoreProvider),
        resolver: ref.read(storyPlaceResolverProvider),
        paused: false,
        pausedCheck: pausedCheck,
      );
    });

/// The camera's "Pin to our map" pill. Renders nothing unless the couple
/// map is enabled. Reads my paused state ONCE (fetchMapPresence), never the
/// sampling provider: the camera must not trigger presence samples (§6.1).
class StoryPinToggle extends ConsumerWidget {
  const StoryPinToggle({
    super.key,
    required this.relationshipId,
    required this.onController,
  });
  final String relationshipId;
  final ValueChanged<StoryPinController?> onController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(coupleMapEnabledProvider).valueOrNull == true;
    if (!enabled) return const SizedBox.shrink();
    return _PinToggleBody(
      relationshipId: relationshipId,
      onController: onController,
    );
  }
}

class _PinToggleBody extends ConsumerStatefulWidget {
  const _PinToggleBody({
    required this.relationshipId,
    required this.onController,
  });
  final String relationshipId;
  final ValueChanged<StoryPinController?> onController;
  @override
  ConsumerState<_PinToggleBody> createState() => _PinToggleBodyState();
}

class _PinToggleBodyState extends ConsumerState<_PinToggleBody> {
  StoryPinController? _c;

  @override
  void initState() {
    super.initState();
    // The pill and its controller exist at once; my paused state is read
    // in the background and applied when it lands (a shutter before then
    // waits for it), so a slow link never silently drops a remembered on.
    final pausedCheck = ref
        .read(presenceRepositoryProvider)
        .fetchMapPresence(widget.relationshipId)
        .then((p) => p.state.status == PresenceStatus.paused);
    final c = ref.read(storyPinControllerFactoryProvider)(
      pausedCheck: pausedCheck,
    );
    c.addListener(() {
      if (mounted) setState(() {});
    });
    _c = c;
    unawaited(c.init());
    // After this frame: the parent's callback may call setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onController(c);
    });
  }

  @override
  void dispose() {
    widget.onController(null);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    final place = c.place;
    final sub = switch (c.notice) {
      StoryPinNotice.paused => 'Your area is paused',
      StoryPinNotice.nearHome => 'This looks near your home area',
      StoryPinNotice.notFound => "Couldn't find this place",
      StoryPinNotice.allowLocation => 'Allow location for Attune to pin places',
      StoryPinNotice.turnOnLocation => 'Turn on location to pin places',
      null =>
        c.resolving
            ? 'Finding this place…'
            : (c.on && place != null
                ? (c.approximate ? '${place.label} · approximate' : place.label)
                : null),
    };
    // "Allow location": the whole pill is the target — it asks again while
    // the system still would, else opens Settings.
    final needsAllow =
        c.notice == StoryPinNotice.allowLocation ||
        c.notice == StoryPinNotice.turnOnLocation;
    void allow() =>
        c.canAsk
            ? c.setOn(true)
            : ref.read(presenceSamplerProvider).openSettings();
    return Semantics(
      container: true,
      button: needsAllow,
      label: sub == null ? 'Pin to our map' : 'Pin to our map. $sub',
      hint:
          needsAllow
              ? (c.canAsk ? 'Asks for location' : 'Opens Settings')
              : null,
      onTap: needsAllow ? allow : null,
      // The camera route has no Scaffold around this overlay; the Switch
      // needs a Material ancestor.
      child: Material(
        type: MaterialType.transparency,
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTap: needsAllow ? allow : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadiusTokens.floatingNavAll,
              ),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: Spacing.md,
                  right: Spacing.xs,
                ),
                // On the narrowest phones the icon gives way first, so the
                // words stay readable.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 220;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!compact) ...[
                          const Icon(
                            Icons.place_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: Spacing.sm),
                        ],
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pin to our map',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: compact ? 13 : 14,
                                ),
                              ),
                              if (sub != null)
                                Text(
                                  sub,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Its own labelled node when the pill itself is a
                        // button, so a screen reader can still flip it.
                        Semantics(
                          container: needsAllow,
                          label: needsAllow ? 'Pin to our map' : null,
                          child: Switch(
                            value: c.on,
                            onChanged: (v) => c.setOn(v),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
