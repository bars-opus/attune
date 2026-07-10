import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

class CustomUniversalTabs extends ConsumerStatefulWidget {
  final List<TabItem> tabs;
  final int? selectedIndex;
  final ValueChanged<int>? onIndexChanged;
  final StateProvider<dynamic>? provider;
  final StateProvider<dynamic>? selectedValueProvider;
  final void Function(int index, dynamic value)? onTabSelected;
  final void Function(int index, TabItem tab)? onTabTap;
  final VoidCallback? onRefreshContent;
  final double height;
  final bool showUnderline;
  final Color? selectedColor;
  final Color? unselectedColor;
  final Color? underlineColor;
  final Duration animationDuration;
  final bool animateIconScale;
  final double iconSize;
  final double fontSize;
  final EdgeInsetsGeometry? padding;
  final bool showBottomBorder;
  final Color? backgroundColor;
  final bool showLabels;

  const CustomUniversalTabs({
    super.key,
    required this.tabs,
    this.selectedIndex,
    this.onIndexChanged,
    this.provider,
    this.selectedValueProvider,
    this.onTabSelected,
    this.onTabTap,
    this.onRefreshContent,
    this.height = 80,
    this.showUnderline = true,
    this.selectedColor,
    this.unselectedColor,
    this.underlineColor,
    this.animationDuration = const Duration(milliseconds: 250),
    this.animateIconScale = true,
    this.iconSize = 30,
    this.fontSize = 12,
    this.padding,
    this.showBottomBorder = true,
    this.backgroundColor,
    this.showLabels = true,
  }) : assert(
         (selectedIndex != null && onIndexChanged != null) ||
             provider != null ||
             onTabSelected != null,
         'Either provide (selectedIndex + onIndexChanged), provider, or onTabSelected',
       );

  @override
  ConsumerState<CustomUniversalTabs> createState() =>
      _CustomUniversalTabsState();
}

class _CustomUniversalTabsState extends ConsumerState<CustomUniversalTabs>
    with TickerProviderStateMixin {
  late List<AnimationController> _animationControllers;
  int _internalSelectedIndex = 0;

  // Safe for build: uses ref.watch to register dependency.
  int get _selectedIndex {
    if (widget.provider != null) {
      final selectedValue = ref.watch(widget.provider!);
      final index =
          widget.tabs.indexWhere((tab) => tab.value == selectedValue);
      return index >= 0 ? index : 0;
    }
    if (widget.selectedIndex != null) return widget.selectedIndex!;
    return _internalSelectedIndex;
  }

  // Safe for lifecycle hooks: uses ref.read (no dependency registration).
  int _readCurrentIndex() {
    if (widget.provider != null) {
      final selectedValue = ref.read(widget.provider!);
      final index =
          widget.tabs.indexWhere((tab) => tab.value == selectedValue);
      return index >= 0 ? index : 0;
    }
    if (widget.selectedIndex != null) return widget.selectedIndex!;
    return _internalSelectedIndex;
  }

  @override
  void initState() {
    super.initState();
    _animationControllers = List.generate(
      widget.tabs.length,
      (_) => AnimationController(
        duration: const Duration(milliseconds: 200),
        vsync: this,
      ),
    );
    final initial = widget.selectedIndex ?? _internalSelectedIndex;
    if (initial < _animationControllers.length) {
      _animationControllers[initial].value = 1.0;
    }
  }

  @override
  void didUpdateWidget(CustomUniversalTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIndex = oldWidget.selectedIndex ?? _internalSelectedIndex;
    final newIndex = _readCurrentIndex();

    if (oldIndex != newIndex) {
      if (oldIndex < _animationControllers.length) {
        _animationControllers[oldIndex].reverse();
      }
      if (newIndex < _animationControllers.length) {
        _animationControllers[newIndex].forward();
      }
    }
  }

  void _handleTabSelected(int index) {
    final tab = widget.tabs[index];

    if (index < _animationControllers.length) {
      _animationControllers[index].forward();
    }

    if (widget.selectedIndex != null && widget.onIndexChanged != null) {
      widget.onIndexChanged!(index);
    }

    if (widget.provider != null && tab.value != null) {
      ref.read(widget.provider!.notifier).state = tab.value;
      widget.onRefreshContent?.call();
    }

    if (widget.onTabSelected != null) {
      widget.onTabSelected!(index, tab.value);
    }

    widget.onTabTap?.call(index, tab);

    if (widget.selectedIndex == null && widget.provider == null) {
      setState(() => _internalSelectedIndex = index);
    }
  }

  @override
  void dispose() {
    for (final controller in _animationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final selectedColor = widget.selectedColor ?? colorScheme.primary;
    final unselectedColor = widget.unselectedColor ??
        colorScheme.onSurface.withValues(alpha: 0.6);
    final underlineColor = widget.underlineColor ?? colorScheme.primary;
    final tabWidth = MediaQuery.of(context).size.width / widget.tabs.length;

    return AnimatedBuilder(
      animation: Listenable.merge(_animationControllers),
      builder: (context, _) {
        final currentIndex = _selectedIndex;
        return Container(
          height: widget.height.h,
          padding: widget.padding ?? EdgeInsets.only(top: Spacing.md),
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? Colors.transparent,
            border: widget.showBottomBorder
                ? Border(
                    bottom: BorderSide(
                      color: colorScheme.outline.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(widget.tabs.length, (index) {
              final tab = widget.tabs[index];
              final isSelected = index == currentIndex;
              // Animate scale 0.8→1.0 as controller goes 0→1.
              final scale = widget.animateIconScale
                  ? (0.8 + _animationControllers[index].value * 0.2)
                  : 1.0;

              return GestureDetector(
                onTap: () => _handleTabSelected(index),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: tabWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.scale(
                        scale: isSelected ? scale : 0.9,
                        child: Icon(
                          isSelected
                              ? (tab.selectedIcon ?? tab.icon)
                              : tab.icon,
                          color: isSelected ? selectedColor : unselectedColor,
                          size: widget.iconSize.r,
                        ),
                      ),
                      if (widget.showLabels) ...[
                        Gap(Spacing.xs.h),
                        Text(
                          tab.label,
                          style: textTheme.labelMedium?.copyWith(
                            color:
                                isSelected ? selectedColor : unselectedColor,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: widget.fontSize,
                          ),
                          textScaler: TextScaler.noScaling,
                        ),
                      ],
                      if (widget.showUnderline) ...[
                        Gap(Spacing.sm),
                        AnimatedContainer(
                          duration: widget.animationDuration,
                          curve: Curves.easeInOut,
                          height: 1.5.r,
                          width: isSelected ? 40.w : 0,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? underlineColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(1.r),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class TabItem {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final dynamic value;
  final Widget? content;

  const TabItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.value,
    this.content,
  });
}
