import 'package:attune/core/utils/exports/export_screens.dart';

/// Complete Tabs with Content Switcher
/// Complete Tabs with Content Switcher - Now with NestedScrollView option

class TabsWithContent extends StatefulWidget {
  final List<AppTabItem> tabs;
  final int initialIndex;
  final ValueChanged<int>? onTabChanged;
  final AppTabsStyle style;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final bool scrollable;
  final double contentSpacing;
  final bool showContent;
  final bool useNestedScrollMode;
  // final VoidCallback? onDonePressed;
  final Color? scaffoldBackgroundColor;
  final bool showCloseIcon;
  // Defaults to Navigator.pop(context) below when null. Callers presented
  // both as a route push and inside a modal sheet (e.g. LoginScreen) need
  // this to differ by context — a plain pop is only safe when something is
  // actually underneath to reveal.
  final VoidCallback? onClosePressed;
  final String? appBartext;
  final String? headertext;

  /// Extra content placed above the tab bar, inside the same scrolling
  /// sequence as everything else — only meaningful with
  /// [useNestedScrollMode]. Renders as its own sliver ABOVE the existing
  /// headertext/showCloseIcon/appBartext row (which stays independent so
  /// existing callers of those are unaffected), so a caller can add e.g. a
  /// title plus a custom content card that scrolls away together with the
  /// tab bar and content beneath it, without needing a second, separately
  /// coordinated scroll view of their own.
  final Widget? header;

  final double? tabHeight;
  final VoidCallback? appBarOnPressed;
  final void Function(TabController)? onControllerCreated;
  final bool Function(int fromIndex, int toIndex)? onTabChangeRequest;

  final bool enableSwipe;

  const TabsWithContent({
    super.key,
    required this.tabs,
    this.initialIndex = 0,
    this.onTabChanged,
    this.style = const AppTabsStyle(),
    this.padding,
    this.backgroundColor,
    this.scrollable = true,
    this.showCloseIcon = false,
    this.onClosePressed,
    this.contentSpacing = Spacing.lg,
    this.showContent = true,
    this.useNestedScrollMode = false,
    // this.onDonePressed,
    this.scaffoldBackgroundColor,
    this.appBartext,
    this.appBarOnPressed,
    this.enableSwipe = true,
    this.onControllerCreated,
    this.onTabChangeRequest,
    this.tabHeight,
    this.headertext,
    this.header,
  });

  @override
  State<TabsWithContent> createState() => _TabsWithContentState();
}

class _TabsWithContentState extends State<TabsWithContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late int _currentIndex;

  void _onTabControllerChanged() {
    if (!_tabController.indexIsChanging &&
        _tabController.index != _currentIndex &&
        mounted) {
      setState(() => _currentIndex = _tabController.index);
      widget.onTabChanged?.call(_tabController.index);
    }
  }

  // Swipe is disabled automatically when onTabChangeRequest is provided,
  // because swiping would bypass the validation gate.
  bool get _swipeEnabled =>
      widget.enableSwipe && widget.onTabChangeRequest == null;

  ScrollPhysics? get _tabViewPhysics =>
      _swipeEnabled ? null : const NeverScrollableScrollPhysics();

  bool Function(int)? get _onTabTap =>
      widget.onTabChangeRequest != null
          ? (index) {
            final fromIndex = _currentIndex;
            if (fromIndex == index) return true;
            final allow = widget.onTabChangeRequest!(fromIndex, index);
            if (allow) _tabController.animateTo(index);
            return allow;
          }
          : null;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _tabController = TabController(
      length: widget.tabs.length,
      vsync: this,
      initialIndex: _currentIndex,
    );
    _tabController.addListener(_onTabControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onControllerCreated?.call(_tabController);
    });
  }

  @override
  void didUpdateWidget(TabsWithContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length) {
      _tabController.removeListener(_onTabControllerChanged);
      _tabController.dispose();
      _tabController = TabController(
        length: widget.tabs.length,
        vsync: this,
        initialIndex: _currentIndex.clamp(0, widget.tabs.length - 1),
      );
      _tabController.addListener(_onTabControllerChanged);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabControllerChanged);
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildSwipeableContent() {
    if (!widget.showContent) return const SizedBox.shrink();

    return Expanded(
      child: TabBarView(
        controller: _tabController,
        physics: _tabViewPhysics,
        children:
            widget.tabs.map((tab) => tab.content ?? const SizedBox()).toList(),
      ),
    );
  }

  Widget _buildTabBar() {
    return SimpleTabs(
      tabHeight: widget.tabHeight,
      tabs: widget.tabs,
      controller: _tabController,
      style: widget.style,
      padding: widget.padding,
      backgroundColor: widget.backgroundColor,
      scrollable: widget.scrollable,
      onTabTap: _onTabTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (!widget.useNestedScrollMode) {
      return Column(
        children: [
          _buildTabBar(),
          if (widget.showContent) ...[
            SizedBox(height: widget.contentSpacing.h),
            _buildSwipeableContent(),
          ],
        ],
      );
    }

    // Whether the close-icon/headertext/appBartext row has anything to
    // show — a caller using only `header` (no headertext/showCloseIcon/
    // appBartext) has nothing for this row to render, so skip it rather
    // than lay out an empty Row every scroll frame.
    final hasLegacyHeaderRow =
        widget.showCloseIcon ||
        widget.headertext != null ||
        widget.appBartext != null ||
        widget.appBarOnPressed != null;

    // NestedScrollView mode — no Scaffold wrapper needed; bounds come from parent.
    return CustomScrollView(
      slivers: [
        if (widget.header != null) SliverToBoxAdapter(child: widget.header),
        if (hasLegacyHeaderRow)
          SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment:
                  widget.showCloseIcon || widget.headertext != null
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.end,
              children: [
                if (widget.headertext != null)
                  Text(
                    widget.headertext!,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                if (widget.showCloseIcon)
                  AppIconButton(
                    icon: Icons.close,
                    onPressed:
                        widget.onClosePressed ?? () => Navigator.pop(context),
                  ),
                if (widget.appBartext != null || widget.appBarOnPressed != null)
                  AppTextButton(
                    text: widget.appBartext ?? 'Done',
                    onPressed: widget.appBarOnPressed,
                  ),
              ],
            ),
          ),

        // Tab bar in its own sliver so SimpleTabs is measured with a
        // min-size Column — avoiding the infinite-height assertion that
        // occurs when a Flex(mainAxisSize: max) is a non-flexible child
        // of another Column with unbounded height.
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Gap(20.h),
              SimpleTabs(
                tabHeight: widget.tabHeight,
                tabs: widget.tabs,
                controller: _tabController,
                style: widget.style,
                padding: widget.padding,
                backgroundColor: widget.backgroundColor,
                scrollable: widget.scrollable,
                onTabTap: _onTabTap,
              ),
              if (widget.showContent) SizedBox(height: widget.contentSpacing.h),
            ],
          ),
        ),

        // Tab content fills whatever remains — no Expanded wrapper needed
        // because SliverFillRemaining provides the height constraint directly.
        if (widget.showContent)
          SliverFillRemaining(
            hasScrollBody: true,
            child: TabBarView(
              controller: _tabController,
              physics: _tabViewPhysics,
              children:
                  widget.tabs
                      .map((tab) => tab.content ?? const SizedBox())
                      .toList(),
            ),
          ),
      ],
    );
  }
}
