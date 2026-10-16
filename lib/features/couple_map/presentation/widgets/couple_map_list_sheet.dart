import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/open_story_places.dart';
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The accessible alternative to the map (spec §3.5), also shown in the
/// map's place when it can't load. Stories join it in Phase 2.
class CoupleMapListContent extends StatelessWidget {
  const CoupleMapListContent({
    super.key,
    required this.presence,
    required this.partnerName,
    required this.notice,
    required this.now,
    this.onNoticeTap,
    this.places = const [],
    this.onPlaceTap,
  });
  final CoupleMapPresence presence;
  final String partnerName;
  final CoupleMapNotice? notice;
  final DateTime now;
  final VoidCallback? onNoticeTap;

  /// Pinned stories (Phase 2), shown after the presence rows, newest day
  /// first. Each row opens its story.
  final List<StoryPlace> places;
  final ValueChanged<StoryPlace>? onPlaceTap;

  @override
  Widget build(BuildContext context) {
    final self = presence.self;
    final partner = presence.partner;
    final offset = partner?.utcOffsetMinutes;
    final partnerLine = [
      if (partner?.city case final c?) c,
      if (offset != null)
        '${formatClock(now.toUtc().add(Duration(minutes: offset)))} there',
    ].join(' · ');
    final n = notice;
    final presenceCard = CardInkWell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (self != null)
            InfoRowWidget(
              // M3's secondary-text colour: meets WCAG AA at 12 sp.
              subTitleFontColor: Theme.of(context).colorScheme.onSurfaceVariant,
              title: 'You',
              subtitle: self.city ?? 'Your area is shared',
              icon: Icons.person_pin_circle_outlined,
              showAvatar: false,
              showDivider: partner != null || n != null,
            ),
          if (partner != null)
            InfoRowWidget(
              // M3's secondary-text colour: meets WCAG AA at 12 sp.
              subTitleFontColor: Theme.of(context).colorScheme.onSurfaceVariant,
              title: partnerName,
              subtitle: partnerLine.isEmpty ? 'On the map' : partnerLine,
              icon: Icons.favorite_border,
              showAvatar: false,
              showDivider: n != null,
            ),
          if (n != null)
            MergeSemantics(
              child: InfoRowWidget(
                // M3's secondary-text colour: meets WCAG AA at 12 sp.
                subTitleFontColor:
                    Theme.of(context).colorScheme.onSurfaceVariant,
                title: noticeText(n),
                subtitle: '',
                icon: Icons.near_me_outlined,
                showAvatar: false,
                showDivider: false,
                titleMaxLines: 3,
                showTrailingArrow: onNoticeTap != null,
                onTap: onNoticeTap,
              ),
            ),
        ],
      ),
    );
    if (places.isEmpty) return presenceCard;
    final byDay = [...places]
      ..sort((a, b) => b.story.occurredOn.compareTo(a.story.occurredOn));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        presenceCard,
        CardInkWell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < byDay.length; i++)
                MergeSemantics(
                  child: InfoRowWidget(
                    // M3's secondary-text colour: meets WCAG AA at 12 sp.
                    subTitleFontColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                    title: byDay[i].label,
                    // A day, never a time: the list is memories, not a log.
                    subtitle: MyDateFormat.toDate(byDay[i].story.occurredOn),
                    icon: Icons.photo_outlined,
                    showAvatar: false,
                    showTrailingArrow: true,
                    showDivider: i < byDay.length - 1,
                    titleMaxLines: 1,
                    onTap:
                        onPlaceTap == null ? null : () => onPlaceTap!(byDay[i]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> showCoupleMapListSheet(
  BuildContext context, {
  required String relationshipId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  // Neutral, like the app's pages: never M3's primary-tinted sheet surface.
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  builder: (_) => _CoupleMapListSheet(relationshipId: relationshipId),
);

class _CoupleMapListSheet extends ConsumerWidget {
  const _CoupleMapListSheet({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence =
        ref.watch(coupleMapPresenceProvider(relationshipId)).valueOrNull ??
        CoupleMapPresence.none;
    final access =
        ref.watch(locationAccessProvider).valueOrNull ?? LocationAccess.granted;
    final people =
        ref.watch(coupleMapPeopleProvider(relationshipId)).valueOrNull;
    final places =
        ref
            .watch(storyPlacesProvider(StoryPlacesKey(relationshipId)))
            .valueOrNull ??
        const <StoryPlace>[];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomSheetHeader(title: 'On our map'),
          Flexible(
            child: SingleChildScrollView(
              child: CoupleMapListContent(
                presence: presence,
                partnerName: people?.partnerName ?? 'your partner',
                notice: coupleMapNotice(presence, access),
                now: DateTime.now(),
                places: places,
                onPlaceTap:
                    (p) => openStoryPlaces(
                      context,
                      relationshipId: relationshipId,
                      places: places,
                      storyIds: [p.storyItemId],
                    ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
