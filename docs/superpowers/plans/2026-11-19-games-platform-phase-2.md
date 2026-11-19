# Games Platform — Phase 2: This or That, the Hub, and the Way In — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put This or That on the shell built in phase 1, give the games a full-screen hub, and open both from the chat's games button — so the owner can play one finished game on a phone and judge the direction.

**Architecture:** Each game gives the shell a `GameController`: where the couple's game stands, what the main button does, the rows under it, and how to open a session. The shell owns the hub (`/games/hub`) and one landing page per game (`/games/play/:gameType`). This or That gets a real controller and its screens are redrawn on the shell; the other four launch games get a thin controller that opens the screens they have today. No provider, repository, RPC or game rule changes.

**Tech stack:** Flutter 3.29.1, Riverpod, GoRouter, the phase 1 platform in `lib/features/games/platform/`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-19-games-platform-design.md` — §1.1 (shared files), §3.1–3.3, §4, §6, §7. Phase 1's plan, for the shell's existing API: `docs/superpowers/plans/2026-11-19-games-platform-phase-1.md` (read its "After the final review" section).

This is **phase 2 of 5**, in **14 tasks**. It ends at the **device gate**: the owner plays it on a phone. Nothing merges to `main`, and phases 3–5 do not start, until that passes.

## Global Constraints

- **Worktree only.** `/Users/user/attune/.worktrees/games-v2`, branch `feat/games-advance`. Never run commands in, or edit, the main checkout. One commit per task. No push, merge or rebase. Never commit `backup-before-planning-p2.sql` or `supabase/.temp/cli-latest`.
- **Shared files.** Outside `lib/features/games/` exactly two files change, both additively or minimally, in Tasks 12 and 13: `lib/app/routing/app_router.dart` and `lib/features/chat/presentation/screens/chat_screen.dart`. In `test/`, outside `test/features/games/`, only `test/architecture/games_untouched_test.dart` may change (its header says a deliberate Games change updates it). `lib/app/text_scale_policy.dart` is not edited: both new routes sit under its existing `/games/` prefix, which is why their paths are `/games/hub` and `/games/play/:gameType` rather than the spec's `/games` and `/games/:gameType`.
- **No server change.** No migration, RPC or RLS edit in this phase.
- **No rule change.** Providers, repositories, models and session logic of every game are unchanged. Redrawn screens keep their constructors.
- **Existing tests are the authority.** Every test in `test/features/games/` that passes today passes at the end. Where a test is tied to an old widget name, tooltip or sentence, re-point the hook and keep the assertion; a re-pointed test must still fail when the behaviour it names is broken. Never delete or loosen one to get green.
- **Inside `platform/`:** no ScreenUtil units (`.w .h .r .sp`); the column is `GameContentWidth`; no blur, `MaskFilter`, `saveLayer`, `BackdropFilter` or `Opacity` widget; every duration through `GameMotion.of`; hand-built controls carry `Semantics(container: true, excludeSemantics: true, onTap: …)`; no `Material` below `GameBackdrop`.
- **Text.** New shell text goes in `platform/game_strings.dart`; new This or That text stays in its screens, English only. A partner's name, never "both of you". No `.arb` edits.
- **Formatting.** `dart format` new files only. Never format an existing file — edit it by hand and leave the rest of it alone.
- **Tests.** Every screen test calls `useSurface(tester, phone)` or another named surface (which makes a missed tap fail). An assertion of absence names its positive control. Anything iterating a collection asserts it is non-empty first. Goldens are phone-pinned, generated on macOS, and opened and looked at before commit.
- **Known flakes, unrelated:** `session_game_abandon`, `session_game_happy_path`, `session_game_invite`, `sound_service`, `audio_session_coordinator`. Re-run the file alone before calling a regression.
- **Baseline before Task 1:** `flutter test test/features/games test/core/ui` → `+896: All tests passed!`; `flutter analyze lib/features/games test/features/games` → `102 issues found.`

## Rulings this plan makes

Recorded here so they are decisions, not accidents. Each costs little to reverse.

1. **A session opens straight into play.** Tapping a chat card, or a row in the hub's in-play list, goes to the game, not to its landing page. The spec's §1.1 says the entry switch routes launch games to their landing page; for a game played a question at a time that is an extra tap on every turn. The landing page is where a game is chosen and started.
2. **The hub's first list is every game in progress**, labelled *Your turn* or *Waiting for Ama*, not only the ones where the viewer can act. The spec's own acceptance (§9.3) needs an in-progress game of any kind to stay reachable.
3. **Play creates the game.** Today a game picked in the chat sheet is staged in the composer and created on Send. From the landing page, Play (or a tone row) creates it, through the same `create_this_or_that_session` path the tone screen has always used. Choosing a game and pressing Play is the deliberate act that staging was protecting. The composer bar stays in the code, unreached from the button, until phase 5 decides its fate.
4. **No "Leave game" for This or That.** The game has no way to end a match part-way today; adding one is a rule change. Its settings sheet offers sound, vibration and How to play. Stepping away is the back button, as now.
5. **The other four launch games show a landing page and then their current screens.** Phases 3 and 4 redraw them. Every other game is listed as coming soon in the hub from this phase on; a game of theirs already in progress still opens from the in-play list.
6. **The card-expands-into-landing transition (spec D7) is not built in this phase.** Pages use the standard transition. It needs a shared-element animation worth doing once the screens it joins are approved; it is listed for the gate.

## Review Focus

What the spec implies and a person will meet, most likely first. Each has a test in the task named.

1. **Two quick taps on Play or a tone row** start one game, not two. (Task 5: the landing page ignores taps while the first is in flight.)
2. **The partner moves while the hub or landing page is open:** the label changes without leaving the screen. (Tasks 6 and 7: a `gameSessionEventsProvider` event refreshes the state.)
3. **Coming back from a game** shows where it now stands, not the *Play* it showed before. (Task 7: state is re-read on return.)
4. **A game the app does not know, or one that is coming soon,** reached from a card or a link: a readable page, no crash, and an in-progress session of it still opens. (Tasks 5 and 6.)
5. **The app in light mode:** text fields, dialogs and list rows inside a game stay readable on the dark ground. (Task 2: the backdrop's Material theme; Task 8: a golden of the custom-question form under a light app theme.)
6. **A long partner name on a small phone:** "Waiting for Bartholomew-James" at 320 wide does not overflow. (Task 5.)

---

## File map

```
lib/features/games/platform/
  game_landing_state.dart        NEW  status, state, landingAction (moved out of the screen)
  game_definition.dart           MOD  GameController; icon; controller replaces open/entriesBuilder
  game_session_status.dart       NEW  a live session -> landing state
  games_catalogue.dart           NEW  the one list of games; gameRegistryProvider
  game_strings.dart              MOD  hub and landing text
  legacy/legacy_game_opener.dart      NEW  opens a game's current screens
  legacy/legacy_game_controller.dart  NEW  controller for games not yet redrawn
  shell/game_material_theme.dart NEW  dark Material theme for inside a game
  shell/game_backdrop.dart       MOD  applies that theme
  shell/game_scaffold.dart       MOD  bottom slot
  shell/game_buttons.dart        MOD  busy state on the primary button
  shell/game_coach.dart          MOD  replay
  shell/game_landing_screen.dart MOD  takes its entries
  shell/game_landing_page.dart   NEW  the route: registry + controller -> landing screen
  shell/games_hub_screen.dart    NEW  the hub
  shell/game_hub_card.dart       NEW  a game's card in the hub

lib/features/games/this_or_that/
  this_or_that_game.dart                         NEW  definition + ThisOrThatController
  domain/this_or_that_tones.dart                 NEW  the five tones (moved out of the tone screen)
  presentation/start_this_or_that.dart           NEW  start a game in a tone (moved out of the tone screen)
  presentation/widgets/this_or_that_game_ui.dart MOD  palette and scaffold on the shell
  presentation/widgets/this_or_that_tab_card.dart MOD redrawn in tiles
  presentation/screens/{question,waiting,reveal,end}_screen.dart  MOD  redrawn
  presentation/screens/tone_selector_screen.dart  MOD  uses the two moved pieces
  presentation/screens/this_or_that_session_router_screen.dart  MOD  where "back" and "play again" go

lib/app/routing/app_router.dart                          MOD  two routes (Task 12)
lib/features/chat/presentation/screens/chat_screen.dart  MOD  two edits (Task 13)

