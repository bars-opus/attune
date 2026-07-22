// lib/features/forums/presentation/screens/forums_tab.dart

import 'package:attune/features/forums/presentation/screens/contributing_forums_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'forums_explore_screen.dart';

class ForumsTab extends ConsumerStatefulWidget {
  const ForumsTab({super.key});

  @override
  ConsumerState<ForumsTab> createState() => _ForumsTabState();
}

class _ForumsTabState extends ConsumerState<ForumsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Contributing/Explore are both kept alive as sibling sub-tabs
    // (TabBarView), so a scroll-hidden nav from one side would otherwise
    // persist after switching — see the matching reset in
    // home_widget.dart's onTap.
    _tabController.addListener(_resetNavVisibilityOnSwitch);
  }

  void _resetNavVisibilityOnSwitch() {
    if (_tabController.indexIsChanging) {
      ref.read(navVisibilityProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_resetNavVisibilityOnSwitch);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forums'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Contributing'),
            Tab(text: 'Explore'),
          ],
          indicatorColor: colorScheme.primary,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ContributingForumsScreen(),
          ForumsExploreScreen(),
        ],
      ),
    );
  }
}
