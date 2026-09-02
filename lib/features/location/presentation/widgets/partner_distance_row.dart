import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How far apart the couple is, on the conversation screen.
///
/// Sits beside the next calendar event deliberately: this is ambient
/// relationship context, the same kind of thing as "dinner on Friday" --
/// not a panel you open to check on someone.
///
/// Renders NOTHING when there is no honest answer. Either partner not
/// sharing, a stale position, or a failed read all produce an absent row
/// rather than a placeholder. A row that says "location unavailable" is a
/// row that invites the question "why", which is the pressure this whole
/// design exists to avoid.
class PartnerDistanceRow extends ConsumerWidget {
  const PartnerDistanceRow({
    super.key,
    required this.relationshipId,
    this.partnerName,
  });

  final String relationshipId;
  final String? partnerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final distance =
        ref.watch(partnerDistanceProvider(relationshipId)).valueOrNull;

    if (distance == null) return const SizedBox.shrink();

    final copy = distanceCopy(distance, partnerName: partnerName);

    return InfoRowWidget(
      title: copy.headline,
      subtitle: copy.detail ?? 'Together',
      iconColor: colorScheme.onSurfaceVariant.withOpacity(.4),
      icon: _iconFor(distance),
      subTitleMaxLines: 1,
      titleMaxLines: 1,
      showDivider: false,
      showAvatar: false,
      disableTrailing: true,
      showTrailingArrow: false,
    );
  }

  IconData _iconFor(PartnerDistance distance) {
    // The icon carries the same meaning as the words, so a glance is
    // enough: a plane when they are a flight away, a heart when they are
    // effectively together.
    return switch (distance.tone) {
      DistanceTone.together => Icons.favorite_rounded,
      DistanceTone.nearby => Icons.directions_walk_rounded,
      DistanceTone.sameCountry => Icons.directions_car_rounded,
      DistanceTone.countdown => Icons.event_rounded,
      DistanceTone.closing => Icons.flight_takeoff_rounded,
      DistanceTone.distant => Icons.public_rounded,
    };
  }
}
