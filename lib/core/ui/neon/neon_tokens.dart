import 'package:flutter/painting.dart';

/// Every number the neon language is made of.
///
/// Master Spec §17.4: animation durations and visual constants live in
/// tokens, never as literals at call sites. In a language where light is
/// the only material (spec §2.1) that extends past durations to alphas,
/// blur radii and geometry ratios -- those ARE the art, and scattering
/// them through painters is how a coherent surface drifts into ten
/// slightly different ones.
class NeonTokens {
  const NeonTokens._();

  // ---- Tier 1: the ground. Receives light, emits none. ----

  /// Not pure black: a hair of blue keeps saturated glow from vibrating
  /// against it, the same reasoning as GameHubTheme.surface.
  static const groundColor = Color(0xFF07070A);

  /// How far the ground's light well reaches, as a fraction of the
  /// field's shorter side. Gives the field a middle rather than being a
  /// flat void.
  static const lightWellRadiusRatio = 0.72;

  /// The well's strength at the centre. Barely there on purpose.
  static const lightWellAlpha = 0.055;

  // ---- Tier 2: structure. Present, not shouting. ----

  /// A bay or divider at rest.
  static const structureAlphaRest = 0.25;

  /// A bay that is selected, aimed at, or holding the active player.
  static const structureAlphaActive = 0.55;

  // ---- Tier 3: actors. The only bright things on the field. ----

  static const actorAlpha = 0.95;

  // ---- Glow construction ----

  /// A luminous outline is one crisp core stroke plus two blurred
  /// passes. Two rather than one because a single wide blur reads as
  /// fog; an inner tight pass plus an outer wide one reads as emission.
  static const coreStrokeWidth = 1.6;
  static const haloBlurInner = 4.0;
  static const haloBlurOuter = 14.0;
  static const haloSpreadInner = 2.0;
  static const haloSpreadOuter = 7.0;

  /// Halo alpha as a fraction of the stroke's own alpha.
  static const haloAlphaInner = 0.45;
  static const haloAlphaOuter = 0.18;

  // ---- Bay geometry, as ratios of the bay's own box ----

  static const bayCornerRatio = 0.18;
  static const bayInsetRatio = 0.08;

  // ---- Event motion durations (Master Spec §17.4 band: 150-320ms) ----

  /// The white instant of impact. Short: it is a flash, not a state.
  static const impactFlashDuration = Duration(milliseconds: 160);

  /// The coloured bloom fading out behind the flash.
  static const bloomFadeDuration = Duration(milliseconds: 300);

  /// Droplets coming to rest after a burst.
  static const burstSettleDuration = Duration(milliseconds: 280);

  // ---- Replay beat thresholds, on the battle screen's single 0->1 ----
  //
  // The first four are carried over unchanged from the implementation
  // they replace. They were tuned on a device, and the reason is
  // documented there: emerging and aiming are given room to read before
  // anything is fired, because the point of the replay is seeing the two
  // decisions meet. A shot that left before the aim landed would skip
  // the part worth watching.

  static const beatEmerge = 0.12;
  static const beatAim = 0.34;
  static const beatFire = 0.52;
  static const beatFlightEnd = 0.86;

  /// Impact occupies the tail the previous implementation left unused;
  /// settle runs from here to 1.0.
  static const beatImpactEnd = 0.94;
}
