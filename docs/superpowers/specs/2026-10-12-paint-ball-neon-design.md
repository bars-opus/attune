# Paint Ball — neon-dark rebuild, and the Arcade's visual foundation

**Status:** approved design, ready for implementation planning.
**Date:** 2026-10-12
**Branch:** `feat/games-advance` (worktree `.worktrees/games-v2`)
**Scope:** client-side rendering only. **Zero migrations, zero server changes.**
**Reference point:** GamePigeon's craft level, explicitly *not* its aesthetic.

This document governs Paint Ball's visual rebuild and the shared
`lib/core/ui/neon/` toolkit it establishes. Requirements below are normative
design contracts, not claims that corresponding code exists.

---

## 0. Decisions

Six decisions were taken during brainstorming. Three reverse an earlier
answer in the same conversation; they are recorded with their reversal so the
reasoning is not lost.

| # | Decision | Note |
|---|---|---|
| D1 | **Art direction: neon-dark minimal**, not GamePigeon's illustrated world | Reverses an initial choice of the illustrated direction. See §1.2 |
| D2 | **The dark games surface stays.** `GameHubTheme` and `GamePalette` are the foundation | Reverses an initial decision to move off the dark storefront |
| D3 | **Mechanic unchanged.** Hidden-position bluffing, server-resolved, turn-based | No aiming skill, no physics, no rules change |
| D4 | **Figures are per-couple tinted luminous marks**, not photos and not drawn cartoon bodies | Survives from the illustrated direction in altered form |
| D5 | **No engine.** Pure Flutter. Flame rejected for this game | See §1.3 for the condition that would reverse this |
| D6 | **Sound: regenerate procedurally**, still labelled placeholder | Paint Ball's five cues only |

### 0.1 Why the art direction reversed

The illustrated direction was chosen first and abandoned deliberately. Three
arguments decided it, in descending weight:

1. **Reachability.** GamePigeon is roughly 80% illustration and 20% code. That
   look requires an illustrator or a long, uncertain asset-generation cycle. The
   neon direction is code, buildable to a high standard without an asset
   dependency on anyone.
2. **Payload thrift.** `ATTUNE_THESIS.md` §6.10 makes performance budgets on
   representative Ghanaian hardware a launch gate and payload thrift "a
   permanent discipline rather than an optimization pass." The illustrated
   direction would have shipped megabytes of raster art over metered data. The
   neon direction ships approximately none.
3. **Coherence.** `GamePalette` already assigns every game a saturated hue
   chosen *for* a dark ground, and documents that those colours only work there.
   The neon direction makes that existing system correct rather than discarded,
   and it is the only direction that scales to the four visually-anonymous
   session games without four more art commissions.

A fourth, softer argument: the game's subject is concealment. A dark field where
things are hidden and revealed by light serves the mechanic. A sunlit meadow
fights it.

### 0.2 The standard this must not fall to

The visual references that prompted D1 are **infographics** — static, flat,
cold. An infographic rendering of this game would be *less* appealing than what
exists today. The target is a **game**: light, depth, weight, motion and sound.
Monument Valley or a premium dark dashboard, never a flat diagram.

---

## 1. Product and technical boundary

### 1.1 What Attune's Paint Ball is

It shares a name with GamePigeon's Paintball and nothing else. GamePigeon's is
an artillery game whose pleasure is aiming well. Attune's is a
**hidden-information bluffing game**: each player picks one of three positions
(`kPaintBallPositions = 3`) to hide behind and one to shoot at, both choose
without seeing the other, and a hit means they guessed right. A round resolves
as a **simultaneous duel**, not alternating turns — both shots cross in the air
during the replay (§2.6). The board already counts repeat choices (`SAME SPOT xN`) because, as the
existing code comment states, staying put "is stubbornness, or a bluff, or a
dare to try the same spot twice."

That is a game about reading your partner, which is Attune-shaped in a way
artillery is not. D3 protects it. Under the current design a miss means *you
misread your partner*; adding aim skill would let a miss mean *your thumb
slipped*, which is a different and lesser game.

### 1.2 Craft parity, not aesthetic parity

"GamePigeon-level" is interpreted throughout as **craft parity**: a player
should open this and think "this is a real game," not "this is GamePigeon."
Feature parity and aesthetic parity are explicit non-goals.

### 1.3 Why no engine

