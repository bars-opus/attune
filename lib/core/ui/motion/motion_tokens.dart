import 'package:flutter/widgets.dart';

/// Tween fallbacks for widgets that use an implicit/explicit tween rather than a
/// physics simulation. Kept in the 150–320ms band (Spec §2 rule 4).
const Duration kSettleDuration = Duration(milliseconds: 280);
const Curve kSettleCurve = Curves.easeOutBack;

/// Ambient/celebration primitives (Master Spec §17.4: animation durations live
/// in tokens, never as raw literals at call sites).
const Duration kGlowBreathPeriod = Duration(milliseconds: 1600);
const Duration kGlowSettleRamp = Duration(milliseconds: 400);
const Duration kBreathingDotsPeriod = Duration(milliseconds: 1200);
const Duration kShimmerSweepCalm = Duration(milliseconds: 1600);
const Duration kShimmerSweepExpressive = Duration(milliseconds: 1100);

/// Reconnect-cascade stagger step per list position (clamped at call site).
const int kCascadeStepCalmMs = 35;
const int kCascadeStepExpressiveMs = 70;
