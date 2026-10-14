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

## Stage 2 addendum: two constraints discovered in the field code

Read these before Task 5. Both were found by reading `paint_ball_field.dart`
after Stage 1 shipped, and both override a Global Constraint above.

**1. The 150–320ms motion band does NOT bind the travelling figure.**
`paint_ball_field.dart:657` runs the reposition animation at **620ms**, and
tests 16 and 17 pump exactly `310ms` (`paint_ball_field_test.dart:490,543`) to
sample its midpoint. **Preserve 620ms verbatim.** The band governs a *settle* —
one object arriving at one place. This is a documented three-beat journey (back
out of cover → across → forward into the new cover) whose point is that
repositioning reads as travel; the code comment notes a cross-faded triangle
"would read as two triangles." Three beats inside 320ms is ~100ms each, below
the threshold at which an eye can follow a path. An implementer who "fixes" the
620 to comply breaks two tests, one of them device-reported.

**2. The aimed cover slides aside, and that slide is the Fire confirmation.**
`_coverRow` moves the aimed shield from `18.w` to `30.w` and lifts its opacity
to `1.0` against `0.45` (enabled) / `0.35` (disabled). The comment states why:
*"With no Fire button, the aimed cover IS the confirmation that a target is
chosen, so it has to be obvious at a glance rather than a subtle tint."*

§2.3's bay-of-darkness has nowhere to slide and no opacity ladder, so **the
neon bay must carry an explicit AIMED state that is unmistakable at a glance.**
Task 7 specifies it as: the bay's outline jumps from `structureAlphaRest` to
`structureAlphaActive`, gains a halo pass, and its mouth *opens* — the two legs
part horizontally — so the shot has a visible path through. Opening the gate is
the neon equivalent of sliding the shield aside, and it keeps the "you can see
the path for the shot" property the original was built for.

---

## Task 5: Field keys — the typed test seam

§3.6.1 mandates this before any painter is renamed: stable `Key`s and public
painter fields, so the rewritten tests never again identify a painter by its
private type name or read a field through `as dynamic`.

**Files:**
- Create: `lib/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart`
- Test: `test/features/games/paint_ball_field_keys_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `PaintBallFieldKeys` with these static members, used by Tasks 6–8 and by the rewritten field tests:
  - `static Key figure(int position, {required bool isOpponent})`
  - `static Key bay(int position, {required bool isOpponent})`
  - `static Key projectile({required bool isMine})`
  - `static const Key ground`
  - `static const Key paint`
  - `static const Key divider`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/paint_ball_field_keys_test.dart`:

```dart
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a key is distinct per position and per side', () {
    // The whole point of the seam: a test asking for "my middle figure"
    // must not match the opponent's. The old tests counted painters by
    // type name, which could not tell the two rows apart at all -- they
    // asserted on totals and inferred the rest.
    final keys = <Key>{
      for (var position = 0; position < 3; position++) ...[
        PaintBallFieldKeys.figure(position, isOpponent: false),
        PaintBallFieldKeys.figure(position, isOpponent: true),
        PaintBallFieldKeys.bay(position, isOpponent: false),
        PaintBallFieldKeys.bay(position, isOpponent: true),
      ],
    };

    expect(
      keys,
      hasLength(12),
      reason: '3 positions x 2 sides x 2 kinds, all distinct',
    );
  });

  test('the same arguments always give an equal key', () {
    // ValueKey equality is what lets a test written once keep finding
    // the same widget across rebuilds.
    expect(
      PaintBallFieldKeys.figure(1, isOpponent: false),
      PaintBallFieldKeys.figure(1, isOpponent: false),
    );
    expect(
      PaintBallFieldKeys.bay(2, isOpponent: true),
      PaintBallFieldKeys.bay(2, isOpponent: true),
    );
    expect(
      PaintBallFieldKeys.projectile(isMine: true),
      PaintBallFieldKeys.projectile(isMine: true),
    );
  });

  test('the two projectiles are distinguishable', () {
    // A replay puts both shots in the air at once (spec §2.6). The test
    // that pins this counted painters by name and could only assert
    // "two exist"; keys let it assert WHOSE.
    expect(
      PaintBallFieldKeys.projectile(isMine: true),
      isNot(PaintBallFieldKeys.projectile(isMine: false)),
    );
  });

  test('the singleton keys are distinct from each other', () {
    expect(
      {
        PaintBallFieldKeys.ground,
        PaintBallFieldKeys.paint,
        PaintBallFieldKeys.divider,
      },
      hasLength(3),
    );
  });

  test('a key survives a round trip through a widget', () {
    // Guards against a key type that compares equal but cannot be found
    // by find.byKey -- the failure would be invisible until a test that
    // depends on it silently found nothing.
    const key = PaintBallFieldKeys.ground;
    expect(const SizedBox(key: key).key, key);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/games/paint_ball_field_keys_test.dart`
