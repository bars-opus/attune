// lib/features/pulse/presentation/screens/pulse_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/presentation/screens/chat_settings_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/chat_settings_identity_skeleton.dart';
import 'package:attune/features/chat/presentation/widgets/chat_settings_static_rows.dart';
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
            label: 'Settings',
            icon: Icons.settings_outlined,
            content: _ChatSettingsTab(),
          ),
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
        ],
      ),
    );
  }
}

/// Resolves the active relationship's Conversation via
/// primaryConversationProvider — the SAME cached, app-wide provider
/// ChatScreen and ConversationsScreen are already backed by (see
/// chat_state.dart), rather than this tab's own relationshipId lookup +
/// getConversation() re-fetch it used to do. Since Chat is almost always
/// opened before Pulse in normal use, conversationsProvider has typically
/// already resolved and cached this exact Conversation object by the time
/// this tab mounts — reading it here is then a synchronous cache hit, not
/// a second network round trip, which is what was making the avatar/name
/// visibly reload every time this tab opened.
///
/// ConsumerStatefulWidget (not ConsumerWidget) so it can hold
/// AutomaticKeepAliveClientMixin — a plain ConsumerWidget has no State to
/// attach the mixin to.
class _ChatSettingsTab extends ConsumerStatefulWidget {
  const _ChatSettingsTab();

  @override
  ConsumerState<_ChatSettingsTab> createState() => _ChatSettingsTabState();
}

class _ChatSettingsTabState extends ConsumerState<_ChatSettingsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// Real page shell shown while Conversation is still resolving — the
  /// identity card (avatar/name) is the only content on this whole screen
  /// that actually depends on Conversation, so only IT is a loading
  /// skeleton. Every row below (Search, Media, Starred, Export/Import,
  /// Previous relationships) is fully static and renders for real
  /// immediately via ChatSettingsStaticRows, just with taps disabled until
  /// conversation is non-null. Replaces the old "spin the whole page" state.
  Widget _loadingShell() {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.all(Spacing.md.h),
        children: const [
          ChatSettingsIdentitySkeleton(),
          ChatSettingsStaticRows(conversation: null),
          SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin requirement
    final conversationAsync = ref.watch(primaryConversationProvider);

    return conversationAsync.when(
      loading: _loadingShell,
      error:
          (_, _) => const Center(
            child: Text('Chat settings are unavailable right now.'),
          ),
      data: (conversation) {
        if (conversation == null) {
          return const Center(
            child: Text('Chat settings are unavailable right now.'),
          );
        }
        return ChatSettingsScreen(conversation: conversation);
      },
    );
  }
}
