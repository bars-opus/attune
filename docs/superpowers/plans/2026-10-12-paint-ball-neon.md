# Paint Ball Neon Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Attune's Paint Ball field in a neon-dark visual language on a new shared `lib/core/ui/neon/` toolkit, so the Arcade reaches GamePigeon's craft level without GamePigeon's art pipeline.

**Architecture:** A thin toolkit of light primitives (`glow_stroke`, `lit_mark`, `bloom_flash`, `paint_burst`, `light_well`) gated by a device-quality tier, consumed first by Paint Ball's field — which splits from one 958-line file into seven focused parts — and then by Sliding Scale to prove reuse. No engine, no migrations, no server changes; the only animation driver remains the single `0→1` value the battle screen already owns.

**Tech Stack:** Flutter 3.29.1 stable, Dart, `CustomPainter`, `flutter_screenutil`, `flutter_test` + `matchesGoldenFile`. No new runtime dependencies.

**Spec:** [`docs/superpowers/specs/2026-10-12-paint-ball-neon-design.md`](../specs/2026-10-12-paint-ball-neon-design.md)

## Global Constraints

Every task's requirements implicitly include all of these. Values are copied verbatim from the spec.

- **Zero migrations, zero server changes.** Client-side only. A concurrent session owns migration range `20261012_2xxxxx`; this branch must not create any migration.
- **`PaintBallField`'s public constructor signature is frozen.** All 15 parameters keep their names, types, and defaults: `splats, myPosition, selectedShot, revealedPartnerPosition, isMyTurn, shotProgress, onSelectShot, onSelectHide, onFire, replayProgress, theirRevealedShot, isReplaying, partnerName, theirStreak`. `paint_ball_battle_screen.dart` and `paint_ball_knockout_screen.dart` must compile untouched.
- **`kPaintBallPositions = 3` stays exported from `paint_ball/presentation/widgets/paint_ball_field.dart`.** `paint_ball_provider.dart:14` imports it from exactly that path. Moving it is out of scope.
- **No durations, blur radii, alphas or geometry ratios as literals at call sites.** All live in `neon_tokens.dart` (Master Spec §17.4). Motion stays in the 150–320ms band.
- **No infinite or looping animations.** Event motion fires once and settles, scheduling no further frames (`GlowPulse` battery budget). Exactly one ambient exception is permitted: a few-cycles-then-settle breath on the active player's bay.
- **Every animated primitive degrades under OS reduce-motion** to its instant end-state, via `reduceMotionOf(context)` from `lib/core/ui/motion/reduce_motion.dart`.
- **No new raster assets.** Any exception requires a spec amendment (§1.5).
- **No fragment shaders.** Deferred (§5.1).
- **White is reserved for the instant of impact.** Nothing else on the field is ever white (§2.2).
- **Figures take their owner's hue:** mint `#5EEAD4` yours, rose `#FF4D6A` theirs. The old neutral yellow `#FFC94D` is removed (§2.2).
- **Paint never persists across rounds.** It arrives with the shot and leaves with the replay (§2.6 correction).
- **A round is a simultaneous duel.** Both players fire blind; both paintballs are airborne together during a replay (§1.1, §2.6).
- **Docs are updated in the same pass as the code** (ATTUNE_THESIS §6.11).

**Test command:** `flutter test <path>` from `/Users/user/attune/.worktrees/games-v2`. Ignore the `file_picker` plugin warnings on stderr — they are pre-existing noise, not failures.

**Golden rule, inherited from `word_hunt_golden_test.dart`:** goldens are *"rendered and LOOKED AT, not merely diffed."* Every visual bug in the Arcade so far — domed arches, a triangle on the edge of its cover, clipped tokens — was found by opening the PNG. After generating any golden, open it and look at it before committing.

## Review Focus

Five input classes the spec implies but no task's tests would otherwise exercise, most likely to bite first. Each has its test assigned to the task that owns the code.

1. **`replayProgress` at exactly `1.0`** — `_skipReplay()` sets the controller to `1`, so a player tapping to skip lands on this exact frame. All six beats must render correctly and simultaneously there, not just at the sampled mid-values the existing tests use. *(Task 9, Step 1)*
2. **`replayProgress` outside `[0,1]`** — a controller driven past its bounds, or a `-0.0`. Beat thresholds compared with `>` must not produce a negative-progress projectile or a NaN offset. *(Task 9, Step 3)*
3. **Both positions null while `shotProgress` is non-null** — already covered for the old projectile ("a shot with no chosen positions still renders") and must survive the rewrite, because a mid-flight rebuild after state clears would otherwise crash the screen. *(Task 7, Step 5)*
4. **`theirStreak` of 0 or 1 during a replay** — the label shows only from two upward. A 0 must not render `SAME SPOT x0`, and the existing test only covers 3. *(Task 6, Step 7)*
5. **A splat list containing an out-of-range `position`** — `PaintSplat.position` is a bare `int` with no validation, and a stale or malformed round could carry `3` or `-1` into the burst emitter, producing an off-field draw or a division artefact. *(Task 10, Step 5)*