test/features/games/platform/…        new tests beside the phase 1 ones
test/features/games/this_or_that/…    new tests for the controller and the redrawn screens
```

---

### Task 1: Give the shell a controller per game

Phase 1's `GameDefinition` carried `open` and `entriesBuilder`, which cannot see the couple's state. Replace them with a controller, and move the landing state out of the screen file so the controller can name it.

**Files:**
- Create: `lib/features/games/platform/game_landing_state.dart`
- Modify: `lib/features/games/platform/game_definition.dart`, `lib/features/games/platform/shell/game_landing_screen.dart`, `lib/features/games/platform/game_strings.dart`
- Test: `test/features/games/platform/game_landing_test.dart`, `test/features/games/platform/game_registry_test.dart`, `test/features/games/platform/support/demo_game.dart` (and every phase 1 test that builds a `GameLandingScreen` or `demoGame`)

**Interfaces:**
- Produces, in `game_landing_state.dart`:

```dart
enum GameLandingStatus { loading, fresh, invited, yourTurn, waiting, finished, comingSoon }

@immutable
class GameLandingState {
  const GameLandingState({
    required this.status,
    this.sessionId,      // the session this state describes, when there is one
    this.partnerName,
    this.caption,        // "Round 3 of 10"
    this.canRemind = false,
  });
}

@immutable
class GameLandingAction { const GameLandingAction({required this.label, required this.enabled, this.icon}); }

GameLandingAction landingAction(GameLandingState state);
```

- Produces, in `game_definition.dart`:

```dart
@immutable
class GameEntry {
  const GameEntry({required this.title, this.subtitle, this.onTap});
  final String title;
  final String? subtitle;
  final void Function(BuildContext context)? onTap;
}

/// What the shell needs from a game to show its landing page and get a
/// player into it.
abstract class GameController {
  const GameController();

  /// Where the couple's game stands. Called from build.
  GameLandingState watchLanding(WidgetRef ref);

  /// Play, Join, Your turn or Play again, according to [state].
  Future<void> onPrimary(BuildContext context, WidgetRef ref, GameLandingState state);

  /// Only called when [state.canRemind].
  Future<void> onRemind(BuildContext context, WidgetRef ref, GameLandingState state) async {}

  /// The rows under the button.
  List<GameEntry> entries(BuildContext context, WidgetRef ref, GameLandingState state) => const [];

  /// Opens one session directly: from a chat card or the hub.
  Future<void> openSession(BuildContext context, WidgetRef ref, {required String sessionId});
}

class GameDefinition {
  const GameDefinition({
    required this.gameType, required this.title, required this.collectionLabel,
    required this.tagline, required this.theme, required this.icon,
    required this.heroBuilder, this.howToPlay = const [], this.settingsBuilder,
    this.controller,                       // null: nothing to open (a coming-soon game with no screens)
    this.availability = GameAvailability.launch,
  });
  final IconData icon;
  final GameController? controller;
  // gameType, title, collectionLabel, tagline, theme, heroBuilder, howToPlay,
  // settingsBuilder, availability: as in phase 1
}
```

`GameEntriesBuilder`, `GameOpen`, `GameDefinition.entriesBuilder` and `GameDefinition.open` are removed. `GameLandingScreen` gains `this.entries = const <GameEntry>[]` and no longer reads entries from the definition; it shows the "?" button only when `onHowToPlay != null`.

- [ ] **Step 1: Write the failing tests.** In `game_landing_test.dart`, change the import to `game_landing_state.dart`, pass `entries:` where the page tests expect rows, and add:

```dart
test('while the game\'s state is loading the button waits', () {
  final action = landingAction(const GameLandingState(status: GameLandingStatus.loading));
  expect(action.label, 'Play');
  expect(action.enabled, isFalse);
});

test('a coming-soon game says so and cannot be started', () {
  final action = landingAction(const GameLandingState(status: GameLandingStatus.comingSoon));
  expect(action.label, 'Coming soon');
  expect(action.enabled, isFalse);
});
```

Change the existing "is only disabled while waiting on the partner" test to expect disabled for exactly `{waiting, loading, comingSoon}`. In `demo_game.dart`, `demoGame` takes `GameController? controller` and `IconData icon = Icons.extension_rounded`; its `withEntries` flag is removed and the three demo rows move to an exported `const demoEntries`.

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/platform` — Expected: compile errors (`game_landing_state.dart` missing, `comingSoon` undefined).
- [ ] **Step 3: Implement** the interfaces above. `GameStrings.comingSoon = 'Coming soon'`. `landingAction`: `loading` → `('Play', enabled: false)`; `comingSoon` → `('Coming soon', enabled: false)`; the rest as phase 1.
- [ ] **Step 4: Run.** `flutter test test/features/games/platform` — Expected: `+147: All tests passed!` (145 + 2). `flutter analyze lib/features/games/platform test/features/games/platform` — Expected: `No issues found!`. Regenerate goldens only if a picture changed; none should.
- [ ] **Step 5: Commit.** `git commit -m "refactor(games): a controller per game replaces open/entriesBuilder (platform phase 2, task 1)"`

---

### Task 2: What the shell needs before a real game sits in it

**Files:**
- Create: `lib/features/games/platform/shell/game_material_theme.dart`
- Modify: `shell/game_backdrop.dart`, `shell/game_scaffold.dart`, `shell/game_buttons.dart`, `shell/game_coach.dart`
- Test: `test/features/games/platform/game_scaffold_test.dart`, `game_buttons_test.dart`, `game_coach_test.dart`; create `game_backdrop_test.dart`

**Interfaces — Produces:**

```dart
// game_material_theme.dart
/// A dark Material theme for everything inside a game, whatever the app's
/// own theme is: text fields, dialogs, list rows, switches. Keeps the
/// ambient text theme's fonts.
ThemeData gameMaterialTheme(BuildContext context, GameTheme theme);

// game_scaffold.dart — new optional slot, pinned under the body, inside the
// content column, above `actions`
final Widget? bottom;

// game_buttons.dart — GamePrimaryButton
final bool busy;   // default false: shows a 20 px progress ring in place of
                   // the icon, ignores taps, and is announced as disabled

// game_coach.dart — GameCoach
final int replay;  // default 0: when it increases, the tutorial restarts at
                   // step one, seen or not
```

`gameMaterialTheme`: `ThemeData(brightness: Brightness.dark, colorScheme: ColorScheme.fromSeed(seedColor: theme.primary, brightness: Brightness.dark).copyWith(surface: GameTheme.raised), scaffoldBackgroundColor: GameTheme.ground, textTheme: Theme.of(context).textTheme.apply(bodyColor: GameTheme.onGround, displayColor: GameTheme.onGround))`. `GameBackdrop` wraps its child in `Theme(data: gameMaterialTheme(context, theme))`, outside its `Material`. `GameCoach` also clamps its step index to `steps.length - 1` in build, so a shorter list on rebuild cannot throw.

- [ ] **Step 1: Write the failing tests.**

```dart
// game_backdrop_test.dart
testWidgets('inside a game, Material widgets are dark even in a light app', (tester) async {
  useSurface(tester, phone);
  late ThemeData inside;
  await tester.pumpWidget(gameHost(   // gameHost's app theme is light
    Scaffold(body: GameBackdrop(
      theme: const GameTheme(primary: GameColors.thisOrThat),
      child: Builder(builder: (context) { inside = Theme.of(context); return const TextField(); }),
    )),
    prefs: await testPrefs(),
  ));
  expect(inside.brightness, Brightness.dark);
  expect(contrast(inside.colorScheme.onSurface, GameTheme.ground), greaterThanOrEqualTo(4.5));
  expect(inside.textTheme.bodyMedium!.fontFamily, 'Roboto', reason: 'the app font is kept');
});

testWidgets('a dialog opened from inside a game is dark too', …);
// showDialog from a button under GameBackdrop; expect Theme.of(dialogContext).brightness == Brightness.dark

// game_scaffold_test.dart
testWidgets('the bottom slot sits under the body and above the actions', …);
// body Text('board'), bottom Text('lock in'), one action captioned 'Hint':
// board.center.dy < lockIn.top < hint.top; and on `tablet` the bottom slot's
// width is < tablet.width and centred

// game_buttons_test.dart
testWidgets('a busy primary button shows progress and takes no taps', …);
// busy: true with onTap counting: CircularProgressIndicator findsOneWidget;
// tap -> count stays 0 (control: the same button with busy: false counts 1);
// semantics: isButton, hasEnabledState, not isEnabled, no tap action

// game_coach_test.dart
testWidgets('asking again replays it from the first step', …);
// stored seen=true, replay: 0 -> no bubble; pump the same tree with replay: 1
// -> 'Welcome to the game.' shows
testWidgets('fewer steps on a rebuild does not throw', …);
// advance to step 3 of 3, rebuild with one step -> takeException() isNull
// and the one step's text shows
```

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/platform/game_backdrop_test.dart test/features/games/platform/game_scaffold_test.dart test/features/games/platform/game_buttons_test.dart test/features/games/platform/game_coach_test.dart` — Expected: compile errors for `bottom`, `busy`, `replay`; the backdrop tests fail on `Brightness.light`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/features/games/platform --update-goldens`, then without the flag — Expected: `+153: All tests passed!` (147 + 6). Open any golden that changed; text and switches must look as before or better. Analyzer clean.
- [ ] **Step 5: Commit.** `git commit -m "feat(games): shell bottom slot, busy button, coach replay, dark Material theme inside a game (platform phase 2, task 2)"`