Flame's value is a continuous simulation — entities whose state evolves every
frame. Paint Ball has none. Its entire animation is one `AnimationController`
driving a single `0.0 → 1.0` value that the field reads as four timing
thresholds; the outcome is decided by the server before the animation begins.
The replay is a recap of a known result, i.e. a **timeline, not a simulation**.

Adopting Flame would cost four concrete things:

- **Reduce-motion plumbing.** `reduceMotionOf(context)` is an `InheritedWidget`
  lookup. Flame components have no `BuildContext`; every reduce-motion
  guarantee would need manual bridging. The games are fully reduce-motion-safe
  today and that is an accessibility property, not a nicety.
- **Golden coverage.** A Flame canvas does not render deterministically under
  `flutter test` without substantial harness work.
- **A Riverpod seam** that exists only to serve the dependency.
- **The particle system we would write anyway** — a paint-droplet emitter is
  roughly 150 lines of `CustomPainter`, less than the integration layer.

Unity is rejected for a larger version of the same reasons plus 60–100MB of
build size against §6.10. Roblox is not an embeddable library and was never an
option.

**The condition that reverses D5:** if the Arcade later wants a game with real
continuous physics — pool, mini-golf, archery, tanks — Flame plus `forge2d`
becomes the correct choice and this decision should be revisited rather than
defended.

### 1.4 Constraints this design is bound by

All drawn from existing project documents, none invented here.

| Constraint | Source |
|---|---|
| Performance budgets on representative Ghanaian hardware are a launch gate | `ATTUNE_THESIS.md` §6.10 |
| Payload thrift is a permanent discipline | `ATTUNE_THESIS.md` §6.10 |
| No infinite or looping animations — battery and jank budget | `GlowPulse` doc comment |
| Durations live in tokens, never literals; 150–320ms band | Master Spec §17.4 |
| Every animated primitive degrades under OS reduce-motion | `lib/core/ui/motion/reduce_motion.dart` |
| Docs are updated in the same pass as the code | `ATTUNE_THESIS.md` §6.11 |

### 1.5 Explicit non-goals

- No migrations, RPCs, RLS changes or edge functions. This branch is
  client-side only and cannot collide with concurrent sessions working in the
  `20261012_2xxxxx` migration range.
- No change to Paint Ball's rules, scoring, lifecycle or server contract.
- No changes to the other nine games, except Sliding Scale in §4 Stage 7.
- No new raster assets. The direction is rendered entirely in code; if a
  trivial exception is ever warranted (for example a tiling grain texture) it
  requires an explicit amendment to this section, because §6.10's payload
  thrift is one of the reasons the direction was chosen (§0.1).
- No fragment shaders in this work. Deferred until the blur-glow baseline is
  measured on real low-end hardware (§5.1).
- No parameter-list cleanup of `PaintBallField`. Its public signature is frozen
  (§3.3); cleanup is a separate later change so a regression cannot be
  ambiguous between the two.

---

## 2. Visual language

Six normative rules. Everything rendered on the field must satisfy them.

### 2.1 Light is the only material

No textures, no illustration, no gradients as decoration. Every element is
either a surface that receives light or a thing that emits it. Three tiers,
and nothing exists outside them:

| Tier | Members | Treatment |
|---|---|---|
| **Ground** | The field | Near-black `#07070A`. Receives light, emits none. A low-amplitude radial light-well behind the centre so the field has a middle rather than being a flat void. |
| **Structure** | Cover bays, divider, labels | Thin luminous outlines, unfilled at rest, dim (alpha ≈ 0.25). Architecture: present, not shouting. A bay may be transiently filled with light while a reveal plays (§2.3); it returns to unfilled when the beat settles. |
| **Actors** | Figures, paintball, splats | Fully lit. Emit glow and cast onto the ground. The only bright things on screen. |

The governing discipline: **if everything glows, nothing does.** When the
composition looks gaudy the correct fix is always to remove a glow, never to
add one.

### 2.2 Colour means ownership, and nothing else

The existing `PaintBallPalette` ownership colours are retained: mint `#5EEAD4`
is yours, rose `#FF4D6A` is theirs. Two changes:

- **The third hue is removed.** A figure is currently `#FFC94D`, documented as
  "deliberately neither side's colour." Under §2.2 that is a third hue
  competing for attention and it breaks the ownership rule. Figures take their
  owner's hue: you are mint, they are rose.
- **White is reserved for the instant of impact.** Nothing else on the field is
  ever white, which makes a hit unmistakable.