---

## File Structure

**Created — the toolkit (`lib/core/ui/neon/`):**

| File | Responsibility |
|---|---|
| `neon_tokens.dart` | Every alpha, blur radius, glow spread, geometry ratio and beat duration. No logic. |
| `neon_quality.dart` | Device tier (`plain`/`glow`/`rich`) resolution and an inherited accessor. |
| `light_well.dart` | A radial ground falloff, so the field has a middle. |
| `glow_stroke.dart` | The workhorse: a luminous outline as core stroke + halo passes. |
| `lit_mark.dart` | An emitting actor (figure, ball): glow plus optional ground-cast. |
| `bloom_flash.dart` | One-shot impact: white core → coloured bloom → fade. Self-terminating. |
| `paint_burst.dart` | Deterministic droplet emitter: scatter, gravity, wet highlight. |

**Created — the field parts (`lib/features/games/paint_ball/presentation/widgets/field/`):**

| File | Responsibility |
|---|---|
| `paint_ball_field_keys.dart` | Stable `Key`s and the typed test seam, replacing `as dynamic` painter reads. |
| `field_ground.dart` | Light well, centre divider, the two row labels. |
| `cover_bay.dart` | ONE bay. Behind `PaintBallCoverStyle` — the swap seam for §2.3. |
| `cover_row.dart` | The three bays, selection and aim state for one side. |
| `field_figure.dart` | A player as a lit mark; occlusion-aware; owns the travel animation. |
| `field_paint.dart` | Splat rendering for the current round only; wraps `paint_burst`. |
| `field_replay.dart` | Emits `ReplayBeats` from one progress double. Timing lives here and nowhere else. |

**Modified:**

| File | Change |
|---|---|
| `paint_ball/presentation/widgets/paint_ball_field.dart` | Reduced to composition + layout (~180 lines). Keeps the frozen signature, `kPaintBallPositions`, `PaintSplat` and `PaintBallPalette` exports. |
| `tool/generate_paint_ball_sounds.dart` | Five cues regenerated as layered noise with pitch envelopes. |
| `assets/sounds/README.md` | Note the regeneration; keep the placeholder review gate open. |
| `lib/architecture/GAMES.md` | Reconcile the three-games-and-deferrals drift (Stage 7). |
| `lib/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart` | Second toolkit consumer (Stage 7). |

**Tests created:**

`test/core/ui/neon/` — `neon_quality_test.dart`, `glow_stroke_test.dart`, `light_well_test.dart`, `lit_mark_test.dart`, `bloom_flash_test.dart`, `paint_burst_test.dart`
`test/features/games/` — `paint_ball_replay_beats_test.dart`, `paint_ball_field_golden_test.dart`
`test/features/games/paint_ball_field_test.dart` — rewritten per §3.6.1, behaviour preserved

---

## Task 0: Map every existing field test to its replacement

The spec (§3.6.1) requires this mapping to exist **before Stage 2 touches the field.** Its output is a document, not code: a dropped device-reported regression must be visible as a gap now rather than discovered after the rewrite.

**Files:**
- Create: `docs/superpowers/plans/2026-10-12-paint-ball-test-map.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the mapping document every later field task checks itself against.

- [ ] **Step 1: Confirm the baseline is green before changing anything**

Run: `flutter test test/features/games/paint_ball_field_test.dart`
Expected: `All tests passed!` with `+25`. If it is not 25, stop and report — the plan's mapping is built on that count.

- [ ] **Step 2: Write the mapping document**

Create `docs/superpowers/plans/2026-10-12-paint-ball-test-map.md` with this exact content:

```markdown
# Paint Ball field test map

Per spec §3.6.1. Every row's **behaviour** must survive the rewrite. Only the
**hook** may change. A row marked `DROP` requires a written justification in
the commit that drops it.

`B` = behavioural (must survive). `S` = structural hook (may be rewritten).