---

### Task 3: From a live session to "Your turn"

One pure function turns the live card state the chat already computes into the landing state, so the hub, every landing page and the chat card can never disagree about whose move it is.

**Files:**
- Create: `lib/features/games/platform/game_session_status.dart`
- Test: `test/features/games/platform/game_session_status_test.dart`

**Interfaces:**
- Consumes: `GameCardState` and `gameCardProvider` (`lib/features/games/presentation/providers/game_card_provider.dart`); `currentUserIdProvider` (`games_hub_providers.dart`); `gamePartnerNameProvider`.
- Produces:

```dart
GameLandingState landingStateFromCard({
  required GameCardState card,
  required String sessionId,
  required String viewerId,
  required bool viewerStarted,   // the viewer is game_sessions.initiator_id
  String? partnerName,
});

/// Watches one session live. Loading, or signed out, is
/// GameLandingStatus.loading with the sessionId set.
GameLandingState watchSessionLanding(WidgetRef ref, {required String sessionId, required String? initiatorId});
```

Rules, in order:

| `card.status` | Condition | Status |
|---|---|---|
| `invited` | viewer started it | `waiting` |
| `invited` | partner started it | `invited` |
| `active` | `currentTurnUserId == viewerId` | `yourTurn` |
| `active` | `currentTurnUserId` is the partner | `waiting` |
| `active` | no turn holder; viewer answered, partner has not | `waiting` |
| `active` | no turn holder; anything else, including unknown | `yourTurn` |
| `completed` | | `finished` |
| anything else | | `fresh` |

`caption` is `'Round $r of $t'` when `currentRound > 0 && totalRounds > 0`, else null. `canRemind` is always false here; a game that supports reminders sets it itself.

- [ ] **Step 1: Write the failing test** — one `test` per row of the table, named for the row ("an invitation you sent is waiting on your partner", …), each asserting `status`, `sessionId` and `partnerName`; plus:

```dart
test('unknown answers still let the player in', () {
  // The round-state read can fail; a wrong "waiting" would lock the game shut.
  final state = landingStateFromCard(
    card: card(status: 'active'), sessionId: 's1', viewerId: 'me', viewerStarted: true,
  );
  expect(state.status, GameLandingStatus.yourTurn);
});

test('round zero is not shown as a round', () {
  expect(landingStateFromCard(card: card(status: 'active', currentRound: 0, totalRounds: 10), …).caption, isNull);
  expect(landingStateFromCard(card: card(status: 'active', currentRound: 3, totalRounds: 10), …).caption, 'Round 3 of 10');
});
```

- [ ] **Step 2: Run and watch it fail.** `flutter test test/features/games/platform/game_session_status_test.dart` — Expected: compile error, file missing.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same command — Expected: `+10: All tests passed!`. Analyzer clean.
- [ ] **Step 5: Commit.** `git commit -m "feat(games): one mapping from a live session to its landing state (platform phase 2, task 3)"`

---

### Task 4: The catalogue — the one list of games

**Files:**
- Create: `lib/features/games/platform/games_catalogue.dart`, `lib/features/games/platform/legacy/legacy_game_opener.dart`, `lib/features/games/platform/legacy/legacy_game_controller.dart`
- Modify: `lib/features/games/platform/game_theme.dart` (one colour)
- Test: `test/features/games/platform/games_catalogue_test.dart`, `test/features/games/platform/legacy_game_controller_test.dart`

