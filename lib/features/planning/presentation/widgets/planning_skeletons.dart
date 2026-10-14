import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/core/widgets/schimmer_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// Loading placeholders shaped like Planning's real rows, so the list
/// fills in where it will appear instead of replacing a spinner.

/// A grey bar [widthFactor] of the row's width, centred in a text line
/// [lineHeight] tall, so the skeleton row is as tall as the real one.
Widget _bar(double widthFactor, double barHeight, double lineHeight) =>
    SizedBox(
      width: double.infinity,
      height: lineHeight,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: widthFactor,
          child: SchimmerSkeleton(height: barHeight, raduis: 6),
        ),
      ),
    );

/// Title and subtitle lines, as an InfoRowWidget lays them out.
Widget _lines(double title, double subtitle) => Column(
  children: [
    Gap(Spacing.xs.h),
    _bar(title, 12, 20),
    Gap(Spacing.xs.h),
    _bar(subtitle, 10, 17),
  ],
);

/// Announces the wait once, and hides the grey shapes from screen readers.
Widget _loading(String label, Widget child) =>
    Semantics(label: label, child: ExcludeSemantics(child: child));

/// The Planning home's category cards: a round icon, the name and its count.
class PlanningCategoriesSkeleton extends StatelessWidget {
  const PlanningCategoriesSkeleton({super.key});

  static const _titles = [0.45, 0.3, 0.55, 0.35, 0.4, 0.5];

  @override
  Widget build(BuildContext context) => _loading(
    'Loading categories',
    ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        vertical: Spacing.sm,
        horizontal: Spacing.md,
      ),
      children: [
        for (final title in _titles)
          CardInkWell(
            padding: const EdgeInsets.all(Spacing.sm),
            margin: EdgeInsets.only(bottom: .5.h),
            elevation: ElevationTokens.xs,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: Row(
                children: [
                  // The icon (20.h) in its padded circle.
                  SchimmerSkeleton(
                    width: 20.h + Spacing.sm * 2,
                    height: 20.h + Spacing.sm * 2,
                    shape: BoxShape.circle,
                  ),
                  Gap(Spacing.md.w),
                  Expanded(child: _lines(title, 0.2)),
                  // The "More" menu button's slot.
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SchimmerSkeleton(width: 4, height: 16, raduis: 2),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

/// A category's plans (or notes): date-section titles over cards of rows,
/// each a title and a date line.
class PlanningEntriesSkeleton extends StatelessWidget {
  const PlanningEntriesSkeleton({super.key, this.label = 'Loading plans'});

  /// What screen readers hear, e.g. "Loading notes".
  final String label;

  static const _sections = [
    [0.6, 0.45, 0.7],
    [0.5, 0.65, 0.4, 0.55],
  ];

  @override
  Widget build(BuildContext context) => _loading(
    label,
    ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final rows in _sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              0,
            ),
            child: _bar(0.22, 12, 20),
          ),
          Padding(
            padding: Spacing.allMd,
            child: CardInkWell(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      // The real row draws its divider under the text.
                      child: Column(
                        children: [
                          _lines(rows[i], 0.3),
                          if (i < rows.length - 1) const AppDivider(),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