| # | Existing test | Kind | Current hook | Replacement hook |
|---|---|---|---|---|
| 1 | the field renders with a full match of paint | B | no exception w/ 20 splats | same, via `FieldPaint` |
| 2 | an empty field renders | B | no exception, all nulls | same |
| 3 | each row taps to its own action | B | `bySemanticsLabel('<Name> target'/'cover')` | unchanged labels, `CoverRow` |
| 4 | firing is the triangle, never a cover | B | descendant `CustomPaint` of cover | `PaintBallFieldKeys.figure(position)` |
| 5 | nothing is selectable when it is not your turn | B | tap every `GestureDetector` | same |
| 6 | your own triangle is visible, theirs is not | B | count painters named `Triangle` | count `FieldFigure` widgets |
| 7 | a revealed partner position becomes visible | B | same count, expects 2 | same |
| 8 | a shot in flight renders | B | no exception, `shotProgress: 0.5` | same |
| 9 | a shot with no chosen positions still renders | B | no exception, nulls + progress | same |
| 10 | the three targets are labelled and focusable | B | `bySemanticsLabel` + tap | unchanged |
| 11 | reduce motion makes all field transitions immediate | B | every `Animated*.duration == 0` | same, plus `ReplayBeats.instant` |
| 12 | lives use text and become immediate with reduce motion | B | `PaintBallLivesDisplay` semantics | **untouched** — different widget |
| 13 | a replay shows both players, then hides theirs again | B | triangle count == 2 | `FieldFigure` count == 2 |
| 14 | mid-replay both paintballs are in flight at once | B | painters named `Projectile` == 2 | `PaintBallFieldKeys.projectile(side)` == 2 |
| 15 | early in a replay nobody has fired yet | B | projectile count == 0 at 0.05 | same |
| 16 | repositioning travels rather than teleporting | B | triangle centre moves, count stays 1 | `FieldFigure` centre, same assertions |
| 17 | a travelling player steps clear of cover | B | crossing `dy` < resting `dy` | same |
| 18 | the character stands in the centre of its cover | B | centre within 1.0pt at 3 widths | same — **device-reported, keep verbatim** |
| 19 | the two rows of cover face each other | B+S | `(painter as dynamic).opensDown` | `CoverBay.facing` public field — **device-reported** |
| 20 | the far row is named for the partner | B | `find.text('AMA')` | same, `FieldGround` |
| 21 | an unknown partner falls back rather than showing a gap | B | `find.text('THEIR COVER')` | same |
| 22 | an idle board carries no paint | B+S | `(painter as dynamic).splats` empty | `FieldPaint.splats` public field |
| 23 | a partner who stays put is called out | B | `find.text('SAME SPOT x3')` | same |
| 24 | a streak is not kept on the board between rounds | B | that text absent when idle | same |
| 25 | a shot crosses the field rather than teleporting | B+S | `(painter as dynamic).progress` set size > 3 | `FieldProjectile.progress` public field |

**Count: 25. Behavioural: 25. Dropped: 0.**

Test 12 touches `PaintBallLivesDisplay`, not the field, so it must pass
completely unmodified.

Tests 18 and 19 record bugs reported from a real device. Their assertions are
carried over verbatim wherever the hook allows.
```

- [ ] **Step 3: Verify the mapping covers every test in the file**

Run:
```bash
diff <(grep -o "testWidgets('[^']*'" test/features/games/paint_ball_field_test.dart | sed "s/testWidgets('//; s/'$//" | sort) \
     <(grep -oE '^\| [0-9]+ \| [^|]+' docs/superpowers/plans/2026-10-12-paint-ball-test-map.md | sed 's/^| [0-9]* | //; s/ *$//' | sort)
```
Expected: no output. Any line means a test is missing from the map or the map names one that does not exist. Fix the map, not the test file.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/2026-10-12-paint-ball-test-map.md
git commit -m "$(cat <<'EOF'
docs(games): map every Paint Ball field test to its post-rewrite hook

Spec §3.6.1 requires this before the rewrite starts. The 25 existing
tests identify painters by runtime type-NAME substring and read fields
through `as dynamic`, so renaming a painter breaks a dozen assertions
with no behaviour change -- and two of those tests record bugs reported
from a real device. Mapping them first makes a dropped regression a
visible gap rather than a later discovery.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 1: Neon tokens

**Files:**
- Create: `lib/core/ui/neon/neon_tokens.dart`
- Test: `test/core/ui/neon/neon_tokens_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `NeonTokens` — a const class every other neon file and field part reads. All members, since later tasks consume them by name:
  - Ground: `groundColor` (`Color`), `lightWellRadiusRatio` (`double`), `lightWellAlpha` (`double`)
  - Alphas: `structureAlphaRest`, `structureAlphaActive`, `actorAlpha` (all `double`)
  - Glow: `coreStrokeWidth`, `haloBlurInner`, `haloBlurOuter`, `haloSpreadInner`, `haloSpreadOuter`, `haloAlphaInner`, `haloAlphaOuter` (all `double`)
  - Bay geometry: `bayCornerRatio`, `bayInsetRatio` (both `double`)
  - Durations: `impactFlashDuration`, `bloomFadeDuration`, `burstSettleDuration` (all `Duration`)
  - Beats: `beatEmerge`, `beatAim`, `beatFire`, `beatFlightEnd`, `beatImpactEnd` (all `double`)

- [ ] **Step 1: Write the failing test**

Create `test/core/ui/neon/neon_tokens_test.dart`:

