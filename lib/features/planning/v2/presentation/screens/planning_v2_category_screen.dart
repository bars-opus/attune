import 'package:flutter/material.dart';

import '../../data/planning_v2_models.dart';

class PlanningV2CategoryScreen extends StatelessWidget {
  const PlanningV2CategoryScreen({super.key, required this.relationshipId, required this.category});
  final String relationshipId;
  final PlanningCategory category;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(category.name)));
}
