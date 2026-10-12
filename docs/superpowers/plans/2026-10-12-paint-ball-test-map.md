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
