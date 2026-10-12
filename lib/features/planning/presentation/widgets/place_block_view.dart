import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/location_provider.dart';
import 'package:attune/core/utils/location/location_search_mode.dart';
import 'package:attune/core/utils/location/map_launcher_helper.dart';
import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planning_models.dart';
import '../../domain/code_point_limit.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

class PlaceBlockView extends ConsumerWidget {
  const PlaceBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final place = block.place;
    if (place == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.place_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: Spacing.sm),
        Expanded(child: Text(place.name, style: theme.textTheme.titleMedium)),
        IconButton(
          tooltip: 'Change place',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            final picked = await showPlanningPlacePicker(context, initial: place.name);
            if (picked == null || !context.mounted) return;
            try {
              await ref.read(planningEntryProvider(args).notifier).updateBlockPayload(block, picked.toJson());
            } catch (e) {
              if (context.mounted) showPlanningError(context, e);
            }
          },
        ),
      ]),
      if (place.address != null && place.address!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: Spacing.lg + Spacing.xs),
          child: Text(place.address!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.map_outlined),
          label: const Text('Open in Maps'),
          onPressed: () => MapLauncherHelper.openMapLocation(
              lat: place.lat, lng: place.lng, address: place.address ?? place.name, label: place.name),
        ),
      ),
    ]);
  }
}

/// Search for a place with the app's location search; if it can't be
/// reached, the typed name is kept without coordinates (spec §6.12).
Future<PlanningPlace?> showPlanningPlacePicker(BuildContext context, {String initial = ''}) =>
    showModalBottomSheet<PlanningPlace>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlacePicker(initial: initial),
    );

class _PlacePicker extends ConsumerStatefulWidget {
  const _PlacePicker({required this.initial});
  final String initial;

  @override
  ConsumerState<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends ConsumerState<_PlacePicker> {
  late final _query = TextEditingController(text: widget.initial);
  Timer? _debounce;
  List<ParsedAddress> _results = const [];
  bool _searchFailed = false;
  bool _resolving = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q.trim()));
    setState(() {});
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() => _results = const []);
      return;
    }
    try {
      final r = await ref
          .read(locationServiceProvider)
          .getLocationSuggestions(q, mode: LocationSearchMode.address)
          .timeout(const Duration(seconds: 5));
      if (mounted && _query.text.trim() == q) {
        setState(() {
          _results = r;
          _searchFailed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _results = const [];
          _searchFailed = true;
        });
      }
    }
  }

  Future<void> _pick(ParsedAddress a) async {
    setState(() => _resolving = true);
    var resolved = a;
    if (a.latitude == null && a.placeId != null) {
      try {
        resolved = await ref.read(locationServiceProvider).getPlaceDetails(a.placeId!).timeout(const Duration(seconds: 5)) ?? a;
      } catch (_) {
        resolved = a; // keep the name and address without coordinates
      }
    }
    if (!mounted) return;
    final name = a.fullAddress.split(',').first.trim();
    Navigator.pop(
      context,
      PlanningPlace(
        name: truncateCodePoints(name.isEmpty ? a.fullAddress : name, 120),
        address: truncateCodePoints(resolved.fullAddress, 300),
        lat: resolved.latitude,
        lng: resolved.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typed = _query.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, MediaQuery.viewInsetsOf(context).bottom + Spacing.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _query,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Search for a place', prefixIcon: Icon(Icons.search_rounded)),
          inputFormatters: [CodePointLengthFormatter(120)],
          onChanged: _onChanged,
        ),
        if (_resolving) const LinearProgressIndicator(),
        if (_searchFailed)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text("Search isn't available right now. You can still save the name.",
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
          child: ListView(shrinkWrap: true, children: [
            for (final a in _results)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(a.fullAddress.split(',').first),
                subtitle: Text(a.fullAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: _resolving ? null : () => _pick(a),
              ),
            if (typed.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: Text('Use "$typed"'),
                subtitle: const Text('Without a map pin'),
                onTap: () => Navigator.pop(context, PlanningPlace(name: typed)),
              ),
          ]),
        ),
      ]),
    );
  }
}
