import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/schimmer_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// Placeholder rows shaped like the settings rows (icon, title, subtitle),
/// so the sheet keeps its layout while a section loads instead of jumping
/// from a spinner to rows of another height.
class TogetherSettingsSkeleton extends StatelessWidget {
  const TogetherSettingsSkeleton({super.key, required this.rows});

  /// How many rows the section will show once loaded.
  final int rows;

  static const _titles = [0.55, 0.7, 0.45];
  static const _subtitles = [0.8, 0.6, 0.7];

  /// A grey bar [factor] of the line's width, centred in a line [line] tall.
  Widget _bar(double factor, double bar, double line) => SizedBox(
    width: double.infinity,
    height: line,
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: factor,
        child: SchimmerSkeleton(height: bar, raduis: 6),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading settings',
    child: ExcludeSemantics(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w, vertical: Spacing.sm),
              child: Row(
                children: [
                  SchimmerSkeleton(width: 36.r, height: 36.r, shape: BoxShape.circle),
                  Gap(Spacing.md.w),
                  Expanded(
                    child: Column(
                      children: [
                        _bar(_titles[i % _titles.length], 12, 20),
                        Gap(Spacing.xs.h),
                        _bar(_subtitles[i % _subtitles.length], 10, 17),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
