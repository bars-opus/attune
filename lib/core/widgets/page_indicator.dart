import 'package:attune/core/utils/exports/export_screens.dart';

class PageIndicator extends StatelessWidget {
  final PageController controller;
  final int itemCount;
  final Color activeColor;
  final Color inactiveColor;

  const PageIndicator({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 1) return SizedBox.shrink();

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // All safety checks in one place
        if (!controller.hasClients ||
            controller.positions.isEmpty ||
            itemCount == 0) {
          return SizedBox.shrink();
        }

        final page = controller.page;
        final currentPage = (page != null) ? page.round() : 0;
        final safeCurrentPage = currentPage.clamp(0, itemCount - 1);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(itemCount, (index) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.xs.w),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 200),
                width: safeCurrentPage == index ? 12.w : 8.w,
                height: safeCurrentPage == index ? 12.w : 8.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      safeCurrentPage == index
                          ? activeColor
                          : inactiveColor.withOpacity(0.3),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
