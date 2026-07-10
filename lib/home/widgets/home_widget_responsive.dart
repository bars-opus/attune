// Simple responsive helper
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_packages.dart';
import 'package:attune/home/widgets/home_widget.dart';
import 'package:attune/home/widgets/home_tab.dart';
import 'package:attune/home/widgets/home_widget_factory.dart';

class HomeWidgetResponsive {
  static HomeWidget adaptive({
    required BuildContext context,
    required List<HomeTab> tabs,
    int initialTabIndex = 0,
  }) {
    final isTablet = MediaQuery.of(context).size.width >= Breakpoints.tablet;

    return isTablet
        ? HomeWidgetFactory.tablet(tabs: tabs, initialTabIndex: initialTabIndex)
        : HomeWidgetFactory.mobile(
          tabs: tabs,
          initialTabIndex: initialTabIndex,
        );

    // HomeWidgetFactory.mobile(
    //   tabs: tabs,
    //   initialTabIndex: initialTabIndex,
    // );
  }
}
