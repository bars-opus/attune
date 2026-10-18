import 'package:attune/features/ai_assistant/data/repositories/assistant_error.dart';
import 'package:attune/features/safety/presentation/outside_perspective_screen.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Research 05 Scenario 12 item 5, verbatim (plan review C3).
const kBoundaryLine =
    "A no is complete on its own. If you want to understand more, ask them "
    "when you're both calm.";

/// The Safety resources screen's own opening line, which already ships:
/// what the supporter and writer cards say until their own words are
/// signed off (final review I-6).
const kShippedSafetyLine =
    'If something does not feel safe, these contacts and planning resources '
    'may be useful.';

/// The fixed cards of the deterministic pre-check (Spec 8, F15 (2)): shown
/// to the requester only, carrying nothing about what matched.
class AssistantNoticeCard extends ConsumerWidget {
  const AssistantNoticeCard({super.key, required this.notice});

  final AssistantNotice notice;

  void _push(BuildContext context, Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    // The same flag gates every piece of Spec 8's draft safety content.
    final drafts = ref.watch(outsidePerspectiveEnabledProvider);
    final fallback = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kShippedSafetyLine, style: text.bodyLarge),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => _push(context, const SafetyResourcesScreen()),
          child: const Text('See support options'),
        ),
      ],
    );
    return switch (notice) {
      AssistantNotice.boundary => Text(kBoundaryLine, style: text.bodyLarge),
      AssistantNotice.supporter when !drafts => fallback,
      AssistantNotice.supporter => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Crisis line first (research 05 Scenario 5).
          Text(
            '[DRAFT] If they might be in danger right now, call your local '
            'emergency number or stay with them and get help.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _push(context, const OutsidePerspectiveScreen()),
            child: const Text('When your partner is struggling'),
          ),
        ],
      ),
      AssistantNotice.writerResources when !drafts => fallback,
      AssistantNotice.writerResources => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "[DRAFT] It sounds like you're going through something hard. "
            "You don't have to handle it alone.",
            style: text.bodyLarge,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _push(context, const SafetyResourcesScreen()),
            child: const Text('See support options'),
          ),
        ],
      ),
    };
  }
}
