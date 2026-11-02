// lib/core/widgets/home_widget.dart
import 'dart:math' as math;
import 'dart:ui';

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

  /// When this changes, the shell selects [initialTabIndex] again (Spec 1
  /// W3a: a new `/home?tab=` request opens Tab 2 without a rebuild).
  final Object? reselectToken;

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
    this.reselectToken,
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
    // A new shell starts with its nav bar showing: a bar hidden by the
    // previous shell's scroll can't be brought back by a tab that doesn't
    // scroll (navVisibilityProvider is shared).
    _showNavAfterFrame();
  }

  @override
  void didUpdateWidget(covariant HomeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reselectToken != oldWidget.reselectToken) {
      _visitedIndices.add(widget.initialTabIndex);
      _currentIndex = widget.initialTabIndex;
      _showNavAfterFrame();
    }
  }

  /// Providers can't change while the tree builds; after the frame they can.
  void _showNavAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(navVisibilityProvider.notifier).state = true;
    });
  }

  /// The smallest tap target a tab gets (Material, Android and iOS rules).
  static const double _minTapTarget = 48;

  /// A tab item's laid-out width: its icon or its one-line label, whichever
  /// is wider (the Column in [_buildTabItem]; the badge paints outside it).
  double _naturalTabWidth(
    BuildContext context,
    TextTheme textTheme,
    HomeTab tab, {
    required bool isActive,
    required double iconSize,
    required double activeIconSize,
  }) {
    final icon = isActive ? activeIconSize : iconSize;
    if (!widget.showLabels) return icon;
    final isWideScreen =
        MediaQuery.of(context).size.width >= Breakpoints.tablet;
    var style = DefaultTextStyle.of(context).style.merge(
      textTheme.labelSmall?.copyWith(
        fontSize: widget.labelFontSize ?? (isWideScreen ? 8.5 : 9.0),
        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
      ),
    );
    // As Text does: the system bold-text setting makes the label bold.
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final painter = TextPainter(
      text: TextSpan(text: tab.label, style: style),
      textDirection: Directionality.of(context),
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return math.max(icon, width);
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

    // Spec 1 W3a fix round (review I#3): with two tabs, the gap between
    // them and an equal outer margin become each tab's tap area, so every
    // tab is at least 48 dp wide and nothing moves on screen. The gap is
    // split between the two; equal outer margins keep the centred pair
    // exactly where it was, and never grow past the bar's spare width (on
    // the narrowest phones a tab can then stay a little under 48 dp wide).
    final gap = Spacing.xxl.w;
    List<EdgeInsetsGeometry>? hitPaddings;
    if (widget.tabs.length == 2) {
      final widths = [
        for (var i = 0; i < 2; i++)
          _naturalTabWidth(
            context,
            textTheme,
            widget.tabs[i],
            isActive: i == _currentIndex,
            iconSize: iconSize,
            activeIconSize: activeIconSize,
          ),
      ];
      // The Row's width: the screen, less SafeArea's sides, the pill's
      // side padding below and its hairline border.
      final insets = MediaQuery.paddingOf(context);
      final rowWidth =
          MediaQuery.sizeOf(context).width -
          insets.left -
          insets.right -
          2 * (Spacing.xxl.w + Spacing.xxl) -
          2 * BorderWidthTokens.hairline;
      final spare = rowWidth - (widths[0] + gap + widths[1]);
      final outer = math.max(
        0.0,
        math.min(
          (_minTapTarget - math.min(widths[0], widths[1]) - gap / 2)
              .ceilToDouble(),
          (spare / 2 - 1).floorToDouble(),
        ),
      );
      hitPaddings = [
        EdgeInsetsDirectional.only(start: outer, end: gap / 2),
        EdgeInsetsDirectional.only(start: gap / 2, end: outer),
      ];
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.xxl.w + Spacing.xxl,
          Spacing.sm.h,
          Spacing.xxl.w + Spacing.xxl,
          0,
        ),
        child: DecoratedBox(
          // The shadow lives on its own DecoratedBox, OUTSIDE the ClipRRect
          // below — a shadow needs to paint beyond the pill's own edge, but
          // ClipRRect hard-clips everything inside it to exactly the pill's
          // bounds, so a shadow on the inner Container was being clipped
          // away entirely and never actually showing.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100.r),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.12),
                blurRadius: ElevationTokens.lg.r,
                offset: Offset(0, ElevationTokens.xs.h),
              ),
            ],
          ),
          child: ClipRRect(
            // Clipping has to wrap the BackdropFilter (not just live on the
            // Container below): BackdropFilter blurs everything within its
            // nearest clip's bounds, so without this the blur would spill
            // into a rectangle instead of following the pill shape.
            borderRadius: BorderRadius.circular(100.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: navBarHeight,
                decoration: BoxDecoration(
                  color:
                      widget.navigationBarColor ??
                      colorScheme.surface.withOpacity(.5),
                  borderRadius: BorderRadius.circular(100.r),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.1),
                    width: BorderWidthTokens.hairline,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int index = 0; index < widget.tabs.length; index++) ...[
                      if (index > 0 && hitPaddings == null)
                        // Only meaningful with a fixed (non-Expanded) item width —
                        // see the 2-tab branch in _buildTabItem. With 3+ tabs items
                        // still stretch via Expanded, so this gap collapses to
                        // nothing between them (harmless).
                        Gap(gap),
                      _buildTabItem(
                        context,
                        tab: widget.tabs[index],
                        hitPadding: hitPaddings?[index] ?? EdgeInsets.zero,
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
    required EdgeInsetsGeometry hitPadding,
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
        padding: EdgeInsets.symmetric(vertical: 2.h).add(hitPadding),
        constraints: const BoxConstraints(minHeight: _minTapTarget),
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
    // Spec 1 W3a fix round (review I#3): a selectable button to a screen
    // reader; the label is the tab's own text.
    final item = Semantics(
      container: true,
      button: true,
      selected: isActive,
      child: content,
    );
    if (widget.tabs.length == 2) {
      return item;
    }
    return Expanded(child: item);
  }
}
