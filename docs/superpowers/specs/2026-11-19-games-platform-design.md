# Games platform — one shell, five games, full colour

**Status:** design approved in conversation 2026-11-19; awaiting owner review of
this document before planning.
**Branch:** `feat/games-advance` (worktree `.worktrees/games-v2`). Nothing in
this work is done in `main`'s working tree.
**Reference:** Netflix Puzzled (owner screenshots, 2026-11-19) for structure
and feel. Not for copying art, names or layouts one-to-one.
**Supersedes for the games area:** the dark neon direction in
`2026-10-12-paint-ball-neon-design.md`. That document still governs Paint
Ball's field and `lib/core/ui/neon/`, which this work does not touch.

Requirements below are design contracts, not claims that code exists.

---

## 0. Decisions

| # | Decision | Who |
|---|---|---|
| D1 | **Launch set is five games:** This or That, Truth or Dare, 36 Questions, Word Hunt, Snakes and Ladders. Every other game shows as coming soon. | Owner |
| D2 | **Per-question play stays.** In the question games both partners answer each question before the next. No game rules change. | Owner |
| D3 | **Flutter only, no game engine.** | Owner, on recommendation |
| D4 | **Full colour replaces dark neon** in the games area: one colour per game. The rest of Attune keeps its look. | Owner |
| D5 | **Shell first, then one game, then a device gate.** Nothing else is ported until the owner has played phase 2 on a phone. | Owner, on recommendation |
| D6 | **The hub becomes a full screen**, opened from the same chat button that opens today's sheet. | Recommended, approved |
| D7 | **No loading screen.** Games open instantly; the hub card expands into the landing page instead. | Recommended, approved |

### 0.1 Why there is a device gate

Paint Ball's neon rebuild passed every review and 2,969 tests, and the owner
rejected it after playing it. Tests and rendered stills cannot judge whether a
game is worth opening. D5 exists so that verdict arrives after one game, not
five.

---

## 1. Scope

**In scope**
- A game registry and a shared shell (hub, landing, play scaffold, settings
  sheet, tutorial coach, completion screen).
- A shared feel layer (tile, motion, bursts, sound and haptic map).
- The five launch games moved onto the shell and redrawn in full colour.
- One server change: a push when it becomes your move mid-game (§5).
- Moving every other game to coming soon.

**Out of scope**
- Any change to game rules, scoring, session lifecycle, RPCs or RLS, other
  than §5.
- Paint Ball, `lib/core/ui/neon/`, and the code of the games going to coming
  soon. Their files stay; only their catalogue entry changes.
- New dependencies. `flutter_animate` is already installed and is enough.
- A licensed sound pack and artist-made animation (Rive or Lottie). Both are
  owner purchases. The sound map (§3.4) is built so a pack drops in without
  code changes.
- Translating game text. See §1.2.

### 1.1 Shared files this work must touch

Two files outside `lib/features/games/` change, and both are busy on `main`:

| File | Change | Risk control |
|---|---|---|
| `lib/app/routing/app_router.dart` | Two new routes: the hub and the landing page. | Additive only; no existing route edited. |
| `lib/features/chat/presentation/screens/chat_screen.dart` | The games button opens the hub route instead of the sheet; the entry switch (currently around line 5290) routes launch games to their landing page. | Smallest possible edit, made last in phase 2, with the existing chat tests run before and after. |

No other file outside the games feature and its tests may change without
being raised first.

### 1.2 Text is not translated in this work

None of the 145 files under `lib/features/games/` uses `AppLocalizations`
today. The `.arb` files are also being edited by other sessions on `main`, so
adding keys from this branch would conflict at merge.

Ruling: all new shell text lives in one constants file per area
(`platform/game_strings.dart`), never inline, so a later translation pass is
mechanical. Cost: the new shell ships English-only, like the games it wraps.

### 1.3 Project rules that bind this work

