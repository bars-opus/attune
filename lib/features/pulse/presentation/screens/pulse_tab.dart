// lib/features/pulse/presentation/screens/pulse_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/presentation/screens/chat_settings_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart';
import 'package:attune/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pulse_screen.dart';

/// Hosts Pulse, Timeline, and Chat settings as sibling tabs using the app's
/// shared AppTabItem/TabsWithContent — mirrors CouplesCalendarScreen's tab
/// setup rather than the ad hoc pill switcher this file used before.
class PulseTab extends ConsumerWidget {
  const PulseTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Chat Insight',
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ),
      body: TabsWithContent(
        showContent: true,
        initialIndex: 0,
        scrollable: false,
        tabs: [
          const AppTabItem(
            label: 'Pulse',
            icon: Icons.monitor_heart_outlined,
            content: PulseScreen(),
          ),
          const AppTabItem(
            label: 'Timeline',
            icon: Icons.timeline,
            content: TimelineScreen(),
          ),
          AppTabItem(
            label: 'Chat settings',
            icon: Icons.settings_outlined,
            content: Consumer(builder: (context, ref, _) => _ChatSettingsTab()),
          ),
        ],
      ),
    );
  }
}

/// Resolves the active relationship's Conversation before handing off to
/// ChatSettingsScreen, which needs the full entity (name, avatar,
/// relationshipId) — not just the bare relationship id this tab starts with.
/// Mirrors ChatChannelLoader's relationshipId -> Conversation resolve.
class _ChatSettingsTab extends ConsumerWidget {
  const _ChatSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relationshipIdAsync = ref.watch(currentRelationshipIdProvider);

    return relationshipIdAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (_, _) => const Center(
            child: Text('Chat settings are unavailable right now.'),
          ),
      data: (relationshipId) {
        if (relationshipId == null) {
          return const Center(
            child: Text('Chat settings are unavailable right now.'),
          );
        }

        return FutureBuilder(
          future: ref
              .read(chatRepositoryProvider)
              .getConversation(relationshipId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final conversation = snapshot.data;
            if (conversation == null) {
              return const Center(
                child: Text('Chat settings are unavailable right now.'),
              );
            }

            return ChatSettingsScreen(conversation: conversation);
          },
        );
      },
    );
  }
}
