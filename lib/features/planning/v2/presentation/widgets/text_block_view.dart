import 'package:flutter/material.dart';

import '../../data/planning_v2_models.dart';
import '../planning_v2_providers.dart';

class TextBlockView extends StatelessWidget {
  const TextBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  @override
  Widget build(BuildContext context) {
    final t = block.plainText ?? '';
    return Text(t.isEmpty ? 'Tap to write' : t);
  }
}
