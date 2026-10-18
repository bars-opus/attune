import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:flutter/material.dart';

import '../../domain/planning_money.dart';

/// The budget gauge's timing and curve, so a rolling headline arrives with it.
const _duration = Duration(milliseconds: 700);
const _curve = Cubic(0.05, 0.7, 0.1, 1.0);

/// A headline amount in Planning (a total, what's left, what's spent): it
/// rolls up from 0 when its block first shows and from the old figure when
/// it changes, then settles as plain text ([prefix] and [suffix] included).
/// Line items use plain text instead.
class PlanningRollingMoney extends StatelessWidget {
  const PlanningRollingMoney({
    super.key,
    required this.minor,
    required this.currency,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.textAlign = TextAlign.start,
  });

  final int minor;
  final String currency;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => AnimatedRollingCounter(
    count: minor,
    format: (m) => formatPlanningMoney(m, currency),
    prefix: prefix,
    suffix: suffix,
    style: style,
    textAlign: textAlign,
    fromZero: true,
    settleAsText: true,
    duration: _duration,
    curve: _curve,
  );
}

/// A headline count (steps done, a counted target), rolling like
/// [PlanningRollingMoney].
class PlanningRollingCount extends StatelessWidget {
  const PlanningRollingCount({
    super.key,
    required this.count,
    this.style,
    this.suffix = '',
  });

  final int count;
  final TextStyle? style;
  final String suffix;

  @override
  Widget build(BuildContext context) => AnimatedRollingCounter(
    count: count,
    suffix: suffix,
    style: style,
    fromZero: true,
    settleAsText: true,
    duration: _duration,
    curve: _curve,
  );
}