| Rule | Source |
|---|---|
| Never run `dart format` on an existing file; format new files only. | Owner memory |
| Displayed dates use `MyDateFormat`. | Owner memory |
| Say the couple's chosen name (`coupleNameProvider`) or a partner's name, not "both of you". | Owner memory |
| Wide screens: content sits in `AppContentWidth`; ScreenUtil scale is capped at 1.25×. | iPad layout work |
| Large text must not break layouts; error red is `#C62828`. | Accessibility wave W10 |
| Every animation degrades under the OS reduce-motion setting. | `lib/core/ui/motion/reduce_motion.dart` |
| Performance on low-end Android is a launch gate. | `ATTUNE_THESIS.md` §6.10 |
| No scorecard of a partner; results are shared, never one person's failures. | Permanent product constraints |

---

## 2. Visual language

Three rules, taken from what makes the reference read well.

1. **One colour per game.** The colour fills the top of every screen for that
   game and fades to near-black (`#0B0B0B`) by roughly the vertical midpoint.
   Titles sit on the colour; body text and lists sit on the dark half, where
   contrast is easy.
2. **White tiles are the only material.** Game pieces, letters, hero art and
   the primary button are white shapes with a hard offset shadow (no blur).
   A tile pressed moves down onto its shadow.
3. **Flat fills only.** No blur, no glow, no `saveLayer`. This is cheaper to
   draw than the neon direction it replaces, which matters for §1.3's
   low-end-device gate.

The games surface is always dark-based, whatever the app theme, as it is today.

| Game | Colour (provisional) | `game_type` |
|---|---|---|
| This or That | Orange `#EE8A3A` | `this_or_that` |
| Truth or Dare | Red `#E5484D` | `truth_or_dare` |
| 36 Questions | Purple `#A56FD6` | `36_questions` |
| Word Hunt | Green `#1FA463` | `word_hunt` |
| Snakes and Ladders | Blue `#4C7CF0` | `snakes_and_ladders` |

Hex values are starting points. They are tuned once, at the phase 2 gate,
against a real screen.

**Hero art** is composed in code from tiles (letter tiles, a small board, two
doors). It is not illustration, and the spec does not promise illustration.

---

## 3. The platform

New code lives in `lib/features/games/platform/`.

### 3.1 Registry

Today the list of games is repeated in five places:
`gameTypeDisplayName`, `GamePalette._byType`, the glyph map in
`game_icon.dart`, `chatGameDestinationForType`, and the catalogue in
`chat_games_sheet.dart`. A game added to one and missed in another renders as
a raw database value or routes nowhere.

`GameDefinition` becomes the single source. One per game:

| Field | Purpose |
|---|---|
| `gameType` | The `game_sessions.game_type` value. |
| `title`, `collectionLabel`, `tagline` | Landing and hub text. |
| `theme` | The colour and its derived gradient and shadow colours. |
| `heroBuilder` | Draws the tile hero art. |
| `entriesBuilder` | The list under the Play button (§4). |
| `howToPlay` | Tutorial steps for the coach and the "?" button. |
| `settingsBuilder` | The game's own settings tab; null hides the tab. |
| `open` | How to enter play for a new or existing session. Wraps today's routes; does not replace them. |
| `availability` | `launch` or `comingSoon`. |

The existing helpers stay as thin wrappers over the registry, because the chat
card and the push label still call them. The SQL display-name function in
`20260931200000_game_message_trigger.sql` is a server-side mirror and is not
changed.

### 3.2 Shell screens

**Hub** — route `/games`. Three rails:
- *Your turn*: active sessions where the viewer can act, from the existing
  `activeGamesProvider`, kept live by the existing `gameSessionEventsProvider`.
- *Play together*: the five launch cards, each a block of the game's colour
  with its tile icon.
- *Coming soon*: dimmed, not tappable.

A coming-soon game with a session already in progress stays reachable from
*Your turn*, so nobody loses a game mid-match.

