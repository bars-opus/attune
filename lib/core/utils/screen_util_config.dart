import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// ScreenUtil configuration for consistent responsive design
/// 
/// Design based on iPhone 13 (375 x 812) - Standard mobile design size
/// 
/// Usage:
/// 1. Wrap your MaterialApp with ScreenUtilInit (see app.dart)
/// 2. Use .w for width, .h for height, .sp for font size, .r for radius
/// 3. Use Gap widget for spacing between widgets
class ScreenUtilConfig {
  /// Design size based on iPhone 13 (standard mobile design)
  static const Size designSize = Size(375, 812);
  
  /// Minimum text adaptation - ensures text scales properly
  static const bool minTextAdapt = true;
  
  /// Support split screen mode (tablets, foldables)
  static const bool splitScreenMode = true;
  
  /// Orientation changes handling
  static const bool useInheritedMediaQuery = true;

  /// Keep typography stable across tablets instead of scaling font sizes by
  /// viewport width. Flutter's MediaQuery text scaler still handles user
  /// accessibility text-size preferences.
  static double resolveFontSize(num fontSize, ScreenUtil instance) {
    return fontSize.toDouble();
  }
  
  /// The most .w/.h/.r may scale the phone design. Phones (up to about
  /// 469 x 1015) are under it, so they look exactly as designed; on an iPad
  /// spacing and icons grow a little instead of 2.75x, while text keeps its
  /// size either way.
  static const double maxScale = 1.25;

  /// The design size for [screen]: [designSize], or larger on a big screen
  /// so the scale stops at [maxScale]. The height follows ScreenUtil's own
  /// split-screen rule (at least 700).
  static Size designSizeFor(Size screen) {
    final height = screen.height < 700 ? 700.0 : screen.height;
    return Size(
      math.max(designSize.width, screen.width / maxScale),
      math.max(designSize.height, height / maxScale),
    );
  }

  /// Initialize ScreenUtil with proper configuration
  /// Call this in your main app widget builder
  static Widget builder({
    required WidgetBuilder builder,
    Widget? child,
  }) {
    // Re-read on rotation and window resizes (iPad split view).
    return Builder(
      builder:
          (context) =>
              _init(designSizeFor(MediaQuery.sizeOf(context)), builder, child),
    );
  }

  static Widget _init(Size designSize, WidgetBuilder builder, Widget? child) {
    return ScreenUtilInit(
      designSize: designSize,
      minTextAdapt: minTextAdapt,
      splitScreenMode: splitScreenMode,
      useInheritedMediaQuery: useInheritedMediaQuery,
      fontSizeResolver: resolveFontSize,
      builder: (context, widget) {
        return builder(context);
      },
      child: child,
    );
  }
}

/// Quick reference for responsive units
/// 
/// Examples:
/// - 100.w = 100 design pixels scaled to current device width
/// - 50.h = 50 design pixels scaled to current device height  
/// - 16.sp = 16 logical font pixels; Flutter text scaling handles accessibility
/// - 12.r = 12 design pixels scaled for border radius
/// 