### 2.3 Cover is a light gate, not an object

The keystone of the design. Each of the three positions is a vertical **bay**
outlined in dim light. A figure behind cover is *occluded* — its glow leaks
around the bay's edges, but the figure itself is not drawn.

Concealment is therefore rendered as **literal darkness**, which matches the
mechanic exactly: the game turns on hidden information, and hiding appears as
an absence of light. When a round resolves, light floods the revealed bay and
the figure appears standing inside it.

**This is explicitly provisional.** It is the design's biggest visual bet. The
cover renderer sits behind a `PaintBallCoverStyle` interface with
bay-of-darkness as the first implementation, so replacing it with a drawn or
solid object is a new class rather than surgery on the field (§5 risk table).

### 2.4 Your side is lit, their side is not

Deliberately asymmetric. Your row sits in a soft pool of your own hue — you see
yourself, your bay, your aim. Their row is darker, cooler and further away,
showing only dim bay outlines. You are peering across at shapes.

This also reinforces a property the existing code already relies on: the field
never flips, so "mine is bottom, theirs is top" is learned once. Lighting
teaches it without a label.

### 2.5 Motion is the art, inside the battery budget

Motion is divided in two, and the division is normative:

- **Event motion** fires once, settles to a static end-state, and schedules no
  further frames. The replay, impact bloom, splat landing and reveal are all
  event motion. Nearly all spectacle lives here, and it is free in battery
  terms because it stops.
- **Ambient motion** is permitted in exactly one place: a slow breath on the
  active player's bay while awaiting input, following `GlowPulse`'s existing
  pattern of a few cycles then settle. Nothing else may loop, ever.

Consequently **the field at rest is a still image.** This is not a compromise.
A still, well-composed frame that bursts into motion on an event reads as more
expensive than perpetual wobble, and it is what allows the game to run inside
§6.10's budget.

### 2.6 The replay is the hero

The existing four beats (emerge 0.12 / aim 0.34 / fire 0.52 / flight to 0.86)
are well-judged and their rationale — the point is seeing the two decisions
meet — is retained. Light is added to each, and the sequence extended to six:

**A round is a simultaneous duel, not alternating turns.** Both players chose
without seeing the other, so during a replay *both* sides emerge, aim and fire,
and the two paintballs cross in the air. `paint_ball_field_test.dart` pins this
("mid-replay both paintballs are in flight at once" expects two projectiles).
Every beat below therefore happens twice over, once per side, in parallel.

1. **Emerge** — both bays light; both figures rise out of darkness.
2. **Aim** — a thin, dim beam from each shooter toward their chosen bay. A
   suggestion of a line, not a tracer, so the beat reads as *intent*.
3. **Fire** — the beams snap off; both balls leave on a muzzle flash that
   briefly lights each shooter's bay.
4. **Flight** — the balls travel with short motion trails and **cast light on
   the ground as they pass**, crossing mid-field. This single effect is
   expected to carry the design's credibility more than any other.
5. **Impact** — white flash, then paint blooms outward in each shooter's hue.
   Where a shot found its target, that bay floods with light and the figure is
   revealed standing in it.
6. **Settle** — the splat dims to a wet, slightly glossy decal for the rest of
   the replay, then leaves with it.

**Correction to an earlier draft of this section:** paint must *not* persist
across rounds. `paint_ball_battle_screen.dart` passes `onlyRound: replay?.roundNumber`
so paint belongs to the shot being watched, not to the match, and
`paint_ball_field_test.dart` pins it ("an idle board carries no paint").
The reason is a fairness and privacy property, not aesthetics: accumulated
paint is a map of where your partner has already fired — their habits
readable for free, which is the clue this game asks you to earn. A persistent
decal would reintroduce a deliberately fixed bug. Paint arrives with the shot
and leaves with the replay.

The four existing thresholds are retained as the first four beats. Impact and
settle occupy the tail the current implementation leaves unused: impact begins
when flight completes (existing `0.86`) and settle runs from there to `1.0`.
Exact fractions are tuned at Stage 4 against a rendered frame and live in
`neon_tokens.dart`, not as literals (§17.4). The invariant that matters is
§3.5's: **all six beats must render correctly at exactly `1.0`**, because
`_skipReplay` jumps there.

Total ≈ 2.5–3s, entirely event motion, and intended to be worth watching twice.

---

## 3. Architecture

