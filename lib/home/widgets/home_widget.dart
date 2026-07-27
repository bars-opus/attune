// lib/core/widgets/home_widget.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_packages.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:attune/home/widgets/home_tab.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Simple, scalable home widget with bottom navigation
/// Supports 2-5 tabs with minimal, clean implementation
class HomeWidget extends ConsumerStatefulWidget {
  final List<HomeTab> tabs;
  final int initialTabIndex;
  final Color? backgroundColor;
  final Color? navigationBarColor;
  final double? navigationBarHeight;
  final double? iconSize;
  final double? activeIconSize;
  final double? labelFontSize;
  final double? badgeFontSize;
  final bool showLabels;
  final double? centeredFabMarginBottom;

  const HomeWidget({
    super.key,
    required this.tabs,
    this.initialTabIndex = 0,
    this.backgroundColor,
    this.navigationBarColor,
    this.navigationBarHeight,
    this.iconSize,
    this.activeIconSize,
    this.labelFontSize,
    this.badgeFontSize,
    this.showLabels = true,
    this.centeredFabMarginBottom,
  }) : assert(
         tabs.length >= 2 && tabs.length <= 5,
         'HomeWidget supports 2-5 tabs',
       ),
       assert(
         initialTabIndex >= 0 && initialTabIndex < tabs.length,
         'Invalid initial tab index',
       );

  @override
  ConsumerState<HomeWidget> createState() => _HomeWidgetState();
}

class _HomeWidgetState extends ConsumerState<HomeWidget> {
  late int _currentIndex;
  late final Set<int> _visitedIndices;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _visitedIndices = {widget.initialTabIndex};
  }

  Widget _buildBottomNavigationBarWithCustomFab(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= Breakpoints.tablet;

    // Responsive sizing
    final navBarHeight =
        widget.navigationBarHeight ?? (isWideScreen ? 64.h : 50.h);
    final iconSize = widget.iconSize ?? (isWideScreen ? 26.h : 22.h);
    final activeIconSize =
        widget.activeIconSize ?? (isWideScreen ? 28.h : 24.h);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.xxl.w + Spacing.xxl,
          Spacing.sm.h,
          Spacing.xxl.w + Spacing.xxl,
          0,
        ),
        child: Container(
          height:navBarHeight,

          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color:
                widget.navigationBarColor ??
                colorScheme.surface.withOpacity(.5),
            borderRadius: BorderRadius.circular(100.r),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.1),
              width: BorderWidthTokens.hairline,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: ElevationTokens.lg.r,
                offset: Offset(0, ElevationTokens.xs.h),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int index = 0; index < widget.tabs.length; index++) ...[
                if (index > 0)
                  // Only meaningful with a fixed (non-Expanded) item width —
                  // see the 2-tab branch in _buildTabItem. With 3+ tabs items
                  // still stretch via Expanded, so this gap collapses to
                  // nothing between them (harmless).
                  Gap(Spacing.xxl.w),
                _buildTabItem(
                  context,
                  tab: widget.tabs[index],
                  isActive: index == _currentIndex,
                  iconSize: iconSize,
                  activeIconSize: activeIconSize,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                  onTap: () {
                    setState(() {
                      _visitedIndices.add(index);
                      _currentIndex = index;
                    });
                    // Tabs stay mounted (Offstage, not real navigation) so a
                    // scroll-hidden nav from the PREVIOUS tab would otherwise
                    // stay hidden after switching, since navVisibilityProvider
                    // is shared across every tab's scroll listener.
                    ref.read(navVisibilityProvider.notifier).state = true;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Any scrollable tab content (Discover, Following, Forums...) can hide
    // this nav bar on scroll-down and restore it on scroll-up, even though
    // this widget sits several levels above those screens — see
    // nav_visibility_provider.dart for why a shared flag rather than local
    // state.
    final navVisible = ref.watch(navVisibilityProvider);
    return Scaffold(
      extendBody: true,
      backgroundColor: widget.backgroundColor ?? colorScheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ...List.generate(widget.tabs.length, (index) {
            if (!_visitedIndices.contains(index))
              return const SizedBox.shrink();
            return Offstage(
              offstage: index != _currentIndex,
              child: widget.tabs[index].screen,
            );
          }),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              // Hidden nav must not eat taps meant for content underneath it.
              ignoring: !navVisible,
              child: AnimatedSlide(
                duration: AnimationDurations.fast,
                curve: Curves.easeOut,
                offset: navVisible ? Offset.zero : const Offset(0, 1),
                child: AnimatedOpacity(
                  duration: AnimationDurations.fast,
                  opacity: navVisible ? 1 : 0,
                  child: _buildBottomNavigationBarWithCustomFab(
                    context,
                    colorScheme,
                    textTheme,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(
    BuildContext context, {
    required HomeTab tab,
    required bool isActive,
    required double iconSize,
    required double activeIconSize,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= Breakpoints.tablet;
    final iconColor =
        isActive
            ? (tab.activeIconColor ?? colorScheme.primary)
            : (tab.iconColor ??
                colorScheme.onSurface.withValues(alpha: OpacityTokens.medium));

    final labelColor =
        isActive
            ? (tab.activeLabelColor ?? colorScheme.primary)
            : (tab.labelColor ??
                colorScheme.onSurface.withValues(alpha: OpacityTokens.medium));
    final labelFontSize = widget.labelFontSize ?? (isWideScreen ? 8.5 : 9.0);
    final badgeFontSize = widget.badgeFontSize ?? 9.0;

    final content = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 2.h),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with optional unread badge
            Badge(
              isLabelVisible: tab.badgeCount > 0,
              label: Text(
                tab.badgeCount > 99 ? '99+' : tab.badgeCount.toString(),
                style: TextStyle(fontSize: badgeFontSize),
                textScaler: TextScaler.noScaling,
              ),
              child: Icon(
                isActive ? (tab.activeIcon ?? tab.icon) : tab.icon,
                size: isActive ? activeIconSize : iconSize,
                color: iconColor,
              ),
            ),

            // Label
            if (widget.showLabels) ...[
              Gap(2.h),
              Text(
                tab.label,
                style: textTheme.labelSmall?.copyWith(
                  color: labelColor,
                  fontSize: labelFontSize,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
                textScaler: TextScaler.noScaling,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );

    // With exactly 2 tabs, size each item to its own content and let the
    // parent Row's mainAxisAlignment.center + the Gap between them do the
    // centering/spacing — Expanded would stretch both items to fill the
    // whole bar width, leaving no room for the Row to center anything.
    // 3+ tabs keep the normal Expanded fill-the-bar behavior.
    if (widget.tabs.length == 2) {
      return content;
    }
    return Expanded(child: content);
  }
}
