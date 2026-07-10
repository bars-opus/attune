import 'package:flutter/material.dart';

// =============================================================================
// DESIGN TOKENS - Single source of truth for design values
// =============================================================================

// Spacing tokens (8px base unit - Material Design standard)
class Spacing {
  static const double xs = 4.0; // Extra small
  static const double sm = 8.0; // Small
  static const double smMd =
      12.0; // Between sm and md — icon-label gaps, compact card padding
  static const double md = 16.0; // Medium (base unit)
  static const double lg = 24.0; // Large
  static const double xl = 32.0; // Extra large
  static const double xxl = 48.0; // Extra extra large

  // Edge insets (pre-defined for consistency)
  static const EdgeInsets allXs = EdgeInsets.all(xs);
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);

  static const EdgeInsets horizontalSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets horizontalLG = EdgeInsets.symmetric(horizontal: xl);
  static const EdgeInsets verticalLg = EdgeInsets.symmetric(vertical: xl);

  static const EdgeInsets pagePadding = EdgeInsets.all(lg);
}

// Border radius tokens (Material Design 3 standard)
class BorderRadiusTokens {
  static const double none = 0;
  static const double xs = 4.0; // Extra small
  static const double sm = 8.0; // Small
  static const double md = 12.0; // Medium
  static const double lg = 16.0; // Large
  static const double floatingNav = 30.0; // Floating navigation containers
  static const double xl = 28.0; // Extra large
  static const double full = 9999.0; // Full circle/pill

  // Pre-defined BorderRadius objects
  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius floatingNavAll = BorderRadius.all(
    Radius.circular(floatingNav),
  );
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

// Elevation tokens (Material Design - dp units)
class ElevationTokens {
  static const double none = 0; // No shadow
  static const double xs = 1.0; // Subtle separation
  static const double sm = 3.0; // Cards, dialogs
  static const double md = 6.0; // Navigation drawer
  static const double lg = 8.0; // App bar
  static const double xl = 12.0; // Modal bottom sheet
}

// Animation durations (Material Design timing)
class AnimationDurations {
  static const Duration instant = Duration(
    milliseconds: 50,
  ); // Instant feedback
  static const Duration fastest = Duration(milliseconds: 100); // Very fast
  static const Duration fast = Duration(milliseconds: 200); // Fast
  static const Duration medium = Duration(milliseconds: 300); // Standard
  static const Duration slow = Duration(milliseconds: 500); // Slow/emphasized
  static const Duration slowest = Duration(milliseconds: 700); // Very slow

  // Specific use cases
  static const Duration buttonPress = fastest;
  static const Duration pageTransition = medium;
  static const Duration dialogAnimation = slow;
}

// Animation curves (Material Design 3 easing curves)
class AnimationCurves {
  // Standard easing - most UI elements
  static const Curve standard = Curves.easeInOut;

  // Emphasized easing - for important transitions
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  // Decelerating - elements appearing on screen
  static const Curve decelerate = Curves.decelerate;

  // Accelerating - elements disappearing
  static const Curve accelerate = Curves.fastLinearToSlowEaseIn;

  // Linear - progress indicators, loading
  static const Curve linear = Curves.linear;

  // Playful effects (use sparingly)
  static const Curve bounce = Curves.bounceOut;
  static const Curve elastic = Curves.elasticOut;

  // Specific use cases
  static const Curve buttonPress = Curves.easeOut;
  static const Curve pageTransition = emphasized;
  static const Curve fadeIn = decelerate;
  static const Curve fadeOut = accelerate;
}

// Icon sizes (Material Design standard)
class IconSizes {
  static const double xs = 12.0; // Extra small
  static const double sm = 16.0; // Small
  static const double md = 24.0; // Medium (standard)
  static const double lg = 32.0; // Large
  static const double xl = 48.0; // Extra large
  static const double xxl = 64.0; // Hero icons
}

// Responsive breakpoints (Material Design guidelines)
class Breakpoints {
  // Mobile-first breakpoints
  static const double mobile = 600; // Phones (0-599px)
  static const double tablet = 905; // Tablets (600-904px)
  static const double desktop = 1240; // Desktop (905-1239px)
  static const double large = 1440; // Large screens (1240px+)

  // Alternative (simpler) breakpoints
  static const double small = 480; // Small phones
  static const double medium = 768; // Tablets/landscape phones
  static const double largeAlt = 1024; // Small laptops
  static const double xlarge = 1440; // Desktop monitors
}

// Opacity tokens (for consistent transparency)
class OpacityTokens {
  static const double disabled = 0.38; // Disabled elements
  static const double medium = 0.60; // Secondary text/icons
  static const double high = 0.87; // Primary text
  static const double full = 1.0; // Fully opaque
}

class FontSizeTokens {
  static const double xxs = 10;
  static const double xs = 12;
  static const double sm = 14;
  static const double md = 17; // matches bodyLarge in AppTextTheme
  static const double lg = 18;
  static const double xl = 24;
  static const double xxl = 32;
}

class TextHeightTokens {
  static const double compact = 1.35;
  static const double relaxed = 1.5;
}

// Border width tokens
class BorderWidthTokens {
  static const double none = 0;
  static const double hairline = 0.3; // Very thin
  static const double thin = 1.0; // Standard thin
  static const double thick = 2.0;

  static var md; // Thick border
}

// Tab specific tokens
class TabTokens {
  static const double defaultHeight = 48.0;
  static const double defaultPadding = 16.0;
  static const double defaultIndicatorHeight = 3.0;
  static const double defaultBorderRadius = BorderRadiusTokens.md;
  static const Duration switchDuration = AnimationDurations.fast;
  static const Curve switchCurve = AnimationCurves.standard;
}

class FormTokens {
  static const double defaultFieldHeight = 70.0;
  static const double compactFieldHeight = 45.0;
  static const double defaultFieldRadius = 10.0;
  static const double defaultFieldBorderWidth = 0.5;
  static const double focusedFieldBorderWidth = 2.0;
  static const double fieldBorderOpacity = 0.3;
  static const double disabledFieldBorderOpacity = 0.1;
  static const double darkFieldFillOpacity = 0.5;
}

class OnboardingTokens {
  static const double actionButtonHeight = 40.0;
}

// Responsive layout utilities — consumes Breakpoints to produce adaptive values
class AppResponsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < Breakpoints.mobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= Breakpoints.mobile && w < Breakpoints.desktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= Breakpoints.desktop;

  /// Returns [mobile], [tablet], or [desktop] value based on current screen width.
  /// Falls back up the chain: desktop → tablet → mobile.
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }

  /// Horizontal page padding that grows with screen size.
  static EdgeInsets pagePadding(BuildContext context) => value(
    context,
    mobile: const EdgeInsets.symmetric(horizontal: Spacing.lg),
    tablet: const EdgeInsets.symmetric(horizontal: 40),
    desktop: const EdgeInsets.symmetric(horizontal: 80),
  );

  /// Column count for grids — sensible defaults, fully overridable.
  static int columns(
    BuildContext context, {
    int mobile = 1,
    int tablet = 2,
    int desktop = 3,
  }) => value(context, mobile: mobile, tablet: tablet, desktop: desktop);
}
