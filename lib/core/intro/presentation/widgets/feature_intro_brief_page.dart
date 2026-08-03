// lib/core/intro/presentation/widgets/feature_intro_brief_page.dart

import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/theme/design_tokens.dart';
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
          Container(
            width: 72.w,
            height: 72.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.primary.withOpacity(0.4)),
            ),
            child: Icon(module.icon, size: 32.h, color: colorScheme.primary),
          ),
          Gap(Spacing.lg.h),
          Text(
            module.getSubtitle(context),
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.xl.h),
          Text(
            briefParagraph,
            style: textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