### 3.1 The toolkit: `lib/core/ui/neon/`

A sibling to the existing `lib/core/ui/motion/` and `lib/core/ui/feedback/`.
Deliberately thin: it contains only primitives Paint Ball actually consumes.
**No speculative API.** The second consumer extends it (§4 Stage 7).

| File | Purpose | Verified by |
|---|---|---|
| `neon_tokens.dart` | Alpha tiers, blur radii, glow spreads, bay geometry ratios, beat durations. Satisfies §17.4's no-literals rule. | Pure constants |
| `light_well.dart` | The ground's radial falloff; gives the field a middle. | Golden |
| `glow_stroke.dart` | A luminous outline: core stroke plus two blurred halo passes. The workhorse primitive. | Golden |
| `lit_mark.dart` | An emitting actor (figure, ball): glow plus optional ground-cast. | Golden |
| `bloom_flash.dart` | One-shot impact: white core → coloured bloom → fade. Self-terminating event motion. | Widget + golden |
| `paint_burst.dart` | Droplet emitter: scatter, gravity, wet highlight, settle to static decal. | Unit (fixed seed) + golden |
| `neon_quality.dart` | Resolves device tier → enabled layers. The §6.10 guard. | Unit |

`neon_quality.dart` resolves to `plain | glow | rich`, and every primitive reads
it. Under `plain`, halo passes collapse to a single stroke and bursts drop to a
handful of droplets. This is how the launch gate is honoured structurally rather
than hoped at, and it doubles as the kill-switch if shaders are added later.

### 3.2 Paint Ball restructured

`paint_ball_field.dart` is 958 lines performing five jobs. It becomes a
directory of focused parts:

```
paint_ball/presentation/widgets/field/
  paint_ball_field_keys.dart — stable Keys and typed test seams (§3.6.1)
  paint_ball_field.dart   — composition and layout only (~180 lines)
  field_ground.dart       — light well, divider, row labels
  cover_bay.dart          — ONE bay, behind PaintBallCoverStyle (the §2.3 seam)
  cover_row.dart          — the three bays, selection and aim state
  field_figure.dart       — a player as a lit mark, occlusion-aware
  field_paint.dart        — splat accumulation, wraps paint_burst
  field_replay.dart       — the six-beat choreography, reads one progress value
```

Each part answers in one line what it does, how it is used and what it depends
on. `field_replay.dart` is the only part holding timing knowledge; today those
thresholds are literals smeared through a build method.

**Known hazard:** `field_replay.dart` could become a god-object by accumulating
timing, beat state and per-beat rendering parameters. Its contract is therefore
to expose a plain `ReplayBeats` value object — a record of booleans and
progress fractions — that other parts *read*. If it begins to acquire rendering
logic, that is the signal it has become the thing this split was meant to avoid.

### 3.3 What does not move

Screens, provider, service, models and analytics are untouched.
**`PaintBallField`'s public constructor signature is frozen**, so its callers
compile unchanged. This keeps the blast radius inside the widget layer, which
is the deliberate regression guard: no shared files, no routing, no providers.

**Correction to an earlier draft of this section.** It named two importers and
one shared constant. The real public surface of `paint_ball_field.dart` is
wider, and all of it must stay reachable from that same import path or files
this work promised not to touch will break:

| Public symbol | Consumed by |
|---|---|
| `PaintBallField` | `paint_ball_battle_screen.dart`, `paint_ball_lobby_screen.dart`, `paint_ball_knockout_screen.dart` |
| `kPaintBallPositions` | `paint_ball_provider.dart:14` (an explicit `show` import) |
| `kPaintBallCoverWidth`, `kPaintBallTargetScale` | the field's own row layout |
| `PaintBallPalette` (`.field`, `.mine`, `.theirs`, `.player`, `.divider`) | `paint_ball_history_screen.dart`, `paint_ball_lives_display.dart` |
| `PaintSplat` | `paint_ball_battle_screen.dart`, `paint_ball_screens_test.dart` |
| `paintBallPositionName()` | the field's semantic labels |

Six files import this one, not two. Moving any of these symbols is out of
scope; the split keeps them exported from
`paint_ball/presentation/widgets/paint_ball_field.dart`.