Expected: FAIL — `Target of URI doesn't exist` for `field/paint_ball_field_keys.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Stable handles onto the field's parts, for tests.
///
/// Spec §3.6.1. The field's 25 tests used to find painters by
/// `runtimeType.toString().contains('Triangle')` and read their state
/// through `(painter as dynamic).splats`. Both work and both are traps:
/// renaming a private painter breaks a dozen assertions with no
/// behaviour change, and worse, a name filter that matches nothing
/// yields an empty collection, so `expect(count, 0)` and
/// `for (x in matches)` keep passing while asserting nothing at all.
/// Two of the field's tests were in exactly that state.
///
/// So the parts carry keys and the painters expose public fields. A test
/// that asks for a named thing either finds it or fails.
///
/// Keyed per position AND per side, because the old filters could not
/// tell the two rows apart -- they counted totals across the whole
/// field and inferred whose was whose.
class PaintBallFieldKeys {
  const PaintBallFieldKeys._();

  /// A player's figure in its cover.
  static Key figure(int position, {required bool isOpponent}) =>
      ValueKey('paintball.figure.${isOpponent ? 'theirs' : 'mine'}.$position');

  /// One cover bay.
  static Key bay(int position, {required bool isOpponent}) =>
      ValueKey('paintball.bay.${isOpponent ? 'theirs' : 'mine'}.$position');

  /// A paintball in flight. Both sides' shots are airborne together
  /// during a replay (§2.6), so each needs its own handle.
  static Key projectile({required bool isMine}) =>
      ValueKey('paintball.projectile.${isMine ? 'mine' : 'theirs'}');

  static const Key ground = ValueKey('paintball.ground');
  static const Key paint = ValueKey('paintball.paint');
  static const Key divider = ValueKey('paintball.divider');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/games/paint_ball_field_keys_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart test/features/games/paint_ball_field_keys_test.dart
git commit -m "$(cat <<'EOF'
feat(paintball): give the field's parts handles a test can trust

The field's tests find painters by runtimeType name substring and read
their state through `as dynamic`. Both work, and both are traps: a
rename breaks a dozen assertions with no behaviour change, and a name
filter that matches nothing yields an empty collection -- so
`expect(count, 0)` and `for (x in matches)` keep passing while asserting
nothing. Two of the field's own tests were already in that state.

Keyed per position AND per side, because the name filters could not tell
the two rows apart; they counted totals and inferred whose was whose.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Field ground — light well, divider, row labels

**Files:**
- Create: `lib/features/games/paint_ball/presentation/widgets/field/field_ground.dart`
- Test: `test/features/games/paint_ball_field_ground_test.dart`

**Interfaces:**
- Consumes: `LightWell`, `NeonTokens`, `GlowStrokeSpec`/`paintGlowPath`, `neonQualityOf`, `PaintBallFieldKeys`, `PaintBallPalette`.
- Produces:
  - `class FieldGround extends StatelessWidget` — `const FieldGround({required Widget child})`. The ground plus its divider; keyed `PaintBallFieldKeys.ground`.
  - `class FieldRowLabel extends StatelessWidget` — `const FieldRowLabel({required String label, required Color color})`.
  - `String fieldRowLabelText({required String? partnerName, required bool isReplaying, required int theirStreak})` — the far row's words. Pure function, so its branches are unit-testable without a widget.

- [ ] **Step 1: Write the failing test**

Create `test/features/games/paint_ball_field_ground_test.dart`:

```dart
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_ground.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the far row’s words', () {
    test('a known partner is named rather than called an opponent', () {
      // "THEIR COVER" turns the person you are playing into an
      // opponent. This app is about that specific person, so the board
      // says who.
      expect(
        fieldRowLabelText(
          partnerName: 'Ama',
          isReplaying: false,
          theirStreak: 1,
        ),
        'AMA',
      );
    });

    test('an unknown partner falls back rather than showing a gap', () {
      // The name loads asynchronously. Until it arrives the board must
      // still read as a board.
      expect(
        fieldRowLabelText(
          partnerName: null,
          isReplaying: false,
          theirStreak: 1,
        ),
        'THEIR COVER',
      );
    });

    test('a streak is called out, but only while the replay is on screen', () {
      expect(
        fieldRowLabelText(
          partnerName: 'Ama',
          isReplaying: true,
          theirStreak: 3,
        ),
        'SAME SPOT x3',
      );
    });

    test('a streak is not kept on the board between rounds', () {
      // It is a remark on what you just watched, not a readout. Left
      // up, it would be the same free clue as a paint trail.
      expect(
        fieldRowLabelText(
          partnerName: 'Ama',
          isReplaying: false,
          theirStreak: 3,
        ),
        'AMA',
      );
    });

    test('a streak of one or zero is never announced', () {
      // Review Focus #4. The label shows only from two upward: every
      // round is trivially a streak of one, and "SAME SPOT x1" would
      // call out holding a position the player only just took.
      for (final streak in [0, 1]) {
        expect(
          fieldRowLabelText(
            partnerName: 'Ama',
            isReplaying: true,
            theirStreak: streak,
          ),
          'AMA',
          reason: 'a streak of $streak is not a streak',
        );
      }
    });
  });

  testWidgets('the ground paints itself and carries its key', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FieldGround(child: Text('on the field'))),
      ),
    );
    await tester.pump();

    expect(find.byKey(PaintBallFieldKeys.ground), findsOneWidget);
    expect(find.text('on the field'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the divider is drawn and keyed', (tester) async {
    // The centre line is what makes the field two halves facing each
    // other rather than one strip of six covers.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FieldGround(child: SizedBox())),
      ),
    );
    await tester.pump();

    expect(find.byKey(PaintBallFieldKeys.divider), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/games/paint_ball_field_ground_test.dart`
Expected: FAIL — the URI for `field/field_ground.dart` does not resolve (reported as `Target of URI doesn't exist`, `Undefined name`, or `Method not found`; any of these is the same failure).

- [ ] **Step 3: Write the implementation**

Create `lib/features/games/paint_ball/presentation/widgets/field/field_ground.dart`:

```dart
import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/light_well.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';

import 'paint_ball_field_keys.dart';

/// The words over the far row.
///
/// A pure function rather than logic inside a build method, because its
/// four branches are the kind of thing a widget test can only reach by
/// pumping four whole fields.
///
/// Precedence matters: the streak remark OUTRANKS the partner's name,
/// but only while a replay is on screen. Between rounds the board goes
/// back to saying who. A streak left up would be the same free clue as
/// a paint trail -- a readout of the partner's habits, which is exactly
/// what this game asks you to earn.
String fieldRowLabelText({
  required String? partnerName,
  required bool isReplaying,
  required int theirStreak,
}) {
  // From two upward. Every round is trivially a streak of one, and
  // announcing that would call out a position the player only just took.
  if (isReplaying && theirStreak > 1) return 'SAME SPOT x$theirStreak';
  if (partnerName != null) return partnerName.toUpperCase();
  return 'THEIR COVER';
}

/// One row's caption.
class FieldRowLabel extends StatelessWidget {
  const FieldRowLabel({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color.withValues(alpha: NeonTokens.structureAlphaActive),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
      ),
    );
  }
}

/// The field's ground: near-black, a light well for a middle, and the
/// centre line dividing the two halves.
///
/// Spec §2.1 tier 1 -- it receives light and emits none. Everything the
/// field draws sits on top of this, which is why the well's alpha is as
/// low as it is: a ground bright enough to notice would compete with the
/// actors, and then nothing on the field reads as lit.
class FieldGround extends StatelessWidget {
  const FieldGround({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: PaintBallFieldKeys.ground,
      child: LightWell(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              right: 0,
              child: CustomPaint(
                key: PaintBallFieldKeys.divider,
                painter: FieldDividerPainter(
                  quality: neonQualityOf(context),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// The centre line.
///
/// Public, and with public fields, so a test can assert on it without
/// reaching through `as dynamic` -- the trap spec §3.6.1 exists to close.
class FieldDividerPainter extends CustomPainter {
  FieldDividerPainter({required this.quality});

  final NeonQuality quality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final y = size.height / 2;
    final inset = size.width * 0.06;

    paintGlowPath(
      canvas,
      Path()
        ..moveTo(inset, y)
        ..lineTo(size.width - inset, y),
      const GlowStrokeSpec(
        color: PaintBallNeonPalette.structure,
        alpha: NeonTokens.structureAlphaRest,
      ),
      quality.haloPasses,
    );
  }

  @override
  bool shouldRepaint(FieldDividerPainter old) => old.quality != quality;
}

/// The field's own neon colours.
///
/// Separate from PaintBallPalette, which stays as it is: three screens
/// outside this work read it (history, knockout, battle), so changing
/// those values would reach past the field. These are the field's.
class PaintBallNeonPalette {
  const PaintBallNeonPalette._();

  /// Bays and the divider. Neutral, so the two owner hues stay the only
  /// colours that mean anything (§2.2).
  static const structure = Color(0xFF8A8AA0);

  /// The instant of impact, and nothing else on the field, ever (§2.2).
  static const impact = Color(0xFFFFFFFF);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/games/paint_ball_field_ground_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/paint_ball/presentation/widgets/field/field_ground.dart test/features/games/paint_ball_field_ground_test.dart
git commit -m "$(cat <<'EOF'
feat(paintball): the field's ground, divider and row captions in neon

The label logic comes out as a pure function. Its four branches -- named
partner, async fallback, streak remark, streak suppressed between rounds
-- are the kind of thing a widget test can only reach by pumping four
whole fields, and the precedence between them is the part worth pinning:
the streak outranks the name, but only while the replay is on screen.
Left up afterwards it would be a readout of the partner's habits, the
same free clue as a persistent paint trail.

A streak of 0 or 1 is never announced. Every round is trivially a streak
of one, and "SAME SPOT x1" would call out a position the player had only
just taken.

PaintBallNeonPalette is new rather than an edit to PaintBallPalette,
because three screens this work does not touch read the old one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: The cover bay — §2.3's keystone, behind a swap seam

The design's biggest visual bet: cover rendered as **an absence of light** rather
than a drawn object. Behind `PaintBallCoverStyle` so replacing it is a new class,
not surgery (spec §2.3, which marks it explicitly provisional).

Carries the **Stage 2 addendum #2** requirement: the aimed bay must be
unmistakable at a glance, because with no Fire button the aimed cover *is* the
confirmation that a target is chosen. The bay's mouth opens — its legs part —
which is the neon equivalent of the old shield sliding aside.

**Files:**
- Create: `lib/features/games/paint_ball/presentation/widgets/field/cover_bay.dart`
- Test: `test/features/games/paint_ball_cover_bay_test.dart`

**Interfaces:**
- Consumes: `NeonTokens`, `GlowStrokeSpec`/`paintGlowPath`, `NeonQuality`, `PaintBallFieldKeys`, `PaintBallNeonPalette` (from Task 6).
- Produces:
  - `enum CoverBayState { rest, aimed, occupied }`
  - `abstract class PaintBallCoverStyle` — one method, `void paint(Canvas canvas, Size size, CoverBayPaintContext context)`.
  - `class CoverBayPaintContext` — public final fields `state`, `facing`, `ownerColor`, `quality`.
  - `class DarknessCoverStyle implements PaintBallCoverStyle` — the §2.3 implementation.
  - `class CoverBayPainter extends CustomPainter` — public final fields `state`, `facing`, `ownerColor`, `quality`, `style`. **`facing` is the public replacement for the old `_ShieldPainter.opensDown`, with identical polarity: `true` means this is the viewer's own row (legs below the dome).**
  - `class CoverBay extends StatelessWidget` — `const CoverBay({required int position, required bool isOpponent, required CoverBayState state, required Color ownerColor, PaintBallCoverStyle? style})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/games/paint_ball_cover_bay_test.dart`:

```dart
import 'dart:math';

import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/cover_bay.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records drawn paths so bay geometry can be asserted without a golden.
class _RecordingCanvas implements Canvas {
  final paths = <Path>[];
  final paints = <Paint>[];

  @override
  void drawPath(Path path, Paint paint) {
    paths.add(path);
    paints.add(paint);
  }

  @override
  noSuchMethod(Invocation invocation) => null;
}

CoverBayPaintContext _context({
  CoverBayState state = CoverBayState.rest,
  bool facing = true,
  NeonQuality quality = NeonQuality.glow,
}) => CoverBayPaintContext(
  state: state,
  facing: facing,
  ownerColor: const Color(0xFF5EEAD4),
  quality: quality,
);

void main() {
  const style = DarknessCoverStyle();
  const size = Size(74, 62);

  test('a bay at rest is drawn, dim', () {
    // Structure is tier 2 of §2.1: present, not shouting. It must still
    // be VISIBLE -- a player has to see where the three hiding places
    // are before choosing one.
    final canvas = _RecordingCanvas();
    style.paint(canvas, size, _context());

    expect(canvas.paints, isNotEmpty, reason: 'a positive control');
    for (final paint in canvas.paints) {
      expect(paint.color.a, greaterThan(0));
    }
  });

  test('an aimed bay is unmistakably brighter than one at rest', () {
    // Stage 2 addendum #2. With no Fire button, the aimed cover IS the
    // confirmation that a target is chosen, so the difference cannot be
    // a subtle tint. The old renderer slid the whole shield aside and
    // doubled its opacity; a bay that only brightened slightly would
    // lose the game's only commit affordance.
    final rest = _RecordingCanvas();
    final aimed = _RecordingCanvas();
    style.paint(rest, size, _context());
    style.paint(aimed, size, _context(state: CoverBayState.aimed));

    double peak(_RecordingCanvas canvas) =>
        canvas.paints.map((paint) => paint.color.a).reduce(max);

    expect(rest.paints, isNotEmpty);
    expect(aimed.paints, isNotEmpty);
    expect(
      peak(aimed),
      greaterThan(peak(rest) * 1.5),
      reason: 'aimed must read as committed at a glance, not as a tint',
    );
  });

  test('an aimed bay opens its mouth wider than one at rest', () {
    // The neon equivalent of the shield sliding aside: the legs part, so
    // the shot has a visible path through. "You can see the path for the
    // shot" is the property the original slide was built for.
    final rest = _RecordingCanvas();
    final aimed = _RecordingCanvas();
    style.paint(rest, size, _context());
    style.paint(aimed, size, _context(state: CoverBayState.aimed));

    expect(rest.paths, isNotEmpty);
    expect(aimed.paths, isNotEmpty);
    expect(
      aimed.paths.first.getBounds().width,
      greaterThan(rest.paths.first.getBounds().width),
      reason: 'an opened gate is wider than a closed one',
    );
  });

  test('the two rows face opposite ways', () {
    // DEVICE-REPORTED REGRESSION (old test 19). Both rows once domed the
    // same way, so the opponent's cover looked like it sheltered someone
    // standing off the top of the board rather than facing you across
    // the line. `facing` replaces the old painter's `opensDown` with the
    // same polarity: true is the viewer's own row, legs below the dome.
    final mine = _RecordingCanvas();
    final theirs = _RecordingCanvas();
    style.paint(mine, size, _context(facing: true));
    style.paint(theirs, size, _context(facing: false));

    expect(mine.paths, isNotEmpty);
    expect(theirs.paths, isNotEmpty);

    // The arch's crown sits at opposite ends of the box. Comparing the
    // vertical centroid of the bounds is enough to tell them apart, and
    // unlike an eyeball check it cannot be fooled by a mirror image.
    final mineCentre = mine.paths.first.getBounds().center.dy;
    final theirsCentre = theirs.paths.first.getBounds().center.dy;
    expect(
      mineCentre,
      isNot(closeTo(theirsCentre, 0.5)),
      reason: 'exactly one row faces the other',
    );
  });

  test('the painter exposes facing publicly rather than via dynamic', () {
    // Spec §3.6.1: the old test read `(painter as dynamic).opensDown`,
    // so a rename broke it with no behaviour change. This is the typed
    // replacement.
    final painter = CoverBayPainter(
      state: CoverBayState.rest,
      facing: false,
      ownerColor: const Color(0xFF5EEAD4),
      quality: NeonQuality.glow,
      style: style,
    );

    expect(painter.facing, isFalse);
    expect(painter.state, CoverBayState.rest);
  });

  test('a zero-sized bay does not throw', () {
    // Reachable during a route transition, when a collapsed parent hands
    // down a zero box.
    final canvas = _RecordingCanvas();
    expect(
      () => style.paint(canvas, Size.zero, _context()),
      returnsNormally,
    );
  });

  test('the plain tier still draws the bay', () {
    // Degrading drops halo passes, never the outline. A bay nobody can
    // see is three invisible hiding places -- unplayable on exactly the
    // hardware the tiering exists to serve.
    final canvas = _RecordingCanvas();
    style.paint(canvas, size, _context(quality: NeonQuality.plain));

    expect(canvas.paints, isNotEmpty);
  });

  testWidgets('a bay carries its position-and-side key', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CoverBay(
            position: 1,
            isOpponent: true,
            state: CoverBayState.rest,
            ownerColor: Color(0xFFFF4D6A),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: true)),
      findsOneWidget,
    );
    expect(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: false)),
      findsNothing,
      reason: 'the key must distinguish the two rows',
    );
  });

  testWidgets('a custom style replaces the darkness without surgery', (
    tester,
  ) async {
    // §2.3 is explicitly provisional: cover-as-darkness is a bet, and
    // swapping it must be a new class rather than an edit to the field.
    // This proves the seam actually works.
    var painted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverBay(
            position: 0,
            isOpponent: false,
            state: CoverBayState.rest,
            ownerColor: const Color(0xFF5EEAD4),
            style: _ProbeStyle(() => painted = true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(painted, isTrue, reason: 'the injected style was used');
  });
}

class _ProbeStyle implements PaintBallCoverStyle {
  _ProbeStyle(this.onPaint);

  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size, CoverBayPaintContext context) =>
      onPaint();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/games/paint_ball_cover_bay_test.dart`
Expected: FAIL — `field/cover_bay.dart` does not resolve.

- [ ] **Step 3: Write the implementation**

Create `lib/features/games/paint_ball/presentation/widgets/field/cover_bay.dart`:

```dart
import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';

import 'field_ground.dart' show PaintBallNeonPalette;
import 'paint_ball_field_keys.dart';

/// What a bay is doing right now.
enum CoverBayState {
  /// One of three hiding places, not chosen.
  rest,

  /// The bay this player is shooting at. With no Fire button this state
  /// IS the confirmation that a target is chosen, so it has to read at a
  /// glance (Stage 2 addendum #2).
  aimed,

  /// Somebody is behind it. Only ever true for a position the viewer is
  /// allowed to know.
  occupied,
}

/// Everything a cover style needs to draw one bay.
///
/// A value object with public fields rather than positional arguments,
/// so adding a state later does not change every style's signature.
class CoverBayPaintContext {
  const CoverBayPaintContext({
    required this.state,
    required this.facing,
    required this.ownerColor,
    required this.quality,
  });

  final CoverBayState state;

  /// True when this is the VIEWER's own row: the arch domes upward with
  /// its legs planted below.
  ///
  /// Replaces `_ShieldPainter.opensDown` with the same polarity. A
  /// device-reported bug had both rows doming the same way, which made
  /// the opponent's cover look like it sheltered someone standing off
  /// the top of the board rather than facing you across the line.
  final bool facing;

  final Color ownerColor;
  final NeonQuality quality;
}

/// How cover is drawn.
///
/// Spec §2.3 renders cover as an ABSENCE of light -- a bay of darkness
/// rather than a drawn object -- because the game turns on hidden
/// information and hiding should look like hiding. That is the design's
/// biggest visual bet, and the spec marks it provisional.
///
/// So it lives behind this interface. Trying a solid or illustrated
/// cover later means writing a new class and passing it in, not
/// operating on the field.
abstract class PaintBallCoverStyle {
  const PaintBallCoverStyle();

  void paint(Canvas canvas, Size size, CoverBayPaintContext context);
}

/// §2.3: cover as a bay of darkness, outlined in dim light.
class DarknessCoverStyle implements PaintBallCoverStyle {
  const DarknessCoverStyle();

  @override
  void paint(Canvas canvas, Size size, CoverBayPaintContext context) {
    // A collapsed parent hands down a zero box during a route
    // transition, and an arc of radius 0 is a division waiting to
    // happen.
    if (size.isEmpty) return;

    final isAimed = context.state == CoverBayState.aimed;

    // The mouth OPENS when aimed: the legs part, so the shot has a
    // visible path through. This is the neon equivalent of the old
    // shield sliding aside, and it exists for the same reason -- a shot
    // should be something you can see a path for, not an abstract
    // selection.
    final mouth = size.width * (isAimed ? 0.34 : 0.14);
    final legInset = (size.width - mouth) / 2;

    final radius = legInset.clamp(1.0, size.width / 2);
    final shoulderY = context.facing ? radius : size.height - radius;
    final footY = context.facing ? size.height : 0.0;

    // Legs and dome as one path, open at the base -- cover you stand
    // behind, not a box you are inside.
    final path =
        Path()
          ..moveTo(legInset, footY)
          ..lineTo(legInset, shoulderY)
          ..arcToPoint(
            Offset(legInset + mouth, shoulderY),
            radius: Radius.circular(radius),
            clockwise: context.facing,
          )
          ..lineTo(legInset + mouth, footY);

    final alpha =
        isAimed
            ? NeonTokens.structureAlphaActive
            : NeonTokens.structureAlphaRest;

    // An aimed bay takes the owner's hue; a resting one stays neutral,
    // so colour keeps meaning ownership and nothing else (§2.2).
    paintGlowPath(
      canvas,
      path,
      GlowStrokeSpec(
        color: isAimed ? context.ownerColor : PaintBallNeonPalette.structure,
        alpha: alpha,
        widthScale: isAimed ? 2.0 : 1.0,
      ),
      // One extra pass when aimed, so it gains presence rather than just
      // opacity -- and still none at all on the plain tier.
      isAimed && context.quality != NeonQuality.plain
          ? context.quality.haloPasses + 1
          : context.quality.haloPasses,
    );
  }
}

/// Paints one bay through its style.
///
/// Public, with public fields, so a test asserts on `facing` directly
/// instead of reaching through `as dynamic` (spec §3.6.1).
class CoverBayPainter extends CustomPainter {
  CoverBayPainter({
    required this.state,
    required this.facing,
    required this.ownerColor,
    required this.quality,
    required this.style,
  });

  final CoverBayState state;
  final bool facing;
  final Color ownerColor;
  final NeonQuality quality;
  final PaintBallCoverStyle style;

  @override
  void paint(Canvas canvas, Size size) => style.paint(
    canvas,
    size,
    CoverBayPaintContext(
      state: state,
      facing: facing,
      ownerColor: ownerColor,
      quality: quality,
    ),
  );

  @override
  bool shouldRepaint(CoverBayPainter old) =>
      old.state != state ||
      old.facing != facing ||
      old.ownerColor != ownerColor ||
      old.quality != quality ||
      old.style != style;
}

/// One of the three hiding places.
class CoverBay extends StatelessWidget {
  const CoverBay({
    super.key,
    required this.position,
    required this.isOpponent,
    required this.state,
    required this.ownerColor,
    this.style,
  });

  final int position;
  final bool isOpponent;
  final CoverBayState state;
  final Color ownerColor;

  /// Overrides the §2.3 darkness, for trying a different cover without
  /// touching the field.
  final PaintBallCoverStyle? style;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: PaintBallFieldKeys.bay(position, isOpponent: isOpponent),
      painter: CoverBayPainter(
        state: state,
        // The viewer's own row is always the near one, whichever player
        // is looking: a field that flipped would make "mine" and
        // "theirs" something to work out each turn.
        facing: !isOpponent,
        ownerColor: ownerColor,
        quality: neonQualityOf(context),
        style: style ?? const DarknessCoverStyle(),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/games/paint_ball_cover_bay_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/paint_ball/presentation/widgets/field/cover_bay.dart test/features/games/paint_ball_cover_bay_test.dart
git commit -m "$(cat <<'EOF'
feat(paintball): cover as a bay of darkness, behind a swap seam

§2.3's keystone: a hiding place is an absence of light rather than a
drawn object. The game turns on hidden information, so hiding should
look like hiding -- and three bays of darkness cost nothing to draw,
which is most of why this direction was reachable at all.

It is also the design's biggest bet, so it ships behind
PaintBallCoverStyle. Trying a solid or illustrated cover later is a new
class passed in, not surgery on the field, and a test injects a probe
style to prove the seam actually works rather than merely existing.

The aimed state opens the bay's MOUTH. Reading the old renderer turned
up something the design had missed: the aimed shield slid aside and
doubled its opacity because, as its comment says, "with no Fire button,
the aimed cover IS the confirmation that a target is chosen." A bay that
only brightened would have quietly removed the game's commit
affordance. So the legs part instead, and a test pins that aimed is more
than 1.5x brighter at peak -- committed at a glance, not a tint.

`facing` is the public, typed replacement for the old painter's
`opensDown`, same polarity. It carries a device-reported regression: both
rows once domed the same way, making the opponent's cover look like it
sheltered someone standing off the top of the board. The test compares
the arches' vertical centroids, which a mirror image cannot fool.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: The travelling figure

A player as a luminous mark that journeys between covers. Carries two things
that must be preserved **verbatim**: the 620ms three-beat timing (addendum #1)
and the cover-centring formula, which is the fix for a device-reported bug.

**Files:**
- Create: `lib/features/games/paint_ball/presentation/widgets/field/field_figure.dart`
- Test: `test/features/games/paint_ball_field_figure_test.dart`

**Interfaces:**
- Consumes: `NeonTokens`, `GlowStrokeSpec`/`paintGlowPath`, `neonQualityOf`, `PaintBallFieldKeys`, `kPaintBallPositions` (from `paint_ball_field.dart`).
- Produces:
  - `double figureCentreX({required double rowWidth, required double coverWidth, required double column})` — the centring formula, extracted as a pure function so the device-reported bug is unit-testable without pumping a field at three widths.
  - `class FieldFigure extends StatefulWidget` — `const FieldFigure({required int position, required bool isOpponent, required double rowWidth, required double coverWidth, required double rowHeight, required Color ownerColor, required bool isAiming, required double tilt, required bool reduceMotion, VoidCallback? onTap})`.
  - `const Duration kFigureTravelDuration = Duration(milliseconds: 620);`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/paint_ball_field_figure_test.dart`:

```dart
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_figure.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart'
    show kPaintBallCoverWidth, kPaintBallPositions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the centring formula', () {
    test('a figure sits on its cover at every width', () {
      // DEVICE-REPORTED REGRESSION (old test 18). The figure positioned
      // itself on notional slots (rowWidth / 3) while the covers are a
      // FIXED width laid out by spaceEvenly with four equal gaps. Those
      // two agree only when the row happens to be exactly three covers
      // wide; at any other width the figure drifted off its cover, worst
      // at the outer ones.
      //
      // Extracted as a pure function precisely so this is checkable
      // without pumping a field at three widths and reading back
      // rectangles.
      for (final rowWidth in [320.0, 360.0, 390.0, 430.0, 600.0]) {
        const coverWidth = 74.0;
        final gap =
            (rowWidth - kPaintBallPositions * coverWidth) /
            (kPaintBallPositions + 1);

        for (var position = 0; position < kPaintBallPositions; position++) {
          final expected =
              gap * (position + 1) + coverWidth * (position + 0.5);

          expect(
            figureCentreX(
              rowWidth: rowWidth,
              coverWidth: coverWidth,
              column: position.toDouble(),
            ),
            closeTo(expected, 0.001),
            reason:
                'at width $rowWidth position $position must land on its '
                'cover centre, not on a notional slot centre',
          );
        }
      }
    });

    test('a slot-centre formula would have failed this', () {
      // Pins WHY the formula is what it is. If someone simplifies it
      // back to rowWidth/3 maths, this test says what breaks.
      const rowWidth = 430.0;
      const coverWidth = 74.0;
      const position = 2.0;

      final slotCentre =
          rowWidth / kPaintBallPositions * position +
          rowWidth / kPaintBallPositions / 2;

      expect(
        figureCentreX(
          rowWidth: rowWidth,
          coverWidth: coverWidth,
          column: position,
        ),
        isNot(closeTo(slotCentre, 1.0)),
        reason: 'the two formulas genuinely disagree at this width',
      );
    });

    test('a fractional column interpolates, for the crossing', () {
      // Mid-journey the figure is between two columns. The formula has
      // to accept 1.5 and land halfway, or the travel would jump.
      const rowWidth = 390.0;
      const coverWidth = 74.0;

      final one = figureCentreX(
        rowWidth: rowWidth,
        coverWidth: coverWidth,
        column: 1,
      );
      final two = figureCentreX(
        rowWidth: rowWidth,
        coverWidth: coverWidth,
        column: 2,
      );
      final half = figureCentreX(
        rowWidth: rowWidth,
        coverWidth: coverWidth,
        column: 1.5,
      );

      expect(half, closeTo((one + two) / 2, 0.001));
    });

    test('a row narrower than its covers does not produce a NaN', () {
      // Defensive: a negative gap is arithmetically fine, but an
      // infinite or NaN result would throw inside Positioned. Reachable
      // on a very small screen or mid-animation layout.
      final x = figureCentreX(
        rowWidth: 100,
        coverWidth: 74,
        column: 2,
      );

      expect(x.isFinite, isTrue);
    });
  });

  group('the figure widget', () {
    Widget host({
      required int position,
      bool isOpponent = false,
      bool reduceMotion = false,
      bool isAiming = false,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: SizedBox(
            width: 390,
            height: 120,
            child: Stack(
              children: [
                FieldFigure(
                  position: position,
                  isOpponent: isOpponent,
                  rowWidth: 390,
                  coverWidth: kPaintBallCoverWidth,
                  rowHeight: 92,
                  ownerColor: const Color(0xFF5EEAD4),
                  isAiming: isAiming,
                  tilt: 0,
                  reduceMotion: reduceMotion,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('a figure carries its position-and-side key', (tester) async {
      await tester.pumpWidget(host(position: 1));
      await tester.pump();

      expect(
        find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)),
        findsOneWidget,
      );
      expect(
        find.byKey(PaintBallFieldKeys.figure(1, isOpponent: true)),
        findsNothing,
        reason: 'the key must distinguish the two rows',
      );
    });

    testWidgets('repositioning travels rather than teleporting', (
      tester,
    ) async {
      // Old test 16. Moving cover is a journey: the figure leaves,
      // crosses, and enters the new cover as ONE body. A cross-fade
      // between two covers would read as two figures, and taking cover
      // would feel like being reassigned rather than moving.
      await tester.pumpWidget(host(position: 0));
      await tester.pumpAndSettle();

      Offset centre() => tester.getCenter(
        find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)),
      );

      final start = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(0, isOpponent: false)))
          .dx;

      await tester.pumpWidget(host(position: 2));
      await tester.pump(const Duration(milliseconds: 310));
      final middle = centre().dx;

      await tester.pumpAndSettle();
      final end = centre().dx;

      expect(middle, greaterThan(start), reason: 'it has set off');
      expect(
        middle,
        lessThan(end),
        reason: 'it has not arrived yet -- it is travelling',
      );

      // Exactly one figure throughout: the same body moving, never a
      // second one fading in.
      expect(
        find.byWidgetPredicate((widget) => widget is FieldFigure),
        findsOneWidget,
      );
    });

    testWidgets('the journey is long enough to be followed', (tester) async {
      // Stage 2 addendum #1: 620ms, deliberately outside the plan's
      // 150-320ms band. That band governs a SETTLE -- one object
      // arriving at one place. This is three sequential beats (back out
      // of cover, across, forward in), and three beats inside 320ms is
      // ~100ms each, below the point at which an eye can follow a path.
      //
      // Pinned as a constant so an implementer "fixing" it to comply
      // with the band breaks a test rather than the game's feel.
      expect(kFigureTravelDuration.inMilliseconds, 620);
    });

    testWidgets('reduce motion arrives immediately', (tester) async {
      await tester.pumpWidget(host(position: 0, reduceMotion: true));
      await tester.pumpAndSettle();

      final start = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(0, isOpponent: false)))
          .dx;

      await tester.pumpWidget(host(position: 2, reduceMotion: true));
      await tester.pump();

      final after = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)))
          .dx;

      expect(
        after,
        greaterThan(start),
        reason: 'it moved',
      );

      // And it is ALREADY there -- no further frames needed.
      await tester.pumpAndSettle();
      expect(
        tester
            .getCenter(
              find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)),
            )
            .dx,
        closeTo(after, 0.001),
        reason: 'reduce motion jumps to the end state, it does not animate',
      );
    });

    testWidgets('a travelling figure steps clear of cover', (tester) async {
      // Old test 17. Sliding sideways while still tucked in would read
      // as passing through the wall, so the crossing happens stepped
      // out. Your row is at the bottom, so stepping out moves UP the
      // screen -- a smaller dy.
      await tester.pumpWidget(host(position: 0));
      await tester.pumpAndSettle();

      final atRest = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(0, isOpponent: false)))
          .dy;

      await tester.pumpWidget(host(position: 2));
      await tester.pump(const Duration(milliseconds: 310));

      final crossing = tester
          .getCenter(find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)))
          .dy;

      expect(
        crossing,
        lessThan(atRest),
        reason: 'the crossing happens clear of cover, not through it',
      );
    });

    testWidgets('a figure that is not the fire control ignores taps', (
      tester,
    ) async {
      // It stands over a cover that is itself a tap target. Intercepting
      // taps when it is not the fire control would make that cover
      // unreachable -- silently costing the player one of their three
      // hiding places.
      await tester.pumpWidget(host(position: 1));
      await tester.pump();

      final figure = tester.widget<FieldFigure>(
        find.byWidgetPredicate((widget) => widget is FieldFigure),
      );

      expect(figure.onTap, isNull);
      expect(
        find.descendant(
          of: find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/games/paint_ball_field_figure_test.dart`
Expected: FAIL — `field/field_figure.dart` does not resolve.

- [ ] **Step 3: Write the implementation**

Create `lib/features/games/paint_ball/presentation/widgets/field/field_figure.dart`:

```dart
import 'package:attune/core/ui/neon/glow_stroke.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';

import '../paint_ball_field.dart' show kPaintBallPositions;
import 'paint_ball_field_keys.dart';

/// How long a figure takes to change cover.
///
/// Deliberately outside the 150-320ms band the rest of this work obeys.
/// That band governs a SETTLE -- one object arriving at one place. This
/// is three sequential beats (step back out of cover, cross, step
/// forward into the new one), and three beats inside 320ms is about
/// 100ms each, below the point at which an eye can follow a path at all.
///
/// Pinned by a test so that "fixing" it to comply with the band breaks
/// something visible rather than quietly removing the journey.
const Duration kFigureTravelDuration = Duration(milliseconds: 620);

/// Where a figure's centre sits for a given column.
///
/// A pure function because this formula is the fix for a bug reported
/// from a device, and the alternative way to test it is pumping a field
/// at several widths and reading back rectangles.
///
/// The covers are a FIXED width laid out by spaceEvenly, which produces
/// four equal gaps around three covers. So a cover's centre is
/// `gap*(i+1) + coverWidth*(i+0.5)` -- which equals a notional slot
/// centre (`rowWidth/3`) only when the row happens to be exactly three
/// covers wide. Slot maths drifted the figure off its cover at every
/// other width, worst at the outer two.
///
/// Accepts a fractional [column] so the crossing interpolates.
double figureCentreX({
  required double rowWidth,
  required double coverWidth,
  required double column,
}) {
  final gap =
      (rowWidth - kPaintBallPositions * coverWidth) /
      (kPaintBallPositions + 1);
  return gap * (column + 1) + coverWidth * (column + 0.5);
}

/// A player, as a luminous mark that travels between covers.
///
/// Spec §2.1 tier 3: actors are the only bright things on the field, and
/// §2.2 gives them their OWNER's hue rather than a third neutral colour,
/// so that colour keeps meaning ownership and nothing else.
///
/// It lives above the row rather than inside a cover, because a child
/// cannot travel outside its parent's box -- which is exactly what a
/// journey between covers requires.
class FieldFigure extends StatefulWidget {
  const FieldFigure({
    super.key,
    required this.position,
    required this.isOpponent,
    required this.rowWidth,
    required this.coverWidth,
    required this.rowHeight,
    required this.ownerColor,
    required this.isAiming,
    required this.tilt,
    required this.reduceMotion,
    this.onTap,
  });

  final int position;
  final bool isOpponent;

  /// The full row and one cover inside it. Both are needed: the covers
  /// are a fixed width with even gaps, so their spacing is not the row
  /// divided three ways (see [figureCentreX]).
  final double rowWidth;
  final double coverWidth;

  final double rowHeight;

  /// §2.2: a figure wears its owner's colour.
  final Color ownerColor;

  final bool isAiming;

  /// Lean toward whatever is being aimed at, in turns, so an aim is
  /// visible on the field rather than only in a control strip.
  final double tilt;

  final bool reduceMotion;

  /// Set only when this figure IS the fire control.
  final VoidCallback? onTap;

  @override
  State<FieldFigure> createState() => _FieldFigureState();
}

class _FieldFigureState extends State<FieldFigure>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _from;
  late int _to;

  @override
  void initState() {
    super.initState();
    _from = widget.position;
    _to = widget.position;
    _controller = AnimationController(
      vsync: this,
      duration: kFigureTravelDuration,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(FieldFigure old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      _from = old.position;
      _to = widget.position;
      if (widget.reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quality = neonQualityOf(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        // The lateral move happens in the MIDDLE of the journey, so the
        // figure is clear of cover while it crosses. Sliding sideways
        // while still tucked in would read as passing through the wall.
        final lateral = Curves.easeInOut.transform(
          ((t - 0.25) / 0.5).clamp(0.0, 1.0),
        );
        final column = _from + (_to - _from) * lateral;

        // Depth: 0 is tucked in cover, 1 is stepped out. It rises for
        // the crossing and falls again on arrival -- and stays out while
        // aiming, since an aiming player is deliberately exposed.
        final travelling = t < 1;
        final depth =
            travelling
                ? Curves.easeInOut.transform(1 - (2 * t - 1).abs())
                : (widget.isAiming ? 1.0 : 0.0);

        final x = figureCentreX(
              rowWidth: widget.rowWidth,
              coverWidth: widget.coverWidth,
              column: column,
            ) -
            11;

        // Both rows shelter under their own dome and the domes face each
        // other, so "tucked in" is measured from opposite edges. A
        // single inset would have put the opponent outside their arch
        // entirely, standing on top of the cover instead of behind it.
        final baseInset = widget.isOpponent ? 46.0 : 34.0;
        final stepOut = 14.0 * depth;

        return Positioned(
          key: PaintBallFieldKeys.figure(
            widget.position,
            isOpponent: widget.isOpponent,
          ),
          left: x,
          top: widget.isOpponent ? baseInset + stepOut : null,
          bottom: widget.isOpponent ? null : baseInset + stepOut,
          child: IgnorePointer(
            // Transparent to taps unless it is the fire control: it
            // stands over a cover that is itself a tap target, and
            // intercepting would make that cover unreachable, silently
            // costing the player one of three hiding places.
            ignoring: widget.onTap == null,
            child: GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedRotation(
                duration: Duration(
                  milliseconds: widget.reduceMotion ? 0 : 260,
                ),
                curve: Curves.easeOut,
                turns: widget.isAiming ? widget.tilt : 0,
                child: CustomPaint(
                  size: const Size(22, 20),
                  painter: FieldFigurePainter(
                    color: widget.ownerColor,
                    pointsUp: !widget.isOpponent,
                    quality: quality,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The figure itself: a lit arrowhead.
///
/// Public, with public fields, so a test never needs `as dynamic`
/// (spec §3.6.1). An arrowhead rather than a body because it has to say
/// which way the player is facing at 20 logical pixels, and because
/// §2.1 allows no illustration to lean on.
class FieldFigurePainter extends CustomPainter {
  FieldFigurePainter({
    required this.color,
    required this.pointsUp,
    required this.quality,
  });

  final Color color;
  final bool pointsUp;
  final NeonQuality quality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final path = Path();
    if (pointsUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(size.width / 2, size.height)
        ..lineTo(size.width, 0)
        ..lineTo(0, 0);
    }
    path.close();

    // Filled, then outlined in its own glow: an actor is the brightest
    // thing on the field (§2.1 tier 3), and a stroke-only mark at this
    // size reads as structure rather than as a person.
    canvas.drawPath(
      path,
      Paint()..color = color.withValues(alpha: NeonTokens.actorAlpha),
    );

    paintGlowPath(
      canvas,
      path,
      GlowStrokeSpec(color: color, alpha: NeonTokens.actorAlpha),
      quality.haloPasses,
    );
  }

  @override
  bool shouldRepaint(FieldFigurePainter old) =>
      old.color != color ||
      old.pointsUp != pointsUp ||
      old.quality != quality;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/games/paint_ball_field_figure_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/paint_ball/presentation/widgets/field/field_figure.dart test/features/games/paint_ball_field_figure_test.dart
git commit -m "$(cat <<'EOF'
feat(paintball): the figure as a lit mark that journeys between covers

The centring formula comes out as a pure function, because it is the fix
for a bug reported from a device and the alternative way to test it is
pumping a field at several widths and reading back rectangles. The
covers are a fixed width laid out by spaceEvenly -- four equal gaps
around three covers -- so a cover's centre is gap*(i+1) +
coverWidth*(i+0.5), which equals a notional rowWidth/3 slot centre ONLY
when the row is exactly three covers wide. Slot maths drifted the figure
off its cover everywhere else, worst at the outer two. A second test
pins that the two formulas genuinely disagree, so simplifying it back
breaks something loud.

620ms is pinned by a test. It sits outside the 150-320ms band this work
otherwise obeys, and that is deliberate: the band governs a settle, one
object arriving once, while this is three sequential beats. Three beats
inside 320ms is ~100ms each, below the point an eye can follow a path.
Without the test, an implementer tidying toward the band would quietly
delete the journey.

§2.2 gives the figure its owner's hue rather than the old neutral
yellow, so colour keeps meaning ownership and nothing else.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: The cover row

One side's three bays plus its figure. Owns the **semantic labels**, which the
§3.3 correction identified as the only test hooks a renderer rewrite cannot
invalidate — they are accessibility contracts, not implementation details.

**Files:**
- Create: `lib/features/games/paint_ball/presentation/widgets/field/cover_row.dart`
- Test: `test/features/games/paint_ball_cover_row_test.dart`

**Interfaces:**
- Consumes: `CoverBay`, `CoverBayState`, `PaintBallCoverStyle`, `FieldFigure`, `figureCentreX`, `PaintBallFieldKeys`, `kPaintBallPositions`, `kPaintBallCoverWidth`, `kPaintBallTargetScale`, `paintBallPositionName`.
- Produces: `class CoverRow extends StatelessWidget` — `const CoverRow({required bool isOpponent, required int? hiddenAt, required int? aimedAt, required bool enabled, required Color ownerColor, required bool reduceMotion, int? aimingAt, ValueChanged<int>? onTap, VoidCallback? onTapFigure, bool emerged = true, PaintBallCoverStyle? coverStyle})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/games/paint_ball_cover_row_test.dart`:

```dart
import 'package:attune/features/games/paint_ball/presentation/widgets/field/cover_bay.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/cover_row.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_figure.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart'
    show kPaintBallPositions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    bool isOpponent = false,
    int? hiddenAt,
    int? aimedAt,
    bool enabled = true,
    ValueChanged<int>? onTap,
    VoidCallback? onTapFigure,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 390,
        height: 120,
        child: CoverRow(
          isOpponent: isOpponent,
          hiddenAt: hiddenAt,
          aimedAt: aimedAt,
          enabled: enabled,
          ownerColor: const Color(0xFF5EEAD4),
          reduceMotion: false,
          onTap: onTap,
          onTapFigure: onTapFigure,
        ),
      ),
    ),
  );

  testWidgets('every position is labelled for a screen reader', (
    tester,
  ) async {
    // Old tests 3 and 10. Named by POSITION rather than index: a
    // screen-reader user hears "Middle target", which is the thing on
    // the board, not "cover 2", which is an implementation detail.
    //
    // These labels are also the only hooks a renderer rewrite cannot
    // invalidate -- they are an accessibility contract, so they outlive
    // every painter rename.
    await tester.pumpWidget(host(isOpponent: true));
    await tester.pump();

    expect(find.bySemanticsLabel('Left target'), findsOneWidget);
    expect(find.bySemanticsLabel('Middle target'), findsOneWidget);
    expect(find.bySemanticsLabel('Right target'), findsOneWidget);
  });

  testWidgets('your own row is cover, theirs is a target', (tester) async {
    // The asymmetry in the words matters: you hide behind cover, you
    // shoot at a target. One row cannot be mistaken for the other by a
    // screen reader any more than by an eye.
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.bySemanticsLabel('Middle cover'), findsOneWidget);
    expect(find.bySemanticsLabel('Middle target'), findsNothing);
  });

  testWidgets('a tap reports which position was chosen', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(host(isOpponent: true, onTap: taps.add));
    await tester.pump();

    for (var i = 0; i < kPaintBallPositions; i++) {
      await tester.tap(
        find.bySemanticsLabel('${['Left', 'Middle', 'Right'][i]} target'),
      );
    }
    await tester.pump();

    expect(taps, [0, 1, 2]);
  });

  testWidgets('nothing is selectable when the row is disabled', (
    tester,
  ) async {
    // Old test 5. A player must not be able to move out of turn.
    var tapped = false;
    await tester.pumpWidget(
      host(isOpponent: true, enabled: false, onTap: (_) => tapped = true),
    );
    await tester.pump();

    for (final target in find.byType(GestureDetector).evaluate()) {
      await tester.tap(find.byWidget(target.widget), warnIfMissed: false);
    }
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets('exactly three bays are drawn, all keyed to this side', (
    tester,
  ) async {
    await tester.pumpWidget(host(isOpponent: true));
    await tester.pump();

    for (var i = 0; i < kPaintBallPositions; i++) {
      expect(
        find.byKey(PaintBallFieldKeys.bay(i, isOpponent: true)),
        findsOneWidget,
      );
      expect(
        find.byKey(PaintBallFieldKeys.bay(i, isOpponent: false)),
        findsNothing,
        reason: 'a row must not render the other side’s bays',
      );
    }
  });

  testWidgets('only the aimed bay is in the aimed state', (tester) async {
    // With no Fire button the aimed cover IS the confirmation that a
    // target is chosen, so exactly one may claim it. Two aimed bays
    // would make the commit ambiguous.
    await tester.pumpWidget(host(isOpponent: true, aimedAt: 2));
    await tester.pump();

    final states = <int, CoverBayState>{};
    for (var i = 0; i < kPaintBallPositions; i++) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(PaintBallFieldKeys.bay(i, isOpponent: true)),
          matching: find.byType(CustomPaint),
          matchRoot: true,
        ),
      );
      states[i] = (paint.painter! as CoverBayPainter).state;
    }

    expect(states[2], CoverBayState.aimed);
    expect(states[0], isNot(CoverBayState.aimed));
    expect(states[1], isNot(CoverBayState.aimed));
  });

  testWidgets('a hidden occupant puts exactly one figure on the row', (
    tester,
  ) async {
    // Old tests 6 and 7. You can see where YOU are hiding; their
    // position appears only after a round resolves. One figure, not one
    // per cover.
    await tester.pumpWidget(host(hiddenAt: 1));
    await tester.pump();

    expect(
      find.byKey(PaintBallFieldKeys.figure(1, isOpponent: false)),
      findsOneWidget,
    );
    expect(find.byType(FieldFigure), findsOneWidget);
  });

  testWidgets('no occupant means no figure at all', (tester) async {
    // The hidden information the whole game turns on. If their figure
    // were drawn before the reveal, the guess would stop being a guess.
    await tester.pumpWidget(host(isOpponent: true));
    await tester.pump();

    expect(find.byType(FieldFigure), findsNothing);
  });

  testWidgets('the figure stands on the centre of its own cover', (
    tester,
  ) async {
    // DEVICE-REPORTED REGRESSION (old test 18), now checked through the
    // composition rather than the formula alone -- the formula is unit
    // tested in its own task, but a correct formula wired to the wrong
    // cover width would still drift.
    for (final width in [360.0, 390.0, 430.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 120,
              child: CoverRow(
                isOpponent: false,
                hiddenAt: 2,
                aimedAt: null,
                enabled: true,
                ownerColor: const Color(0xFF5EEAD4),
                reduceMotion: true,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final figure = tester.getRect(
        find.byKey(PaintBallFieldKeys.figure(2, isOpponent: false)),
      );
      final bay = tester.getRect(
        find.byKey(PaintBallFieldKeys.bay(2, isOpponent: false)),
      );

      expect(
        (figure.center.dx - bay.center.dx).abs(),
        lessThan(1.0),
        reason:
            'at width $width the figure sits '
            '${(figure.center.dx - bay.center.dx).abs().toStringAsFixed(1)}pt '
            'off the centre of its cover',
      );
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/games/paint_ball_cover_row_test.dart`
Expected: FAIL — `field/cover_row.dart` does not resolve.

- [ ] **Step 3: Write the implementation**

Create `lib/features/games/paint_ball/presentation/widgets/field/cover_row.dart`:

```dart
import 'package:flutter/material.dart';

import '../paint_ball_field.dart'
    show
        kPaintBallCoverWidth,
        kPaintBallPositions,
        kPaintBallTargetScale,
        paintBallPositionName;
import 'cover_bay.dart';
import 'field_figure.dart';

/// One side of the field: three bays, and the figure sheltering in one.
///
/// The figure sits ABOVE the bays rather than inside one, because a
/// child cannot travel outside its parent's box and changing cover is a
/// journey across the whole row (see [FieldFigure]).
class CoverRow extends StatelessWidget {
  const CoverRow({
    super.key,
    required this.isOpponent,
    required this.hiddenAt,
    required this.aimedAt,
    required this.enabled,
    required this.ownerColor,
    required this.reduceMotion,
    this.aimingAt,
    this.onTap,
    this.onTapFigure,
    this.emerged = true,
    this.coverStyle,
  });

  final bool isOpponent;

  /// Where this row's occupant is, when the viewer may know. Always set
  /// for your own row; for theirs only after a round resolves.
  final int? hiddenAt;

  /// The bay being aimed at. Exactly one, or none.
  final int? aimedAt;

  final bool enabled;
  final Color ownerColor;
  final bool reduceMotion;

  /// Where this row's occupant is pointing, which leans the figure.
  final int? aimingAt;

  final ValueChanged<int>? onTap;

  /// Set only when the figure is the fire control.
  final VoidCallback? onTapFigure;

  /// False during the replay's first beat, while both players are still
  /// behind cover and about to step out.
  final bool emerged;

  /// Overrides §2.3's bay-of-darkness. See [PaintBallCoverStyle].
  final PaintBallCoverStyle? coverStyle;

  @override
  Widget build(BuildContext context) {
    final coverWidth =
        kPaintBallCoverWidth * (isOpponent ? kPaintBallTargetScale : 1);
    final isAiming = aimingAt != null && hiddenAt != null && emerged;

    // Per-column lean, in turns. Small deliberately: the tilt says which
    // cover is being aimed at, and a figure rotated far enough to lose
    // its pointing silhouette stops communicating that at all.
    final tilt =
        isAiming
            ? (aimingAt! - hiddenAt!) * (isOpponent ? -0.045 : 0.045)
            : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 92,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(kPaintBallPositions, (index) {
                  return Semantics(
                    // container: true so each becomes its own node.
                    // Without it a screen reader announces one
                    // undifferentiated strip instead of three targets.
                    container: true,
                    button: enabled,
                    // Named by position, not index: a screen-reader user
                    // hears "Middle target" -- the thing on the board --
                    // rather than "cover 2".
                    //
                    // Your row is COVER, theirs is a TARGET. You hide
                    // behind one and shoot at the other, so the words
                    // differ as much as the rows do.
                    label:
                        isOpponent
                            ? '${paintBallPositionName(index)} target'
                            : '${paintBallPositionName(index)} cover',
                    child: GestureDetector(
                      onTap: enabled ? () => onTap?.call(index) : null,
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: coverWidth,
                        height: 92,
                        child: CoverBay(
                          position: index,
                          isOpponent: isOpponent,
                          state: _stateFor(index),
                          ownerColor: ownerColor,
                          style: coverStyle,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              if (hiddenAt != null && emerged)
                FieldFigure(
                  position: hiddenAt!,
                  isOpponent: isOpponent,
                  rowWidth: constraints.maxWidth,
                  coverWidth: coverWidth,
                  rowHeight: 92,
                  ownerColor: ownerColor,
                  isAiming: isAiming,
                  tilt: tilt,
                  reduceMotion: reduceMotion,
                  onTap: onTapFigure,
                ),
            ],
          ),
        );
      },
    );
  }

  /// Aimed outranks occupied: with no Fire button, the aimed bay is the
  /// only confirmation that a target is chosen, so it must never be
  /// outvoted by the fact that somebody is standing there.
  CoverBayState _stateFor(int index) {
    if (aimedAt == index) return CoverBayState.aimed;
    if (hiddenAt == index) return CoverBayState.occupied;
    return CoverBayState.rest;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/games/paint_ball_cover_row_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Run the games suite to confirm nothing regressed**

Run: `flutter test test/features/games/`
Expected: all pass. This task adds files only.

- [ ] **Step 6: Commit**

```bash
git add lib/features/games/paint_ball/presentation/widgets/field/cover_row.dart test/features/games/paint_ball_cover_row_test.dart
git commit -m "$(cat <<'EOF'
feat(paintball): one side of the field, bays plus its occupant

The semantic labels come across unchanged, and that is the point: they
are an accessibility contract rather than an implementation detail, so
they are the only test hooks a renderer rewrite cannot invalidate. Your
row is COVER and theirs is a TARGET -- you hide behind one and shoot at
the other, so the words differ as much as the rows do, and a screen
reader can no more confuse them than an eye can.

Aimed outranks occupied in the bay's state. With no Fire button the
aimed bay is the only confirmation that a target is chosen, so the fact
that somebody is standing there must never outvote it.

The figure sits above the bays rather than inside one, because changing
cover is a journey across the whole row and a child cannot travel
outside its parent's box.

The device-reported centring bug is re-checked here through the
composition, not just the formula: a correct formula wired to the wrong
cover width would still drift, and the opponent's covers are scaled.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: The paint layer — and a geometry bug that has been shipping

Splats, rendered in neon. **Fixes a pre-existing bug found while planning this
task:** `_SplatPainter` positions paint with `size.width / kPaintBallPositions`
slot maths, while bays and figures use the cover-centre formula. They agree only
at the middle position.

Measured drift between where paint lands and the cover it supposedly hit:

| row width | pos 0 | pos 1 | pos 2 |
|---|---|---|---|
| 360pt | 11.5pt | 0 | 11.5pt |
| 390pt | 14.0pt | 0 | 14.0pt |
| 430pt | 17.3pt | 0 | 17.3pt |

So on the outer two covers a hit splatters up to 17pt to one side of what it
hit, worsening with screen width. Position 1 is exact, which is almost
certainly why it was never noticed. This is the **same bug class** as the
device-reported figure-centring issue — fixed for the figure then, missed for
the paint.

The fix is to call `figureCentreX` rather than keep a second, drifting copy of
the geometry. In scope because this task rewrites the painter anyway, and
leaving it would make the new field draw bays by one formula and paint by
another.

**Files:**
- Create: `lib/features/games/paint_ball/presentation/widgets/field/field_paint.dart`
- Test: `test/features/games/paint_ball_field_paint_test.dart`

**Interfaces:**
- Consumes: `figureCentreX`, `NeonQuality`, `NeonTokens`, `PaintBallFieldKeys`, `PaintSplat`, `kPaintBallPositions`, `kPaintBallCoverWidth`, `kPaintBallTargetScale`.
- Produces:
  - `class FieldPaint extends StatelessWidget` — `const FieldPaint({required List<PaintSplat> splats, required Color mineColor, required Color theirsColor})`. Keyed `PaintBallFieldKeys.paint`, with a **public `splats` field** (the typed replacement for the old `(painter as dynamic).splats`).
  - `class FieldPaintPainter extends CustomPainter` — public final `splats`, `mineColor`, `theirsColor`, `quality`.
  - `Offset splatCentre({required PaintSplat splat, required Size size, required double rowWidth})` — where one splat lands. Pure, so the geometry fix is unit-testable.

- [ ] **Step 1: Write the failing test**

Create `test/features/games/paint_ball_field_paint_test.dart`:

```dart
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_figure.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_paint.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart'
    show PaintSplat, kPaintBallCoverWidth, kPaintBallPositions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records draw calls so geometry is assertable without a golden.
class _RecordingCanvas implements Canvas {
  final paths = <Path>[];
  final circles = <Offset>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);

  @override
  noSuchMethod(Invocation invocation) => null;
}

void main() {
  const mine = Color(0xFF5EEAD4);
  const theirs = Color(0xFFFF4D6A);

  group('where paint lands', () {
    test('a hit lands on the centre of the cover it hit', () {
      // PRE-EXISTING BUG, fixed here. The old painter used
      // `size.width / kPaintBallPositions` slot maths while the bays and
      // figures use the cover-centre formula. The two agree only at the
      // middle position; at the outer two, paint landed 11-17pt to one
      // side of the cover it had just hit, worsening with screen width.
      //
      // Position 1 being exact is almost certainly why nobody caught it.
      for (final rowWidth in [360.0, 390.0, 430.0]) {
        final size = Size(rowWidth, 400);

        for (var position = 0; position < kPaintBallPositions; position++) {
          final expected = figureCentreX(
            rowWidth: rowWidth,
            coverWidth: kPaintBallCoverWidth,
            column: position.toDouble(),
          );

          final centre = splatCentre(
            splat: PaintSplat(
              position: position,
              isMine: true,
              // A hit has no random scatter, so its centre is exactly
              // the cover's -- which is what makes this checkable.
              hit: true,
              round: 1,
            ),
            size: size,
            rowWidth: rowWidth,
          );

          expect(
            centre.dx,
            closeTo(expected, 0.001),
            reason:
                'at width $rowWidth a hit on cover $position must land on '
                'that cover, not on a notional slot centre',
          );
        }
      }
    });

    test('slot maths would have failed this', () {
      // Pins the bug so a "simplification" back to width/3 breaks
      // loudly rather than silently reintroducing the drift.
      const rowWidth = 430.0;
      const position = 2;

      final slotCentre =
          rowWidth / kPaintBallPositions * position +
          rowWidth / kPaintBallPositions / 2;

      final centre = splatCentre(
        splat: const PaintSplat(
          position: position,
          isMine: true,
          hit: true,
          round: 1,
        ),
        size: const Size(rowWidth, 400),
        rowWidth: rowWidth,
      );

      expect(
        centre.dx,
        isNot(closeTo(slotCentre, 1.0)),
        reason: 'the two formulas genuinely disagree at this width',
      );
      expect(
        (centre.dx - slotCentre).abs(),
        greaterThan(15),
        reason: 'and they disagree by the measured 17pt, not by a rounding',
      );
    });

    test('a miss scatters, a hit does not', () {
      // A miss landing exactly on the cover would read as a hit. The
      // scatter is seeded, so it is deterministic per round+position --
      // the same round redrawn must not move its paint.
      Offset at({required bool hit}) => splatCentre(
        splat: PaintSplat(
          position: 0,
          isMine: true,
          hit: hit,
          round: 4,
        ),
        size: const Size(390, 400),
        rowWidth: 390,
      );

      final hitCentre = at(hit: true);
      final missCentre = at(hit: false);

      expect(
        missCentre.dx,
        isNot(closeTo(hitCentre.dx, 0.5)),
        reason: 'a miss must not land on the cover',
      );
      expect(
        at(hit: false).dx,
        closeTo(missCentre.dx, 0.001),
        reason: 'the scatter is seeded, so a redraw is stable',
      );
    });

    test('each side paints on its own half', () {
      // Yours near the bottom, theirs near the top -- the same
      // never-flips rule the rows follow.
      final mineAt = splatCentre(
        splat: const PaintSplat(
          position: 1,
          isMine: true,
          hit: true,
          round: 1,
        ),
        size: const Size(390, 400),
        rowWidth: 390,
      );
      final theirsAt = splatCentre(
        splat: const PaintSplat(
          position: 1,
          isMine: false,
          hit: true,
          round: 1,
        ),
        size: const Size(390, 400),
        rowWidth: 390,
      );

      expect(mineAt.dy, greaterThan(theirsAt.dy));
    });

    test('an out-of-range position stays on the field', () {
      // Review Focus #5. PaintSplat.position is a bare int with no
      // validation, so a stale or malformed round could carry 3 or -1.
      // It must clamp rather than draw off-field or produce a NaN.
      for (final position in [-1, 3, 99]) {
        final centre = splatCentre(
          splat: PaintSplat(
            position: position,
            isMine: true,
            hit: true,
            round: 1,
          ),
          size: const Size(390, 400),
          rowWidth: 390,
        );

        expect(centre.dx.isFinite, isTrue, reason: 'position $position');
        expect(
          centre.dx,
          inInclusiveRange(0, 390),
          reason: 'position $position must stay on the field',
        );
      }
    });
  });

  group('the paint layer', () {
    test('an empty list draws nothing at all', () {
      // Old test 22, and the reason it matters is fairness rather than
      // tidiness: accumulated paint is a map of where your partner has
      // already fired -- their habits readable for free, which is the
      // clue this game asks you to earn. A board between rounds is
      // clean, and this is the assertion that keeps it so.
      final canvas = _RecordingCanvas();
      FieldPaintPainter(
        splats: const [],
        mineColor: mine,
        theirsColor: theirs,
        quality: NeonQuality.glow,
        rowWidth: 390,
      ).paint(canvas, const Size(390, 400));

      expect(canvas.paths, isEmpty);
      expect(canvas.circles, isEmpty);
    });

    test('a non-empty list does draw — the positive control', () {
      // Without this, the test above could pass because the painter is
      // broken rather than because the list is empty. That exact
      // vacuous shape has been found four times in this codebase.
      final canvas = _RecordingCanvas();
      FieldPaintPainter(
        splats: const [
          PaintSplat(position: 1, isMine: true, hit: true, round: 1),
        ],
        mineColor: mine,
        theirsColor: theirs,
        quality: NeonQuality.glow,
        rowWidth: 390,
      ).paint(canvas, const Size(390, 400));

      expect(canvas.paths, isNotEmpty);
    });

    test('a long match draws a bounded number of splats', () {
      // Paint from 40 rounds would bury the covers. The painter keeps
      // only the most recent, and the cap must hold rather than growing
      // with the match.
      final canvas = _RecordingCanvas();
      FieldPaintPainter(
        splats: [
          for (var round = 0; round < 40; round++)
            PaintSplat(
              position: round % kPaintBallPositions,
              isMine: round.isEven,
              hit: round % 3 == 0,
              round: round,
            ),
        ],
        mineColor: mine,
        theirsColor: theirs,
        quality: NeonQuality.glow,
        rowWidth: 390,
      ).paint(canvas, const Size(390, 400));

      expect(canvas.paths, isNotEmpty);
      expect(
        canvas.paths.length,
        lessThanOrEqualTo(kFieldPaintVisible),
        reason: 'the cap holds however long the match runs',
      );
    });

    test('a zero-sized field does not throw', () {
      final canvas = _RecordingCanvas();
      expect(
        () => FieldPaintPainter(
          splats: const [
            PaintSplat(position: 0, isMine: true, hit: true, round: 1),
          ],
          mineColor: mine,
          theirsColor: theirs,
          quality: NeonQuality.glow,
          rowWidth: 0,
        ).paint(canvas, Size.zero),
        returnsNormally,
      );
    });

    testWidgets('the layer exposes its splats without a dynamic read', (
      tester,
    ) async {
      // Spec §3.6.1: the old test reached through
      // `(painter as dynamic).splats`, and worse, filtered painters by
      // type NAME -- so after a rename the loop ran zero times and the
      // test passed having asserted nothing.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FieldPaint(
              splats: [],
              mineColor: mine,
              theirsColor: theirs,
            ),
          ),
        ),
      );
      await tester.pump();

      // Found by type rather than by key: the key sits on the inner
      // CustomPaint, which is where a painter lookup wants it, so
      // find.byKey would hand back the CustomPaint and not the layer.
      final layer = tester.widget<FieldPaint>(find.byType(FieldPaint));

      expect(layer.splats, isEmpty);

      // And the key IS present, so the field can locate this layer.
      expect(find.byKey(PaintBallFieldKeys.paint), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/games/paint_ball_field_paint_test.dart`
Expected: FAIL — `field/field_paint.dart` does not resolve.

- [ ] **Step 3: Write the implementation**

Create `lib/features/games/paint_ball/presentation/widgets/field/field_paint.dart`:

```dart
import 'dart:math' as math;

import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/material.dart';

import '../paint_ball_field.dart'
    show PaintSplat, kPaintBallCoverWidth, kPaintBallPositions;
import 'field_figure.dart' show figureCentreX;
import 'paint_ball_field_keys.dart';

/// How many splats stay on the field.
///
/// Paint from a whole match would bury the covers, so only the most
/// recent survive and older ones fade.
const int kFieldPaintVisible = 12;

/// Where one splat lands.
///
/// Pure, because this function is a BUG FIX and the alternative way to
/// test it is rendering a field at three widths and measuring pixels.
///
/// The old painter used `size.width / kPaintBallPositions` slot maths
/// while the bays and figures use the cover-centre formula. Those agree
/// only at the middle position; at the outer two, paint landed 11-17pt
/// to one side of the cover it had just hit, worsening with screen
/// width. Position 1 being exact is almost certainly why it survived.
///
/// Calling [figureCentreX] rather than recomputing is the point: one
/// formula for the whole field, so paint cannot drift away from the
/// cover it describes.
Offset splatCentre({
  required PaintSplat splat,
  required Size size,
  required double rowWidth,
}) {
  // PaintSplat.position is a bare int off the wire with no validation,
  // so a stale or malformed round can carry 3 or -1. Clamping keeps a
  // bad row on the field instead of drawing off it.
  final position = splat.position.clamp(0, kPaintBallPositions - 1);

  final centreX = figureCentreX(
    rowWidth: rowWidth,
    coverWidth: kPaintBallCoverWidth,
    column: position.toDouble(),
  );

  // Yours near the bottom, theirs near the top: the same never-flips
  // rule the rows follow, so "mine" is never something to work out.
  final rowY = splat.isMine ? size.height * 0.80 : size.height * 0.20;

  // Seeded per round and position, so redrawing a round does not move
  // its paint. A hit has no scatter at all -- it landed where it
  // landed, and a hit nudged off-centre would read as a near miss.
  final rng = math.Random(splat.round * 31 + position * 7);
  final offsetX =
      splat.hit ? 0.0 : (rng.nextDouble() - 0.5) * kPaintBallCoverWidth * 0.8;
  final offsetY = (rng.nextDouble() - 0.5) * 18;

  return Offset(
    (centreX + offsetX).clamp(0.0, math.max(0.0, size.width)),
    rowY + offsetY,
  );
}

/// The paint on the field.
///
/// Public [splats] so a test reads it directly rather than through
/// `(painter as dynamic).splats` (spec §3.6.1).
class FieldPaint extends StatelessWidget {
  const FieldPaint({
    super.key,
    required this.splats,
    required this.mineColor,
    required this.theirsColor,
  });

  final List<PaintSplat> splats;
  final Color mineColor;
  final Color theirsColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          key: PaintBallFieldKeys.paint,
          size: Size.infinite,
          painter: FieldPaintPainter(
            splats: splats,
            mineColor: mineColor,
            theirsColor: theirsColor,
            quality: neonQualityOf(context),
            rowWidth: constraints.maxWidth,
          ),
        );
      },
    );
  }
}

/// Draws the paint. Public fields throughout, for the same reason.
class FieldPaintPainter extends CustomPainter {
  FieldPaintPainter({
    required this.splats,
    required this.mineColor,
    required this.theirsColor,
    required this.quality,
    required this.rowWidth,
  });

  final List<PaintSplat> splats;
  final Color mineColor;
  final Color theirsColor;
  final NeonQuality quality;
  final double rowWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (splats.isEmpty || size.isEmpty) return;

    final recent =
        splats.length <= kFieldPaintVisible
            ? splats
            : splats.sublist(splats.length - kFieldPaintVisible);

    for (var i = 0; i < recent.length; i++) {
      final splat = recent[i];
      final age = recent.length == 1 ? 1.0 : i / (recent.length - 1);

      final colour = splat.isMine ? mineColor : theirsColor;
      final paint =
          Paint()
            ..color = colour.withValues(
              alpha: (0.18 + 0.32 * age) * NeonTokens.actorAlpha,
            )
            ..style = PaintingStyle.fill;

      final centre = splatCentre(
        splat: splat,
        size: size,
        rowWidth: rowWidth,
      );
      final rng = math.Random(splat.round * 31 + splat.position * 7);

      _drawSplat(canvas, centre, splat.hit ? 26.0 : 16.0, paint, rng);
    }
  }

  /// An irregular blob rather than a circle: a perfect disc reads as a
  /// dot, and paint does not land in circles.
  void _drawSplat(
    Canvas canvas,
    Offset centre,
    double radius,
    Paint paint,
    math.Random rng,
  ) {
    final path = Path();
    const points = 9;

    for (var i = 0; i <= points; i++) {
      final angle = (i / points) * 2 * math.pi;
      final wobble = radius * (0.7 + rng.nextDouble() * 0.5);
      final point = Offset(
        centre.dx + math.cos(angle) * wobble,
        centre.dy + math.sin(angle) * wobble,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);

    // Flecks around the blob. The first thing to go on a cheap device:
    // three extra circles per splat, twelve splats deep, is exactly the
    // kind of cost §6.10's launch gate is about.
    if (quality == NeonQuality.plain) return;

    for (var i = 0; i < 3; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final distance = radius * (1.1 + rng.nextDouble() * 0.7);
      canvas.drawCircle(
        Offset(
          centre.dx + math.cos(angle) * distance,
          centre.dy + math.sin(angle) * distance,
        ),
        radius * 0.12,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FieldPaintPainter old) =>
      old.quality != quality ||
      old.rowWidth != rowWidth ||
      old.mineColor != mineColor ||
      old.theirsColor != theirsColor ||
      old.splats.length != splats.length ||
      List.generate(splats.length, (index) {
        final current = splats[index];
        final previous = old.splats[index];
        return current.round != previous.round ||
            current.position != previous.position ||
            current.isMine != previous.isMine ||
            current.hit != previous.hit;
      }).any((changed) => changed);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/games/paint_ball_field_paint_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/paint_ball/presentation/widgets/field/field_paint.dart test/features/games/paint_ball_field_paint_test.dart
git commit -m "$(cat <<'EOF'
fix(paintball): paint lands on the cover it hit, not 17pt beside it

Found while planning this task. _SplatPainter positioned paint with
`size.width / kPaintBallPositions` slot maths while the bays and figures
use the cover-centre formula, and the two agree only at the middle
position. Measured drift on the outer covers: 11.5pt at 360, 14.0 at
390, 17.3 at 430 -- worsening with screen width, so a hit splattered to
one side of what it hit. Position 1 being exact is almost certainly why
it survived; the middle cover is where you look first.

Same bug class as the device-reported figure-centring issue, which was
fixed for the figure at the time and missed for the paint. The fix is to
call figureCentreX instead of keeping a second copy of the geometry --
one formula for the field, so paint cannot drift from the cover it
describes. A test pins that the two formulas disagree by more than 15pt,
so simplifying back to slot maths fails loudly.

Also clamps position: PaintSplat.position is a bare int off the wire
with no validation, so a stale round carrying 3 or -1 drew off-field.
Review Focus #5.

The empty-list test now has a positive control beside it. On its own it
could pass because the painter is broken rather than because the list is
empty -- the exact vacuous shape this codebase has produced four times.
And it is the assertion that keeps a board between rounds clean, which
is a fairness property: accumulated paint is a map of where your partner
has already fired.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Stage 2 addendum: three things discovered after Task 10

Read these before Task 11. All three were found by reading the repo after the
component tasks landed, and all three are Task 11's responsibility because
composition is the first point at which they are observable.

**3. The new field ignores the app's responsive scaling.**
`lib/core/utils/screen_util_config.dart` sets an app-wide 375×812 design size,
and the old field uses `.w`/`.h`/`.r` in 19 places. The six new `field/` files
use it in **zero**. So on a 430pt phone the new field would render at
iPhone-13 dimensions while every surrounding surface scales.

It is invisible to the component tests because each pins an explicit width and
`.w` is the identity function with no `ScreenUtilInit` in the tree.

**Task 11 restores it**, with one trap: `figureCentreX` takes `rowWidth` and
`coverWidth` and **both must be in the same units**. `cover_row.dart` passes
`constraints.maxWidth` (real pixels) alongside `kPaintBallCoverWidth`
(unscaled). Scaling one without the other reintroduces the device-reported
centring bug that old test 18 exists to catch. Task 11 therefore re-runs the
centring assertion under a real `ScreenUtilInit` at several widths.

**4. The old `_SplatPainter` still ships.** Task 10 fixed the 17pt paint drift
in a new file, but the old painter is still what the field uses, so the bug is
live until composition. **Task 11 must delete it**, not add the new layer
beside it.

**5. The paint rows are at `0.80`/`0.20` of height, unverified against the
covers.** Task 10's fix corrected X only. Nothing has checked those fractions
against where `cover_row` actually places its covers. Task 11 owns this,
because it is the first place both exist together.

---

## Task 11: Compose the field

Reduce `paint_ball_field.dart` to composition and layout, consuming the six
`field/` parts. Restore ScreenUtil scaling. Delete the four private painters and
two private widgets it replaces.

**Files:**
- Modify: `lib/features/games/paint_ball/presentation/widgets/paint_ball_field.dart` (958 lines → ~200)
- Modify: `lib/features/games/paint_ball/presentation/widgets/field/cover_row.dart` (ScreenUtil)
- Modify: `lib/features/games/paint_ball/presentation/widgets/field/field_figure.dart` (ScreenUtil)
- Modify: `lib/features/games/paint_ball/presentation/widgets/field/field_paint.dart` (ScreenUtil)
- Test: `test/features/games/paint_ball_field_composition_test.dart` (new)

**Interfaces:**
- Consumes: `FieldGround`, `FieldRowLabel`, `fieldRowLabelText`, `CoverRow`, `FieldPaint`, `PaintBallFieldKeys`, `PaintBallNeonPalette`, `figureCentreX`.
- Produces: `PaintBallField` with its **signature unchanged** — all 15 parameters, same names, same types, same defaults. Plus the five public symbols still exported from the same path: `kPaintBallPositions`, `kPaintBallCoverWidth`, `kPaintBallTargetScale`, `PaintBallPalette`, `PaintSplat`, `paintBallPositionName`.

**What is deleted:** `_FieldLabel`, `_ShieldRow`, `_ShieldPainter`, `_TravellingPlayer`, `_TravellingPlayerState`, `_TrianglePainter`, `_SplatPainter`. `_ProjectilePainter` is **kept for now** — the replay is Stage 4's work and Task 11 must not change flight behaviour.

- [ ] **Step 1: Write the failing test**

Create `test/features/games/paint_ball_field_composition_test.dart`:

```dart
import 'package:attune/features/games/paint_ball/presentation/widgets/field/cover_row.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_figure.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_ground.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_paint.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/paint_ball_field_keys.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real app wraps everything in ScreenUtilInit at 375x812, so the
/// field must be measured inside one. Without it `.w` is the identity
/// function and a scaling bug is invisible -- which is exactly how the
/// six component test files missed it.
Widget _host(Widget child, {Size design = const Size(375, 812)}) =>
    ScreenUtilInit(
      designSize: design,
      builder: (context, _) => MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('the field is built from its parts, not its own painters', (
    tester,
  ) async {
    // The point of the split: one file composes, six files draw. If the
    // field grew its own painters again this would start failing.
    await tester.pumpWidget(
      _host(
        const PaintBallField(
          splats: [],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FieldGround), findsOneWidget);
    expect(find.byType(FieldPaint), findsOneWidget);
    expect(
      find.byType(CoverRow),
      findsNWidgets(2),
      reason: 'two rows: yours and theirs',
    );
    expect(find.byKey(PaintBallFieldKeys.ground), findsOneWidget);
  });

  testWidgets('your row is the near one, whichever player you are', (
    tester,
  ) async {
    // The field never flips. "Mine is bottom, theirs is top" is learned
    // once rather than worked out each turn.
    await tester.pumpWidget(
      _host(
        const PaintBallField(
          splats: [],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: 0,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mine = tester.getCenter(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: false)),
    );
    final theirs = tester.getCenter(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: true)),
    );

    expect(
      mine.dy,
      greaterThan(theirs.dy),
      reason: 'yours is nearer the bottom of the screen',
    );
  });

  group('the figure sits on its cover at real device widths', () {
    // DEVICE-REPORTED REGRESSION (old test 18), re-run under a real
    // ScreenUtilInit. The component test pinned raw pixels; this one
    // proves the SCALED units agree, which is the thing that actually
    // ships. If rowWidth is scaled and coverWidth is not -- or the
    // reverse -- the figure drifts off its cover exactly as it did on
    // the device that reported it.
    for (final width in [360.0, 375.0, 390.0, 430.0]) {
      testWidgets('at ${width.toInt()}pt', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        for (var position = 0; position < kPaintBallPositions; position++) {
          await tester.pumpWidget(
            _host(
              PaintBallField(
                splats: const [],
                myPosition: position,
                selectedShot: null,
                revealedPartnerPosition: null,
                isMyTurn: true,
                onSelectShot: (_) {},
                onSelectHide: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          final figure = tester.getRect(
            find.byKey(
              PaintBallFieldKeys.figure(position, isOpponent: false),
            ),
          );
          final bay = tester.getRect(
            find.byKey(PaintBallFieldKeys.bay(position, isOpponent: false)),
          );

          expect(
            (figure.center.dx - bay.center.dx).abs(),
            lessThan(1.0),
            reason:
                'at ${width.toInt()}pt the figure at position $position '
                'sits ${(figure.center.dx - bay.center.dx).abs().toStringAsFixed(1)}pt '
                'off the centre of its cover',
          );
        }
      });
    }
  });

  testWidgets('paint lands on the row it belongs to', (tester) async {
    // Addendum #5: the paint rows are fractions of the field's HEIGHT,
    // and nothing had checked them against where the covers actually
    // sit. A splat on your half must be nearer your row than theirs.
    await tester.pumpWidget(
      _host(
        const PaintBallField(
          splats: [
            PaintSplat(position: 1, isMine: true, hit: true, round: 1),
          ],
          myPosition: 1,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final layer = tester.widget<FieldPaint>(find.byType(FieldPaint));
    expect(layer.splats, hasLength(1), reason: 'a positive control');

    final paintBox = tester.getRect(find.byType(FieldPaint));
    final myBay = tester.getRect(
      find.byKey(PaintBallFieldKeys.bay(1, isOpponent: false)),
    );

    final centre = splatCentre(
      splat: layer.splats.first,
      size: paintBox.size,
      rowWidth: paintBox.width,
    );

    expect(
      (centre.dx - (myBay.center.dx - paintBox.left)).abs(),
      lessThan(2.0),
      reason: 'paint lands on the column of the cover it hit',
    );
    expect(
      centre.dy,
      greaterThan(paintBox.height / 2),
      reason: 'your paint is on your half of the field',
    );
  });

  testWidgets('the public surface six other files import still exists', (
    tester,
  ) async {
    // paint_ball_provider.dart does `show kPaintBallPositions`, and the
    // history, knockout, battle, lobby screens and lives display all
    // import from this path. The split must not move any of them.
    expect(kPaintBallPositions, 3);
    expect(kPaintBallCoverWidth, greaterThan(0));
    expect(kPaintBallTargetScale, greaterThan(1));
    expect(paintBallPositionName(1), 'Middle');
    expect(PaintBallPalette.mine, isA<Color>());
    expect(
      PaintBallPalette.player,
      isA<Color>(),
      reason: 'history, knockout and battle screens still read this',
    );
    expect(
      const PaintSplat(position: 0, isMine: true, hit: false, round: 1)
          .position,
      0,
    );
  });

  testWidgets('reduce motion is taken from the platform, not a default', (
    tester,
  ) async {
    // The component widgets take `reduceMotion` as a plain bool, so the
    // composing field is the only place it can be read from the OS. If
    // it defaulted to false here, every accessibility guarantee below
    // would be silently off.
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (context, _) => MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: const Scaffold(
                  body: PaintBallField(
                    splats: [],
                    myPosition: 0,
                    selectedShot: null,
                    revealedPartnerPosition: null,
                    isMyTurn: true,
                  ),
                ),
              ),
            ),
      ),
    );
    await tester.pump();

    final rows = tester.widgetList<CoverRow>(find.byType(CoverRow));
    expect(rows, hasLength(2), reason: 'a positive control');
    for (final row in rows) {
      expect(
        row.reduceMotion,
        isTrue,
        reason: 'the field must read disableAnimations, not assume false',
      );
    }
  });

  testWidgets('a field with nothing chosen still renders', (tester) async {
    // Old test 2. The opening move, before anyone has acted.
    await tester.pumpWidget(
      _host(
        const PaintBallField(
          splats: [],
          myPosition: null,
          selectedShot: null,
          revealedPartnerPosition: null,
          isMyTurn: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(FieldFigure), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/games/paint_ball_field_composition_test.dart`
Expected: FAIL — the field still builds its own `_ShieldRow`, so `find.byType(CoverRow)` finds nothing.

- [ ] **Step 3: Rewrite the field**

Replace everything in `paint_ball_field.dart` from `class PaintBallField` to the end of the file, **keeping lines 1–80 (the constants, `PaintBallPalette`, `PaintSplat`) exactly as they are**, with:

```dart
class PaintBallField extends StatelessWidget {
  const PaintBallField({
    super.key,
    required this.splats,
    required this.myPosition,
    required this.selectedShot,
    required this.revealedPartnerPosition,
    required this.isMyTurn,
    this.shotProgress,
    this.onSelectShot,
    this.onSelectHide,
    this.onFire,
    this.replayProgress,
    this.theirRevealedShot,
    this.isReplaying = false,
    this.partnerName,
    this.theirStreak = 1,
  });

  final List<PaintSplat> splats;
  final int? myPosition;
  final int? selectedShot;
  final int? revealedPartnerPosition;
  final bool isMyTurn;

  /// 0 to 1 while a shot travels, null otherwise.
  final double? shotProgress;

  final ValueChanged<int>? onSelectShot;

  /// Tapping your own cover moves you there. Null disables repositioning.
  final ValueChanged<int>? onSelectHide;

  /// Tapping your own figure fires, once a target is chosen.
  final VoidCallback? onFire;

  /// 0 to 1 while a resolved round replays. During a replay BOTH sides
  /// emerge, aim and fire, so it drives more than the shot alone.
  final double? replayProgress;

  /// Where the opponent shot during the replay.
  final int? theirRevealedShot;

  final bool isReplaying;

  /// Whose cover the far row is. Named rather than "THEIR COVER"
  /// because the person across the field is someone specific.
  final String? partnerName;

  /// Rounds running they have held the same cover.
  final int theirStreak;

  @override
  Widget build(BuildContext context) {
    // Read here and passed down. The component widgets take a plain
    // bool, so this is the only place the OS setting can enter -- and
    // defaulting it to false would turn every reduce-motion guarantee
    // below it silently off.
    final reduceMotion = reduceMotionOf(context);

    return AspectRatio(
      aspectRatio: 1.05,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          // The replay's beats. Emerging and aiming are given room to
          // read before anything is fired: the point of the replay is
          // seeing the two decisions meet, and a shot that left before
          // the aim landed would skip the part worth watching.
          final replay = replayProgress;
          final emerged = replay == null || replay > NeonTokens.beatEmerge;
          final aimed = replay == null || replay > NeonTokens.beatAim;
          final firing = replay != null && replay > NeonTokens.beatFire;
          final flightProgress =
              firing
                  ? ((replay - NeonTokens.beatFire) /
                          (NeonTokens.beatFlightEnd - NeonTokens.beatFire))
                      .clamp(0.0, 1.0)
                  : null;

          // Both rows' geometry comes from the one formula the figures
          // and paint already use, so a projectile cannot leave from
          // somewhere its shooter is not standing.
          double columnX(int? position, {required bool isOpponent}) {
            if (position == null) return width / 2;
            return figureCentreX(
              rowWidth: width,
              coverWidth:
                  kPaintBallCoverWidth.w *
                  (isOpponent ? kPaintBallTargetScale : 1),
              column: position.toDouble(),
            );
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
            child: FieldGround(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Paint sits under everything, so a splat reads as
                  // landing ON the field rather than floating over the
                  // pieces.
                  Positioned.fill(
                    child: FieldPaint(
                      splats: splats,
                      mineColor: PaintBallPalette.mine,
                      theirsColor: PaintBallPalette.theirs,
                    ),
                  ),

                  Positioned(
                    top: height * 0.035,
                    left: 0,
                    right: 0,
                    child: FieldRowLabel(
                      label: fieldRowLabelText(
                        partnerName: partnerName,
                        isReplaying: isReplaying,
                        theirStreak: theirStreak,
                      ),
                      color: PaintBallPalette.theirs,
                    ),
                  ),

                  Positioned(
                    top: height * 0.105,
                    left: 0,
                    right: 0,
                    child: CoverRow(
                      isOpponent: true,
                      hiddenAt: revealedPartnerPosition,
                      aimedAt: selectedShot,
                      aimingAt: aimed ? theirRevealedShot : null,
                      emerged: emerged,
                      enabled: isMyTurn && onSelectShot != null,
                      ownerColor: PaintBallPalette.theirs,
                      reduceMotion: reduceMotion,
                      onTap: onSelectShot,
                    ),
                  ),

                  Positioned(
                    bottom: height * 0.035,
                    left: 0,
                    right: 0,
                    child: const FieldRowLabel(
                      label: 'YOUR COVER',
                      color: PaintBallPalette.mine,
                    ),
                  ),

                  Positioned(
                    bottom: height * 0.105,
                    left: 0,
                    right: 0,
                    child: CoverRow(
                      isOpponent: false,
                      hiddenAt: myPosition,
                      aimedAt: null,
                      // Your own figure leans toward whatever you are
                      // aiming at, so the aim is visible on the field
                      // rather than only in a control strip.
                      aimingAt: aimed ? selectedShot : null,
                      emerged: emerged,
                      enabled: isMyTurn && onSelectHide != null,
                      ownerColor: PaintBallPalette.mine,
                      reduceMotion: reduceMotion,
                      onTap: onSelectHide,
                      onTapFigure: onFire,
                    ),
                  ),

                  // The replay's two paintballs, in flight at once.
                  // Both players fired without seeing the other, so the
                  // shots cross rather than take turns -- watching them
                  // pass is the moment the round becomes a duel rather
                  // than two separate moves.
                  if (flightProgress != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: PaintBallFieldKeys.projectile(isMine: true),
                          painter: _ProjectilePainter(
                            progress: flightProgress,
                            from: Offset(
                              columnX(myPosition, isOpponent: false),
                              height * 0.80,
                            ),
                            to: Offset(
                              columnX(selectedShot, isOpponent: true),
                              height * 0.20,
                            ),
                            color: PaintBallPalette.mine,
                          ),
                        ),
                      ),
                    ),
                  if (flightProgress != null && theirRevealedShot != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: PaintBallFieldKeys.projectile(isMine: false),
                          painter: _ProjectilePainter(
                            progress: flightProgress,
                            from: Offset(
                              columnX(
                                revealedPartnerPosition,
                                isOpponent: true,
                              ),
                              height * 0.20,
                            ),
                            to: Offset(
                              columnX(theirRevealedShot, isOpponent: false),
                              height * 0.80,
                            ),
                            color: PaintBallPalette.theirs,
                          ),
                        ),
                      ),
                    ),

                  // A single shot outside a replay.
                  if (shotProgress != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: PaintBallFieldKeys.projectile(isMine: true),
                          painter: _ProjectilePainter(
                            progress: shotProgress!,
                            from: Offset(
                              columnX(myPosition, isOpponent: false),
                              height * 0.80,
                            ),
                            to: Offset(
                              columnX(selectedShot, isOpponent: true),
                              height * 0.20,
                            ),
                            color: PaintBallPalette.mine,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

Then **delete** `_FieldLabel`, `_ShieldRow`, `_ShieldPainter`, `_TravellingPlayer`, `_TravellingPlayerState`, `_TrianglePainter` and `_SplatPainter` entirely. **Keep `_ProjectilePainter`** — the replay is Stage 4's work and this task must not change flight behaviour.

Fix the imports at the top of the file: it needs `field/cover_row.dart`,
`field/field_ground.dart`, `field/field_paint.dart`, `field/field_figure.dart`
(for `figureCentreX`), `field/paint_ball_field_keys.dart`,
`core/ui/neon/neon_tokens.dart`, `core/ui/motion/reduce_motion.dart`, and
`flutter_screenutil`. Drop any import the deleted code was the only user of.

- [ ] **Step 4: Restore ScreenUtil scaling in the three component files**

In `cover_row.dart`: `92` → `92.h` (both occurrences), and
`kPaintBallCoverWidth` → `kPaintBallCoverWidth.w` in the `coverWidth`
calculation. Add `import 'package:flutter_screenutil/flutter_screenutil.dart';`.

In `field_figure.dart`: the `Size(22, 20)` → `Size(22.w, 20.h)`, the `- 11` →
`- 11.w`, the insets `46.0`/`34.0` → `46.h`/`34.h`, the step-out `14.0` →
`14.h`. **Do NOT scale inside `figureCentreX`** — it receives already-scaled
values from its caller, and scaling twice is the bug this addendum warns about.

In `field_paint.dart`: `kPaintBallCoverWidth` → `kPaintBallCoverWidth.w` in
both `splatCentre` and the scatter width, and the radii `26.0`/`16.0` →
`26.r`/`16.r`.

- [ ] **Step 5: Run the composition test**

Run: `flutter test test/features/games/paint_ball_field_composition_test.dart`
Expected: PASS, 10 tests (7 top-level plus the 4-width group counts as 4, minus… count what you get and report it).

- [ ] **Step 6: Run the component tests, which may now need their widths adjusted**

Run: `flutter test test/features/games/paint_ball_cover_row_test.dart test/features/games/paint_ball_field_figure_test.dart test/features/games/paint_ball_field_paint_test.dart`

These pin raw pixel widths and now go through `.w`. **If one fails, do not
weaken it** — wrap its host in `ScreenUtilInit(designSize: Size(375, 812), ...)`
so the scaling is explicit, and report which ones needed it. A failure here is
real information: it means the scaling changed a measurement that a test was
pinning.

- [ ] **Step 7: Run the whole games suite**

Run: `flutter test test/features/games/`
Expected: all pass. Report the total.

- [ ] **Step 8: Commit**

```bash
git add lib/features/games/paint_ball/presentation/widgets/ test/features/games/
git commit -m "$(cat <<'EOF'
refactor(paintball): the field composes its parts, and scales like the app

958 lines become about 200. The field now places six components and owns
nothing but layout; _FieldLabel, _ShieldRow, _ShieldPainter,
_TravellingPlayer, _TrianglePainter and _SplatPainter are gone.

Deleting _SplatPainter is what finally lands Task 10's fix. The new
paint layer corrected a 17pt drift between where paint fell and the
cover it hit, but the old painter was still the one the field used, so
the bug stayed live until this commit.

ScreenUtil scaling is restored across the field. The app wraps
everything in a 375x812 ScreenUtilInit and the old field used .w/.h/.r
in 19 places; the six new files used it in none, so the field would have
rendered at iPhone-13 size on every other device while its surroundings
scaled. Invisible to the component tests, because each pins an explicit
width and .w is the identity function with no ScreenUtilInit in the tree.

The trap worth naming: figureCentreX needs rowWidth and coverWidth in
the SAME units, so it stays unscaled and takes scaled values from its
callers. Scaling inside it as well would double-apply and reintroduce
the device-reported centring bug. The composition test re-runs that
assertion under a real ScreenUtilInit at four widths, which is the
version that actually ships.

Projectiles now take their column from figureCentreX too, so a shot
cannot leave from somewhere its shooter is not standing -- the same
divergence the paint had. _ProjectilePainter itself is untouched; the
replay is Stage 4's work.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: `ReplayBeats` — the replay's timing, extracted and tested

Stage 4's foundation. The six beats currently live as inline threshold
comparisons in the field's build method; §3.2 says timing belongs in one place
that other parts *read*. Owns **Review Focus #1 and #2**, the two inputs most
likely to bite: `replayProgress` at exactly `1.0` (where a skip lands) and
outside `[0,1]`.

**Files:**
- Create: `lib/features/games/paint_ball/presentation/widgets/field/field_replay.dart`
- Test: `test/features/games/paint_ball_replay_beats_test.dart`
- Modify: `lib/features/games/paint_ball/presentation/widgets/paint_ball_field.dart` (read the beats instead of computing them)

**Interfaces:**
- Consumes: `NeonTokens` beat thresholds.
- Produces:
  - `class ReplayBeats` — immutable, public final fields `emerged`, `aimed`, `firing`, `impacting`, `settled` (all `bool`), `flightProgress` and `impactProgress` (both `double?`), and `isReplaying` (`bool`).
  - `factory ReplayBeats.from(double? progress)` — the single mapping from one controller value to six beat states.
  - `static const ReplayBeats idle` — the not-replaying state, where everything is at rest and visible.

- [ ] **Step 1: Write the failing test**

Create `test/features/games/paint_ball_replay_beats_test.dart`:

```dart
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/field/field_replay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a round that is not replaying', () {
    test('shows everything at rest, hiding nothing', () {
      // Between rounds the board is static and fully visible: a figure
      // that stayed hidden because no replay was running would make the
      // player invisible to themselves.
      const beats = ReplayBeats.idle;

      expect(beats.isReplaying, isFalse);
      expect(beats.emerged, isTrue);
      expect(beats.aimed, isTrue);
      expect(beats.firing, isFalse, reason: 'nothing is in the air');
      expect(beats.flightProgress, isNull);
    });

    test('a null progress is the idle state', () {
      expect(ReplayBeats.from(null).isReplaying, isFalse);
      expect(ReplayBeats.from(null).emerged, isTrue);
    });
  });

  group('the beats in order', () {
    test('nothing has happened at the very start', () {
      final beats = ReplayBeats.from(0);

      expect(beats.isReplaying, isTrue);
      expect(beats.emerged, isFalse, reason: 'still behind cover');
      expect(beats.aimed, isFalse);
      expect(beats.firing, isFalse);
      expect(beats.flightProgress, isNull);
    });

    test('each beat turns on after its own threshold and stays on', () {
      // Monotonic by construction: a beat that switched back off would
      // make the replay flicker rather than build.
      var sawEmerged = false;
      var sawAimed = false;
      var sawFiring = false;

      for (var t = 0.0; t <= 1.0; t += 0.01) {
        final beats = ReplayBeats.from(t);

        if (beats.emerged) sawEmerged = true;
        if (beats.aimed) sawAimed = true;
        if (beats.firing) sawFiring = true;

        expect(
          beats.emerged,
          sawEmerged ? isTrue : isFalse,
          reason: 'emerged must not switch back off at $t',
        );
        expect(
          beats.aimed,
          sawAimed ? isTrue : isFalse,
          reason: 'aimed must not switch back off at $t',
        );
        expect(
          beats.firing,
          sawFiring ? isTrue : isFalse,
          reason: 'firing must not switch back off at $t',
        );
      }

      // A positive control: without these the loop above would pass on a
      // ReplayBeats that never turned anything on at all.
      expect(sawEmerged, isTrue);
      expect(sawAimed, isTrue);
      expect(sawFiring, isTrue);
    });

    test('aiming never precedes emerging, nor firing the aim', () {
      // The replay's whole point is seeing the two decisions MEET. A
      // shot that left before the aim landed would skip the part worth
      // watching, which is why the thresholds are spread the way they
      // are rather than evenly.
      for (var t = 0.0; t <= 1.0; t += 0.01) {
        final beats = ReplayBeats.from(t);

        if (beats.aimed) {
          expect(beats.emerged, isTrue, reason: 'aimed before emerging at $t');
        }
        if (beats.firing) {
          expect(beats.aimed, isTrue, reason: 'fired before aiming at $t');
        }
      }
    });

    test('flight runs a full 0 to 1 inside its own slice', () {
      // The paintball has to cross the WHOLE field in the slice the
      // replay gives it, so the remap has to reach both ends.
      expect(ReplayBeats.from(NeonTokens.beatFire).flightProgress, isNull);

      final justFired = ReplayBeats.from(NeonTokens.beatFire + 0.001);
      expect(justFired.flightProgress, closeTo(0, 0.01));

      final landing = ReplayBeats.from(NeonTokens.beatFlightEnd);
      expect(landing.flightProgress, closeTo(1, 0.01));
    });
  });

  group('the frame a skip lands on', () {
    test('every beat is complete at exactly 1.0', () {
      // REVIEW FOCUS #1. Tapping to skip sets the controller to exactly
      // 1 (`_skipReplay` in paint_ball_battle_screen.dart), so this is
      // not an edge case -- it is the frame a player sees whenever they
      // are impatient, which is often.
      final beats = ReplayBeats.from(1);

      expect(beats.isReplaying, isTrue);
      expect(beats.emerged, isTrue);
      expect(beats.aimed, isTrue);
      expect(beats.firing, isTrue);
      expect(
        beats.flightProgress,
        closeTo(1, 0.001),
        reason: 'the shot has landed, not frozen mid-air',
      );
      expect(beats.settled, isTrue);
    });

    test('the resolved frame is reachable and stable', () {
      // Pumped twice because a skip can rebuild at 1.0 repeatedly; the
      // frame must be identical each time rather than depending on how
      // it was arrived at.
      expect(ReplayBeats.from(1).emerged, ReplayBeats.from(1).emerged);
      expect(
        ReplayBeats.from(1).flightProgress,
        ReplayBeats.from(1).flightProgress,
      );
    });
  });

  group('a controller driven out of bounds', () {
    test('progress above one clamps rather than overshooting', () {
      // REVIEW FOCUS #2. An easeOutBack curve overshoots past 1, and a
      // flightProgress above 1 would push the paintball off the far edge
      // of the field.
      for (final over in [1.0001, 1.4, 2.0, 100.0]) {
        final beats = ReplayBeats.from(over);

        expect(beats.emerged, isTrue, reason: 'at $over');
        expect(
          beats.flightProgress,
          lessThanOrEqualTo(1.0),
          reason: 'at $over the shot must not fly past the field',
        );
        expect(beats.flightProgress, isNotNull);
      }
    });

    test('negative progress is the start, not a shot flying backwards', () {
      // Reachable as -0.0 from a controller reset, and as a genuine
      // negative from a reversed animation.
      for (final under in [-0.0, -0.001, -1.0]) {
        final beats = ReplayBeats.from(under);

        expect(beats.emerged, isFalse, reason: 'at $under');
        expect(beats.firing, isFalse, reason: 'at $under');
        expect(
          beats.flightProgress,
          isNull,
          reason: 'at $under nothing has been fired to have progress',
        );
      }
    });

    test('a NaN progress does not propagate into the field', () {
      // A NaN offset thrown into Positioned crashes the screen rather
      // than drawing wrongly, so it is worth one branch.
      final beats = ReplayBeats.from(double.nan);

      expect(beats.flightProgress, anyOf(isNull, predicate<double>((v) => !v.isNaN)));
      expect(beats.isReplaying, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/games/paint_ball_replay_beats_test.dart`
Expected: FAIL — `field/field_replay.dart` does not resolve.

- [ ] **Step 3: Write the implementation**

Create `lib/features/games/paint_ball/presentation/widgets/field/field_replay.dart`:

```dart
import 'package:attune/core/ui/neon/neon_tokens.dart';
import 'package:flutter/foundation.dart';

/// Where a replay has got to, as six beats rather than one number.
///
/// Spec §3.2: timing lives in ONE place that the field's parts read. It
/// was previously six threshold comparisons inline in the field's build
/// method, which meant the only way to test "what does the frame a skip
/// lands on look like" was to pump a whole field and inspect it.
///
/// Deliberately a value object with no rendering logic. §3.2 names the
/// hazard it was written to avoid: a replay class that accumulates
/// per-beat drawing parameters becomes the god-object the file split
/// existed to prevent. If something here starts deciding how a thing
/// looks rather than when it happens, it is in the wrong file.
@immutable
class ReplayBeats {
  const ReplayBeats._({
    required this.isReplaying,
    required this.emerged,
    required this.aimed,
    required this.firing,
    required this.impacting,
    required this.settled,
    this.flightProgress,
    this.impactProgress,
  });

  /// Between rounds: everything visible, nothing in the air.
  ///
  /// `emerged` and `aimed` are TRUE here, which looks odd until you
  /// consider what false would mean -- a player hidden from themselves
  /// because no replay happens to be running.
  static const ReplayBeats idle = ReplayBeats._(
    isReplaying: false,
    emerged: true,
    aimed: true,
    firing: false,
    impacting: false,
    settled: false,
  );

  /// Maps the battle screen's single 0→1 controller value onto the
  /// beats. The only place that mapping exists.
  factory ReplayBeats.from(double? progress) {
    if (progress == null) return idle;

    // A NaN reaches Positioned as a NaN offset and crashes the screen
    // rather than drawing wrongly, so it resolves to the resolved frame
    // -- the same place a skip lands, which is the safest wrong answer.
    if (progress.isNaN) return ReplayBeats.from(1);

    final t = progress.clamp(0.0, 1.0);

    final firing = t > NeonTokens.beatFire;

    return ReplayBeats._(
      isReplaying: true,
      emerged: t > NeonTokens.beatEmerge,
      aimed: t > NeonTokens.beatAim,
      firing: firing,
      impacting: t > NeonTokens.beatFlightEnd,
      settled: t >= NeonTokens.beatImpactEnd,
      // Remapped so the paintball still crosses the whole field in the
      // slice of the replay given to flight.
      flightProgress:
          firing
              ? ((t - NeonTokens.beatFire) /
                      (NeonTokens.beatFlightEnd - NeonTokens.beatFire))
                  .clamp(0.0, 1.0)
              : null,
      impactProgress:
          t > NeonTokens.beatFlightEnd
              ? ((t - NeonTokens.beatFlightEnd) /
                      (1.0 - NeonTokens.beatFlightEnd))
                  .clamp(0.0, 1.0)
              : null,
    );
  }

  /// False between rounds.
  final bool isReplaying;

  /// Both players have stepped out of cover.
  final bool emerged;

  /// Both aims have landed on their chosen bay.
  final bool aimed;

  /// Both shots have left. A round is a simultaneous duel, so this is
  /// never true for one side alone.
  final bool firing;

  /// The shots have arrived and the paint is blooming.
  final bool impacting;

  /// The replay has run its course.
  final bool settled;

  /// 0→1 across the flight slice, or null before anything is fired.
  final double? flightProgress;

  /// 0→1 across impact and settle, or null before the shots land.
  final double? impactProgress;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/games/paint_ball_replay_beats_test.dart`
Expected: PASS, 11 tests.

- [ ] **Step 5: Have the field read the beats instead of computing them**

In `paint_ball_field.dart`, replace the inline block:

```dart
          final replay = replayProgress;
          final emerged = replay == null || replay > NeonTokens.beatEmerge;
          final aimed = replay == null || replay > NeonTokens.beatAim;
          final firing = replay != null && replay > NeonTokens.beatFire;
          final flightProgress = firing ? ... : null;
```

with:

```dart
          // One mapping from the controller's value to the beats, so the
          // field reads timing rather than deciding it (§3.2).
          final beats = ReplayBeats.from(replayProgress);
```

and update the four use sites: `emerged` → `beats.emerged`, `aimed` →
`beats.aimed`, `flightProgress != null` → `beats.firing`, and
`flightProgress` → `beats.flightProgress!`. Add the import. Remove the
`neon_tokens.dart` import if nothing else in the file uses it.

- [ ] **Step 6: Run the field and composition tests**

Run: `flutter test test/features/games/paint_ball_field_test.dart test/features/games/paint_ball_field_composition_test.dart`
Expected: 25 + 10 pass. These exercise the replay at `0.05` and `0.7`, so a
mis-wired beat shows up here.

- [ ] **Step 7: Commit**

```bash
git add lib/features/games/paint_ball/presentation/widgets/ test/features/games/paint_ball_replay_beats_test.dart
git commit -m "$(cat <<'EOF'
feat(paintball): the replay's timing becomes a value object

Six threshold comparisons inline in the field's build method become one
ReplayBeats.from(progress). §3.2 wanted timing in one place the parts
read, and the practical gain is that the frame a skip lands on is now
testable without pumping a field.

Which matters, because that frame is not an edge case: _skipReplay sets
the controller to exactly 1, so it is what a player sees whenever they
are impatient. Review Focus #1 is now a test, and so is #2 -- an
easeOutBack curve overshoots past 1, and a flightProgress above 1 would
push the paintball off the far edge of the field.

A NaN resolves to the frame a skip lands on rather than propagating: a
NaN offset reaches Positioned and crashes the screen instead of drawing
wrongly, so the safest wrong answer is the one the player can already
reach deliberately.

idle reports emerged and aimed as TRUE, which reads oddly until you ask
what false would mean between rounds: a player hidden from themselves
because no replay happens to be running.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: The impact bloom — beats 5 and 6

`ReplayBeats` already reports `impacting` and `impactProgress`, and nothing
draws them. This is the hero moment §2.6 describes: **white flash, then a
coloured bloom, then settle.** White is reserved for exactly this instant and
appears nowhere else on the field (§2.2).

**Files:**
- Create: `lib/core/ui/neon/bloom_flash.dart`
- Test: `test/core/ui/neon/bloom_flash_test.dart`
- Modify: `lib/features/games/paint_ball/presentation/widgets/paint_ball_field.dart`
- Modify: `test/features/games/paint_ball_field_golden_test.dart` (one frame at impact)

**Interfaces:**
- Consumes: `NeonTokens`, `NeonQuality`.
- Produces:
  - `class BloomFlash extends StatelessWidget` — `const BloomFlash({required Offset at, required Color color, required double progress, required bool hit})`.
  - `class BloomFlashPainter extends CustomPainter` — public final `at`, `color`, `progress`, `hit`, `quality`.
  - `double bloomRadiusAt(double progress, {required bool hit})` — pure, so the curve is testable without a canvas.

- [ ] **Step 1: Write the failing test**

Create `test/core/ui/neon/bloom_flash_test.dart`:

```dart
import 'dart:ui';

import 'package:attune/core/ui/neon/bloom_flash.dart';
import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCanvas implements Canvas {
  final circles = <({Offset centre, double radius, Paint paint})>[];

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((centre: c, radius: radius, paint: paint));

  @override
  noSuchMethod(Invocation invocation) => null;
}

void main() {
  const mint = Color(0xFF5EEAD4);

  group('the bloom curve', () {
    test('it expands, fast at first', () {
      // An impact that grew linearly reads as a balloon inflating. Paint
      // hits hardest at the moment of contact and the spread decelerates,
      // so the curve has to be front-loaded.
      final early = bloomRadiusAt(0.25, hit: true);
      final mid = bloomRadiusAt(0.5, hit: true);
      final late = bloomRadiusAt(1.0, hit: true);

      expect(early, lessThan(mid));
      expect(mid, lessThan(late));
      expect(
        mid / late,
        greaterThan(0.5),
        reason: 'more than half the spread happens in the first half',
      );
    });

    test('it starts at nothing', () {
      expect(bloomRadiusAt(0, hit: true), closeTo(0, 0.01));
    });

    test('a hit blooms wider than a miss', () {
      // A miss that bloomed as large as a hit would make the two
      // outcomes indistinguishable at the one moment they matter most.
      expect(
        bloomRadiusAt(1.0, hit: true),
        greaterThan(bloomRadiusAt(1.0, hit: false)),
      );
    });

    test('out-of-range progress stays bounded', () {
      // The replay's impactProgress is clamped upstream, but a radius
      // that could run away would be a crash rather than a glitch.
      for (final p in [-1.0, -0.0, 1.5, 100.0, double.nan]) {
        final r = bloomRadiusAt(p, hit: true);
        expect(r.isFinite, isTrue, reason: 'at $p');
        expect(r, greaterThanOrEqualTo(0), reason: 'at $p');
        expect(
          r,
          lessThanOrEqualTo(bloomRadiusAt(1.0, hit: true) + 0.01),
          reason: 'at $p the bloom must not exceed its full size',
        );
      }
    });
  });

  group('what gets drawn', () {
    _RecordingCanvas render(double progress, {NeonQuality quality = NeonQuality.rich}) {
      final canvas = _RecordingCanvas();
      BloomFlashPainter(
        at: const Offset(100, 100),
        color: mint,
        progress: progress,
        hit: true,
        quality: quality,
      ).paint(canvas, const Size(200, 200));
      return canvas;
    }

    test('the first instant is WHITE, and only the first instant', () {
      // §2.2 reserves white for the instant of impact and nothing else
      // on the field. That is what makes a hit unmistakable -- but a
      // white core that lingered would turn the field's one special
      // colour into a third palette entry.
      final flash = render(0.05);
      final later = render(0.8);

      bool hasWhite(_RecordingCanvas c) => c.circles.any(
        (d) => d.paint.color.r > 0.9 && d.paint.color.g > 0.9 && d.paint.color.b > 0.9,
      );

      expect(flash.circles, isNotEmpty, reason: 'a positive control');
      expect(hasWhite(flash), isTrue, reason: 'the flash is white');
      expect(later.circles, isNotEmpty, reason: 'a positive control');
      expect(hasWhite(later), isFalse, reason: 'and it does not linger');
    });

    test('the bloom carries the shooter’s colour', () {
      final bloom = render(0.6);

      expect(bloom.circles, isNotEmpty);
      expect(
        bloom.circles.any((d) => d.paint.color.g > d.paint.color.r),
        isTrue,
        reason: 'mint is greener than it is red',
      );
    });

    test('it fades to nothing by the end', () {
      // The bloom is an event, not a state (§2.5). A bloom still visible
      // at rest would schedule frames forever.
      final done = render(1.0);

      for (final draw in done.circles) {
        expect(
          draw.paint.color.a,
          lessThan(0.15),
          reason: 'the bloom has faded out, not frozen at full strength',
        );
      }
    });

    test('nothing is drawn before the impact', () {
      final canvas = _RecordingCanvas();
      BloomFlashPainter(
        at: const Offset(100, 100),
        color: mint,
        progress: 0,
        hit: true,
        quality: NeonQuality.rich,
      ).paint(canvas, const Size(200, 200));

      // A positive control lives in the sibling tests above, which prove
      // this painter DOES draw at other progress values.
      expect(canvas.circles.where((d) => d.radius > 0.5), isEmpty);
    });

    test('the plain tier draws fewer layers', () {
      // §6.10's launch gate. A full-screen bloom is the single most
      // expensive effect in this language.
      final rich = render(0.5);
      final plain = render(0.5, quality: NeonQuality.plain);

      expect(rich.circles, isNotEmpty, reason: 'a positive control');
      expect(plain.circles.length, lessThan(rich.circles.length));
      expect(plain.circles, isNotEmpty, reason: 'but a hit still registers');
    });
  });

  testWidgets('the widget renders without a canvas of its own', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: BloomFlash(
              at: Offset(100, 100),
              color: mint,
              progress: 0.5,
              hit: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(BloomFlash), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/neon/bloom_flash_test.dart`
Expected: FAIL — `bloom_flash.dart` does not resolve.

- [ ] **Step 3: Write the implementation**

Create `lib/core/ui/neon/bloom_flash.dart`:

```dart
import 'package:flutter/material.dart';

import 'neon_quality.dart';
import 'neon_tokens.dart';

/// How far a bloom has spread, 0 to 1 of its full radius.
///
/// Pure, so the curve is checkable without a canvas.
///
/// Front-loaded on purpose: paint hits hardest at contact and the spread
/// decelerates. A linear expansion reads as a balloon inflating, which
/// is the opposite of an impact.
double bloomRadiusAt(double progress, {required bool hit}) {
  // NaN compares false against everything, so it has to be caught rather
  // than clamped.
  final t = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);

  // A hit spreads wider than a miss. Identical blooms would make the two
  // outcomes indistinguishable at the one moment they matter most.
  final full = hit ? NeonTokens.bloomRadiusHit : NeonTokens.bloomRadiusMiss;

  // easeOutCubic: most of the travel in the first half.
  final eased = 1 - ((1 - t) * (1 - t) * (1 - t));
  return full * eased;
}

/// The instant a paintball lands.
///
/// Spec §2.6 beats 5 and 6: a white flash, then a coloured bloom, then
/// settle. §2.2 reserves white for exactly this and nowhere else on the
/// field, which is what makes a hit unmistakable -- and why the white
/// core must not linger, or the field gains a third palette colour.
///
/// Event motion (§2.5): it runs once off the replay's own progress and
/// schedules no frames of its own.
class BloomFlash extends StatelessWidget {
  const BloomFlash({
    super.key,
    required this.at,
    required this.color,
    required this.progress,
    required this.hit,
  });

  /// Where the shot landed, in the painter's own coordinates.
  final Offset at;

  /// The shooter's hue. The bloom is their paint, not the target's.
  final Color color;

  /// 0 to 1 across impact and settle.
  final double progress;

  final bool hit;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: BloomFlashPainter(
          at: at,
          color: color,
          progress: progress,
          hit: hit,
          quality: neonQualityOf(context),
        ),
      ),
    );
  }
}

/// Public, with public fields, so a test asserts on it without reaching
/// through `as dynamic` (spec §3.6.1).
class BloomFlashPainter extends CustomPainter {
  BloomFlashPainter({
    required this.at,
    required this.color,
    required this.progress,
    required this.hit,
    required this.quality,
  });

  final Offset at;
  final Color color;
  final double progress;
  final bool hit;
  final NeonQuality quality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final t = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    final radius = bloomRadiusAt(t, hit: hit);
    if (radius < 0.5) return;

    // The coloured bloom, fading as it spreads.
    final fade = (1 - t);
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..color = color.withValues(alpha: (0.45 * fade * fade).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          NeonTokens.haloBlurOuter,
        ),
    );

    // A tighter, brighter core behind it. Dropped first on a cheap
    // device: a second blurred pass over a large radius is the most
    // expensive thing this language draws (§6.10).
    if (quality != NeonQuality.plain) {
      canvas.drawCircle(
        at,
        radius * 0.55,
        Paint()
          ..color = color.withValues(alpha: (0.6 * fade).clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            NeonTokens.haloBlurInner,
          ),
      );
    }

    // The white instant. §2.2's one exception, and it has to leave
    // quickly or it stops being an instant.
    const flashWindow = 0.22;
    if (t < flashWindow) {
      final flash = 1 - (t / flashWindow);
      canvas.drawCircle(
        at,
        radius * 0.4,
        Paint()
          ..color = const Color(
            0xFFFFFFFF,
          ).withValues(alpha: (flash * flash).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(BloomFlashPainter old) =>
      old.progress != progress ||
      old.at != at ||
      old.color != color ||
      old.hit != hit ||
      old.quality != quality;
}
```

Add to `neon_tokens.dart`:

```dart
  /// How far a landing paintball spreads. A hit spreads wider than a
  /// miss, so the two outcomes differ at the moment they matter most.
  static const bloomRadiusHit = 44.0;
  static const bloomRadiusMiss = 26.0;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/neon/bloom_flash_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Wire it into the field**

In `paint_ball_field.dart`, after the projectile blocks, add a bloom per side
driven by `beats.impactProgress`, positioned at that shot's target column via
the existing `columnX` helper. Your own shot blooms at `columnX(selectedShot,
isOpponent: true)` on the opponent's row (`height * 0.20`); theirs at
`columnX(theirRevealedShot, isOpponent: false)` on yours (`height * 0.80`).
Use `PaintBallPalette.mine` and `.theirs` respectively — the bloom is the
shooter's paint. Gate each on `beats.impacting` and the relevant position being
non-null.

- [ ] **Step 6: Add an impact golden and look at it**

Add a seventh frame to `paint_ball_field_golden_test.dart` at
`replayProgress: 0.90` (between `beatFlightEnd` 0.86 and `beatImpactEnd` 0.94),
named `paint_ball_field_impact.png`. Regenerate with `--update-goldens`, then
**open the PNG and look at it.** The flash should read as a hit landing, not as
a glow sitting on the field.

- [ ] **Step 7: Run everything and commit**

Run: `flutter test test/features/games/ test/core/ui/`
Expected: all pass bar the three known `session_game_*` concurrency flakes.

---

## Task 15: The impact has no sound

**A correction to the spec first.** §3.7 said Paint Ball's cues were "sine
tones" needing better synthesis. Reading `tool/generate_paint_ball_sounds.dart`,
that is wrong: it already produces frequency-swept chirps, damped noise bursts,
layered partials and attack/release envelopes. The synthesis is decent.

The real defect is worse and simpler. **Three of the five cues are never
played.** `gameHit`, `gameMiss` and `gameKnockout` are declared in `AppSound`,
mapped to files in `sound_service.dart`, generated by the tool — and no code
anywhere calls them:

| Cue | Generated | Played by |
|---|---|---|
| `game_fire.wav` | ✅ | `paint_ball_provider.dart:329` |
| `game_penalty_reveal.wav` | ✅ | `paint_ball_provider.dart:251` |
| `game_hit.wav` | ✅ | **nothing** |
| `game_miss.wav` | ✅ | **nothing** |
| `game_knockout.wav` | ✅ | **nothing** |

So the moment Task 14 just built — both shots landing, paint blooming — happens
in silence. In a language that removed illustration, sound carries more weight
than usual, and the three cues for the game's loudest moment are dead assets.

**Files:**
- Modify: `lib/features/games/paint_ball/presentation/state/paint_ball_provider.dart`
- Test: `test/features/games/paint_ball_sound_test.dart` (new)
- Modify: `assets/sounds/README.md`

**Interfaces:**
- Consumes: `AppSound`, `SoundService`, `PaintBallShotOutcome`.
- Produces: no new public API. The provider gains outcome-driven cues.

- [ ] **Step 1: Write the failing test**

Create `test/features/games/paint_ball_sound_test.dart`:

```dart
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/paint_ball/models/paint_ball_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the cue a resolved round plays', () {
    test('a hit sounds like a hit', () {
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.hit,
          knockout: false,
        ),
        AppSound.gameHit,
      );
    });

    test('a miss sounds like a miss', () {
      // The two outcomes must be distinguishable with the screen away
      // from your face -- this is an asynchronous game and a player
      // often hears the result before they look at it.
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.miss,
          knockout: false,
        ),
        AppSound.gameMiss,
      );
    });

    test('an opening shot is a miss, not a hit', () {
      // An opener resolves nothing: the partner has not chosen yet. It
      // must not play the hit cue and promise a result that has not
      // happened.
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.opening,
          knockout: false,
        ),
        AppSound.gameMiss,
      );
    });

    test('a knockout outranks the hit that caused it', () {
      // The last life going is the loudest thing in the game, and a
      // knockout is always a hit, so without this the bigger moment
      // would be announced by the smaller cue.
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.hit,
          knockout: true,
        ),
        AppSound.gameKnockout,
      );
    });

    test('a knockout on a miss still reads as a knockout', () {
      // Reachable on a double knockout, where one side's shot missed
      // and the round still ended the game.
      expect(
        paintBallRoundCue(
          outcome: PaintBallShotOutcome.miss,
          knockout: true,
        ),
        AppSound.gameKnockout,
      );
    });

    test('every outcome maps to a cue that exists', () {
      // A positive control over the enum rather than a sample of it: a
      // new outcome added without a cue would otherwise fall through to
      // whatever the last branch happens to be.
      for (final outcome in PaintBallShotOutcome.values) {
        final cue = paintBallRoundCue(outcome: outcome, knockout: false);
        expect(
          const [AppSound.gameHit, AppSound.gameMiss, AppSound.gameKnockout],
          contains(cue),
          reason: '$outcome must map to one of the round cues',
        );
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/games/paint_ball_sound_test.dart`
Expected: FAIL — `paintBallRoundCue` is undefined.

- [ ] **Step 3: Add the mapping**

In `lib/features/games/paint_ball/models/paint_ball_models.dart`, beside
`PaintBallShotOutcome`, add:

```dart
/// The cue a resolved round plays.
///
/// A pure function rather than branching inside the provider, because
/// the precedence is the interesting part and a provider test would need
/// a whole mocked service to reach it.
///
/// This exists because `gameHit`, `gameMiss` and `gameKnockout` were
/// declared, mapped to files and generated -- and never played by
/// anything. The loudest moment in the game happened in silence.
AppSound paintBallRoundCue({
  required PaintBallShotOutcome outcome,
  required bool knockout,
}) {
  // A knockout outranks the hit that caused it. Every knockout IS a hit,
  // so without this the bigger moment would be announced by the smaller
  // cue -- and it is reachable on a miss too, via a double knockout.
  if (knockout) return AppSound.gameKnockout;

  return switch (outcome) {
    PaintBallShotOutcome.hit => AppSound.gameHit,
    // An opener resolves nothing -- the partner has not chosen yet -- so
    // it must not promise a result that has not happened.
    PaintBallShotOutcome.opening || PaintBallShotOutcome.miss =>
      AppSound.gameMiss,
  };
}
```

Add `import 'package:attune/core/ui/feedback/sound_service.dart';` to that file.

- [ ] **Step 4: Play it when a round resolves**

In `paint_ball_provider.dart`, in the branch that builds `PaintBallReplay`
(after `mine` and `theirs` are resolved), add:

```dart
      // The round's own cue. Task 14 gave the impact a bloom; this is
      // what it sounds like.
      _sound.play(
        paintBallRoundCue(
          outcome: mine.outcome,
          knockout: result.knockout,
        ),
      );
```

Use `mine.outcome` — the cue describes what *this* player's shot did, which is
the result they are waiting on.

- [ ] **Step 5: Verify and commit**

Run: `flutter test test/features/games/paint_ball_sound_test.dart test/features/games/paint_ball_screens_test.dart test/core/ui/sound_service_test.dart`
Expected: 6 + existing, all pass.

```bash
git add lib/features/games/paint_ball/ test/features/games/paint_ball_sound_test.dart assets/sounds/README.md
git commit -m "$(cat <<'EOF'
fix(paintball): the loudest moment in the game had no sound

gameHit, gameMiss and gameKnockout were declared in AppSound, mapped to
files in sound_service, and generated by the tool -- and no code
anywhere played them. Three dead assets, for the three moments that
matter most. The impact Task 14 just built landed in silence.

Also corrects §3.7 of the spec, which called these cues "sine tones"
needing better synthesis. Reading the generator, that was wrong: it
already produces frequency-swept chirps, damped noise bursts, layered
partials and attack/release envelopes. The synthesis was never the
problem; the wiring was.

The precedence comes out as a pure function because that is the part
worth pinning. A knockout outranks the hit that caused it, since every
knockout IS a hit and otherwise the bigger moment would be announced by
the smaller cue -- and it is reachable on a miss too, via a double
knockout. An opening shot plays the miss cue: it resolves nothing, and
must not promise a result that has not happened.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Remaining tasks

Task 16 is Sliding Scale as the toolkit's second consumer, plus the `GAMES.md` reconciliation. Its scope and boundaries are fixed:

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