**Landing** — route `/games/:gameType`. Hero art, collection label, title,
tagline, one primary button, the entries list, and "?" for how to play. The
button reflects the couple's state:

| State | Button | Enabled |
|---|---|---|
| No session | Play | Yes |
| Partner invited the viewer | Join | Yes |
| Active, viewer can act | Your turn | Yes |
| Active, waiting on partner | Waiting for {partner name} | No; shows Remind where the game already supports it |
| Finished | Play again | Yes |

A small caption under the button names where the game stands (for example
"ROUND 3 OF 10"), as the reference does.

**Play scaffold** — one header for every game: round back button, small
subtitle over a bold title, settings gear. Gradient background, a body slot,
and an optional bottom row of round labelled buttons.

**Settings sheet** — three tabs:
- *General*: sound effects on/off, haptics on/off. Stored per device.
- *The game's own tab*: from `settingsBuilder`.
- *Support*: how to play, report a problem (existing support flow), leave
  game (each game's existing abandon path, with its existing confirmation).

**Coach** — a tutorial bubble with a pointing hand and a highlighted target,
driven by `howToPlay`. Shown the first time a game is played on a device and
replayable from "?". Skippable at every step.

**Completion** — letter tiles spelling the outcome, the players' names, a
summary slot the game fills, and two buttons: Play again, Back to games.

### 3.3 Retiring the sheet

`ChatGamesSheet` leaves the entry path in phase 2 and is deleted in phase 5.
Its tests guard real behaviour (a coming-soon row launches nothing; an
in-progress game resumes; names never render as raw types; the sheet grows
with large text). Before the file is deleted, each of those tests is mapped to
a hub test that asserts the same behaviour. A behaviour with no replacement
test blocks the deletion.

### 3.4 Feel layer

`platform/feel/`:

| Piece | What it is |
|---|---|
| `GameTile` | The white tile: radius, hard offset shadow, press-down. Used for letters, options, board cells, hero art and the primary button. |
| Motion tokens | Named springs and durations. No raw numbers at call sites. |
| `BurstPainter` | The short spark burst when something is placed or matched. Fires once and stops. |
| `GameFeedback` | `GameFeedback.fire(event)` maps a named event (tap, place, match, reveal, complete, turn) to a sound and a haptic, and respects the settings sheet and reduce-motion. Games name events; they never pick sound files. |

Sounds remain the current synthesized placeholders. Because games only name
events, a licensed pack later means replacing files, not editing games.

---

## 4. The five games on the shell

For every game: providers, repositories, models, RPC calls and session logic
are unchanged. What changes is the visual layer (onto the play scaffold and
`GameTile`) and the way in (through the landing page).

| Game | Entries under the Play button | What is redrawn |
|---|---|---|
| This or That | The five tones; Your questions; Past games | Question, waiting, reveal and end screens. The tabbed choice card keeps its mechanic and is redrawn in tiles. |
| Truth or Dare | The tones; Your prompts; Past games | Card flip, truth and dare reveals, partner-watching, result, end. |
| 36 Questions | Chapters 1–3; Your journey | Entry, chapter intro, question, waiting, reveal, chapter and journey completion. |
| Word Hunt | Past games | Board, found-word reveal, result. |
| Snakes and Ladders | Past games | Board, die, tokens, result. |

Tone selection moves from its own screen into the landing page's entries. The
Intimate tone's consent gate is behaviour, not decoration, and carries over
unchanged.

Each ported screen keeps every behavioural test it has today. Where a test is
tied to an old widget name, the hook is re-pointed and the assertion is kept;
the Paint Ball work's rule applies: a re-pointed test must fail if the
behaviour it names is broken, and anything iterating a collection asserts the
collection is non-empty first.

---

## 5. The mid-game push

**Today:** a push is queued only when a game is created
(`notify_game_invite`). Paint Ball alone queues a `game_turn` push when the
turn passes. In the launch games, a partner who is not looking at the chat
does not learn it is their move; This or That offers a manual Remind after two
hours.

**Requirement:** when it becomes a player's move in any launch game, that
player gets a push.

1. It uses the existing `scheduled_notifications` queue and the existing
   `game_turn` type, so the quiet-hours rule for live games
   (`quiet_hours_game_live`) applies without change.
2. It never fires at a player who is evidently in the game: no push if the
   recipient made a move in that session within the last 60 seconds.
3. At most one undelivered turn push exists per session; a newer one replaces
   an older one.
4. Tapping it opens that game.
5. It is delivered by one migration in a timestamp range agreed with the owner
   before it is written, with a contract test under `supabase/tests/`.

"Becomes your move" is defined per game in the phase 5 plan, after reading
each game's session columns: Snakes and Ladders has `current_turn_user_id`;
the question games derive it from who has answered the current round.

This is the only server change in this work.

---

## 6. Phases

Five phases. Each ends committed on the branch and runnable.

| Phase | Content | Ends with |
|---|---|---|
| 1 | Registry, colour system, feel layer, and five shell screens (landing, play scaffold, settings sheet, coach, completion), exercised by a throwaway demo game definition. | A shell that can be opened and tapped through. |
| 2 | This or That on the shell; the hub; the two shared-file edits (§1.1). | **Device gate.** The owner plays it on a phone. |
| 3 | Truth or Dare and 36 Questions. | Three games on the shell. |
| 4 | Word Hunt and Snakes and Ladders. | All five. |
| 5 | Mid-game push (§5); sound and haptic pass; other games to coming soon; sheet deleted per §3.3; `GAMES.md` and the user manual updated. | Ready to merge. |

Nothing merges to `main` before the phase 2 gate passes. If the gate fails,
phase 2 is reworked; phases 3–5 do not start.

---

## 7. Testing

- **Goldens are pinned to a phone** (375×812), with one frame per screen at
  430 wide and one in a tablet-width `AppContentWidth`. The default 800×600
  test surface distorted Paint Ball's goldens by nearly 3× and is never used
  for judging shape.
- **Goldens are opened and looked at** before they are committed.
- **Large text:** each shell screen has a test at the largest text scale
  asserting no overflow.
- **Reduce motion:** each animated piece has a test asserting it reaches its
  end state with no frames pending.
- **Existing suites stay green**, counted before and after each phase.

---

## 8. Risks

| Risk | Control |
|---|---|
| It tests well and still does not feel good. | The phase 2 device gate (D5). |
| Code-drawn hero art reads as plain. | Named as a limit in §2; judged at the gate; illustration is a later owner decision. |
| Placeholder sounds undercut the feel. | Event-named sound map (§3.4) so a licensed pack is a file swap. |
| Edits to `chat_screen.dart` and `app_router.dart` collide with other sessions. | §1.1: additive or minimal, made last, chat tests run before and after. |
| White text on orange or green fails contrast at small sizes. | §2 rule 1: only large bold titles sit on the colour; body text sits on the dark half. Checked per colour at the gate. |
| Per-question play still stalls when a partner is away. | Accepted by D2; §5's push is the mitigation. |
| Deleting the sheet drops a behaviour its tests guarded. | §3.3 mapping before deletion. |

---

## 9. Acceptance

1. The owner passes the phase 2 device gate.
2. All five launch games open from the hub through a landing page, play on the
   shared scaffold, and end on the shared completion screen.
3. Every game other than the five shows as coming soon, and an in-progress
   session of any game is still reachable.
4. The list of games exists in one place (the registry).
5. A player whose move it is receives a push, per §5, with its contract test
   passing.
6. No game rule, RPC or RLS policy changed other than §5's migration.
7. No file outside the games feature changed other than the two in §1.1.
8. Existing test suites are green, and every pre-existing behavioural test of
   a ported screen and of the retired sheet has a living equivalent.

Acceptance describes the design contract. It is not a claim that any of it is
built, nor approval to merge or deploy.
