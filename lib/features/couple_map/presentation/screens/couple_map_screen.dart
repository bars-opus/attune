import 'package:attune/features/couple_map/presentation/screens/couple_map_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds the map's body (a seam: tests swap the Mapbox view out).
final coupleMapBodyBuilderProvider =
    Provider<Widget Function(String relationshipId, VoidCallback onBack)>(
      (ref) =>
          (relationshipId, onBack) =>
              CoupleMapTab(relationshipId: relationshipId, onBack: onBack),
    );

/// Opens the couple map full screen over the couple's journal.
Future<void> openCoupleMap(BuildContext context, String relationshipId) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/couple-map'),
        builder: (_) => CoupleMapScreen(relationshipId: relationshipId),
      ),
    );

/// The couple map, full screen (owner, 2026-10-16): no app bar or tabs; the
/// map draws under the status bar and its own Back button returns to the
/// journal. Leaving disposes it, so sampling stops with it (spec §6.1).
class CoupleMapScreen extends ConsumerWidget {
  const CoupleMapScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: ref.watch(coupleMapBodyBuilderProvider)(
      relationshipId,
      () => Navigator.of(context).maybePop(),
    ),
  );
}
