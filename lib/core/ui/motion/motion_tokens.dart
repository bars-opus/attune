import 'package:flutter/widgets.dart';

/// Tween fallbacks for widgets that use an implicit/explicit tween rather than a
/// physics simulation. Kept in the 150–320ms band (Spec §2 rule 4).
const Duration kSettleDuration = Duration(milliseconds: 280);
const Curve kSettleCurve = Curves.easeOutBack;

/// A new list item opening room for itself. Slightly longer than a plain
/// settle: the eye is tracking everything above it moving, not just the
/// item itself. easeOutCubic rather than easeOutBack — an overshoot here
/// would bounce the whole list above it, not just the arriving bubble.
const Duration kMakeRoomDuration = Duration(milliseconds: 320);
const Curve kMakeRoomCurve = Curves.easeOutCubic;

/// A list item moving to its new place when the list is re-sorted, filtered
/// or put back. Emphasized decelerate: it sets off promptly and glides into
/// place, so the eye can follow each item to where it landed.
const Duration kReorderDuration = Duration(milliseconds: 320);
const Curve kReorderCurve = Cubic(0.05, 0.7, 0.1, 1.0);

/// A payload travelling from its source control to the surface that receives
/// it (for example composer -> message bubble or reaction menu -> bubble).
/// Long enough for the eye to follow the path, but still below the point at
/// which sending starts to feel delayed.
const Duration kPayloadFlightDuration = Duration(milliseconds: 440);

/// The brief impact after a reaction payload reaches its bubble: one compact
/// expand-compress-settle beat with a fading ripple, not a second full motion.
const Duration kReactionLandingDuration = Duration(milliseconds: 360);

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

/// How long after a message arrives its one-time arrival animation may still
/// play. A row first built later than this (the reader was scrolled up, in a
/// game, or backgrounded) is simply there — iMessage never replays an arrival
/// minutes late under your finger.
const Duration kArrivalAnimationWindow = Duration(milliseconds: 1500);