**Interfaces:**
- Consumes: `openGameRoute` and `chatGameDestinationForType` (today's single routing switch, in `chat_screen.dart` and `chat_games_sheet.dart`); `activeGamesProvider`, `currentRelationshipIdProvider`, `gameTypeDisplayName` (`games_hub_providers.dart`); `gameGlyphFor` (`game_icon.dart`); `watchSessionLanding` (Task 3).
- Produces:

```dart
// legacy_game_opener.dart
typedef LegacyGameOpener = Future<void> Function(BuildContext context, String gameType, {String? sessionId});
/// Opens a game's current screens through the chat's routing switch.
/// Overridden in tests.
final legacyGameOpenerProvider = Provider<LegacyGameOpener>(…);

// legacy_game_controller.dart
/// For a game not yet redrawn on the shell: reads its state from the shared
/// session list and opens the screens it has today.
class LegacyGameController extends GameController { const LegacyGameController(this.gameType); final String gameType; }

// games_catalogue.dart
final List<GameDefinition> gameCatalogue;
final gameRegistryProvider = Provider<GameRegistry>((ref) => GameRegistry(gameCatalogue));

// game_theme.dart
static const Color comingSoon = Color(0xFF3A3A40);   // in GameColors; not in GameColors.all
```

The catalogue, in this order:

| `gameType` | Availability | Colour | Collection label | Hero word | Controller |
|---|---|---|---|---|---|
| `this_or_that` | launch | `thisOrThat` | Quick play | `THIS` | `LegacyGameController` (replaced in Task 7) |
| `truth_or_dare` | launch | `truthOrDare` | Fun and playful | `DARE` | `LegacyGameController` |
| `36_questions` | launch | `thirtySixQuestions` | Go deeper | `36` | `LegacyGameController` |
| `word_hunt` | launch | `wordHunt` | Arcade | `WORD` | `LegacyGameController` |
| `snakes_and_ladders` | launch | `snakesAndLadders` | Arcade | `ROLL` | `LegacyGameController` |
| `mirror`, `sliding_scale`, `scenario`, `love_map`, `paint_ball` | comingSoon | `comingSoon` | Coming soon | — | `LegacyGameController` (so a game in progress still opens) |
| `never_have_i_ever` | comingSoon | `comingSoon` | Coming soon | — | null |

`title` is `gameTypeDisplayName(gameType)` (`never_have_i_ever` → "Never Have I Ever"). `tagline` is that game's `subtitle` string in `chat_games_sheet.dart`, copied exactly. `icon` is `gameGlyphFor(gameType)`. `heroBuilder` is `GameLetterTiles(word: <hero word>, tileSize: 52)`; coming-soon games use a `SizedBox.shrink()`. `howToPlay` is empty for all of them in this task. The two prototypes are not listed.

The older helpers (`gameTypeDisplayName`, the glyph map, the sheet's catalogue) are not rewritten over this list yet; the tests below keep them from drifting apart until phase 5 does that.

`LegacyGameController.watchLanding`: the first row of `activeGamesProvider` whose `game_type` matches → `watchSessionLanding(sessionId: row['id'], initiatorId: row['initiator_id'])`; none → `fresh`; the list still loading → `loading`. It listens to `gameSessionEventsProvider` and invalidates `activeGamesProvider` on each event. `onPrimary` and `openSession` call the opener, passing `state.sessionId` / `sessionId`.

- [ ] **Step 1: Write the failing tests.**

```dart
// games_catalogue_test.dart
test('the five launch games, in order', () {
  final registry = GameRegistry(gameCatalogue);
  expect(registry.launch.map((g) => g.gameType),
      ['this_or_that', 'truth_or_dare', '36_questions', 'word_hunt', 'snakes_and_ladders']);
});
test('every title is the name the chat card uses', () {
  expect(gameCatalogue, isNotEmpty);
  for (final game in gameCatalogue) { expect(game.title, gameTypeDisplayName(game.gameType), reason: game.gameType); }
});
test('every launch game can be opened', () {
  final launch = GameRegistry(gameCatalogue).launch;
  expect(launch, hasLength(5));
  for (final game in launch) { expect(game.controller, isNotNull, reason: game.gameType); }
});
test('every game type the chat can route has a place in the catalogue', () {
  // The sheet's own list: a game added there and missed here would vanish
  // from the hub.
  final known = gameCatalogue.map((g) => g.gameType).toSet();
  for (final type in kInvitableGameTypes) { expect(known, contains(type)); }
  expect(kInvitableGameTypes, isNotEmpty);
});
test('each launch game has its own colour, and no coming-soon game borrows one', …);

// legacy_game_controller_test.dart — a probe ConsumerWidget calls watchLanding;
// activeGamesProvider, gameCardProvider(id), gameSessionEventsProvider,
// currentUserIdProvider, gamePartnerNameProvider and legacyGameOpenerProvider overridden
testWidgets('no game in progress reads as fresh', …);
testWidgets('a game in progress reads from its live card', …);        // yourTurn, sessionId 's1'
testWidgets('another game\'s session is not mistaken for this one', …); // a word_hunt row, controller for truth_or_dare -> fresh
testWidgets('the button opens the game\'s current screens, with the session when there is one', …);
// opener records (gameType, sessionId): fresh -> ('truth_or_dare', null); in progress -> ('truth_or_dare', 's1')
testWidgets('a partner\'s move refreshes it', …);
// a StreamController for gameSessionEventsProvider; change what activeGamesProvider
// returns, add an event, pump -> the probe shows the new status
```

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/platform/games_catalogue_test.dart test/features/games/platform/legacy_game_controller_test.dart` — Expected: compile errors.
- [ ] **Step 3: Implement.** The default opener: `chatGameDestinationForType(gameType)` null → do nothing; else `openGameRoute(context, destination, relationshipId: <currentRelationshipIdProvider>, sessionId: sessionId)`, returning quietly if there is no relationship.
- [ ] **Step 4: Run** the same command — Expected: `+10: All tests passed!`. Analyzer clean.
- [ ] **Step 5: Commit.** `git commit -m "feat(games): the games catalogue and a controller for games not yet redrawn (platform phase 2, task 4)"`

---

### Task 5: The landing page as a route

**Files:**
- Create: `lib/features/games/platform/shell/game_landing_page.dart`, `test/features/games/platform/support/route_recorder.dart`
- Modify: `lib/features/games/platform/game_strings.dart`
- Test: `test/features/games/platform/game_landing_page_test.dart`

**Interfaces:**
- Consumes: `gameRegistryProvider` (Task 4), `GameController` (Task 1), `GameLandingScreen`, `showGameHowToPlay`.
- Produces:

```dart
/// The page a game opens on. Route: /games/play/:gameType.
class GameLandingPage extends ConsumerStatefulWidget { const GameLandingPage({super.key, required this.gameType}); }

// route_recorder.dart (test support)
/// Hosts [home] in a GoRouter whose named routes are stand-ins. Each shows
/// `opened:<name>:<detail>`, where detail is the gameType path parameter,
/// else the `type` query parameter, else `extra`, else empty. Names:
/// gamesHub, gameLanding, thisOrThatSessionRouter, thisOrThatCustomList,
/// thisOrThatSessionHistory, communityFeed.
Widget gameRouterHost({required Widget home, required SharedPreferences prefs,
    List<Override> overrides = const [], Brightness brightness = Brightness.light, double textScale = 1});
```

Behaviour: an unknown `gameType` → a `GameScaffold` titled `GameStrings.games` ('Games') with `GameStrings.notAvailable` ('This game is not available.') and a Back button. A coming-soon game with no session in progress → the landing screen with `GameLandingStatus.comingSoon` and no entries. Otherwise the controller's state, entries, primary and remind. While `onPrimary` (or an entry's tap that returns a future) is running, the button is `busy` and further taps on it and on the entries are ignored. "?" appears only when `howToPlay` is not empty.

- [ ] **Step 1: Write the failing tests** with a `_FakeController` that records calls and whose `onPrimary` completes when the test says so:

```dart
testWidgets('shows the game the route names', …);                       // title and tagline of the definition
testWidgets('the button and rows come from the game\'s controller', …); // state yourTurn + 2 entries
testWidgets('a second tap while the first is still starting does nothing', (tester) async {
  // Review Focus 1.
  …
  await tester.tap(find.byType(GamePrimaryButton));
  await tester.pump();
  await tester.tap(find.byType(GamePrimaryButton), warnIfMissed: false);
  await tester.pump();
  expect(controller.primaryCalls, 1);
  controller.finishPrimary();
  await tester.pump();
  await tester.tap(find.byType(GamePrimaryButton));
  await tester.pump();
  expect(controller.primaryCalls, 2, reason: 'the control: it is tappable again once the first finished');
});
testWidgets('a game the app does not know gets a readable page, not a crash', …);   // Review Focus 4
// gameType 'made_up': 'This game is not available.' findsOneWidget; takeException isNull;
// inkOnGround on the page: none under 4.5
testWidgets('a coming-soon game cannot be started', …);                 // 'Coming soon', primaryCalls stays 0
testWidgets('a coming-soon game already in progress can still be opened', …);  // controller state yourTurn -> 'Your turn', enabled
testWidgets('the reminder reaches the game', …);                        // waiting + canRemind -> onRemind called once
testWidgets('there is no help button for a game with no rules written', …);     // control: a definition with howToPlay shows it
testWidgets('a long name on a small phone does not overflow', (tester) async {
  // Review Focus 6.
  useSurface(tester, const Size(320, 568));
  … state: waiting, partnerName: 'Bartholomew-James', canRemind: true …
  expect(tester.takeException(), isNull);
  expect(find.text('Waiting for Bartholomew-James'), findsOneWidget);
});
```

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/platform/game_landing_page_test.dart` — Expected: compile errors.
- [ ] **Step 3: Implement.** Add `GameStrings.games` and `GameStrings.notAvailable`.
- [ ] **Step 4: Run** — Expected: `+9: All tests passed!`. Analyzer clean.
- [ ] **Step 5: Commit.** `git commit -m "feat(games): the landing page route (platform phase 2, task 5)"`

---

### Task 6: The hub

**Files:**
- Create: `lib/features/games/platform/shell/games_hub_screen.dart`, `lib/features/games/platform/shell/game_hub_card.dart`
- Modify: `lib/features/games/platform/game_strings.dart`
- Test: `test/features/games/platform/games_hub_test.dart`

**Interfaces:**
- Consumes: `gameRegistryProvider`, `activeGamesProvider`, `gameSessionEventsProvider`, `watchSessionLanding`, `landingAction`, `legacyGameOpenerProvider`, `gameTypeDisplayName`, `gamePartnerNameProvider`.
- Produces:

```dart
/// Every game, and every game in progress. Route: /games/hub.
class GamesHubScreen extends ConsumerWidget { const GamesHubScreen({super.key}); }

/// A game in the hub: a block of its colour, a white tile with its icon,
/// its name. [onTap] null draws it dimmed and takes no touches.
class GameHubCard extends StatelessWidget {
  const GameHubCard({super.key, required this.definition, this.onTap, this.featured = false});
}
```

Layout, top to bottom, in a `GameContentWidth(maxWidth: ContentWidth.list)` scrolling column on `GameTheme.ground`:

1. A back button, then `GameStrings.games` at 34 px weight 900, and under it `GameStrings.playWith(name)` ("Play with Ama") — or `GameStrings.playTogether` ("Play together") while the name is unknown.
2. **In play** (`GameStrings.inPlay`) — only when there is at least one session. One row per row of `activeGamesProvider`: a chip of the game's colour with its icon, the game's title, and the label from `landingAction(watchSessionLanding(…)).label`. A tap opens that session: `definition.controller.openSession` when the catalogue has a controller for it, else the legacy opener. A row is never disabled.
3. **Play together** (`GameStrings.playTogether`) — the launch games. The first as one full-width card (`featured: true`, 150 high, showing its tagline), the rest two to a row (120 high). A tap pushes `gameLanding` with the game's type.
4. **Coming soon** (`GameStrings.comingSoon`) — two to a row, `onTap: null`, announced as "`<title>`, coming soon" with no button trait.

The card: `DecoratedBox` of `definition.theme.primary`, radius 20; a `GameTile` (not tappable itself) holding the icon in `GameTheme.tileInk`; the title in white, weight 800, bottom-left. The whole card is one semantics button. A session list that fails to load hides section 2 and nothing else. The hub listens to `gameSessionEventsProvider` and invalidates `activeGamesProvider`.

- [ ] **Step 1: Write the failing tests.** These carry the behaviour `chat_games_sheet_test.dart` guards (spec §3.3); the comment on each names the sheet test it stands in for.

```dart
testWidgets('lists the five launch games under Play together', …);
// each title found once; This or That's card is above the others (featured)
testWidgets('a launch game opens its landing page', …);
// stands in for: "a built game still selects"
// gameRouterHost; tap 'Truth or Dare' -> find.text('opened:gameLanding:truth_or_dare')
testWidgets('a coming-soon game is labelled and takes no taps', …);
// stands in for: "a coming-soon row is inert and labelled"
// tap 'Mirror' (warnIfMissed: false) -> still on the hub; semantics label
// 'Mirror, coming soon', not a button. Control: the test above, where a tap navigates.
testWidgets('a game in progress is listed and opens that session', …);
// stands in for: "an active game is listed and resumes on tap"
// activeGamesProvider -> one truth_or_dare row 's1'; opener records ('truth_or_dare', 's1')
testWidgets('a coming-soon game already in progress still opens', …);
// a mirror row 's2' -> In play shows 'Mirror'; tap -> opener records ('mirror', 's2')
testWidgets('names are words, never database values', …);
// stands in for: "every game_type … resumes somewhere" / raw type rendering
// a row with game_type 'brand_new_game' -> 'Brand New Game' found, 'brand_new_game' not;
// tapping it does not throw
testWidgets('In play is not shown when nothing is in progress', …);
// stands in for: "neither section appears when both lists are empty". Control: the test above.
testWidgets('says whose turn it is, live', (tester) async {
  // Review Focus 2.
  … gameCardProvider('s1') driven by a StreamController …
  expect(find.text('Your turn'), findsOneWidget);
  cards.add(card(status: 'active', viewerAnswered: true, partnerAnswered: false));
  await tester.pump();
  expect(find.text('Waiting for Ama'), findsOneWidget);
});
testWidgets('a failed session list still shows the games', …);          // launch titles found, no exception
testWidgets('the largest text size scrolls and does not overflow', …);
// stands in for: "the sheet grows with large text". textScale 2 on `phone`;
// takeException isNull; scrollUntilVisible the last coming-soon title
testWidgets('everything written on the ground can be read there', …);   // inkOnGround, >= 8 pieces, none under 4.5
testWidgets('every card can be activated by a screen reader', …);       // performSemanticsAction tap on 'Word Hunt' -> navigates
```

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/platform/games_hub_test.dart` — Expected: compile errors.
- [ ] **Step 3: Implement.** Add `GameStrings.inPlay = 'In play'`, `playTogether = 'Play together'`, `playWith(String name) => 'Play with $name'`.
- [ ] **Step 4: Run** — Expected: `+12: All tests passed!`. Analyzer clean.
- [ ] **Step 5: Commit.** `git commit -m "feat(games): the games hub (platform phase 2, task 6)"`

---

### Task 7: This or That's definition and controller

**Files:**
- Create: `lib/features/games/this_or_that/this_or_that_game.dart`, `lib/features/games/this_or_that/domain/this_or_that_tones.dart`, `lib/features/games/this_or_that/presentation/start_this_or_that.dart`
- Modify: `lib/features/games/this_or_that/presentation/screens/tone_selector_screen.dart`, `lib/features/games/platform/games_catalogue.dart`
- Test: `test/features/games/this_or_that/this_or_that_controller_test.dart`, `test/features/games/this_or_that/start_this_or_that_test.dart`; existing `test/features/games/this_or_that_question_ui_test.dart` (the tone test) stays green

**Interfaces:**
- Consumes: `activeThisOrThatSessionProvider`, `createThisOrThatSessionProvider`, `sessionRoundsProvider`, `relationshipMembersProvider`, `sendReminderProvider`, `currentRelationshipIdProvider`, `currentUserIdProvider` (all `this_or_that_providers.dart` — import the platform's same-named providers with `hide`); `recentGamesProvider`, `gameSessionEventsProvider`; `watchSessionLanding`.
- Produces:

```dart
// this_or_that_tones.dart
@immutable
class ThisOrThatTone { const ThisOrThatTone({required this.id, required this.label, required this.description, required this.icon, required this.color}); }
/// connecting, romantic, playful, spicy, intimate — values moved unchanged
/// from the tone screen's private list.
const List<ThisOrThatTone> thisOrThatTones;

// start_this_or_that.dart
/// Starts a game in [tone]. Returns the new session's id, or null when it
/// did not start: no active relationship, the Intimate question declined,
/// or an error (already shown to the player).
Future<String?> startThisOrThat(BuildContext context, WidgetRef ref, {required String tone});

/// When the player may nudge: they have answered the current round, their
/// partner has not, and their answer is at least two hours old.
bool thisOrThatCanRemind({required List<GameRound> rounds, required bool viewerIsPartnerA, required DateTime now});

// this_or_that_game.dart
const GameTheme thisOrThatTheme = GameTheme(primary: GameColors.thisOrThat);
class ThisOrThatController extends GameController { const ThisOrThatController(); }
final GameDefinition thisOrThatGame;
```

`startThisOrThat` is the body of `ToneSelectorScreen._startGame` moved, with its three messages and its Intimate dialog word for word; the tone screen calls it and keeps only its own navigation. `thisOrThatGame`: collection label "Quick play", tagline "Quick choices, shared reveals", icon `gameGlyphFor('this_or_that')`, hero = two `GameTile`s side by side reading THIS (in `0xFFFF8A76`) and THAT (in `0xFF8DA7FF`) with a small "or" between, and

```dart
howToPlay: [
  'Pull THIS or THAT forward to choose, then lock it in.',
  'Your pick stays hidden until your partner has answered too.',
  'When you have both picked, the two answers turn over together.',
  'There are no wrong answers.',
],
```

The catalogue's `this_or_that` entry becomes `thisOrThatGame`.

`ThisOrThatController`:

| Member | Behaviour |
|---|---|
| `watchLanding` | `activeThisOrThatSessionProvider` loading → `loading`. A session → `watchSessionLanding(sessionId, initiatorId)`, with `caption` `'Round r of t'` from the session (`currentRound` clamped to 1…`totalRounds`) and `canRemind` from `thisOrThatCanRemind` when the status is `waiting` on an active session. None → `finished` when the newest row of `recentGamesProvider` is a `this_or_that`, else `fresh`. An error → `fresh`. Listens to `gameSessionEventsProvider` and invalidates `activeThisOrThatSessionProvider`. |
| `onPrimary` | `fresh` / `finished` → `startThisOrThat(tone: 'connecting')`, then `openSession`. Any state with a `sessionId` → `openSession`. |
| `entries` | No session in progress: the five tones (title = label, subtitle = description; tap → `startThisOrThat` in that tone, then `openSession`), then **Your questions** → `thisOrThatCustomList`, **Past games** → `thisOrThatSessionHistory`, **From the community** → `communityFeed` with `type=This or That`. A session in progress: the last three only. |
| `onRemind` | `sendReminderProvider(sessionId)`; then the waiting screen's two messages, unchanged: "A gentle nudge was sent to `<name>`." / "The reminder could not be sent yet." |
| `openSession` | `await context.pushNamed('thisOrThatSessionRouter', extra: sessionId)`, then invalidate `activeThisOrThatSessionProvider` so the landing page re-reads on return. |

- [ ] **Step 1: Write the failing tests.**

```dart
// start_this_or_that_test.dart (mocktail repository, as this_or_that_question_ui_test.dart does)
testWidgets('starts a game in the tone asked for and returns its id', …);     // createSession called once with tone 'playful'
testWidgets('Intimate asks first, and "Not now" starts nothing', …);
// dialog title 'Choose Intimate together' shows; tap 'Not now' -> null; verifyNever(createSession)
testWidgets('Intimate continues after consent', …);                           // tap 'Continue' -> createSession tone 'intimate'
testWidgets('with no relationship it explains and starts nothing', …);        // 'This game unlocks when a relationship is active.'
testWidgets('a failure is shown and returns null', …);                        // 'The game could not start. Try again.'
test('a nudge is offered two hours after answering, not before', () {
  final answered = DateTime.utc(2026, 11, 19, 10);
  List<GameRound> rounds(…) => …; // current round: viewer (partner A) answered at `answered`, partner not
  expect(thisOrThatCanRemind(rounds: rounds(), viewerIsPartnerA: true, now: answered.add(const Duration(minutes: 119))), isFalse);
  expect(thisOrThatCanRemind(rounds: rounds(), viewerIsPartnerA: true, now: answered.add(const Duration(hours: 2))), isTrue);
});
test('no nudge when the partner has answered, or the viewer has not', …);

// this_or_that_controller_test.dart (probe widget in gameRouterHost)
testWidgets('no game: Play, with the five tones first', …);
// status fresh; entry titles == ['Connecting','Romantic','Playful','Spicy','Intimate','Your questions','Past games','From the community']
testWidgets('a game in progress hides the tones and keeps the rest', …);
// entry titles == ['Your questions','Past games','From the community']
testWidgets('Play starts a Connecting game and opens it', …);
// createSession tone 'connecting'; find.text('opened:thisOrThatSessionRouter:new-session')
testWidgets('a tone row starts a game in that tone', …);                      // tap the Playful entry -> tone 'playful'
testWidgets('Your turn opens the game in progress and starts nothing', …);    // verifyNever(createSession); opened with 's1'
testWidgets('after a finished game the button offers another', …);            // recentGamesProvider newest this_or_that -> finished
testWidgets('coming back from the game re-reads where it stands', (tester) async {
  // Review Focus 3. The session provider answers 'none' the first time and
  // an active session the second.
  … open, then pop the stand-in route …
  expect(reads, 2);
  expect(find.text('status:yourTurn'), findsOneWidget);
});
testWidgets('a partner\'s move refreshes it', …);                              // Review Focus 2: an event -> reads goes up
testWidgets('the rows open the question decks, past games and the community feed', …);
// 'opened:thisOrThatCustomList:', 'opened:thisOrThatSessionHistory:', 'opened:communityFeed:This or That'
testWidgets('a nudge is sent, and says so', …);                               // sendReminder called; 'A gentle nudge was sent to Ama.'
```

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/this_or_that` — Expected: compile errors.
- [ ] **Step 3: Implement.** Edit `tone_selector_screen.dart` by hand; do not format it.
- [ ] **Step 4: Run** `flutter test test/features/games/this_or_that test/features/games/this_or_that_question_ui_test.dart test/features/games/platform/games_catalogue_test.dart` — Expected: all pass (17 new; the existing file's count unchanged). Analyzer: no new issues in `lib/features/games`.
- [ ] **Step 5: Commit.** `git commit -m "feat(games): This or That's definition and controller (platform phase 2, task 7)"`

---

### Task 8: Every This or That screen onto the shell

One file, `this_or_that_game_ui.dart`, gives the game's thirteen screens their palette and scaffold. Changing it moves all of them at once: question decks, history, recap, the invitation screens and the next-card chooser included.

**Files:**
- Modify: `lib/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart`, `lib/features/games/this_or_that/presentation/screens/waiting_screen.dart` (its `leading:` only)
- Test: `test/features/games/this_or_that/this_or_that_shell_test.dart`, `test/features/games/this_or_that/this_or_that_shell_golden_test.dart`; `test/features/games/this_or_that_question_ui_test.dart` and `this_or_that_custom_ui_test.dart` stay green

**Interfaces:**
- Consumes: `GameScaffold` (with `bottom`), `GamePrimaryButton` (with `busy`), `showGameSettingsSheet`, `showGameHowToPlay`, `thisOrThatGame`, `thisOrThatTheme`.
- Produces (same names, same constructors, new drawing):

```dart
class ThisOrThatPalette { static ThisOrThatPalette of(BuildContext context); }   // one palette; no longer follows app brightness
class ThisOrThatGameScaffold { … this.onBack, this.onHowToPlay … }               // two new optional callbacks; `leading` is removed
class ThisOrThatPrimaryAction { … }                                              // draws a GamePrimaryButton
```

The palette, whatever the app theme: `thisColor 0xFFFF8A76`, `thatColor 0xFF8DA7FF`, `thisSurface 0xFF3A2424`, `thatSurface 0xFF202B46`, `canvas GameTheme.ground`, `panel GameTheme.raised`, `ink GameTheme.onGround`, `mutedInk GameTheme.mutedOnGround`, `line GameTheme.hairline`.

The scaffold builds a `GameScaffold(theme: thisOrThatTheme)`: with `roundNumber` and `totalRounds`, the title is "Round r of t" and the subtitle is `title`; without, the title is `title`. The thin progress track stays, directly under the header. `child` goes in the body with its existing padding, scrolling when `scrollable`. `bottom` goes in the scaffold's `bottom` slot. `actions` (app-bar widgets — check for callers; none pass it today) is removed if unused. The gear opens `showGameSettingsSheet(definition: thisOrThatGame, onHowToPlay: onHowToPlay ?? () => showGameHowToPlay(context, definition: thisOrThatGame))` and passes no `onLeaveGame` (ruling 4). `onBack` defaults to popping. The decorative split-canvas texture is removed; the backdrop replaces it.

`WaitingScreen` passed a custom `leading` button (tooltip "Leave game") that asks "Leave for now?" before popping; it now passes that same function as `onBack`.

- [ ] **Step 1: Write the failing tests.**

```dart
// this_or_that_shell_test.dart
testWidgets('the palette is the same in a light app and a dark one', …);
// pump under ThemeData.light() and ThemeData.dark(); ThisOrThatPalette.of -> canvas == GameTheme.ground both times
testWidgets('with a round, the header reads the round over the game\'s name', …);
// ThisOrThatGameScaffold(roundNumber: 3, totalRounds: 10): 'Round 3 of 10' and 'This or That' found,
// the name above the round
testWidgets('the gear opens settings with sound and vibration, and no Leave game', …);
// tap Settings -> 'Sound effects' found; Support tab -> 'How to play' found, 'Leave game' findsNothing
// (control: phase 1's settings test, where passing onLeaveGame shows it)
testWidgets('the primary action shows progress while loading and takes no taps', …);
testWidgets('everything written on the ground can be read, in a light app too', …);
// the question deck list screen under ThemeData.light(): inkOnGround none under 4.5
testWidgets('leaving the waiting screen still asks first', …);
// tap Back on WaitingScreen -> 'Leave for now?' shows; 'Keep waiting' stays; 'Leave game' pops
```

Golden test, phone only unless noted, with `loadGameTestFonts()` and the macOS skip from phase 1: the question deck list, the write-a-question form **under a light app theme** (Review Focus 5), past games, the next-card chooser, and the invitation decision (through `ThisOrThatSessionRouterScreen` with an invited session, as the existing router test sets one up).

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/this_or_that/this_or_that_shell_test.dart` — Expected: failures (`onBack` undefined; canvas is the light colour).
- [ ] **Step 3: Implement.** Re-point any existing test that finds the tooltip "Leave game" to the Back button's semantics label; keep its assertions.
- [ ] **Step 4: Run** `flutter test test/features/games --update-goldens`, then without the flag — Expected: all pass. Then **open every new golden** and check: dark ground with orange at the top; every word readable; text fields and list rows dark with light text; nothing clipped; buttons are the white pill. Fix in the screen that owns the problem, with a test, and regenerate. `this_or_that_tab_card_golden_test`'s pictures are regenerated in Task 9, not here — if they changed already, look at them now too.
- [ ] **Step 5: Commit.** `git commit -m "feat(games): This or That's screens move onto the shell (platform phase 2, task 8)"`

---

### Task 9: The question, in tiles

**Files:**
- Modify: `lib/features/games/this_or_that/presentation/widgets/this_or_that_tab_card.dart`, `lib/features/games/this_or_that/presentation/screens/question_screen.dart`
- Test: `test/features/games/this_or_that_tab_card_test.dart`, `this_or_that_tab_card_golden_test.dart`, `this_or_that_question_ui_test.dart` (all existing, all kept); add to `test/features/games/this_or_that/this_or_that_question_test.dart`

**Interfaces:**
- Consumes: `GameTile`, `GameMotion`, `gameFeedbackProvider` / `GameEvent`, `GameCoach` / `GameCoachStep` (with `replay`), `ThisOrThatGameScaffold.onHowToPlay`.
- Produces: `ThisOrThatTabCard` and `QuestionScreen` keep their constructors exactly.

The card, redrawn. Its mechanic does not change: it opens on the question, pulling THIS or THAT forward floods the card with that option's colour and shows the option, the middle tab is not a way back, and a null `onSelect` makes every tab inert.

- The three tabs are `GameTile`s: THIS in `thisColor`, OR in `GameTheme.tile` with `tileInk`, THAT in `thatColor`. The forward tab has `depth: 5`; the others `depth: 2` with their label at 62% strength. Semantics labels stay `THIS`, `OR`, `THAT`, with `selected` on the forward one.
- The body is one tile-shaped panel: radius 22, a hard shadow 6 px down and 3.6 px right in `GameTheme.tileShadow`, no blur. On the question it is white with the question in `tileInk` at 30 px weight 800. On a choice its colour becomes the option's (animated over `GameMotion.settle`), the question drops to 17 px, and the option shows at 26 px weight 800 with its emoji.
- Ink on a flooded card is whichever of white and `tileInk` has the higher contrast with that colour.

The screen: selecting fires `GameEvent.tap`; locking in fires `GameEvent.place`; both through `gameFeedbackProvider`, replacing the direct sound and haptic calls. The line under the button becomes "Your pick stays hidden until `<partnerName>` has answered too." The body is wrapped in a `GameCoach(gameType: 'this_or_that')` with three steps, the first two pointing at the tab row and the lock button:

1. "Pull THIS or THAT forward to choose."
2. "Then lock it in. `<partnerName>` will not see your pick until they have answered too."
3. "When you have both picked, the two answers turn over together."

How to play, from the settings sheet on this screen, closes the sheet and replays the coach (`replay` + 1).

- [ ] **Step 1: Write the failing tests.** Existing assertions are the authority: `this_or_that_question_ui_test.dart` expects `sounds.played == [AppSound.gameTap]` and `haptics.selectionCount == 1` after choosing, which is what `GameEvent.tap` produces. Its `_wrap` helper gains an override of `sharedPreferencesProvider` with `{GameCoachStore.key('this_or_that'): true}` so the tutorial is not in the way; nothing else in that file changes unless a hook is tied to the old drawing. New tests:

```dart
testWidgets('with sound switched off in settings, choosing is silent', …);
// prefs {GamePrefsNotifier.soundKey: false}: tap THAT -> sounds.played isEmpty.
// Control: the existing test, where the same tap plays gameTap.
testWidgets('a first-time player is walked through it', …);
// prefs empty: 'Pull THIS or THAT forward to choose.' shows, with a ring around the tab row
testWidgets('the game can be played with the tutorial still up', …);
// with the bubble showing, tap THAT -> 'Lock in That' appears
testWidgets('How to play in settings replays the tutorial', …);
// seen=true -> no bubble; Settings > Support > How to play -> the first step shows
testWidgets('the hidden-pick line names the partner', …);
// partnerName 'Ama': 'Your pick stays hidden until Ama has answered too.'; find.textContaining('both of you') findsNothing
testWidgets('the tabs are tiles and the forward one stands proud', …);
// GameTile descendants of the card: 3; the selected tab's depth > the others'
testWidgets('ink on a chosen card is readable on both option colours', …);
// choose THIS, then a fresh card THAT: contrast(ink, card colour) >= 4.5 each
```

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/this_or_that/this_or_that_question_test.dart` — Expected: failures (no `GameTile` in the card, no tutorial, old sentence).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/features/games/this_or_that_tab_card_test.dart test/features/games/this_or_that_question_ui_test.dart test/features/games/this_or_that` — Expected: all pass, the two existing files at their existing counts. Then `flutter test test/features/games/this_or_that_tab_card_golden_test.dart --update-goldens` and **open the pictures**: the question state (white panel, dark question, three tabs with OR forward), THIS chosen, THAT chosen. Each must read at a glance as one card with three tabs, with the choice unmistakable. Add `question.phone.png`, `question_this.phone.png`, `question_coach.phone.png` of the whole screen to `this_or_that_shell_golden_test.dart` and look at those too.
- [ ] **Step 5: Commit.** `git commit -m "feat(games): This or That's question card redrawn in tiles, with a first-time tutorial (platform phase 2, task 9)"`

---

### Task 10: Waiting and the reveal

**Files:**
- Modify: `lib/features/games/this_or_that/presentation/screens/waiting_screen.dart`, `reveal_screen.dart`, `lib/features/games/this_or_that/presentation/widgets/match_indicator.dart` (colours only, if it needs them)
- Test: `this_or_that_question_ui_test.dart` (existing waiting and reveal tests kept); add `test/features/games/this_or_that/this_or_that_reveal_test.dart`

**Interfaces:**
- Consumes: `GameTile`, `GameBurst`, `GameSecondaryButton`, `gameFeedbackProvider`.
- Produces: `WaitingScreen` and `RevealScreen` keep their constructors exactly.

Waiting: the locked pick is one `GameTile` in the pick's colour, labelled "Your locked pick", with the option and its emoji. Under it the existing waiting mark, then "Your answer is tucked away. The reveal begins as soon as `<partnerName>` locks theirs in." **Nudge `<partnerName>`** and **Change my pick** are `GameSecondaryButton`s; every rule about when the nudge appears is unchanged.

Reveal: two `GameTile`s side by side, "You" and the partner's name above them, each in its option's colour with the option and emoji; they arrive one after the other (`GameMotion.stagger`). On a match with `celebrate`, a `GameBurst` plays once over the pair and `GameEvent.match` fires once; otherwise `GameEvent.reveal` fires once. The existing match indicator and its wording stay. The bottom buttons become `GamePrimaryButton` (next) and `GameSecondaryButton` (previous), with `busy` while advancing.

- [ ] **Step 1: Write the failing tests.**

```dart
testWidgets('a match bursts once and plays the match sound once', …);
// isMatch: true: after pumpAndSettle, sounds.played == [AppSound.gameMatch];
// rebuild the same screen -> still one
testWidgets('different answers reveal without a burst', …);
// isMatch: false: played == [AppSound.gameReveal]; the GameBurst's count is 0.
// Control: the test above.
testWidgets('under reduce motion both picks are there on the first frame', …);
// both option texts found after one pump; transientCallbackCount == 0
testWidgets('each pick is drawn in its own option\'s colour', …);
// you chose a, partner chose b: your tile's colour == palette.thisColor, theirs == palette.thatColor
testWidgets('the waiting line names the partner', …);
// 'The reveal begins as soon as Ama locks theirs in.'
```

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/this_or_that/this_or_that_reveal_test.dart` — Expected: failures.
- [ ] **Step 3: Implement.** If an existing test asserts a sound or haptic on reveal, that assertion decides which event fires; do not change it.
- [ ] **Step 4: Run** `flutter test test/features/games/this_or_that_question_ui_test.dart test/features/games/this_or_that` — Expected: all pass. Add `waiting.phone.png`, `reveal_match.phone.png`, `reveal_differ.phone.png` to the shell golden test, regenerate, **open them**: two tiles of clearly different colours on a difference, the same colour on a match; names readable above; nothing clipped at 375 wide with a long option ("Stay in and cook something slow together").
- [ ] **Step 5: Commit.** `git commit -m "feat(games): This or That's waiting and reveal redrawn (platform phase 2, task 10)"`

---

### Task 11: The end, and where the buttons lead

**Files:**
- Modify: `lib/features/games/this_or_that/presentation/screens/end_screen.dart`, `this_or_that_session_router_screen.dart`
- Test: `this_or_that_question_ui_test.dart` ("end screen celebrates every score without calling it a loss", "final answered round reveals before session completion" — kept); add `test/features/games/this_or_that/this_or_that_end_test.dart`

**Interfaces:**
- Consumes: `GameCompleteScreen`, `startThisOrThat`, `gamePartnerNameProvider`.
- Produces: `EndScreen` keeps its constructor (`matchCount`, `totalRounds`, `mostInterestingPick`, `onPlayAgain`, `onTryAnotherGame`).

`EndScreen` builds a `GameCompleteScreen(theme: thisOrThatTheme)`: `headline` is the existing verdict ("Very much in sync" / "More alike than not" / "Full of surprises"), `word` is `COMPLETE`, `names` is `['You', <partner name>]`, and `summary` holds the existing sentence for the score and the existing "Talk about this one" pick, drawn as a tile. The score ring is removed; the count is said in words ("You matched on 7 of 10."). It stays a shared result: nothing names who "got it wrong".

In the session router: **Play again** starts a new game in the finished game's tone — `startThisOrThat(tone: session.tone)`, then `context.pushReplacementNamed('thisOrThatSessionRouter', extra: id)` — and does nothing more if that returns null. **Back to games**, and the "Back to games" action on the ended-game and error screens, pop the route (`Navigator.of(context).maybePop()`), replacing the three `pushReplacementNamed('thisOrThatGamesHub')` calls. The old hub and tone screens stay registered and unreached; phase 5 removes them with the sheet.

- [ ] **Step 1: Write the failing tests.**

```dart
testWidgets('says the score in words and names the two players', …);
// matchCount 7, totalRounds 10, partner 'Ama': 'You matched on 7 of 10.' and 'You & Ama' found; 8 GameTiles spell COMPLETE
testWidgets('a low score is still not a loss', …);
// matchCount 1: 'Full of surprises' found; none of 'lost', 'failed', 'wrong', 'only' found (case-insensitive)
testWidgets('the pick worth talking about is shown', …);
testWidgets('Play again starts a new game in the same tone', …);
// through the router screen with a completed 'playful' session: createSession tone 'playful';
// 'opened:thisOrThatSessionRouter:new-session'
testWidgets('Back to games returns to where the player came from', …);
// router pushed over a page showing 'came from here': tap Back to games -> 'came from here' found
testWidgets('the win sound plays once', …);
```

- [ ] **Step 2: Run and watch them fail.** `flutter test test/features/games/this_or_that/this_or_that_end_test.dart` — Expected: failures.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/features/games` — Expected: all pass. Add `end.phone.png` and `end_low.phone.png` to the shell golden test, regenerate, **open them**.
- [ ] **Step 5: Commit.** `git commit -m "feat(games): This or That ends on the shared completion screen (platform phase 2, task 11)"`

---

### Task 12: The two routes

**Files:**
- Modify: `lib/app/routing/app_router.dart` (additive), `test/architecture/games_untouched_test.dart`
- Test: `test/features/games/platform/game_routes_test.dart`

**Interfaces — Produces:**

```dart
// RouteNames
static const String gamesHub = '/games/hub';
static const String gameLanding = '/games/play/:gameType';

GoRoute(path: RouteNames.gamesHub, name: 'gamesHub', builder: (context, state) => const GamesHubScreen()),
GoRoute(path: RouteNames.gameLanding, name: 'gameLanding',
    builder: (context, state) => GameLandingPage(gameType: state.pathParameters['gameType'] ?? '')),
```

Placed beside the other `/games/…` routes. No existing route, import order or line is changed beyond the two imports, two constants and two routes.

- [ ] **Step 1: Run the guards first** and note the result: `flutter test test/architecture` — Expected: all pass (this is the before).
- [ ] **Step 2: Write the failing test.**

```dart
test('the hub and landing routes exist under the games prefix', () {
  final router = createAppRouter(RoutingNotifier());
  addTearDown(router.dispose);
  expect(router.namedLocation('gamesHub'), '/games/hub');
  expect(router.namedLocation('gameLanding', pathParameters: {'gameType': 'this_or_that'}), '/games/play/this_or_that');
});
test('neither new path is taken by an older games route', () {
  // /games/snakes/:relationshipId and /games/word-hunt/:relationshipId are
  // three segments too; the literal second segment must keep them apart.
  final router = createAppRouter(RoutingNotifier());
  addTearDown(router.dispose);
  expect(router.configuration.findMatch('/games/play/word_hunt').matches.last.route, isA<GoRoute>()
      .having((r) => r.name, 'name', 'gameLanding'));
  expect(router.configuration.findMatch('/games/snakes/abc').matches.last.route, isA<GoRoute>()
      .having((r) => r.name, 'name', 'snakesGame'));
});
```

Add `'gamesHub': '/games/hub'` and `'gameLanding': '/games/play/:gameType'` to `_gamesRoutes` in `games_untouched_test.dart`, and their source hashes to `_gamesRouteSource` (compute each with the test's own `_goRouteBlocks` + `sha256`).

- [ ] **Step 3: Run and watch it fail.** `flutter test test/features/games/platform/game_routes_test.dart` — Expected: `namedLocation` throws for an unknown route name.
- [ ] **Step 4: Implement,** by hand, unformatted.
- [ ] **Step 5: Run** `flutter test test/architecture test/features/games/platform/game_routes_test.dart` — Expected: all pass, including `text_scale_routes_test.dart` (both routes fall under `/games/`) and "the source of every Games route is unchanged". `git diff --stat lib/app/routing/app_router.dart` — Expected: insertions only.
- [ ] **Step 6: Commit.** `git commit -m "feat(games): routes for the hub and the landing page (platform phase 2, task 12)"`

---

### Task 13: The way in from chat

The last change, and the only one to a file other sessions are editing. Two edits.

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart`
- Test: `test/features/games/platform/chat_entry_test.dart`

**The edits:**

1. `_openGames()` — keep the method, its name and its two leading lines. Its body's `showChatGamesPicker(…)` call becomes `context.pushNamed('gamesHub')`.
2. `openGameRoute`, `case ChatGameDestination.thisOrThat:` — with a `sessionId`, `await context.pushNamed('thisOrThatSessionRouter', extra: sessionId)`; without, `await context.pushNamed('gameLanding', pathParameters: {'gameType': 'this_or_that'})`.

`showChatGamesPicker`, `ChatGamesSheet`, the composer bar and every other case stay exactly as they are. `games_untouched_test.dart` pins the strings `void _openGames() {`, `showChatGamesPicker(`, `onOpenGames: _openGames,` and `widget: ChatGamesSheet(`; all four survive these edits.

- [ ] **Step 1: Before touching the file,** run and record: `flutter test test/features/chat test/architecture test/accessibility/w10/in_chat_games_large_text_test.dart test/features/location/location_wiring_test.dart --reporter failures-only` — note the pass count and any failure that is already there.
- [ ] **Step 2: Confirm the server posts the card either way.** A game started from the landing page is created by `create_this_or_that_session`, not `game_invite_create`, so the chat card and the invitation push must come from the table, not from that RPC. Checked when this plan was written: `post_game_message` (`20260931200000_game_message_trigger.sql:89`) and `notify_game_invite` (`20260930150000_notify_game_invite.sql:85`) are both `AFTER INSERT ON public.game_sessions`. Run `grep -rn "post_game_message\|notify_game_invite" supabase/migrations | grep -i "drop trigger\|create trigger"` — Expected: no later migration drops either without recreating it. If one does, **stop and report**: that is a server change outside this phase.
- [ ] **Step 3: Write the failing test.**

```dart
testWidgets('a This or That card opens that game, not a landing page', (tester) async {
  // gameRouterHost; a button calls openGameRoute(context, ChatGameDestination.thisOrThat,
  // relationshipId: 'r1', sessionId: 's1')
  expect(find.text('opened:thisOrThatSessionRouter:s1'), findsOneWidget);
});
testWidgets('This or That with no session opens its landing page', …);
// sessionId null -> 'opened:gameLanding:this_or_that'
test('the games button opens the hub', () {
  // The chat screen cannot be pumped in a unit test; this pins the wiring
  // the same way games_untouched_test pins the rest of it.
  final chat = File('lib/features/chat/presentation/screens/chat_screen.dart').readAsStringSync();
  final body = chat.substring(chat.indexOf('void _openGames() {'), chat.indexOf('void _toggleHeaderExpanded()'));
  expect(body, contains("pushNamed('gamesHub')"));
  expect(body, isNot(contains('showChatGamesPicker(')));
});
```

- [ ] **Step 4: Run and watch it fail.** `flutter test test/features/games/platform/chat_entry_test.dart` — Expected: 3 failures (old routes).
- [ ] **Step 5: Make the two edits,** by hand. Do not format the file.
- [ ] **Step 6: Run** the command from Step 1 plus `test/features/games` — Expected: the same pass count as Step 1 plus the new tests, and no new failure. `git diff --stat lib/features/chat/presentation/screens/chat_screen.dart` — Expected: a handful of lines.
- [ ] **Step 7: Commit.** `git commit -m "feat(games): the chat's games button opens the hub; This or That opens through it (platform phase 2, task 13)"`

---

### Task 14: The pictures, and the gate

**Files:**
- Create: `test/features/games/platform/games_hub_golden_test.dart`
- Modify: `docs/superpowers/plans/2026-11-19-games-platform-phase-2.md` (the gate notes at the end)

- [ ] **Step 1: Hub and landing goldens.** With real fonts and the macOS skip, on `phone`, `widePhone` and `tablet`: the hub with nothing in progress; the hub with two games in play (one *Your turn*, one *Waiting for Ama*); This or That's landing page fresh (five tones); in progress and your turn (caption "ROUND 3 OF 10"); waiting with a reminder. On `phone` only: Truth or Dare's landing page, a coming-soon landing page, the unknown-game page.
- [ ] **Step 2: Generate and open them.** `flutter test test/features/games/platform/games_hub_golden_test.dart --update-goldens`. For each picture: the hub reads as vibrant — five blocks of five different colours, This or That largest; coming-soon cards are clearly quieter and clearly not buttons; every word readable; on the tablet the content is a centred column. Compare the hub and the landing page with the owner's reference screenshots (Netflix Puzzled: image 5 for the hub, image 1 for the landing page) and write down, plainly, where they fall short. Fix what is a defect; list what is a matter of art for the gate.
- [ ] **Step 3: Whole-suite check.**
  - `flutter test test/features/games test/core/ui` — Expected: all pass; record the count.
  - `flutter test test/features/chat test/architecture test/accessibility` — Expected: no failure that was not there at Task 13 Step 1.
  - `flutter analyze lib/features/games test/features/games` — Expected: `102 issues found.` or fewer.
  - `git diff --stat 1944966c -- . ':!lib/features/games' ':!test/features/games' ':!docs'` — Expected: exactly `lib/app/routing/app_router.dart`, `lib/features/chat/presentation/screens/chat_screen.dart` and `test/architecture/games_untouched_test.dart`.
  - `grep -rnE "[0-9)]\.(w|h|r|sp)\b" lib/features/games/platform; grep -rnE "MaskFilter|saveLayer|BackdropFilter|ImageFilter|Opacity\(" lib/features/games/platform` — Expected: no output.
- [ ] **Step 4: Write the gate notes** at the end of this plan: what to play and in what order (below), what is finished and what is deliberately not, and the list from Step 2.
- [ ] **Step 5: Commit.** `git commit -m "test(games): hub and landing goldens; phase 2 ready for the device gate (platform phase 2, task 14)"`

---

## The device gate

Two phones, the two partners' accounts, the app built from `feat/games-advance`.

1. Open a chat, tap the games button: the hub.
2. Open This or That: the landing page. Read "?".
3. Tap a tone. On the other phone, the card arrives in chat; tap it and join.
4. Play all the way through: choose, lock in, wait, reveal, next card, the end. Let one phone wait long enough to see the waiting screen. Leave mid-game from one phone and come back through the hub's *In play* row.
5. Play again from the end screen.
6. Open one other launch game to see a landing page leading to a screen that has not been redrawn yet.

**Finished in this phase:** the hub, every landing page, and all of This or That.
**Not finished, on purpose:** the other four launch games' own screens (phases 3–4); the card-into-landing transition (ruling 6); the mid-game push, licensed sounds and the removal of the old sheet (phase 5).

The question for the gate is the one tests cannot answer: does this feel like a game worth opening? If not, phase 2 is reworked before anything else is ported.
