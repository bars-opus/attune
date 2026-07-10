import 'package:attune/core/utils/exports/export_screens.dart';

class SimpleProviderTabs<T> extends StatelessWidget {
  final List<SimpleProviderTabItem<T>> tabs;
  final T selectedValue;
  final void Function(T) onValueSelected;
  final double height;
  final double iconSize;
  final double fontSize;

  const SimpleProviderTabs({
    super.key,
    required this.tabs,
    required this.selectedValue,
    required this.onValueSelected,
    this.height = 80,
    this.iconSize = 25,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: height.h,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children:
            tabs.map((tab) {
              final isSelected = tab.value == selectedValue;
              final color =
                  isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.6);

              return Expanded(
                child: GestureDetector(
                  onTap: () => onValueSelected(tab.value),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected ? tab.selectedIcon : tab.icon,
                                color: color,
                                size: iconSize.r,
                              ),
                              Gap(Spacing.xs.h),
                              Text(
                                tab.label,
                                style: textTheme.labelMedium?.copyWith(
                                  color: color,
                                  fontWeight:
                                      isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                  fontSize: fontSize,
                                ),
                                textScaler: TextScaler.noScaling,
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        height: 2.r,
                        width: isSelected ? 40.w : 0,
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? colorScheme.primary
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(1.r),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class SimpleProviderTabItem<T> {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final T value;

  const SimpleProviderTabItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.value,
  });
}
