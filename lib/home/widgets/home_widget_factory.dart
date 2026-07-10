// lib/core/widgets/home_widget_factory.dart
import 'package:attune/core/utils/exports/export_packages.dart';
import 'package:attune/home/widgets/home_widget.dart';
import 'package:attune/home/widgets/home_tab.dart';

class HomeWidgetFactory {
  // Standard mobile home
  static HomeWidget mobile({
    required List<HomeTab> tabs,
    int initialTabIndex = 0,
  }) {
    return HomeWidget(
      tabs: tabs,
      initialTabIndex: initialTabIndex,
      navigationBarHeight: 72,
      iconSize: 20,
      activeIconSize: 22,
      labelFontSize: 9,
      badgeFontSize: 9,
      showLabels: true,
    );
  }

  // Tablet/desktop home (larger)
  static HomeWidget tablet({
    required List<HomeTab> tabs,
    int initialTabIndex = 0,
    Widget? floatingActionButton,
  }) {
    return HomeWidget(
      tabs: tabs,
      initialTabIndex: initialTabIndex,
      navigationBarHeight: 76,
      iconSize: 22,
      activeIconSize: 24,
      labelFontSize: 7,
      badgeFontSize: 8,
      showLabels: true,
    );
  }

  // Minimal (icons only)
  static HomeWidget minimal({
    required List<HomeTab> tabs,
    int initialTabIndex = 0,
    Widget? floatingActionButton,
  }) {
    return HomeWidget(
      tabs: tabs,
      initialTabIndex: initialTabIndex,
      navigationBarHeight: 30.h,
      iconSize: 24.h,
      activeIconSize: 26.h,
      labelFontSize: 8,
      badgeFontSize: 8,
      showLabels: false,
    );
  }
}