Two consequences worth stating. `PaintBallPalette.player` is the neutral yellow
§2.2 removes from the field — but `paint_ball_history_screen.dart` also reads
it, so the constant stays (possibly deprecated) even after the field stops
using it; deleting it would break a screen this work does not touch. And the
semantic labels `'<Name> target'` / `'<Name> cover'` from `paintBallPositionName`
are the **genuinely stable test hooks**: they are accessibility contracts rather
than implementation details, which is why §3.6.1's rewrite should prefer them
over painter type names wherever a test can use them.

### 3.4 Data flow

Unchanged, and stated because it is why the work is safe:

```
server resolves round → provider → battle screen
  → AnimationController (one 0→1 value)
  → PaintBallField
  → field_replay maps progress → six beat states
  → each part renders its beat
```

No new state and no new source of truth. The replay remains a pure function of
one double.

### 3.5 Error and edge handling

Existing behaviour is preserved; the new concerns are rendering-only.

| Case | Required behaviour |
|---|---|
| OS reduce-motion on | Every primitive renders its end-state. The replay presents as resolved. Matches current behaviour. |
| Mid-replay skip (`_skipReplay`) | Controller value is set to `1`. All six beats must render correctly at exactly `1.0`; this boundary is tested. |
| Legacy rounds | `shotPosition` / `hidePosition` are nullable for pre-position rounds. Bays render empty and must not throw. |
| Low-end device | `neon_quality` degrades silently. No user-facing message. |

### 3.6 Testing

- **Unit:** `neon_quality` tiering; `paint_burst` determinism under a fixed
  seed; `field_replay` beat boundaries, including `0.0` and `1.0`.
- **Golden:** field at rest, mid-flight, on hit, on miss, under reduce-motion,
  and at `plain` quality. Six goldens, which is where regressions will actually
  be caught.
- The suite must remain green (128+ tests at time of writing).

#### 3.6.1 The existing field test is a specification, not an obstacle