```dart
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('beat thresholds are ordered and inside the unit interval', () {
    // field_replay maps one 0->1 value onto six beats by comparing
    // against these. Out-of-order thresholds would make a beat
    // unreachable, and the bug would present as a missing animation
    // rather than as a crash.
    final beats = [
      NeonTokens.beatEmerge,
      NeonTokens.beatAim,
      NeonTokens.beatFire,
      NeonTokens.beatFlightEnd,
      NeonTokens.beatImpactEnd,
    ];

    for (final beat in beats) {
      expect(beat, greaterThan(0.0));
      expect(beat, lessThanOrEqualTo(1.0));
    }
    for (var i = 1; i < beats.length; i++) {
      expect(
        beats[i],
        greaterThan(beats[i - 1]),
        reason: 'beat $i must come after beat ${i - 1}',
      );
    }
  });

  test('the four original thresholds are preserved', () {
    // The existing replay choreography was tuned on a device and its
    // rationale is documented: emerging and aiming need room to read
    // before anything is fired. Keeping the numbers means the rebuild
    // is a repaint, not a retiming.
    expect(NeonTokens.beatEmerge, 0.12);
    expect(NeonTokens.beatAim, 0.34);
    expect(NeonTokens.beatFire, 0.52);
    expect(NeonTokens.beatFlightEnd, 0.86);
  });

  test('motion durations stay inside the 150-320ms band', () {
    // Master Spec §17.4. A duration outside the band reads as either a
    // glitch or a wait.
    for (final duration in [
      NeonTokens.impactFlashDuration,
      NeonTokens.bloomFadeDuration,
      NeonTokens.burstSettleDuration,
    ]) {
      expect(duration.inMilliseconds, greaterThanOrEqualTo(150));
      expect(duration.inMilliseconds, lessThanOrEqualTo(320));
    }
  });

  test('structure is dimmer than actors', () {
    // Spec §2.1: if everything glows, nothing does. Structure is
    // architecture; actors are the only bright things on the field.
    expect(NeonTokens.structureAlphaRest, lessThan(NeonTokens.actorAlpha));
    expect(NeonTokens.structureAlphaActive, lessThan(NeonTokens.actorAlpha));
    expect(
      NeonTokens.structureAlphaRest,
      lessThan(NeonTokens.structureAlphaActive),
    );
  });

  test('the ground emits nothing', () {
    // §2.1 tier 1: the ground receives light and emits none. Near-black
    // rather than pure black, so coloured glow does not vibrate on it.
    expect(NeonTokens.groundColor.a, 1.0);
    expect(NeonTokens.groundColor.r, lessThan(0.08));
    expect(NeonTokens.groundColor.g, lessThan(0.08));
    expect(NeonTokens.groundColor.b, lessThan(0.08));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/neon/neon_tokens_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'attune' ... neon_tokens.dart` or `Target of URI doesn't exist`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/ui/neon/neon_tokens.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/neon/neon_tokens_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/neon/neon_tokens.dart test/core/ui/neon/neon_tokens_test.dart
git commit -m "$(cat <<'EOF'
feat(neon): add the tokens the neon language is made of

In a language where light is the only material, the alphas and blur
radii ARE the art, so §17.4's no-literals rule has to cover more than
durations -- scattering them through painters is how one coherent
surface drifts into ten slightly different ones.

The four replay beat thresholds carry over unchanged at 0.12/0.34/0.52/
0.86. They were tuned on a device for a documented reason: emerging and
aiming need room to read before anything fires, because the point of the
replay is watching the two decisions meet. Keeping them makes this a
repaint rather than a retiming. Impact and settle take the 0.86-1.0 tail
the old implementation left unused.

Tested for ordering, because field_replay maps one double onto six beats
by comparing against these and an out-of-order threshold would present
as a missing animation rather than a crash.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Device quality tiering

The §6.10 guard. Built now rather than retrofitted, because every later primitive reads it.

**Files:**
- Create: `lib/core/ui/neon/neon_quality.dart`
- Test: `test/core/ui/neon/neon_quality_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum NeonQuality { plain, glow, rich }`
  - `int get haloPasses` on `NeonQuality` — `0` for plain, `1` for glow, `2` for rich.
  - `int get maxDroplets` on `NeonQuality` — `3` / `10` / `24`.
  - `bool get castsGroundLight` on `NeonQuality` — false only for plain.
  - `class NeonQualityScope extends InheritedWidget` with `const NeonQualityScope({required NeonQuality quality, required Widget child})`.
  - `NeonQuality neonQualityOf(BuildContext context)` — returns `NeonQuality.glow` when no scope is present.

- [ ] **Step 1: Write the failing test**

Create `test/core/ui/neon/neon_quality_test.dart`:

```dart
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each tier costs strictly less than the one above it', () {
    // The tiers exist to honour the thesis §6.10 launch gate on
    // representative Ghanaian hardware. A tier that is not actually
    // cheaper is a tier that does not help.
    expect(NeonQuality.plain.haloPasses, lessThan(NeonQuality.glow.haloPasses));
    expect(NeonQuality.glow.haloPasses, lessThan(NeonQuality.rich.haloPasses));

    expect(
      NeonQuality.plain.maxDroplets,
      lessThan(NeonQuality.glow.maxDroplets),
    );
    expect(
      NeonQuality.glow.maxDroplets,
      lessThan(NeonQuality.rich.maxDroplets),
    );
  });

  test('plain draws no halo at all', () {
    // Spec §3.1: under plain, halo passes collapse to a single stroke.
    // The outline must still be VISIBLE -- the game has to remain
    // playable, not merely cheap -- so this asserts the halo is gone,
    // not the stroke.
    expect(NeonQuality.plain.haloPasses, 0);
    expect(NeonQuality.plain.castsGroundLight, isFalse);
  });

  test('every tier still draws something', () {
    // A tier that renders nothing would make the field unplayable on
    // the hardware the tier exists to serve.
    for (final quality in NeonQuality.values) {
      expect(quality.maxDroplets, greaterThan(0));
    }
  });

  testWidgets('a subtree with no scope assumes the middle tier', (
    tester,
  ) async {
    // Defaulting to rich would punish exactly the devices the tiering
    // protects; defaulting to plain would make every screen that forgot
    // the scope look broken. The middle is the only safe default.
    late NeonQuality seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = neonQualityOf(context);
          return const SizedBox();
        },
      ),
    );

    expect(seen, NeonQuality.glow);
  });

  testWidgets('a scope overrides the default for its subtree', (tester) async {
    late NeonQuality seen;
    await tester.pumpWidget(
      NeonQualityScope(
        quality: NeonQuality.plain,
        child: Builder(
          builder: (context) {
            seen = neonQualityOf(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(seen, NeonQuality.plain);
  });

  testWidgets('a changed scope rebuilds its dependents', (tester) async {
    // Without this the tier would be latched at first build, and a
    // runtime downgrade after a jank measurement could never take
    // effect.
    final seen = <NeonQuality>[];
    Widget host(NeonQuality quality) => NeonQualityScope(
      quality: quality,
      child: Builder(
        builder: (context) {
          seen.add(neonQualityOf(context));
          return const SizedBox();
        },
      ),
    );

    await tester.pumpWidget(host(NeonQuality.rich));
    await tester.pumpWidget(host(NeonQuality.plain));

    expect(seen, [NeonQuality.rich, NeonQuality.plain]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/neon/neon_quality_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:attune/core/ui/neon/neon_quality.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/ui/neon/neon_quality.dart`:

```dart
import 'package:flutter/widgets.dart';

/// How much light this device can afford.
///
/// ATTUNE_THESIS §6.10 makes performance budgets on representative
/// Ghanaian hardware a LAUNCH GATE, and payload thrift a permanent
/// discipline rather than an optimization pass. A neon surface is made
/// of blur passes, which is exactly the kind of cost that is invisible
/// on a developer's phone and ruinous on a low-end one.
///
/// So the tier exists from the first primitive rather than being
/// retrofitted: every neon widget reads it, and degrading is a
/// multiplication rather than a branch nobody wrote.
enum NeonQuality {
  /// One crisp stroke, no halo, few droplets. Still playable, still
  /// legible -- the game must not become unusable on the hardware this
  /// tier is for.
  plain,

  /// The everyday look: one halo pass. The default.
  glow,

  /// Two halo passes and ground-cast light.
  rich;

  /// Blurred passes drawn behind a core stroke.
  int get haloPasses => switch (this) {
    NeonQuality.plain => 0,
    NeonQuality.glow => 1,
    NeonQuality.rich => 2,
  };

  /// Droplets a single paint burst may emit.
  int get maxDroplets => switch (this) {
    NeonQuality.plain => 3,
    NeonQuality.glow => 10,
    NeonQuality.rich => 24,
  };

  /// Whether a travelling actor lights the ground under it. The most
  /// expensive effect in the language and the first to go.
  bool get castsGroundLight => this != NeonQuality.plain;
}

/// Declares the tier for a subtree.
class NeonQualityScope extends InheritedWidget {
  const NeonQualityScope({
    super.key,
    required this.quality,
    required super.child,
  });

  final NeonQuality quality;

  @override
  bool updateShouldNotify(NeonQualityScope oldWidget) =>
      quality != oldWidget.quality;
}

/// The tier in effect, or [NeonQuality.glow] where nothing declared one.
///
/// The middle is the only safe default: rich would punish precisely the
/// devices the tiering protects, and plain would make any screen that
/// forgot the scope look broken.
NeonQuality neonQualityOf(BuildContext context) =>
    context
        .dependOnInheritedWidgetOfExactType<NeonQualityScope>()
        ?.quality ??
    NeonQuality.glow;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/neon/neon_quality_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/neon/neon_quality.dart test/core/ui/neon/neon_quality_test.dart
git commit -m "$(cat <<'EOF'
feat(neon): tier the light by what the device can afford

Thesis §6.10 makes performance budgets on representative Ghanaian
hardware a launch gate. A neon surface is made of blur passes -- the
kind of cost that is invisible on a developer's phone and ruinous on a
low-end one -- so the tier ships with the first primitive instead of
being retrofitted after a jank report.

plain still draws a visible stroke and some droplets. A tier that
rendered nothing would break the game on exactly the hardware the tier
exists to serve, so the tests assert each tier is cheaper than the one
above AND that all three still draw.

Absent a scope the answer is glow, not rich: defaulting high would
punish the devices this protects, and defaulting low would make any
screen that forgot the scope look broken.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: The light well

**Files:**
- Create: `lib/core/ui/neon/light_well.dart`
- Test: `test/core/ui/neon/light_well_test.dart`

**Interfaces:**
- Consumes: `NeonTokens.groundColor`, `NeonTokens.lightWellRadiusRatio`, `NeonTokens.lightWellAlpha`, `NeonQuality` via `neonQualityOf`.
- Produces: `class LightWell extends StatelessWidget` with `const LightWell({Color? tint, Widget? child})`. Paints the ground and its falloff, then its child over it.

- [ ] **Step 1: Write the failing test**

Create `test/core/ui/neon/light_well_test.dart`:

```dart
import 'package:attune/core/ui/neon/light_well.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the ground is painted even with nothing on it', (tester) async {
    // The field's ground is tier 1 of §2.1: it receives light and emits
    // none. An unpainted ground would fall through to the app theme,
    // which in light mode is white -- and every neon colour was chosen
    // against near-black.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LightWell())),
    );
    await tester.pump();

    final well = tester.widget<LightWell>(find.byType(LightWell));
    expect(well.tint, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a child renders over the ground, not under it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LightWell(child: Text('on the field')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('on the field'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the plain tier still paints the ground', (tester) async {
    // Degrading may drop the falloff, never the ground itself. A
    // transparent ground on a low-end device would be the worst
    // possible failure: the one place the tiering must not break.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NeonQualityScope(
            quality: NeonQuality.plain,
            child: LightWell(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(LightWell), findsOneWidget);
  });

  testWidgets('a zero-sized well does not throw', (tester) async {
    // A LayoutBuilder inside a collapsed parent hands down a zero box,
    // and a radial gradient with radius 0 is a division waiting to
    // happen. Reachable during a route transition.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 0, height: 0, child: LightWell()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  test('the tokens it depends on are sane', () {
    expect(NeonTokens.lightWellRadiusRatio, greaterThan(0));
    expect(NeonTokens.lightWellAlpha, greaterThan(0));
    expect(
      NeonTokens.lightWellAlpha,
      lessThan(0.2),
      reason: 'a well bright enough to notice is a gradient, not a ground',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/neon/light_well_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:attune/core/ui/neon/light_well.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/ui/neon/light_well.dart`:

```dart
import 'package:flutter/material.dart';

import 'neon_quality.dart';
import 'neon_tokens.dart';

/// The ground, and the barely-there glow that gives it a middle.
///
/// Spec §2.1 tier 1: the ground receives light and emits none. Without
/// the well a neon field is a flat void -- correct, and dead. With it
/// there is a centre for the composition to sit in, at an alpha low
/// enough that nobody would describe the screen as having a gradient.
///
/// Degrading drops the falloff but NEVER the ground: a transparent
/// ground would fall through to the app theme, which in light mode is
/// white, and every colour in this language was chosen against
/// near-black.
class LightWell extends StatelessWidget {
  const LightWell({super.key, this.tint, this.child});

  /// The hue of the well. Defaults to a neutral lift.
  final Color? tint;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final quality = neonQualityOf(context);
    final colour = tint ?? const Color(0xFFFFFFFF);

    return DecoratedBox(
      decoration: BoxDecoration(color: NeonTokens.groundColor),
      child:
          quality == NeonQuality.plain
              // Ground only. The gradient is the first thing to go.
              ? (child ?? const SizedBox.expand())
              : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: NeonTokens.lightWellRadiusRatio,
                    colors: [
                      colour.withValues(alpha: NeonTokens.lightWellAlpha),
                      colour.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: child ?? const SizedBox.expand(),
              ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/neon/light_well_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/neon/light_well.dart test/core/ui/neon/light_well_test.dart
git commit -m "$(cat <<'EOF'
feat(neon): give the ground a middle

Without a falloff a neon field is a flat void -- technically correct and
visually dead. The well sits at alpha 0.055, low enough that nobody
would say the screen has a gradient, high enough that the composition
has a centre.

Degrading drops the falloff but never the ground. A transparent ground
falls through to the app theme, which in light mode is white, and every
colour in this language was chosen against near-black -- so that is the
one place the tiering must not break, and a test pins it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: The glow stroke

The workhorse. Every bay outline, divider and aim beam is one of these, so its cost and its look set the whole surface.

**Files:**
- Create: `lib/core/ui/neon/glow_stroke.dart`
- Test: `test/core/ui/neon/glow_stroke_test.dart`

**Interfaces:**
- Consumes: `NeonTokens` halo constants, `NeonQuality.haloPasses`.
- Produces:
  - `class GlowStrokeSpec` — `const GlowStrokeSpec({required Color color, required double alpha, double widthScale = 1.0})`, with public final fields `color`, `alpha`, `widthScale`.
  - `void paintGlowPath(Canvas canvas, Path path, GlowStrokeSpec spec, int haloPasses)` — the painting primitive field painters call directly.
  - `int glowPassCountFor(NeonQuality quality)` — `quality.haloPasses`, re-exported so painters need not import the enum.

- [ ] **Step 1: Write the failing test**

Create `test/core/ui/neon/glow_stroke_test.dart`:

```dart
import 'dart:ui';

import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what was drawn, so the halo structure can be asserted
/// without a golden. A golden proves it LOOKS right; this proves the
/// right number of passes happened, which is the performance contract.
class _RecordingCanvas implements Canvas {
  final drawnPaths = <Paint>[];

  @override
  void drawPath(Path path, Paint paint) => drawnPaths.add(paint);

  @override
  noSuchMethod(Invocation invocation) => null;
}

void main() {
  final path = Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10));
  const spec = GlowStrokeSpec(color: Color(0xFF5EEAD4), alpha: 0.9);

  test('a core stroke is always drawn, whatever the tier', () {
    // The outline is what makes the field legible. Halo is decoration;
    // the core is the information, and it may never be optimised away.
    for (final quality in NeonQuality.values) {
      final canvas = _RecordingCanvas();
      paintGlowPath(canvas, path, spec, quality.haloPasses);

      expect(
        canvas.drawnPaths,
        isNotEmpty,
        reason: '$quality must still draw the stroke itself',
      );
    }
  });

  test('each tier draws exactly its halo passes plus the core', () {
    for (final quality in NeonQuality.values) {
      final canvas = _RecordingCanvas();
      paintGlowPath(canvas, path, spec, quality.haloPasses);

      expect(
        canvas.drawnPaths.length,
        quality.haloPasses + 1,
        reason: '$quality: ${quality.haloPasses} halo passes and one core',
      );
    }
  });

  test('halo passes are dimmer and wider than the core', () {
    // §2.1: an outline reads as EMITTING only if the blur sits behind a
    // crisp edge. Equal-alpha passes read as a fuzzy line instead.
    final canvas = _RecordingCanvas();
    paintGlowPath(canvas, path, spec, NeonQuality.rich.haloPasses);

    // Painted back to front: widest and dimmest first, core last.
    final core = canvas.drawnPaths.last;
    final halos = canvas.drawnPaths.take(canvas.drawnPaths.length - 1);

    for (final halo in halos) {
      expect(
        halo.color.a,
        lessThan(core.color.a),
        reason: 'a halo must be dimmer than the edge it surrounds',
      );
      expect(
        halo.strokeWidth,
        greaterThan(core.strokeWidth),
        reason: 'a halo must be wider than the edge it surrounds',
      );
      expect(
        halo.maskFilter,
        isNotNull,
        reason: 'a halo without blur is just a thick line',
      );
    }

    expect(
      core.maskFilter,
      isNull,
      reason: 'the core must stay crisp or the whole thing reads as fog',
    );
  });

  test('zero alpha draws nothing rather than an invisible pass', () {
    // Reachable: a bay fading out passes alpha through to 0, and
    // painting a fully transparent blur is pure cost for no pixels.
    final canvas = _RecordingCanvas();
    paintGlowPath(
      canvas,
      path,
      const GlowStrokeSpec(color: Color(0xFF5EEAD4), alpha: 0),
      NeonQuality.rich.haloPasses,
    );

    expect(canvas.drawnPaths, isEmpty);
  });

  test('alpha above one is clamped rather than throwing', () {
    // An animation overshooting with easeOutBack can hand this a value
    // over 1, and Color.withValues asserts on out-of-range alpha.
    final canvas = _RecordingCanvas();

    expect(
      () => paintGlowPath(
        canvas,
        path,
        const GlowStrokeSpec(color: Color(0xFF5EEAD4), alpha: 1.4),
        NeonQuality.glow.haloPasses,
      ),
      returnsNormally,
    );
    for (final paint in canvas.drawnPaths) {
      expect(paint.color.a, lessThanOrEqualTo(1.0));
    }
  });

  test('the pass count helper agrees with the enum', () {
    for (final quality in NeonQuality.values) {
      expect(glowPassCountFor(quality), quality.haloPasses);
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/neon/glow_stroke_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:attune/core/ui/neon/glow_stroke.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/ui/neon/glow_stroke.dart`:

```dart
import 'dart:ui';

import 'neon_quality.dart';
import 'neon_tokens.dart';

/// How bright, and in what colour, one luminous outline is.
class GlowStrokeSpec {
  const GlowStrokeSpec({
    required this.color,
    required this.alpha,
    this.widthScale = 1.0,
  });

  final Color color;

  /// 0 to 1. Clamped when painted, because an overshooting curve can
  /// hand this a value above 1 and Color.withValues asserts on those.
  final double alpha;

  /// Multiplies the core stroke width, for an outline that should read
  /// heavier than the default without changing the token.
  final double widthScale;
}

/// Halo passes for a tier, re-exported so painters need not import the
/// enum alongside this file.
int glowPassCountFor(NeonQuality quality) => quality.haloPasses;

/// Paints [path] as a luminous outline: blurred halo passes behind one
/// crisp core stroke.
///
/// The two-part construction is the whole trick of spec §2.1. A single
/// wide blur reads as fog. A blur sitting BEHIND a sharp edge reads as
/// emission, because that is what a real light source does to a camera.
/// So the core is never blurred and never dropped -- it carries the
/// information; the halo is the only part that degrades.
///
/// Drawn back to front: widest and dimmest first, core last.
void paintGlowPath(
  Canvas canvas,
  Path path,
  GlowStrokeSpec spec,
  int haloPasses,
) {
  final alpha = spec.alpha.clamp(0.0, 1.0);

  // A fully transparent outline is pure cost for no pixels, and a bay
  // fading out passes exactly that.
  if (alpha <= 0) return;

  final coreWidth = NeonTokens.coreStrokeWidth * spec.widthScale;

  // Outer first so the inner pass layers over it.
  for (var pass = haloPasses; pass >= 1; pass--) {
    final isOuter = pass == 2;
    final blur = isOuter ? NeonTokens.haloBlurOuter : NeonTokens.haloBlurInner;
    final spread =
        isOuter ? NeonTokens.haloSpreadOuter : NeonTokens.haloSpreadInner;
    final haloAlpha =
        alpha * (isOuter ? NeonTokens.haloAlphaOuter : NeonTokens.haloAlphaInner);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = coreWidth + spread
        ..color = spec.color.withValues(alpha: haloAlpha.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = coreWidth
      ..color = spec.color.withValues(alpha: alpha),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/neon/glow_stroke_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Run the whole suite to confirm nothing regressed**

Run: `flutter test`
Expected: all tests pass. Stage 1 added files only; nothing existing should move.

- [ ] **Step 6: Commit**

```bash
git add lib/core/ui/neon/glow_stroke.dart test/core/ui/neon/glow_stroke_test.dart
git commit -m "$(cat <<'EOF'
feat(neon): the luminous outline every bay and beam is made of

A single wide blur reads as fog. A blur sitting BEHIND a crisp edge
reads as emission, because that is what a real light source does to a
camera -- so the core stroke is never blurred and never dropped. It
carries the information; only the halo degrades.

Tested with a recording canvas rather than a golden, because the
assertion here is the performance contract, not the look: each tier
draws exactly its halo passes plus one core, halos are strictly dimmer
and wider than the edge they surround, and the core keeps no mask
filter. A golden would prove it looks right; this proves it costs what
the tier promised.

Two reachable inputs are pinned. Alpha 0 draws nothing at all, since a
bay fading out passes exactly that and a transparent blur is cost for no
pixels. Alpha above 1 is clamped, since easeOutBack overshoots and
Color.withValues asserts on out-of-range alpha.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

**Stage 1 is complete here.** Four tested primitives exist; nothing in the app looks different yet.

---

## Remaining tasks: Stages 2–7

Tasks 5–14 are the field rewrite and are written in the next pass at the same granularity as Tasks 0–4 — full test code, full implementation, exact commands and expected output. Their scope and boundaries are fixed:

| Task | Stage | Deliverable |
|---|---|---|
| 5 | 2 | `paint_ball_field_keys.dart` — the typed test seam §3.6.1 mandates, replacing every `as dynamic` painter read |
| 6 | 2 | `field_ground.dart` — light well, divider, row labels, partner name, streak (owns Review Focus #4) |
| 7 | 2 | `cover_bay.dart` + `PaintBallCoverStyle` — the bay-of-darkness and its swap seam (owns Review Focus #3) |
| 8 | 2 | `cover_row.dart`, `field_figure.dart`, and `paint_ball_field.dart` reduced to composition; **the 25-test rewrite per the Task 0 map** |
| 9 | 4 | `field_replay.dart` + `ReplayBeats` (owns Review Focus #1 and #2) |
| 10 | 5 | `paint_burst.dart` + `field_paint.dart` (owns Review Focus #5) |
| 11 | 4 | `bloom_flash.dart` and the six-beat choreography wired through the field |
| 12 | 2+4 | `paint_ball_field_golden_test.dart` — six goldens, each rendered and **looked at** |
| 13 | 6 | `tool/generate_paint_ball_sounds.dart` — five cues as layered noise with pitch envelopes |
| 14 | 7 | Sliding Scale on the toolkit; `GAMES.md` drift reconciled per §6.11 |

**Execution may begin at Task 0.** Tasks 0–4 are complete, verified, self-contained and independently committable. They end at a natural boundary: the toolkit exists and is tested, and no game code has changed.

**Note for the executor:** Tasks 1–4's test and implementation code was written against Flutter 3.29.1 in this worktree and **verified to compile and pass** (11 tests green) before the plan was committed — then the scaffold was deleted so the executor writes it. If a step fails as written, that is a real discrepancy worth reporting, not an expected gap to paper over.
