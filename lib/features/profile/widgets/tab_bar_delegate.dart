
import 'package:attune/core/utils/exports/export_screens.dart';

class TabBarDelegate extends SliverPersistentHeaderDelegate {
  final List<AppTabItem> tabs;
  final TabController tabController;

  TabBarDelegate({required this.tabs, required this.tabController});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceDim,
      child: SimpleTabs(
        tabs: tabs,
        controller: tabController,
        scrollable: false,
      ),
    );
  }

  @override
  double get maxExtent => 50.h; // Height of your tab bar

  @override
  double get minExtent => 50.h; // Same height when collapsed

  @override
  bool shouldRebuild(covariant TabBarDelegate oldDelegate) {
    return oldDelegate.tabs != tabs ||
        oldDelegate.tabController != tabController;
  }
}
