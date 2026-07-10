import 'package:attune/core/utils/exports/export_screens.dart';

class HorizontalCategoryTabs extends StatefulWidget {
  final List<String> categories;
  final String? selectedCategory;
  final Function(String?) onCategorySelected;
  final Map<String, bool>? hasShopsMap;
  final bool isLoading;
  final String Function(String)? categoryFormatter;
  final double? tabWidth;
  final double? containerHeight;
  final bool showBottomBorder;
  final Color? selectedIndicatorColor;
  final Color? selectedTextColor;
  final Color? unselectedTextColor;
  final Color? disabledTextColor;
  final bool noTopIndicatorPadding;

  const HorizontalCategoryTabs({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    this.hasShopsMap,
    this.isLoading = false,
    this.categoryFormatter,
    this.tabWidth,
    this.containerHeight,
    this.showBottomBorder = true,
    this.selectedIndicatorColor,
    this.selectedTextColor,
    this.unselectedTextColor,
    this.disabledTextColor,
    this.noTopIndicatorPadding = false,
  });

  @override
  State<HorizontalCategoryTabs> createState() => _HorizontalCategoryTabsState();
}

class _HorizontalCategoryTabsState extends State<HorizontalCategoryTabs> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context)!;

    final effectiveContainerHeight = widget.containerHeight ?? 44.h;
    final effectiveTabWidth = widget.tabWidth ?? 90.w;

    return Container(
      height: effectiveContainerHeight,
      decoration: BoxDecoration(
        border:
            widget.showBottomBorder
                ? Border(
                  bottom: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.1),
                    width: 1,
                  ),
                )
                : null,
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: Spacing.sm),
        itemCount: widget.categories.length,
        itemBuilder: (context, index) {
          final category = widget.categories[index];

          final isSelected =
              !widget.isLoading &&
              ((category == 'all' && widget.selectedCategory == null) ||
                  (category != 'all' && category == widget.selectedCategory));

          final hasShops =
              widget.isLoading ? true : (widget.hasShopsMap?[category] ?? true);
          final displayName =
              widget.categoryFormatter != null
                  ? widget.categoryFormatter!(category)
                  : _defaultFormatCategoryName(category, loc);

          final double indicatorWidth =
              (isSelected && hasShops) ? effectiveTabWidth * 0.6 : 0.0;

          return GestureDetector(
            onTap:
                (!widget.isLoading && hasShops)
                    ? () => widget.onCategorySelected(
                      category == 'all' ? null : category,
                    )
                    : null,
            child: Container(
              width:
                  category == 'all'
                      ? effectiveTabWidth - 30.w
                      : effectiveTabWidth,
              margin: EdgeInsets.only(right: Spacing.sm.w),
              color: Colors.transparent,
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Text(
                        displayName,
                        style: textTheme.labelLarge?.copyWith(
                          color:
                              widget.isLoading
                                  ? (widget.disabledTextColor ??
                                      colorScheme.onSurface.withValues(
                                        alpha: 0.3,
                                      ))
                                  : isSelected
                                  ? (widget.selectedTextColor ??
                                      colorScheme.primary)
                                  : (widget.unselectedTextColor ??
                                      colorScheme.onSurface.withValues(
                                        alpha: hasShops ? 0.8 : 0.3,
                                      )),
                          fontWeight:
                              (!widget.isLoading && isSelected && hasShops)
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    height: 2.r,
                    width: indicatorWidth,
                    decoration: BoxDecoration(
                      color:
                          (isSelected && hasShops)
                              ? (widget.selectedIndicatorColor ??
                                  colorScheme.primary)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(1.r),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _defaultFormatCategoryName(String category, AppLocalizations loc) {
    if (category == 'all') return loc.categoriesAll;
    switch (category) {
      case 'salon':
        return loc.categoriesSalon;
      case 'barbershop':
        return loc.categoriesBarbershop;
      case 'spa':
        return loc.categoriesSpa;
      case 'nail_salon':
        return loc.categoriesNailSalon;
      case 'lash_studio':
        return loc.categoriesLashStudio;
      case 'waxing':
        return loc.categoriesWaxing;
      case 'massage':
        return loc.categoriesMassage;
      case 'makeup':
        return loc.categoriesMakeup;
      case 'skincare':
        return loc.categoriesSkincare;
      default:
        return category
            .split('_')
            .map((word) => word[0].toUpperCase() + word.substring(1))
            .join(' ');
    }
  }
}
