# Paint Ball field test map

Per spec §3.6.1. Every row's **behaviour** must survive the rewrite. Only the
**hook** may change. A row marked `DROP` requires a written justification in
the commit that drops it.

`B` = behavioural (must survive). `S` = structural hook (may be rewritten): the
test finds a painter by `runtimeType.toString().contains(...)` name or reads a
field via `as dynamic`. `B+S` = both; a rename breaks it with no behaviour change.

| # | Existing test | Kind | Current hook | Replacement hook |
|---|---|---|---|---|
| 1 | the field renders with a full match of paint | B | no exception w/ 20 splats | same, via `FieldPaint` |
| 2 | an empty field renders | B | no exception; `splats: []` plus null `myPosition`/`selectedShot`/`revealedPartnerPosition` | same |
| 3 | each row taps to its own action | B | `bySemanticsLabel('<Name> target'/'cover')` | unchanged labels, `CoverRow` |
| 4 | firing is the triangle, never a cover | B+S | `bySemanticsLabel('Right target')`, `bySemanticsLabel('Middle cover')`, then `.first` descendant `CustomPaint` tapped with `warnIfMissed: false` (order-dependent, fragile) | `PaintBallFieldKeys.figure(position)`; drop the `.first` |
| 5 | nothing is selectable when it is not your turn | B | tap every `GestureDetector` | same |
| 6 | your own triangle is visible, theirs is not | B+S | `runtimeType.toString().contains('Triangle')` name filter; asserts count | count `FieldFigure` widgets |
| 7 | a revealed partner position becomes visible | B+S | same `'Triangle'` name filter; asserts count 2 | same |
| 8 | a shot in flight renders | B | no exception, `shotProgress: 0.5` | same |
| 9 | a shot with no chosen positions still renders | B | no exception, nulls + progress | same |
| 10 | the three targets are labelled and focusable | B | `bySemanticsLabel` + tap | unchanged |
| 11 | reduce motion makes all field transitions immediate | B | every `Animated*.duration == 0` loop. ⚠️ VACUOUS-PASS RISK: passes if no widget of that type exists | same, plus `ReplayBeats.instant`; positive control first |
| 12 | lives use text and become immediate with reduce motion | B | `PaintBallLivesDisplay` semantics | **untouched** — different widget |
| 13 | a replay shows both players, then hides theirs again | B+S | `'Triangle'` name filter; asserts count == 2 | `FieldFigure` count == 2 |
| 14 | mid-replay both paintballs are in flight at once | B+S | `'Projectile'` name filter; asserts count == 2 | `PaintBallFieldKeys.projectile(side)` == 2 |
| 15 | early in a replay nobody has fired yet | B+S | `'Projectile'` name filter; asserts count == 0 at 0.05. ⚠️ VACUOUS-PASS RISK: after a rename `0 == 0` passes forever | same; positive control (count == 2 mid-replay) in the same test |
| 16 | repositioning travels rather than teleporting | B+S | `'Triangle'` name filter. Assertion: centre moves, count stays 1 | `FieldFigure` centre, same assertions |
| 17 | a travelling player steps clear of cover | B+S | `'Triangle'` name filter. Assertion: crossing `dy` < resting `dy` | `FieldFigure`, same assertion |
| 18 | the character stands in the centre of its cover | B+S | `'Triangle'` name filter + `bySemanticsLabel('<Name> cover')`. Assertion: centre within 1.0pt at 3 widths | `FieldFigure` + same label — assertion **device-reported, keep verbatim** |
| 19 | the two rows of cover face each other | B+S | `'Shield'` name filter, `hasLength(kPaintBallPositions * 2)` (6 covers), then `(painter as dynamic).opensDown` count == 3 | `CoverBay` filter + `hasLength(6)` guard, then `CoverBay.facing` public field — **device-reported**. Polarity must be preserved (`opensDown == true` is your row, legs below dome) |
| 20 | the far row is named for the partner | B | `find.text('AMA')` | same, `FieldGround` |
| 21 | an unknown partner falls back rather than showing a gap | B | `find.text('THEIR COVER')` | same |
| 22 | an idle board carries no paint | B+S | `'Splat'` name filter, then `for` loop over `(painter as dynamic).splats` expecting empty. ⚠️ VACUOUS-PASS RISK: no non-empty guard | **both** the `'Splat'` name filter and the field read change: find `FieldPaint`, assert it is found first, then `FieldPaint.splats` public field |
| 23 | a partner who stays put is called out | B | `find.text('SAME SPOT x3')` | same |
| 24 | a streak is not kept on the board between rounds | B | that text absent when idle | same |
| 25 | a shot crosses the field rather than teleporting | B+S | `(painter as dynamic).progress` set size > 3 (guarded by `isNotEmpty`) | `FieldProjectile.progress` public field |

**Vacuous-pass risk (rows 11, 15, 22).** These can go green after a rename while
asserting nothing: a name filter that matches nothing yields an empty
collection, and `0 == 0` or a loop over nothing passes. When rewritten, each
needs a positive control: assert the collection is non-empty (or the count is
the expected positive number) BEFORE asserting over its contents. Row 22 guards
the fairness property that paint does not persist across rounds, so losing it
silently is the failure most to fear. Rows 19 and 25 were considered and are
already safe: they carry `hasLength(6)` and `isNotEmpty` guards.

Row 19 also contains a dead assertion (`'$painter'.contains('opensDown')`
mapped to a list, then `expect(opensDown, isNotEmpty)`) that asserts nothing
useful. Drop it in the rewrite; do not port it.

**Count: 25 rows. All 25 are behavioural (B or B+S). Dropped: 0.**

Test 12 touches `PaintBallLivesDisplay`, not the field, so it must pass
completely unmodified.

Tests 18 and 19 record bugs reported from a real device. Their assertions are
carried over verbatim wherever the hook allows.
