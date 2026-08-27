// lib/features/chat/presentation/screens/chat_settings_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/widgets/chat_identity_card.dart';
import 'package:attune/features/chat/presentation/widgets/chat_settings_static_rows.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lets either partner set/edit a name and photo for their relationship's
/// chat — e.g. "Perla" + "Javics" -> "Japerl34". See
/// docs/superpowers/specs/2026-08-11-couple-chat-identity-design.md.
///
/// Reached via the settings icon inside the Pulse tab (Chat's AppBar title
/// opens Pulse instead). Not gated to "the person who set it" — either
/// partner may edit at any time the relationship is active, per the spec's
/// explicit "no per-partner override" decision.
///
/// The identity card (avatar/name) itself lives in [ChatIdentityCard] —
/// PulseTab surfaces that same widget directly under its AppBar, above the
/// Settings/Pulse/Timeline tabs, so this screen composes it rather than
/// owning that state inline. This screen is currently reached only as a
/// standalone fallback (route `chatSettings` — nothing pushes it directly
/// today; PulseTab embeds this screen inline for the Settings tab instead),
/// so it keeps the full identity + rows layout for that path.
///
/// Also hosts two other chat-content entry points, moved here from the
/// general Settings screen because they're genuinely chat-scoped (not
/// account/app-wide actions like endRelationship, which stays in Settings'
/// danger section — ending a relationship is a whole-app lifecycle action
/// with chat going read-only as only one of its side effects):
/// - Previous relationships: read-only past-conversation threads, kept off
///   the main Chat tab so an ex's thread is never confused with the active
///   one (CHAT_SYSTEM_SPEC.md §11.1).
/// - Historical chat import (CHAT_SYSTEM_SPEC.md §11.4: "opens 'Import chat
///   history' from chat settings"), shown only when
///   chatHistoricalImportEnabledProvider is true (currently seeded false —
///   Month 5 gate, §11.3 — so this row is invisible until that flag flips).
class ChatSettingsScreen extends ConsumerWidget {
  const ChatSettingsScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md.h),
          children: [
            ChatIdentityCard(conversation: conversation),
            ChatSettingsStaticRows(conversation: conversation),
            Gap(Spacing.xl.h),
          ],
        ),
      ),
    );
  }
}
