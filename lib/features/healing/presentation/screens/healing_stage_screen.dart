import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/screens/healing_pattern_awareness_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_portrait_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_post_mortem_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_readiness_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_reflection_screen.dart';
import 'package:flutter/material.dart';

class HealingStageScreen extends StatelessWidget {
  const HealingStageScreen({
    super.key,
    required this.journey,
    required this.stage,
  });

  final HealingJourney journey;
  final int stage;

  @override
  Widget build(BuildContext context) {
    switch (stage) {
      case 1:
        return HealingReflectionScreen(journey: journey);
      case 2:
        return HealingPostMortemScreen(journey: journey);
      case 3:
        return HealingPatternAwarenessScreen(journey: journey);
      case 4:
        return HealingPortraitScreen(journey: journey);
      case 5:
      default:
        return HealingReadinessScreen(journey: journey);
    }
  }
}