`paint_ball_field_test.dart` holds 25 tests, several recording device-reported
regressions ("the triangle sat at the right edge of its cover", "both rows
domed the same way"). It is the most valuable artifact in this work and its
*behavioural* assertions are normative.

An earlier draft of this section promised the file would pass **unmodified**.
That is not achievable and the promise is withdrawn. The tests reach into
rendering internals by design:

- They identify painters by runtime type *name* substring — `'Triangle'`,
  `'Shield'`, `'Projectile'`, `'Splat'`.
- They read painter fields dynamically — `(painter as dynamic).opensDown`,
  `.splats`, `.progress`.

Renaming `_TrianglePainter` to a lit mark breaks roughly a dozen assertions by
construction, with no behaviour change.

**The contract is therefore split in two, and the distinction is normative:**

| Assertion kind | Treatment |
|---|---|
| **Behavioural** — what the field does: only your own position visible; both shots airborne mid-replay; no shot before the aim lands; rows tap to distinct actions; nothing selectable out of turn; figure centred in its cover at several widths; rows face each other; partner named; streak shown only during replay; idle board carries no paint; repositioning travels rather than teleports and steps clear of cover; reduce-motion durations are zero | **Must survive, every one.** Each is re-expressed against the new structure. None may be deleted or weakened. |
| **Structural** — painter type-name substrings and `as dynamic` field reads | May be rewritten to match new names and types. The *assertion* is preserved; only its hook changes. |

**Required mitigation.** To stop the structural coupling recurring, the new
parts expose explicit, typed test seams rather than relying on private painter
names: each field part carries a stable `Key` from a `PaintBallFieldKeys`
constant class, and painters needing inspection expose public final fields
instead of being read through `dynamic`. The rewritten test uses those.

**Required evidence.** Before Stage 2 begins, the 25 tests are enumerated in
the plan with each one mapped to its replacement, so a dropped behaviour is
visible as a gap rather than discovered later. A behavioural assertion that
genuinely no longer applies is removed only with a written justification in
the commit message.

### 3.7 Sound

`tool/generate_paint_ball_sounds.dart` is extended to produce layered noise
bursts with pitch envelopes in place of sine tones, for the five existing cues:
`game_fire`, `game_hit`, `game_miss`, `game_knockout`, `game_penalty_reveal`.
Filenames are unchanged so no call sites move.
`assets/sounds/README.md` retains the placeholder label and the
cultural/clinical review gate — this work improves the placeholders, it does not
close that gate.

---

## 4. Build sequence

Seven stages. Each ends with something runnable and committed, so the work can
be stopped or redirected at any boundary.

| Stage | Content | Ends with |
|---|---|---|
| 1 | `neon_tokens`, `neon_quality`, `glow_stroke`, `light_well`. No Paint Ball changes. | Four tested primitives; nothing yet visible in the app. |
| 2 | Split the field per §3.2. Ground, bays, rows, figures rebuilt on the toolkit. Static only. | **The first look.** A still field in the new language. |
| 3 | `lit_mark`, owner-hue figures, cover occlusion, lit/unlit asymmetry (§2.4). | The field reads as two people hiding from each other. |
| 4 | `field_replay`, `bloom_flash`. Six beats, ball casting light, reveal flood. | **The hero moment.** |
| 5 | `paint_burst`. Droplets, scatter, wet settle, accumulating match record. | Splats that read as paint, not circles. |
| 6 | Regenerate the five sound cues; verify they land on the right beats. | Audio better than sine tones. |
| 7 | Sliding Scale rebuilt on the toolkit. Reconcile `GAMES.md` drift per §6.11. | Proof the toolkit generalises; docs matching reality. |

**Review checkpoints.** Work stops for human judgement at the end of **Stage 2**
("is the direction right?") and the end of **Stage 4** ("is the replay
thrilling?"). These two decisions cannot be made from prose and must be made
against a rendered frame.

Stage 7's doc reconciliation is required, not optional: `GAMES.md` is v2.0,
still specifies three games, and lists Sliding Scale among post-MVP deferrals
while ten games exist and Sliding Scale ships. `ATTUNE_THESIS.md` §6.11 names
this exact drift as a known process failure.

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| Neon-on-black lands as cheap cyberpunk or a crypto dashboard | §2.1's three-tier discipline; white reserved for impact; the remove-a-glow rule. Stage 2 checkpoint catches it at the cheapest possible moment. |
| Figures read as UI markers rather than characters | The design's least defensible claim from prose. External visual review at the Stage 2 and Stage 4 checkpoints, against screenshots. |
| The toolkit over-fits Paint Ball | Thin by construction, no speculative API. Stage 7's Sliding Scale is the real test, and it is in scope precisely for that. |
| Frame budget fails on low-end hardware | `neon_quality` exists from Stage 1 rather than retrofitted. Shaders deferred until measured on a real device. |
| Golden churn conceals regressions | Six goldens spanning rest/flight/hit/miss/reduce-motion/plain. |
| **Rewriting the field test silently drops a device-reported regression** | The highest-probability real failure in this work. §3.6.1 splits behavioural from structural assertions, requires a one-to-one mapping of all 25 before Stage 2, and mandates typed `Key`-based seams so the coupling does not recur. |
| Cover-as-darkness does not work visually | `PaintBallCoverStyle` seam (§2.3): swapping it is a new class, not surgery. Accepted as provisional by explicit decision. |
| `field_replay` becomes a god-object | Contract limits it to emitting a `ReplayBeats` value object (§3.2). |

### 5.1 Deferred: fragment shaders

Flutter supports `FragmentProgram`, and real bloom would raise the ceiling
beyond layered blur. It is deferred rather than rejected, for two reasons: on
low-end Android GPUs a full-screen bloom pass is a measurable frame cost against
§6.10, and shader-backed widgets do not render deterministically in golden
tests. If adopted later it must be gated by `neon_quality` (off by default on
`plain`) and given a test seam that renders the blur-glow fallback
deterministically. Committing to shaders before measuring the baseline on real
hardware would be backwards.

---

## 6. Acceptance

The work is complete when all of the following hold:

1. Paint Ball's field reads as a designed object rather than a diagram, judged
   against a rendered frame at the Stage 2 and Stage 4 checkpoints.
2. The replay is worth watching twice.
3. `lib/core/ui/neon/` has at least one consumer besides Paint Ball
   (Sliding Scale, Stage 7).
4. Six new goldens exist and pass. Every **behavioural** assertion of the 26
   existing field tests survives, mapped one-to-one per §3.6.1; structural
   hooks may be rewritten. The suite is green.
5. No new raster assets, no new runtime dependency, no migrations, no server
   changes.
6. Paint Ball's five cues are regenerated and audibly better than sine tones,
   with the placeholder review gate still documented as open.
7. `GAMES.md` no longer contradicts the shipped game set.
8. Reduce-motion behaviour is unchanged from today, verified by test.

Acceptance is a statement of design contract. It is not a claim that any of it
is implemented, nor approval to merge or release.
