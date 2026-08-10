// lib/core/intro/presentation/widgets/feature_intro_brief_page.dart

import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/animated_circle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// Page 1 of FeatureIntroFlowScreen: icon, title, subtitle from the
/// module plus one feature-specific brief paragraph.
class FeatureIntroBriefPage extends StatelessWidget {
  const FeatureIntroBriefPage({
    super.key,
    required this.module,
    required this.briefParagraph,
  });

  final DocumentationModule module;
  final String briefParagraph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: EdgeInsets.all(Spacing.xl.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Gap(Spacing.xxl.h),
          AnimatedCircle(
            size: 30,
            stroke: 2,
            animateSize: true,
            animateShape: true,
            firstColor: Colors.transparent,
            secondColor: Colors.transparent,
          ),
          Icon(module.icon, size: 80.h, color: colorScheme.primary),
          Gap(Spacing.lg.h),
          Text(
            'Welcome\nTo ${module.getTitle(context)}',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
              fontSize: FontSizeTokens.xxl,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            module.getSubtitle(context),
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.lg.h),
          // Gap(Spacing.xl.h),
          Text(
            briefParagraph,
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
            textAlign: TextAlign.start,
          ),
        ],
      ),
    );
  }
}
