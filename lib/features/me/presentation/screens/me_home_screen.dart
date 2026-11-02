import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/me/presentation/widgets/dating_slot.dart';
import 'package:attune/features/me/presentation/widgets/first_action_card.dart';
import 'package:attune/features/me/presentation/widgets/journal_reminder_row.dart';
import 'package:attune/features/me/presentation/widgets/more_ways_sheet.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_lifecycle_card.dart';
import 'package:flutter/material.dart';

/// The Me home (Spec 1 §3.10): Tab 2 on Dating and Just for me. "Your
/// space": the lifecycle card while an ending's window is open (§3.12), the
/// Dating slot on the Dating path (from the live answer only, D20), J1,
/// Journal, Quizzes, Healing, and J4.
class MeHomeScreen extends StatelessWidget {
  const MeHomeScreen({super.key, required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    return AllowLargeText(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              const SpaceHeader(),
              const SizedBox(height: Spacing.md),
              if (home.link == LinkState.endedWindow)
                const RelationshipLifecycleCard(),
              if (home.path == AppPath.dating) DatingSlot(home: home),
              const FirstActionCard(),
              YourSpaceSection(
                extraRows: [
                  // W3c: J3, then J4.
                  const JournalReminderRow(),
                  MoreWaysRow(home: home),
                ],
              ),
              const SizedBox(height: Spacing.xxl * 2),
            ],
          ),
        ),
      ),
    );
  }
}
