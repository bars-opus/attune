import 'dart:async';
import 'package:gap/gap.dart';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/planning_models.dart';
import '../planning_providers.dart';

/// Both partners' local times. Stores nothing: the partner's city and zone
/// come from location presence, which only shares them when the partner
/// has chosen to (spec §6.13).
class DualClockBlockView extends ConsumerStatefulWidget {
  const DualClockBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  @override
  ConsumerState<DualClockBlockView> createState() => _DualClockBlockViewState();
}

class _DualClockBlockViewState extends ConsumerState<DualClockBlockView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Widget _clock(BuildContext context, String who, DateTime time, {String? where}) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(DateFormat.jm().format(time), style: theme.textTheme.headlineSmall),
        Text(who, style: theme.textTheme.labelLarge),
        if (where != null) Text(where, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final partner = ref.watch(partnerDistanceProvider(widget.args.relationshipId)).valueOrNull;
    final tz = partner?.partnerTimezone;
    final offset = tz == null ? null : ref.watch(planningTimezoneOffsetProvider(tz)).valueOrNull;
    // Wall-clock time in the partner's zone, built from UTC + their offset.
    final theirs = offset == null ? null : now.toUtc().add(Duration(minutes: offset));
    final local = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.block.title ?? 'Dual clock', style: theme.textTheme.titleMedium),
      const Gap(Spacing.sm),
      if (theirs == null)
        Text("Your partner's time shows here when they share their location.",
            style: TextStyle(color: theme.colorScheme.outline))
      else
        Row(children: [
          _clock(context, 'You', local),
          _clock(context, partner?.partnerCity ?? 'Them', DateTime(theirs.year, theirs.month, theirs.day, theirs.hour, theirs.minute),
              where: partner?.partnerCity == null ? null : 'Them'),
        ]),
    ]);
  }
}
