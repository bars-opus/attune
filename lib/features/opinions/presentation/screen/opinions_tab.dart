// lib/features/opinions/presentation/screens/opinions_tab.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/forums/presentation/screens/forum_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_tab.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/discover_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/following_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

class OpinionsTab extends ConsumerStatefulWidget {
  const OpinionsTab({super.key});

  @override
  ConsumerState<OpinionsTab> createState() => _OpinionsTabState();
}

class _OpinionsTabState extends ConsumerState<OpinionsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAuthenticated = ref.watch(currentUserIdProvider) != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opinions'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Opinions'), Tab(text: 'Forums')],
          indicatorColor: colorScheme.primary,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          OpinionsFeedTab(),
          isAuthenticated ? const ForumsTab() : const ForumScreen(),
        ],
      ),
    );
  }
}

// Opinions Feed Tab (combines Following + Discover)
class OpinionsFeedTab extends ConsumerStatefulWidget {
  const OpinionsFeedTab({super.key});

  @override
  ConsumerState<OpinionsFeedTab> createState() => _OpinionsFeedTabState();
}

class _OpinionsFeedTabState extends ConsumerState<OpinionsFeedTab>
    with SingleTickerProviderStateMixin {
  late TabController _feedTabController;

  @override
  void initState() {
    super.initState();
    _feedTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _feedTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
            ),
          ),
          child: TabBar(
            controller: _feedTabController,
            tabs: const [Tab(text: 'Following'), Tab(text: 'Discover')],
            indicatorColor: colorScheme.primary,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _feedTabController,
            children: const [FollowingFeedScreen(), DiscoverFeedScreen()],
          ),
        ),
      ],
    );
  }
}
