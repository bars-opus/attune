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
  
  /// Initialize ScreenUtil with proper configuration
  /// Call this in your main app widget builder
  static Widget builder({
    required WidgetBuilder builder,
    Widget? child,
  }) {
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
