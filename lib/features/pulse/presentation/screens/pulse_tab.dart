// lib/features/pulse/presentation/screens/pulse_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/chat_settings_static_rows.dart';
import 'package:attune/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pulse_identity_row.dart';
import 'pulse_screen.dart';

/// Hosts Pulse and Chat settings as sibling tabs.
///
/// The couple's identity row (avatar + editable chat name) no longer
/// lives in a shared header above the tabs — it moved into the Settings
/// tab itself (see [PulseIdentityRow], rendered at the top of
/// [_ChatSettingsRowsTab]), and the "Relationship Center" panel that used
/// to sit below it moved into PulseScreen. This keeps each tab
/// self-contained rather than sharing state through a header both tabs
/// scroll underneath.
///
/// Built directly on Flutter's own [NestedScrollView] rather than
/// TabsWithContent's `useNestedScrollMode` (a simplified single-
/// CustomScrollView reimplementation): that mode puts the whole
/// TabBarView inside one SliverFillRemaining, which only scrolls correctly
/// when every tab's own content has no scrollable of its own. PulseScreen
/// and TimelineScreen both already own a full CustomScrollView — under
/// SliverFillRemaining that inner scrollable owns the drag gesture
/// entirely, so the tab bar header never moved with them (the reported
/// bug), and ChatSettingsStaticRows (a plain Column, no scrollable) had
/// nowhere to go but overflow (the reported BOTTOM OVERFLOWED error).
///
/// NestedScrollView is the real fix: it links one outer scroll position to
/// every inner Scrollable inside its `body`, via a
/// SliverOverlapAbsorber/SliverOverlapInjector pair (see PulseScreen's and
/// TimelineScreen's own build methods for the inner half of that pairing).
/// The tab bar is the only header sliver now — neither pinned nor
/// floating, so it scrolls away with the rest exactly as before.
class PulseTab extends ConsumerStatefulWidget {
  const PulseTab({super.key});

  @override
  ConsumerState<PulseTab> createState() => _PulseTabState();
}

class _PulseTabState extends ConsumerState<PulseTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: _tabs.length,
    vsync: this,
  );

  static const _tabs = [
    AppTabItem(label: 'Pulse', icon: Icons.monitor_heart_outlined),
    // AppTabItem(label: 'Timeline', icon: Icons.timeline),
    AppTabItem(label: 'Settings', icon: Icons.settings_outlined),
  ];

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversationAsync = ref.watch(primaryConversationProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: false,
        actions: [
          AppIconButton(
            icon: Icons.notes_rounded,
            tooltip: 'Docs',
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // Wraps the tab bar (the only header element now) rather
              // than standing alone with no sliver: a bare, childless
              // SliverOverlapAbsorber never actually runs a layout pass,
              // so it never reports an extent — every inner
              // CustomScrollView's matching SliverOverlapInjector then
              // hits "found no absorbed extent to inject" on the very
              // first frame. Matches Flutter's own NestedScrollView
              // example, which wraps its SliverAppBar the same way.
              // Redirects the header's layout extent into the matching
              // SliverOverlapInjector each tab's own CustomScrollView
              // carries as its first sliver — without this pair, an inner
              // scrollable can end up rendering as if it starts under the
              // header even though its own scroll offset reads as zero.
              SliverOverlapAbsorber(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // scrollable: false — matches ReflectionJournalScreen's
                      // own TabsWithContent(scrollable: false) call, which is
                      // what makes SimpleTabs use TabAlignment.fill (each tab
                      // takes an equal, centered share of the bar) instead of
                      // the scrollable default's left-aligned, content-sized
                      // tabs.
                      SimpleTabs(
                        tabs: _tabs,
                        controller: _tabController,
                        scrollable: false,
                      ),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              const PulseScreen(),
              // const TimelineScreen(),
              _ChatSettingsRowsTab(conversationAsync: conversationAsync),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Settings tab: the couple's identity row at the top (moved here from
/// the old shared ChatIdentityCard header — its photo strip was removed
/// entirely; "Media, docs and links" below already covers shared photos),
/// then the static rows (Search, Media, Starred, Export/Import, Previous
/// relationships).
///
/// Takes the already-resolved [conversationAsync] from PulseTab rather than
/// re-reading primaryConversationProvider itself.
///
/// Wrapped in its own CustomScrollView (with the SliverOverlapInjector
/// NestedScrollView requires of every inner scrollable) since
/// ChatSettingsStaticRows is a plain Column with no scroll of its own.
class _ChatSettingsRowsTab extends StatelessWidget {
  const _ChatSettingsRowsTab({required this.conversationAsync});

  final AsyncValue<Conversation?> conversationAsync;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.h),
            child: conversationAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data:
                  (conversation) =>
                      conversation == null
                          ? const SizedBox.shrink()
                          : Padding(
                            padding: EdgeInsets.only(
                              top: Spacing.lg.h,
                              bottom: Spacing.xs.h,
                            ),
                            child: PulseIdentityRow(conversation: conversation),
                          ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          // No horizontal padding here — matches the original
          // TabsWithContent-based layout, where ChatSettingsStaticRows
          // rendered directly with no padding wrapper of its own.
          child: conversationAsync.when(
            loading: () => const ChatSettingsStaticRows(conversation: null),
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
              return ChatSettingsStaticRows(conversation: conversation);
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}
