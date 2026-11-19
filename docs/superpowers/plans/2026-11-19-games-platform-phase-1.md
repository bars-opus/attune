# Games Platform — Phase 1: Shell and Feel Layer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared shell every game will sit in — landing page, play scaffold, settings, how-to-play, first-time tutorial, completion — and the feel layer under it (tile, motion, burst, sound and vibration), proven with a demo game and no real game touched.

**Architecture:** A new, self-contained directory, `lib/features/games/platform/`. `feel/` holds the pieces a game is drawn and felt with; `shell/` holds the screens around a game; the top level holds the theme, the strings, and `GameDefinition` plus its registry — the single description of a game that phases 2–5 fill in. Nothing existing imports it yet, so nothing existing can change behaviour.

**Tech stack:** Flutter 3.29.1, Dart, Riverpod (`Notifier`), `shared_preferences`, the existing `SoundService` and `Haptics` in `lib/core/ui/feedback/`, `AppContentWidth` + `ContentWidth` tokens. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-19-games-platform-design.md` (§2 visual language, §3 platform, §7 testing).

---

## Where this sits

This is **phase 1 of 5**, in **13 tasks**.

| Phase | What | Ends with |
|---|---|---|
| **1 (this plan)** | Shell and feel layer, demo game only | 136 new tests green, goldens looked at |
| 2 | This or That on the shell, the games hub, the two shared-file edits | **The owner plays it on a phone.** Nothing further starts until that passes. |
| 3 | Truth or Dare, 36 Questions | |
| 4 | Word Hunt, Snakes and Ladders | |
| 5 | Mid-game push, sound and haptic pass, other games to coming soon, old sheet retired, docs | |

Phase 1 has nothing the owner can open in the app: no route, no hub, no real game. Its pictures are the goldens in Task 12. That is deliberate — it keeps this phase from touching anything shared — and it is why phase 2 ends at a device and this one does not.

## How this plan's code was checked

Every code block below was built in the worktree before this plan was written: 136 tests passing, `flutter analyze` clean on both new directories, and each task's files confirmed to depend only on files from the same or an earlier task. The blocks are copied from those files unchanged. If a block does not compile as written, stop and report it rather than adjusting it — something in the tree has changed since.

Three things the first set of goldens showed that every test had missed, now fixed in the code below and each given a test of its own:

1. The landing page's title and option names were dark ink on the dark ground (a `Material` below the backdrop reset the text colour).
2. The completion screen's content was stranded at the top of the screen.
3. The tutorial bubble covered the game's header.

And three the tests found:

4. The hand-built buttons could be focused by a screen reader but not pressed.
5. With a game's own tab present, the Support tab started off the edge of a phone.
6. One test tapped something off-screen and passed anyway — which is why a missed tap now fails.

## Global constraints

- **Worktree only.** Work in `/Users/user/attune/.worktrees/games-v2` on branch `feat/games-advance`. Never run commands in, or edit, the main checkout.
- **Two directories, nothing else.** Phase 1 creates files under `lib/features/games/platform/` and `test/features/games/platform/` only. It edits no existing file: no routes, no `.arb`, no providers, no existing game, no `pubspec.yaml`. If a task seems to need an edit elsewhere, stop and report.
- **No ScreenUtil inside `platform/`.** No `.w`, `.h`, `.r`, `.sp`. Sizes are plain logical pixels with flexible layout. The extensions throw in tests that have not initialised ScreenUtil, and mixing the two units is how screens end up distorted.
- **Flat drawing.** No blur, no `MaskFilter`, no `saveLayer`, no `BackdropFilter`, and no `Opacity` widget: dim through a colour's alpha, and bring things in by scale rather than fade.
- **Formatting.** `dart format` the new files only. Never format an existing file.
- **Text.** New shell text goes in `game_strings.dart`, in English. Partner names, never "both of you".
- **Tests.** Every test of a screen calls `useSurface(tester, phone)` (or another named surface), which also makes a missed tap fail. The tile test hosts a bare widget and sets that flag itself. A test that asserts something is absent names the test that is its positive control. Never loosen an assertion or silence a missed tap to get green.
- **Commits.** One commit per task, on `feat/games-advance`. Do not push, merge, or rebase. End each commit message with the attribution line your session specifies. Never commit `backup-before-planning-p2.sql` or `supabase/.temp/cli-latest`.
- **Known flakes, unrelated to this work:** `session_game_abandon`, `session_game_happy_path`, `session_game_invite`, `sound_service`, `audio_session_coordinator` can fail when run alongside other suites. Re-run the one file on its own before treating it as a regression.

## File map

```
lib/features/games/platform/
  game_theme.dart               colours; one per game, fading to near-black
  game_strings.dart             the shell's English text
  game_prefs.dart               sound and vibration switches
  game_definition.dart          what a game is: title, colour, hero, entries, rules, settings
  game_registry.dart            the list of games; rejects duplicates
  feel/
    game_motion.dart            named durations and curves; zero under reduce-motion
    game_tile.dart              the white tile that presses down
    game_feedback.dart          event -> sound + haptic
    game_burst.dart             the spark when something lands
    game_letter_tiles.dart      a word in tiles
  shell/
    game_backdrop.dart          the gradient, white ink, and the Material
    game_buttons.dart           round, primary and secondary buttons
    game_scaffold.dart          header + body + actions, for playing
    game_landing_screen.dart    the page before play
    game_settings_sheet.dart    General / the game / Support
    game_how_to_play_sheet.dart the rules
    game_coach.dart             the first-time tutorial
    game_complete_screen.dart   the end

test/features/games/platform/
  support/game_test_support.dart  surfaces, fonts, host, recording canvas, contrast
  support/demo_game.dart          a GameDefinition with no rules
  support/ink_on_ground.dart      what is written on the ground, and how readable
  game_*_test.dart                one per file above, plus the flow and the goldens
  goldens/                        22 pictures (Task 12)
```

---


### Task 1: Colours, motion tokens and the test support

Everything else reads its colours and timings from here. The test support
comes first too, because it pins every later widget test to a phone-sized
screen and makes a missed tap fail.

**Files:**

- Create: `lib/features/games/platform/game_theme.dart`
- Create: `lib/features/games/platform/feel/game_motion.dart`
- Create: `test/features/games/platform/support/game_test_support.dart`
- Create: `test/features/games/platform/game_theme_test.dart`

**What to know before writing it:**

- Orange is `#E0701A`, not the brighter `#EE8A3A` first sketched: white text on the brighter one falls under 3:1.
- `GameMotion.of(context, duration)` returns zero under the OS reduce-motion setting. Every animation in `platform/` takes its duration through it.
- `useSurface` sets `WidgetController.hitTestWarningShouldBeFatal = true`. Do not remove it and do not pass `warnIfMissed: false` to get a test green; scroll the thing into view instead.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/support/game_test_support.dart`

```dart
import 'dart:io';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The screens a golden is taken on.
///
/// A phone first, always. The default test surface is 800x600 landscape,
/// and judging a portrait screen's proportions against that is judging a
/// different screen: it distorted an earlier game's goldens by nearly 3x
/// before anyone noticed.
const Size phone = Size(375, 812);
const Size widePhone = Size(430, 932);
const Size tablet = Size(1024, 1366);

const Map<String, Size> goldenSurfaces = {
  'phone': phone,
  'wide': widePhone,
  'tablet': tablet,
};

/// Pins the test to a real screen size.
///
/// It also makes a tap that lands on nothing fail the test. By default a
/// missed tap only prints a warning, and a test that then checks for the
/// absence of something passes without having done anything.
void useSurface(WidgetTester tester, Size size) {
  WidgetController.hitTestWarningShouldBeFatal = true;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Loads Roboto and the Material icons, so goldens show words and icons
/// rather than the test font's solid blocks. A frame nobody can read is a
/// frame nobody can judge.
///
/// The fonts ship in the Flutter SDK's cache. If they are missing the test
/// font is used and the goldens will not match -- loudly, not silently.
Future<void> loadGameTestFonts() async {
  Directory? fonts;
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8 && fonts == null; i++) {
    for (final candidate in [
      Directory('${dir.path}/material_fonts'),
      Directory('${dir.path}/artifacts/material_fonts'),
    ]) {
      if (candidate.existsSync()) fonts = candidate;
    }
    dir = dir.parent;
  }
  if (fonts == null) return;

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    var any = false;
    for (final name in files) {
      final file = File('${fonts!.path}/$name');
      if (!file.existsSync()) continue;
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
      any = true;
    }
    if (any) await loader.load();
  }

  await load('Roboto', const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]);
  await load('MaterialIcons', const ['MaterialIcons-Regular.otf']);
}

Future<SharedPreferences> testPrefs([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

/// Hosts a shell widget with the three things it reads from the app: local
/// preferences, sound and haptics.
Widget gameHost(
  Widget child, {
  required SharedPreferences prefs,
  SoundService? sound,
  Haptics? haptics,
  bool reduceMotion = false,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      soundServiceProvider.overrideWithValue(sound ?? FakeSoundService()),
      hapticsProvider.overrideWithValue(haptics ?? FakeHaptics()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Roboto'),
      builder:
          (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduceMotion,
              textScaler: TextScaler.linear(textScale),
            ),
            child: app!,
          ),
      home: child,
    ),
  );
}

/// Records what a painter asks a canvas to do.
///
/// It counts the calls a test cares about and NAMES every other call, so a
/// painter that reached for something costlier -- a saveLayer, a clip --
/// cannot satisfy a draw-count check unnoticed.
class RecordingCanvas implements Canvas {
  final List<({Offset from, Offset to, Paint paint})> lines = [];
  final List<String> unmodelled = [];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((from: p1, to: p2, paint: paint));

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unmodelled.add(invocation.memberName.toString());
    return null;
  }
}

/// WCAG contrast between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
```

`test/features/games/platform/game_theme_test.dart`

```dart
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  test('the backdrop runs from the colour down to the ground', () {
    const theme = GameTheme(primary: GameColors.wordHunt);
    final gradient = theme.backdrop;

    expect(gradient.colors.first, theme.primary);
    expect(gradient.colors.last, GameTheme.ground);
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
  });

  test('the ground is reached by a little past halfway', () {
    // Body text and lists live on the lower half. If the colour ran
    // further down, they would be sitting on it.
    const theme = GameTheme(primary: GameColors.thisOrThat);

    expect(theme.backdrop.stops!.last, lessThanOrEqualTo(0.6));
    expect(theme.backdrop.stops!.last, greaterThan(0.4));
  });

  test('the five launch colours are five different colours', () {
    expect(GameColors.all, hasLength(5));
    expect(GameColors.all.toSet(), hasLength(5));
  });

  test('white titles stay readable on every game colour', () {
    // 3:1 is the bar for large bold text, which is all that sits on the
    // colour. A retune that drops below it makes a header unreadable.
    for (final colour in GameColors.all) {
      expect(
        contrast(GameTheme.onGround, colour),
        greaterThanOrEqualTo(3.0),
        reason: 'white on $colour',
      );
    }
  });

  test('body text is comfortably readable on the ground', () {
    expect(
      contrast(GameTheme.mutedOnGround, GameTheme.ground),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(GameTheme.mutedOnGround, GameTheme.raised),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(GameTheme.tileInk, GameTheme.tile),
      greaterThanOrEqualTo(7.0),
    );
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_theme_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/game_theme.dart`

```dart
import 'package:flutter/material.dart';

/// One game's colour, and everything drawn from it.
///
/// The games area is full colour: each game owns one colour, which fills the
/// top of its screens and fades to a near-black ground by about the vertical
/// midpoint. Titles sit on the colour; body text and lists sit on the ground,
/// where contrast is easy.
///
/// The surface is the same whatever the app theme is doing, so nothing here
/// reads the ambient brightness.
@immutable
class GameTheme {
  const GameTheme({required this.primary});

  /// The game's colour.
  final Color primary;

  /// What every game screen fades down to.
  static const Color ground = Color(0xFF0B0B0B);

  /// Cards and rows that sit on the ground.
  static const Color raised = Color(0xFF1E1E20);

  /// A hairline between rows on the ground.
  static const Color hairline = Color(0xFF2A2A2E);

  /// A tile's face, and the ink on it.
  static const Color tile = Color(0xFFFFFFFF);
  static const Color tileInk = Color(0xFF111111);

  /// A tile's hard shadow. Flat, never blurred.
  static const Color tileShadow = Color(0xFF050505);

  static const Color onGround = Color(0xFFFFFFFF);
  static const Color mutedOnGround = Color(0xFFB9B9C2);

  /// The colour on its way down to the ground.
  Color get deep => Color.lerp(primary, ground, 0.6)!;

  /// Colour at the top, ground by a little past halfway.
  LinearGradient get backdrop => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primary, deep, ground],
    stops: const [0.0, 0.34, 0.56],
  );
}

/// The launch games' colours.
///
/// Each keeps white text at 3:1 or better against it, which is the bar for
/// the large bold titles that sit on the colour. A test holds that line, so a
/// retune cannot quietly make a header unreadable.
abstract final class GameColors {
  static const Color thisOrThat = Color(0xFFE0701A);
  static const Color truthOrDare = Color(0xFFE5484D);
  static const Color thirtySixQuestions = Color(0xFFA56FD6);
  static const Color wordHunt = Color(0xFF1FA463);
  static const Color snakesAndLadders = Color(0xFF4C7CF0);

  static const List<Color> all = [
    thisOrThat,
    truthOrDare,
    thirtySixQuestions,
    wordHunt,
    snakesAndLadders,
  ];
}
```

`lib/features/games/platform/feel/game_motion.dart`

```dart
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/widgets.dart';

/// Every duration and curve the games move with.
///
/// Named here so no screen carries a raw number: ten games each choosing
/// their own "about 200ms" is how a set of games stops feeling like one set.
abstract final class GameMotion {
  /// A tile going down under a finger. Short enough to feel like contact.
  static const Duration press = Duration(milliseconds: 90);

  /// Something arriving at rest: a tile landing, a tab changing.
  static const Duration settle = Duration(milliseconds: 240);

  /// A screen's pieces coming in.
  static const Duration enter = Duration(milliseconds: 320);

  /// The spark burst on a placement or a match.
  static const Duration burst = Duration(milliseconds: 420);

  /// The gap between one piece starting and the next, in a staggered entry.
  static const Duration stagger = Duration(milliseconds: 45);

  /// Overshoots a little, then comes back: the spring in a landing tile.
  static const Curve settleCurve = Curves.easeOutBack;

  static const Curve enterCurve = Curves.easeOutCubic;

  /// [duration], or nothing at all when the OS asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduceMotionOf(context) ? Duration.zero : duration;
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_theme_test.dart`

Expected: `All tests passed!` — 5 tests (game_theme_test.dart 5). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/game_theme.dart lib/features/games/platform/feel/game_motion.dart test/features/games/platform/support/game_test_support.dart test/features/games/platform/game_theme_test.dart
git commit -m "feat(games): platform colours, motion tokens and test support (platform phase 1, task 1)"
```


---

### Task 2: GameTile

The white tile with a hard offset shadow that presses down. Letters, options,
board cells and hero art are all made of it.

**Files:**

- Create: `lib/features/games/platform/feel/game_tile.dart`
- Create: `test/features/games/platform/game_tile_test.dart`

**What to know before writing it:**

- The press moves the face with `AnimatedContainer.transform`. That moves what is drawn inside the container, not the container's own box, so the tests measure a keyed child of the face. Measuring the face itself passes whether or not anything moves.
- The tap is announced by the outer `Semantics` (`container: true`, `onTap`), and the `GestureDetector` is excluded from semantics. This keeps a tile one node for a screen reader whether or not it has a label. Task 7 tests it.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/game_tile_test.dart`

```dart
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A tap that lands on nothing fails, rather than only printing a warning.
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);

  const face = ValueKey('game-tile-face');

  // What sits ON the face. A press is measured here, not on the face's own
  // box: the face moves its contents with a transform, so its box stays
  // put and would report "no movement" whether the tile pressed or not.
  const content = ValueKey('content');
  const piece = SizedBox.square(key: content, dimension: 60);

  Widget host(Widget tile, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: tile)),
    ),
  );

  testWidgets('a press moves the face down onto its shadow', (tester) async {
    // The whole point of the tile: a tap reads as pushing a real key.
    await tester.pumpWidget(
      host(GameTile(depth: 10, onTap: () {}, child: piece)),
    );

    final rest = tester.getTopLeft(find.byKey(content));
    final sizeAtRest = tester.getSize(find.byType(GameTile));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(content)),
    );
    await tester.pump();
    await tester.pump(GameMotion.press);

    final pressed = tester.getTopLeft(find.byKey(content));
    expect(pressed.dy - rest.dy, closeTo(10, 0.01));
    expect(pressed.dx - rest.dx, closeTo(10 * GameTile.lean, 0.01));

    // The tile's own box must not change, or everything beside it would
    // jump each time it is pressed.
    expect(tester.getSize(find.byType(GameTile)), sizeAtRest);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(content)), rest);
  });

  testWidgets('a tap is reported', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        GameTile(
          onTap: () => taps++,
          child: const SizedBox.square(dimension: 60),
        ),
      ),
    );

    await tester.tap(find.byType(GameTile));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('a still tile does not press and is not a button', (
    tester,
  ) async {
    // Hero art and board cells that cannot be chosen are tiles too. They
    // must not answer a finger or be announced as something to press.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const GameTile(child: piece)));

    final rest = tester.getTopLeft(find.byKey(content));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(content)),
    );
    await tester.pump();
    await tester.pump(GameMotion.press);

    // The control is the test above, where the same measurement moves.
    expect(tester.getTopLeft(find.byKey(content)), rest);
    expect(
      tester
          .getSemantics(find.byType(GameTile))
          .hasFlag(SemanticsFlag.isButton),
      isFalse,
    );

    await gesture.up();
    handle.dispose();
  });

  testWidgets('a pressable tile is announced as a button, with its state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        GameTile(
          onTap: () {},
          semanticLabel: 'Night in',
          selected: true,
          child: const Text('🛋️'),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(GameTile));
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(node.label, 'Night in');

    handle.dispose();
  });

  testWidgets('reduce motion makes the press immediate', (tester) async {
    Duration durationOf() =>
        tester.widget<AnimatedContainer>(find.byKey(face)).duration;

    await tester.pumpWidget(
      host(GameTile(onTap: () {}, child: const SizedBox.square(dimension: 60))),
    );
    // The control: it does animate when motion is allowed.
    expect(durationOf(), GameMotion.press);

    await tester.pumpWidget(
      host(
        GameTile(onTap: () {}, child: const SizedBox.square(dimension: 60)),
        reduceMotion: true,
      ),
    );
    expect(durationOf(), Duration.zero);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_tile_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/feel/game_tile.dart`

```dart
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';

/// The white tile every game is built from.
///
/// A flat face over a hard offset shadow. Pressed, the face moves down onto
/// its shadow, so a tap reads as pushing a real key. Letters, options, board
/// cells and hero art are all this one widget.
///
/// There is no blur anywhere in it: two flat rounded rectangles are about the
/// cheapest thing a phone can draw, which matters on low-end hardware.
class GameTile extends StatefulWidget {
  const GameTile({
    super.key,
    required this.child,
    this.onTap,
    this.color = GameTheme.tile,
    this.shadowColor = GameTheme.tileShadow,
    this.radius = 12,
    this.depth = 5,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
    this.selected,
  });

  final Widget child;

  /// Null makes the tile a still piece: it does not press and is not
  /// announced as a button.
  final VoidCallback? onTap;

  final Color color;
  final Color shadowColor;
  final double radius;

  /// How far the shadow sits below the face, and how far a press travels.
  final double depth;

  final EdgeInsetsGeometry padding;

  /// Replaces the child's own text for a screen reader when set.
  final String? semanticLabel;

  /// Announced to a screen reader when this tile is a choice.
  final bool? selected;

  /// The shadow sits this share of [depth] to the right of the face.
  static const double lean = 0.6;

  @override
  State<GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<GameTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final dx = widget.depth * GameTile.lean;
    final dy = widget.depth;
    final radius = BorderRadius.circular(widget.radius);

    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      selected: widget.selected,
      container: true,
      excludeSemantics: widget.semanticLabel != null,
      // The tap is announced here, not by the detector below, so a tile
      // is one thing to a screen reader whether or not it has a label.
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        // The padding reserves the room the shadow needs, so a tile's
        // layout size never changes when it is pressed.
        child: Padding(
          padding: EdgeInsets.only(right: dx, bottom: dy),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(dx, dy),
                  child: DecoratedBox(
                    key: const ValueKey('game-tile-shadow'),
                    decoration: BoxDecoration(
                      color: widget.shadowColor,
                      borderRadius: radius,
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                key: const ValueKey('game-tile-face'),
                duration: GameMotion.of(context, GameMotion.press),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(
                  _pressed ? dx : 0,
                  _pressed ? dy : 0,
                  0,
                ),
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: radius,
                ),
                child: IconTheme.merge(
                  data: const IconThemeData(color: GameTheme.tileInk),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      color: GameTheme.tileInk,
                      fontWeight: FontWeight.w800,
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_tile_test.dart`

Expected: `All tests passed!` — 5 tests (game_tile_test.dart 5). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/feel/game_tile.dart test/features/games/platform/game_tile_test.dart
git commit -m "feat(games): GameTile (platform phase 1, task 2)"
```


---

### Task 3: Sound and vibration: preferences and GameFeedback

Games name an event (`tap`, `place`, `match`, `reveal`, `turn`, `complete`);
this decides the sound and the haptic, and stays silent when the player has
switched either off.

**Files:**

- Create: `lib/features/games/platform/game_prefs.dart`
- Create: `lib/features/games/platform/feel/game_feedback.dart`
- Create: `test/features/games/platform/game_prefs_test.dart`
- Create: `test/features/games/platform/game_feedback_test.dart`

**What to know before writing it:**

- `GameFeedback` obeys the two switches only. Reduce-motion governs what moves, not sound or vibration.
- The sounds are the existing synthesized `AppSound` clips. No new audio files in this phase.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/game_prefs_test.dart`

```dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  Future<ProviderContainer> container([
    Map<String, Object> stored = const {},
  ]) async {
    final prefs = await testPrefs(stored);
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('sound and vibration are on until someone turns them off', () async {
    final c = await container();

    expect(c.read(gamePrefsProvider), const GamePrefs());
    expect(c.read(gamePrefsProvider).sound, isTrue);
    expect(c.read(gamePrefsProvider).haptics, isTrue);
  });

  test('a stored choice is read back', () async {
    final c = await container({
      GamePrefsNotifier.soundKey: false,
      GamePrefsNotifier.hapticsKey: true,
    });

    expect(c.read(gamePrefsProvider).sound, isFalse);
    expect(c.read(gamePrefsProvider).haptics, isTrue);
  });

  test('turning sound off is kept, and leaves vibration alone', () async {
    final c = await container();

    c.read(gamePrefsProvider.notifier).setSound(false);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(gamePrefsProvider).sound, isFalse);
    expect(c.read(gamePrefsProvider).haptics, isTrue);
    expect(
      c.read(sharedPreferencesProvider).getBool(GamePrefsNotifier.soundKey),
      isFalse,
    );
  });

  test('turning vibration off is kept, and leaves sound alone', () async {
    final c = await container();

    c.read(gamePrefsProvider.notifier).setHaptics(false);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(gamePrefsProvider).haptics, isFalse);
    expect(c.read(gamePrefsProvider).sound, isTrue);
    expect(
      c.read(sharedPreferencesProvider).getBool(GamePrefsNotifier.hapticsKey),
      isFalse,
    );
  });
}
```

`test/features/games/platform/game_feedback_test.dart`

```dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/feel/game_feedback.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  late FakeSoundService sound;
  late FakeHaptics haptics;

  Future<ProviderContainer> container([
    Map<String, Object> stored = const {},
  ]) async {
    sound = FakeSoundService();
    haptics = FakeHaptics();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(await testPrefs(stored)),
        soundServiceProvider.overrideWithValue(sound),
        hapticsProvider.overrideWithValue(haptics),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  int hapticTotal() =>
      haptics.lightCount + haptics.selectionCount + haptics.mediumCount;

  test('every event has a sound', () {
    // A new event added without a clip would otherwise fail at the moment
    // a player triggers it, not here.
    for (final event in GameEvent.values) {
      expect(
        GameFeedback.sounds.containsKey(event),
        isTrue,
        reason: '$event has no sound',
      );
    }
  });

  test('every event plays its sound and one tap you can feel', () async {
    final c = await container();
    final feedback = c.read(gameFeedbackProvider);

    for (final event in GameEvent.values) {
      feedback.fire(event);
    }

    expect(sound.played, [
      for (final event in GameEvent.values) GameFeedback.sounds[event],
    ]);
    expect(hapticTotal(), GameEvent.values.length);
  });

  test('bigger moments tap harder', () async {
    final c = await container();
    final feedback = c.read(gameFeedbackProvider);

    feedback.fire(GameEvent.tap);
    expect(haptics.selectionCount, 1);

    feedback.fire(GameEvent.place);
    expect(haptics.lightCount, 1);

    feedback.fire(GameEvent.complete);
    expect(haptics.mediumCount, 1);
  });

  test('sound off silences the clips but keeps the vibration', () async {
    final c = await container({GamePrefsNotifier.soundKey: false});

    c.read(gameFeedbackProvider).fire(GameEvent.match);

    expect(sound.played, isEmpty);
    expect(hapticTotal(), 1);
  });

  test('vibration off keeps the sound', () async {
    final c = await container({GamePrefsNotifier.hapticsKey: false});

    c.read(gameFeedbackProvider).fire(GameEvent.match);

    expect(sound.played, [AppSound.gameMatch]);
    expect(hapticTotal(), 0);
  });

  test('a change in settings applies to the very next event', () async {
    final c = await container();
    final feedback = c.read(gameFeedbackProvider);

    feedback.fire(GameEvent.tap);
    c.read(gamePrefsProvider.notifier).setSound(false);
    feedback.fire(GameEvent.tap);

    expect(sound.played, hasLength(1));
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_prefs_test.dart test/features/games/platform/game_feedback_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/game_prefs.dart`

```dart
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a player has switched on in the games' settings sheet.
@immutable
class GamePrefs {
  const GamePrefs({this.sound = true, this.haptics = true});

  final bool sound;
  final bool haptics;

  @override
  bool operator ==(Object other) =>
      other is GamePrefs && other.sound == sound && other.haptics == haptics;

  @override
  int get hashCode => Object.hash(sound, haptics);
}

/// Per device, not per account: whether a phone should make noise is about
/// the phone and where it is, not about the person.
class GamePrefsNotifier extends Notifier<GamePrefs> {
  static const String soundKey = 'games.sound_effects';
  static const String hapticsKey = 'games.haptics';

  @override
  GamePrefs build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return GamePrefs(
      sound: prefs.getBool(soundKey) ?? true,
      haptics: prefs.getBool(hapticsKey) ?? true,
    );
  }

  void setSound(bool value) {
    state = GamePrefs(sound: value, haptics: state.haptics);
    unawaited(ref.read(sharedPreferencesProvider).setBool(soundKey, value));
  }

  void setHaptics(bool value) {
    state = GamePrefs(sound: state.sound, haptics: value);
    unawaited(ref.read(sharedPreferencesProvider).setBool(hapticsKey, value));
  }
}

final gamePrefsProvider = NotifierProvider<GamePrefsNotifier, GamePrefs>(
  GamePrefsNotifier.new,
);
```

`lib/features/games/platform/feel/game_feedback.dart`

```dart
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Something that just happened in a game.
///
/// Games name the event and nothing else. Which clip plays and how the phone
/// taps back is decided here, once, so every game answers a tap the same way
/// and a new sound pack is a change to this file rather than to ten games.
enum GameEvent {
  /// A finger chose something.
  tap,

  /// A piece or an answer went down.
  place,

  /// Two things agreed: a match, a found word.
  match,

  /// Something hidden was shown.
  reveal,

  /// The move passed to the other player.
  turn,

  /// The game finished.
  complete,
}

class GameFeedback {
  GameFeedback(this._ref);

  final Ref _ref;

  /// The clip for each event. Every event has one.
  static const Map<GameEvent, AppSound> sounds = {
    GameEvent.tap: AppSound.gameTap,
    GameEvent.place: AppSound.gameAnswer,
    GameEvent.match: AppSound.gameMatch,
    GameEvent.reveal: AppSound.gameReveal,
    GameEvent.turn: AppSound.gameAnswer,
    GameEvent.complete: AppSound.gameComplete,
  };

  void fire(GameEvent event) {
    final prefs = _ref.read(gamePrefsProvider);

    if (prefs.sound) {
      _ref.read(soundServiceProvider).play(sounds[event]!);
    }
    if (!prefs.haptics) return;

    final haptics = _ref.read(hapticsProvider);
    switch (event) {
      case GameEvent.tap:
        haptics.selection();
      case GameEvent.place:
      case GameEvent.reveal:
      case GameEvent.turn:
        haptics.light();
      case GameEvent.match:
      case GameEvent.complete:
        haptics.medium();
    }
  }
}

final gameFeedbackProvider = Provider<GameFeedback>(GameFeedback.new);
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_prefs_test.dart test/features/games/platform/game_feedback_test.dart`

Expected: `All tests passed!` — 10 tests (game_prefs_test.dart 4, game_feedback_test.dart 6). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/game_prefs.dart lib/features/games/platform/feel/game_feedback.dart test/features/games/platform/game_prefs_test.dart test/features/games/platform/game_feedback_test.dart
git commit -m "feat(games): game sound and vibration preferences, GameFeedback (platform phase 1, task 3)"
```


---

### Task 4: GameBurst

The short spark of lines when something is placed or matched. It plays once
when its `count` rises and never under reduce-motion.

**Files:**

- Create: `lib/features/games/platform/feel/game_burst.dart`
- Create: `test/features/games/platform/game_burst_test.dart`

**What to know before writing it:**

- Lines only: no blur, no `saveLayer`, no `MaskFilter`. The test's recording canvas records any call it does not model, so adding one fails the test.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/game_burst_test.dart`

```dart
import 'package:attune/features/games/platform/feel/game_burst.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  group('one ray', () {
    test('is invisible at the start and gone by the end', () {
      expect(burstRay(0, 40).alpha, 0);
      expect(burstRay(1, 40).alpha, 0);
      expect(burstRay(0.2, 40).alpha, greaterThan(0.8));
    });

    test('travels outward and never turns inside out', () {
      var lastOuter = -1.0;
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final ray = burstRay(t, 40);
        expect(ray.outer, greaterThanOrEqualTo(lastOuter), reason: 'at $t');
        expect(ray.outer, greaterThan(ray.inner), reason: 'at $t');
        expect(ray.outer, lessThanOrEqualTo(40.0001), reason: 'at $t');
        lastOuter = ray.outer;
      }
      expect(lastOuter, greaterThan(30), reason: 'it does reach the edge');
    });

    test('odd progress values stay in bounds', () {
      for (final t in [-1.0, 1.5, 100.0, double.nan]) {
        final ray = burstRay(t, 40);
        expect(ray.inner.isFinite && ray.outer.isFinite, isTrue);
        expect(ray.alpha, inInclusiveRange(0.0, 1.0), reason: 'at $t');
      }
    });
  });

  group('the painter', () {
    RecordingCanvas paint(double progress, {int rays = 9}) {
      final canvas = RecordingCanvas();
      GameBurstPainter(
        progress: progress,
        color: const Color(0xFFFFFFFF),
        rays: rays,
      ).paint(canvas, const Size(80, 80));
      return canvas;
    }

    test('draws one line per ray, mid-burst', () {
      expect(paint(0.3).lines, hasLength(9));
      expect(paint(0.3, rays: 5).lines, hasLength(5));
    });

    test('draws nothing before it starts or after it ends', () {
      // The control is the test above: this painter does draw.
      expect(paint(0).lines, isEmpty);
      expect(paint(1).lines, isEmpty);
    });

    test('uses nothing costlier than lines', () {
      final canvas = paint(0.3);

      expect(canvas.lines, isNotEmpty);
      expect(canvas.unmodelled, isEmpty, reason: '${canvas.unmodelled}');
    });
  });

  group('the widget', () {
    Widget host(int count, {bool reduceMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(
          child: GameBurst(count: count, color: const Color(0xFFFFFFFF)),
        ),
      ),
    );

    double progress(WidgetTester tester) =>
        (tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(GameBurst),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as GameBurstPainter)
            .progress;

    testWidgets('plays once when the count goes up, then stops', (
      tester,
    ) async {
      await tester.pumpWidget(host(0));
      expect(progress(tester), 0);

      await tester.pumpWidget(host(1));
      await tester.pump(GameMotion.burst ~/ 2);
      expect(progress(tester), inExclusiveRange(0.0, 1.0));

      await tester.pumpAndSettle();
      expect(progress(tester), 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('does not play when the count is unchanged', (tester) async {
      await tester.pumpWidget(host(3));
      await tester.pumpWidget(host(3));
      await tester.pump(GameMotion.burst ~/ 2);

      expect(progress(tester), 0);
    });

    testWidgets('does not play at all under reduce motion', (tester) async {
      await tester.pumpWidget(host(0, reduceMotion: true));
      await tester.pumpWidget(host(1, reduceMotion: true));
      await tester.pump();

      expect(progress(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_burst_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/feel/game_burst.dart`

```dart
import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:flutter/material.dart';

/// Where one ray of a burst is, [progress] of the way through.
///
/// Pure, so the shape of the burst is checked without a canvas. A ray starts
/// short and close in, shoots outward, and its tail catches up as it fades:
/// it is brightest early and gone by the end.
({double inner, double outer, double alpha}) burstRay(
  double progress,
  double radius,
) {
  // A NaN compares false with everything, so it is caught rather than
  // clamped, and read as "finished".
  final t = progress.isNaN ? 1.0 : progress.clamp(0.0, 1.0);
  final eased = 1 - math.pow(1 - t, 3).toDouble();

  final outer = radius * (0.35 + 0.65 * eased);
  final inner = radius * (0.2 + 0.7 * eased * eased);
  final alpha = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;

  return (inner: inner, outer: outer, alpha: alpha.clamp(0.0, 1.0));
}

/// Draws the rays. Public fields, so a test reads them directly.
class GameBurstPainter extends CustomPainter {
  GameBurstPainter({
    required this.progress,
    required this.color,
    this.rays = 9,
    this.strokeWidth = 2.5,
  });

  final double progress;
  final Color color;
  final int rays;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || rays <= 0) return;

    final ray = burstRay(progress, size.shortestSide / 2);
    if (ray.alpha <= 0.01) return;

    final paint =
        Paint()
          ..color = color.withValues(alpha: ray.alpha)
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
    final centre = size.center(Offset.zero);

    for (var i = 0; i < rays; i++) {
      final angle = 2 * math.pi * i / rays - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        centre + direction * ray.inner,
        centre + direction * ray.outer,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(GameBurstPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.rays != rays ||
      old.strokeWidth != strokeWidth;
}

/// A short spark burst that plays once each time [count] goes up.
///
/// It is an event, not a state: it runs, stops, and schedules nothing more.
/// Under the OS reduce-motion setting it does not run at all.
class GameBurst extends StatefulWidget {
  const GameBurst({
    super.key,
    required this.count,
    required this.color,
    this.size = 72,
    this.rays = 9,
  });

  /// Raise this to play the burst.
  final int count;

  final Color color;
  final double size;
  final int rays;

  @override
  State<GameBurst> createState() => _GameBurstState();
}

class _GameBurstState extends State<GameBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: GameMotion.burst,
  );

  @override
  void didUpdateWidget(GameBurst old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count && !reduceMotionOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder:
              (context, _) => CustomPaint(
                painter: GameBurstPainter(
                  progress: _controller.value,
                  color: widget.color,
                  rays: widget.rays,
                ),
              ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_burst_test.dart`

Expected: `All tests passed!` — 9 tests (game_burst_test.dart 9). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/feel/game_burst.dart test/features/games/platform/game_burst_test.dart
git commit -m "feat(games): GameBurst (platform phase 1, task 4)"
```


---

### Task 5: GameLetterTiles

A word spelled in tiles, one letter each, arriving in a stagger. Used for hero
art and the completion screen.

**Files:**

- Create: `lib/features/games/platform/feel/game_letter_tiles.dart`
- Create: `test/features/games/platform/game_letter_tiles_test.dart`

**What to know before writing it:**

- A tile pops in by scale alone, from nothing, with the overshoot curve. There is no fade: fading a tile and its shadow together composites them off-screen first.
- The test reads each tile's x scale from its keyed `Transform`. `getMaxScaleOnAxis` is no use here: a 2D scale leaves z at 1, so it reads 1 for every tile.
- The letters use `TextScaler.noScaling`. They are sized to their tiles, which do not grow with the reader's text size; scaling one and not the other pushes the glyph out of the tile. The whole word is still read out through the `Semantics` label.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/game_letter_tiles_test.dart`

```dart
import 'package:attune/features/games/platform/feel/game_letter_tiles.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {bool reduceMotion = false, double? width}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(child: SizedBox(width: width, child: child)),
          ),
        ),
      );

  /// How large each tile is being drawn: 0 before it arrives, 1 once it
  /// has landed, briefly past 1 on the way.
  ///
  /// By key, because a tile has transforms of its own inside it and those
  /// always read 1.
  Iterable<double> scales(WidgetTester tester) => tester
      .widgetList<Transform>(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return widget is Transform &&
              key is ValueKey<String> &&
              key.value.startsWith('game-letter-tile-');
        }),
      )
      // The x scale. Not getMaxScaleOnAxis: a 2D scale leaves z at 1, so
      // the maximum reads 1 for every tile that is not yet full size.
      .map((t) => t.transform.storage[0]);

  testWidgets('one tile per letter, in capitals', (tester) async {
    await tester.pumpWidget(host(const GameLetterTiles(word: 'done')));
    await tester.pumpAndSettle();

    expect(find.byType(GameTile), findsNWidgets(4));
    for (final letter in ['D', 'O', 'N', 'E']) {
      expect(find.text(letter), findsOneWidget);
    }
  });

  testWidgets('a space is a gap, not a tile', (tester) async {
    await tester.pumpWidget(host(const GameLetterTiles(word: 'ALL DONE')));
    await tester.pumpAndSettle();

    expect(find.byType(GameTile), findsNWidgets(7));
  });

  testWidgets('a screen reader hears the word, not seven letters', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const GameLetterTiles(word: 'COMPLETE')));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('COMPLETE'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the tiles land one after another and end at full size', (
    tester,
  ) async {
    await tester.pumpWidget(host(const GameLetterTiles(word: 'PLAY')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Mid-entry the first letter is ahead of the last.
    final mid = scales(tester).toList();
    expect(mid, hasLength(4));
    expect(mid.first, greaterThan(mid.last));

    await tester.pumpAndSettle();
    final end = scales(tester).toList();
    expect(end, hasLength(4));
    expect(end, everyElement(closeTo(1.0, 1e-9)));
  });

  testWidgets('reduce motion shows the word at once', (tester) async {
    await tester.pumpWidget(
      host(const GameLetterTiles(word: 'PLAY'), reduceMotion: true),
    );
    await tester.pump();

    final shown = scales(tester).toList();
    expect(shown, hasLength(4));
    expect(shown, everyElement(closeTo(1.0, 1e-9)));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('art that should not move does not', (tester) async {
    await tester.pumpWidget(
      host(const GameLetterTiles(word: 'PLAY', animate: false)),
    );
    await tester.pump();

    expect(scales(tester), everyElement(closeTo(1.0, 1e-9)));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a long word shrinks to fit instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const GameLetterTiles(word: 'CONGRATULATIONS', animate: false),
        width: 200,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(GameLetterTiles)).width,
      lessThanOrEqualTo(200),
    );
    expect(find.byType(GameTile), findsNWidgets(15));
  });

  testWidgets('a larger text size does not push a letter out of its tile', (
    tester,
  ) async {
    Future<Size> letterAt(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: Center(
                child: GameLetterTiles(word: 'PLAY', animate: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.text('P'));
    }

    final normal = await letterAt(1);
    final largest = await letterAt(2);

    expect(normal.height, greaterThan(0));
    expect(largest, normal);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_letter_tiles_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/feel/game_letter_tiles.dart`

```dart
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:flutter/material.dart';

/// A word spelled in tiles, one letter each.
///
/// Used for a game's hero art and for the word on the completion screen. The
/// tiles land one after another; under reduce motion they are simply there.
/// A word too long for its space shrinks to fit rather than overflowing.
class GameLetterTiles extends StatefulWidget {
  const GameLetterTiles({
    super.key,
    required this.word,
    this.tileSize = 40,
    this.animate = true,
  });

  final String word;
  final double tileSize;

  /// False draws the word at rest, for art that should not move.
  final bool animate;

  @override
  State<GameLetterTiles> createState() => _GameLetterTilesState();
}

class _GameLetterTilesState extends State<GameLetterTiles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration(widget.word.length),
  );
  bool _started = false;

  static Duration _duration(int letters) =>
      GameMotion.enter + GameMotion.stagger * (letters > 1 ? letters - 1 : 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate || reduceMotionOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letters = widget.word.characters.toList();
    final total = _controller.duration!.inMicroseconds;

    return Semantics(
      label: widget.word,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < letters.length; i++)
                  if (letters[i].trim().isEmpty)
                    SizedBox(width: widget.tileSize * 0.5)
                  else
                    _letter(letters[i], i, total),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _letter(String letter, int index, int total) {
    final start = (GameMotion.stagger.inMicroseconds * index) / total;
    final end = (start + GameMotion.enter.inMicroseconds / total).clamp(
      0.0,
      1.0,
    );
    final t = Interval(
      start.clamp(0.0, 1.0),
      end,
      curve: GameMotion.settleCurve,
    ).transform(_controller.value);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.tileSize * 0.04),
      // A tile pops in from nothing: scale only, no fade. Fading a tile
      // and its shadow together means compositing them off-screen first,
      // and the overshoot in the curve gives the landing its life anyway.
      child: Transform.scale(
        key: ValueKey('game-letter-tile-$index'),
        scale: t < 0 ? 0 : t,
        child: GameTile(
          radius: widget.tileSize * 0.22,
          depth: widget.tileSize * 0.1,
          child: SizedBox.square(
            dimension: widget.tileSize,
            child: Center(
              child: Text(
                letter.toUpperCase(),
                // The letter is sized to its tile, which does not grow
                // with the reader's text size. Scaling one and not the
                // other pushes the glyph out of the tile. The word is
                // still read out in full, by the label above.
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: widget.tileSize * 0.56,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_letter_tiles_test.dart`

Expected: `All tests passed!` — 8 tests (game_letter_tiles_test.dart 8). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/feel/game_letter_tiles.dart test/features/games/platform/game_letter_tiles_test.dart
git commit -m "feat(games): GameLetterTiles (platform phase 1, task 5)"
```


---

### Task 6: Strings, GameDefinition and the registry

One `GameDefinition` per game replaces the five parallel lists the games
feature keeps today. Phase 1 registers no real game; the tests use a demo
definition.

**Files:**

- Create: `lib/features/games/platform/game_strings.dart`
- Create: `lib/features/games/platform/game_definition.dart`
- Create: `lib/features/games/platform/game_registry.dart`
- Create: `test/features/games/platform/support/demo_game.dart`
- Create: `test/features/games/platform/game_registry_test.dart`

**What to know before writing it:**

- New shell text is English-only for now and lives in `game_strings.dart` (spec §1.2). Do not add it to the `.arb` files: those are being edited on `main`.
- A duplicate `gameType` throws at construction, so two games can never answer to the same route.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/support/demo_game.dart`

```dart
import 'package:attune/features/games/platform/feel/game_letter_tiles.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';

/// A made-up game, for exercising the shell without a real one.
GameDefinition demoGame({
  bool withSettings = false,
  bool withEntries = true,
  GameAvailability availability = GameAvailability.launch,
  String gameType = 'demo',
  Color color = GameColors.wordHunt,
}) {
  return GameDefinition(
    gameType: gameType,
    title: 'Tile Tutorial',
    collectionLabel: 'Starter pack',
    tagline: 'Learn how the shell fits together.',
    theme: GameTheme(primary: color),
    heroBuilder:
        (context, theme) =>
            const GameLetterTiles(word: 'PLAY', tileSize: 52, animate: false),
    entriesBuilder:
        withEntries
            ? (context) => const [
              GameEntry(title: 'Learn the basics'),
              GameEntry(title: 'Themes', subtitle: 'Pick a mood'),
              GameEntry(title: 'Past games'),
            ]
            : null,
    howToPlay: const [
      'Tap a tile to pick it.',
      'Your partner answers the same question.',
      'See both answers together.',
    ],
    settingsBuilder:
        withSettings ? (context) => const Text('Demo game settings') : null,
    availability: availability,
  );
}
```

`test/features/games/platform/game_registry_test.dart`

```dart
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';

void main() {
  test('a game is found by its database type', () {
    final registry = GameRegistry([
      demoGame(gameType: 'this_or_that'),
      demoGame(gameType: 'word_hunt'),
    ]);

    expect(registry.byType('word_hunt')?.gameType, 'word_hunt');
  });

  test('a type this build does not know is null, not a crash', () {
    // A game type can reach the database before the app is updated.
    final registry = GameRegistry([demoGame()]);

    expect(registry.byType('not_a_game'), isNull);
    expect(registry.byType(null), isNull);
  });

  test('two games cannot share a type', () {
    // The second would shadow the first and make it unreachable.
    expect(
      () => GameRegistry([
        demoGame(gameType: 'same'),
        demoGame(gameType: 'same'),
      ]),
      throwsArgumentError,
    );
  });

  test('every game is either playable or coming soon, never both', () {
    final registry = GameRegistry([
      demoGame(gameType: 'a'),
      demoGame(gameType: 'b', availability: GameAvailability.comingSoon),
      demoGame(gameType: 'c'),
    ]);

    expect(registry.launch.map((g) => g.gameType), ['a', 'c']);
    expect(registry.comingSoon.map((g) => g.gameType), ['b']);
    expect(
      registry.launch.length + registry.comingSoon.length,
      registry.all.length,
    );
  });

  test('games keep the order they were listed in', () {
    final registry = GameRegistry([
      demoGame(gameType: 'z'),
      demoGame(gameType: 'a'),
      demoGame(gameType: 'm'),
    ]);

    expect(registry.all.map((g) => g.gameType), ['z', 'a', 'm']);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_registry_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/game_strings.dart`

```dart
/// Every word the games shell shows.
///
/// In one file, and never inline, because game text is not translated yet:
/// none of the games use the app's localisation today. Keeping the shell's
/// words together makes moving them into it a mechanical pass later.
abstract final class GameStrings {
  // Landing page
  static const String play = 'Play';
  static const String join = 'Join';
  static const String yourTurn = 'Your turn';
  static const String playAgain = 'Play again';
  static const String waitingForPartner = 'Waiting for your partner';
  static String waitingFor(String name) => 'Waiting for $name';
  static const String remind = 'Send a reminder';
  static String entryNumber(int number, String title) => '$number. $title';

  // Header
  static const String back = 'Back';
  static const String settings = 'Settings';
  static const String howToPlay = 'How to play';
  static const String close = 'Close';

  // Settings sheet
  static const String general = 'General';
  static const String support = 'Support';
  static const String soundEffects = 'Sound effects';
  static const String soundEffectsHint = 'Taps, reveals and wins';
  static const String haptics = 'Vibration';
  static const String hapticsHint = 'A small tap you can feel';
  static const String reportProblem = 'Report a problem';
  static const String leaveGame = 'Leave game';

  // Tutorial
  static const String next = 'Next';
  static const String skip = 'Skip';
  static const String gotIt = 'Got it';

  // Completion
  static const String backToGames = 'Back to games';
}
```

`lib/features/games/platform/game_definition.dart`

```dart
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/widgets.dart';

/// Whether a game can be started.
enum GameAvailability {
  /// Playable.
  launch,

  /// Listed, not startable. A session already in progress stays reachable.
  comingSoon,
}

/// One row in the list under a game's Play button: a tone, a chapter, the
/// player's own questions, past games.
@immutable
class GameEntry {
  const GameEntry({required this.title, this.subtitle, this.onTap});

  final String title;
  final String? subtitle;
  final void Function(BuildContext context)? onTap;
}

typedef GameHeroBuilder =
    Widget Function(BuildContext context, GameTheme theme);
typedef GameEntriesBuilder = List<GameEntry> Function(BuildContext context);
typedef GameSettingsBuilder = Widget Function(BuildContext context);

/// Enters play: a new game when [sessionId] is null, that session otherwise.
typedef GameOpen =
    Future<void> Function(BuildContext context, {String? sessionId});

/// Everything the shell needs to know about one game.
///
/// The list of games used to be repeated in five places -- display names,
/// colours, icons, routes and the catalogue -- and a game added to one and
/// missed in another rendered as a raw database value or routed nowhere.
/// This is the one place.
@immutable
class GameDefinition {
  const GameDefinition({
    required this.gameType,
    required this.title,
    required this.collectionLabel,
    required this.tagline,
    required this.theme,
    required this.heroBuilder,
    this.entriesBuilder,
    this.howToPlay = const [],
    this.settingsBuilder,
    this.open,
    this.availability = GameAvailability.launch,
  });

  /// The `game_sessions.game_type` value.
  final String gameType;

  final String title;

  /// The small label over the title, such as "CONVERSATION GAME".
  final String collectionLabel;

  final String tagline;
  final GameTheme theme;

  /// Draws the tile art at the top of the landing page.
  final GameHeroBuilder heroBuilder;

  /// The rows under the Play button. Null means none.
  final GameEntriesBuilder? entriesBuilder;

  /// The rules, a sentence each, for the "?" button.
  final List<String> howToPlay;

  /// The game's own settings tab. Null hides the tab.
  final GameSettingsBuilder? settingsBuilder;

  /// How play is entered. Wraps the game's existing routes.
  final GameOpen? open;

  final GameAvailability availability;
}
```

`lib/features/games/platform/game_registry.dart`

```dart
import 'package:attune/features/games/platform/game_definition.dart';

/// The games Attune knows about.
class GameRegistry {
  /// Throws if two definitions share a game type: a second one would
  /// silently shadow the first and its game would become unreachable.
  GameRegistry(List<GameDefinition> definitions)
    : all = List.unmodifiable(definitions),
      _byType = _index(definitions);

  /// Every game, in the order it should be shown.
  final List<GameDefinition> all;

  final Map<String, GameDefinition> _byType;

  static Map<String, GameDefinition> _index(List<GameDefinition> definitions) {
    final byType = <String, GameDefinition>{};
    for (final definition in definitions) {
      if (byType.containsKey(definition.gameType)) {
        throw ArgumentError(
          'Duplicate game type "${definition.gameType}" in the registry',
        );
      }
      byType[definition.gameType] = definition;
    }
    return byType;
  }

  /// The game for a `game_sessions.game_type`, or null for one this build
  /// has not been taught -- a type added to the database first must not
  /// crash the hub.
  GameDefinition? byType(String? gameType) => _byType[gameType];

  Iterable<GameDefinition> get launch =>
      all.where((game) => game.availability == GameAvailability.launch);

  Iterable<GameDefinition> get comingSoon =>
      all.where((game) => game.availability == GameAvailability.comingSoon);
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_registry_test.dart`

Expected: `All tests passed!` — 5 tests (game_registry_test.dart 5). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/game_strings.dart lib/features/games/platform/game_definition.dart lib/features/games/platform/game_registry.dart test/features/games/platform/support/demo_game.dart test/features/games/platform/game_registry_test.dart
git commit -m "feat(games): GameDefinition, registry and shell strings (platform phase 1, task 6)"
```


---

### Task 7: Backdrop, buttons and the play scaffold

The frame every game is played in: the colour fading to near-black, a header
with back and settings, the body in a capped column, and an optional row of
round actions.

**Files:**

- Create: `lib/features/games/platform/shell/game_backdrop.dart`
- Create: `lib/features/games/platform/shell/game_buttons.dart`
- Create: `lib/features/games/platform/shell/game_scaffold.dart`
- Create: `test/features/games/platform/support/ink_on_ground.dart`
- Create: `test/features/games/platform/game_buttons_test.dart`
- Create: `test/features/games/platform/game_scaffold_test.dart`

**What to know before writing it:**

- `GameBackdrop` owns the transparent `Material`, placed above the white default text style. A `Material` resets the default text style to the app theme's, so one placed lower turns every unstyled word dark on a dark ground. Do not add a `Material` anywhere below the backdrop; `InkWell`s already have one.
- Every hand-built control carries `Semantics(container: true, excludeSemantics: true, onTap: ...)`. `excludeSemantics` drops the `GestureDetector`'s tap along with everything else, so without the explicit `onTap` a screen reader can focus the button and not press it. `game_buttons_test.dart` activates each one through the semantics tree.
- The disabled primary button is dimmed through its colour's alpha, not an `Opacity` widget.
- `inkOnGround` (test support) lists every piece of text drawn straight on the ground with its contrast. Use it in later tasks for every new screen.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/support/ink_on_ground.dart`

```dart
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'game_test_support.dart';

/// What is written directly on the dark ground under [of], and how well
/// each piece can be read there.
///
/// Words on a white tile or the white Play button are left out: those are
/// meant to be dark. Everything else has to be light, and a golden is the
/// only other thing that would notice if it were not.
List<({String text, double contrast})> inkOnGround(
  WidgetTester tester, {
  required Finder of,
}) {
  final found = <({String text, double contrast})>[];
  final texts = find.descendant(of: of, matching: find.byType(RichText));
  for (final element in texts.evaluate()) {
    var onLightSurface = false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is GameTile || widget is GamePrimaryButton) {
        onLightSurface = true;
        return false;
      }
      return true;
    });
    if (onLightSurface) continue;

    final rich = element.widget as RichText;
    final text = rich.text.toPlainText();
    if (text.trim().isEmpty) continue;
    // Icons are RichText too, drawn with private-use glyphs. They sit on
    // surfaces of their own (a white disc, a tinted button), so the ground
    // is not what they are read against.
    final isIcon = text.runes.every(
      (rune) => (rune >= 0xE000 && rune <= 0xF8FF) || rune >= 0xF0000,
    );
    if (isIcon) continue;
    final color = rich.text.style?.color ?? const Color(0xFF000000);
    found.add((text: text, contrast: contrast(color, GameTheme.ground)));
  }
  return found;
}
```

`test/features/games/platform/game_buttons_test.dart`

```dart
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

/// Every control here is hand-built from a GestureDetector, so nothing
/// gives it a screen-reader tap for free. Each one is checked the same
/// way: the node a screen reader lands on can be activated, and
/// activating it does what a finger does.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(Scaffold(body: Center(child: child)), prefs: await testPrefs()),
    );
  }

  void activate(WidgetTester tester, String label) {
    final node = tester.getSemantics(find.bySemanticsLabel(label));
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
  }

  testWidgets('a round button can be activated by a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      GameRoundButton(
        icon: Icons.close_rounded,
        semanticLabel: 'Close',
        onTap: () => taps++,
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Close')),
      matchesSemantics(
        label: 'Close',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    activate(tester, 'Close');
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('the primary button can be activated by a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(tester, GamePrimaryButton(label: 'Play', onTap: () => taps++));

    activate(tester, 'Play');
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a disabled primary button says so and offers no tap', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const GamePrimaryButton(label: 'Waiting for Ama'));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Waiting for Ama')),
      matchesSemantics(
        label: 'Waiting for Ama',
        isButton: true,
        hasEnabledState: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('the secondary button can be activated by a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      GameSecondaryButton(label: 'Back to games', onTap: () => taps++),
    );

    activate(tester, 'Back to games');
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a labelled tile can be activated by a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(
      tester,
      GameTile(
        semanticLabel: 'Letter A',
        onTap: () => taps++,
        child: const Text('A'),
      ),
    );

    activate(tester, 'Letter A');
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('an unlabelled tile is read by its content, and still taps', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pump(tester, GameTile(onTap: () => taps++, child: const Text('A')));

    expect(
      tester.getSemantics(find.bySemanticsLabel('A')),
      matchesSemantics(label: 'A', isButton: true, hasTapAction: true),
    );
    activate(tester, 'A');
    expect(taps, 1);
    handle.dispose();
  });
}
```

`test/features/games/platform/game_scaffold_test.dart`

```dart
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';

void main() {
  const theme = GameTheme(primary: GameColors.wordHunt);

  testWidgets('shows the title over its subtitle', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        const GameScaffold(
          theme: theme,
          title: 'Learn the Basics',
          subtitle: 'Word Hunt',
          body: SizedBox(),
        ),
        prefs: await testPrefs(),
      ),
    );

    expect(find.text('Learn the Basics'), findsOneWidget);
    expect(find.text('Word Hunt'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Word Hunt')).dy,
      lessThan(tester.getTopLeft(find.text('Learn the Basics')).dy),
    );
  });

  testWidgets('the header and an unstyled body are light on the ground', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        const GameScaffold(
          theme: theme,
          title: 'Learn the Basics',
          subtitle: 'Word Hunt',
          body: Center(child: Text('a game that sets no colours')),
        ),
        prefs: await testPrefs(),
      ),
    );

    final ink = inkOnGround(tester, of: find.byType(GameScaffold));
    expect(
      ink.map((piece) => piece.text),
      contains('a game that sets no colours'),
    );
    expect(
      ink.where((piece) => piece.contrast < 4.5).map((piece) => piece.text),
      isEmpty,
    );
  });

  testWidgets('back and settings each report their own tap', (tester) async {
    useSurface(tester, phone);
    final taps = <String>[];
    await tester.pumpWidget(
      gameHost(
        GameScaffold(
          theme: theme,
          title: 'Play',
          body: const SizedBox(),
          onBack: () => taps.add('back'),
          onSettings: () => taps.add('settings'),
        ),
        prefs: await testPrefs(),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.tap(find.bySemanticsLabel('Settings'));

    expect(taps, ['back', 'settings']);
  });

  testWidgets('the gear only exists when there are settings to open', (
    tester,
  ) async {
    useSurface(tester, phone);
    final prefs = await testPrefs();

    await tester.pumpWidget(
      gameHost(
        const GameScaffold(theme: theme, title: 'Play', body: SizedBox()),
        prefs: prefs,
      ),
    );
    expect(find.bySemanticsLabel('Settings'), findsNothing);

    await tester.pumpWidget(
      gameHost(
        GameScaffold(
          theme: theme,
          title: 'Play',
          body: const SizedBox(),
          onSettings: () {},
        ),
        prefs: prefs,
      ),
    );
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  testWidgets('back leaves the screen when nothing else is asked of it', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => const GameScaffold(
                                  theme: theme,
                                  title: 'In the game',
                                  body: SizedBox(),
                                ),
                          ),
                        ),
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
        prefs: await testPrefs(),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('In the game'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('In the game'), findsNothing);
  });

  testWidgets('actions sit under the body', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        GameScaffold(
          theme: theme,
          title: 'Play',
          body: const Center(child: Text('board')),
          actions: [
            GameRoundButton(
              icon: Icons.lightbulb_outline_rounded,
              semanticLabel: 'Hint',
              caption: 'Hint',
              onTap: () {},
            ),
          ],
        ),
        prefs: await testPrefs(),
      ),
    );

    expect(find.text('Hint'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Hint')).dy,
      greaterThan(tester.getCenter(find.text('board')).dy),
    );
  });

  testWidgets('the largest text size does not break the header', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        GameScaffold(
          theme: theme,
          title: 'A game title long enough to need a second line',
          subtitle: 'A subtitle that is also rather long for a phone',
          body: const SizedBox(),
          onSettings: () {},
        ),
        prefs: await testPrefs(),
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('the body is capped and centred on a tablet', (tester) async {
    useSurface(tester, tablet);
    await tester.pumpWidget(
      gameHost(
        const GameScaffold(
          theme: theme,
          title: 'Play',
          body: SizedBox.expand(key: ValueKey('body')),
        ),
        prefs: await testPrefs(),
      ),
    );

    final body = tester.getRect(find.byKey(const ValueKey('body')));
    expect(body.width, lessThan(tablet.width));
    expect(body.center.dx, closeTo(tablet.width / 2, 0.5));
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_buttons_test.dart test/features/games/platform/game_scaffold_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/shell/game_backdrop.dart`

```dart
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A game's colour fading down to the ground, behind everything.
///
/// Sets white as the default ink, because every game screen is dark-based
/// whatever the app theme is doing.
///
/// The Material sits here, above the ink colour, on purpose. A Material
/// resets the default text style to the app theme's, so one placed lower
/// down turns every unstyled word back to the theme's dark ink on a dark
/// ground. Here it gives InkWells something to splash on, over the
/// gradient, and the white default is applied after it.
class GameBackdrop extends StatelessWidget {
  const GameBackdrop({super.key, required this.theme, required this.child});

  final GameTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: theme.backdrop),
        child: Material(
          type: MaterialType.transparency,
          child: IconTheme.merge(
            data: const IconThemeData(color: GameTheme.onGround),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: GameTheme.onGround),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
```

`lib/features/games/platform/shell/game_buttons.dart`

```dart
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:flutter/material.dart';

/// The round translucent button in a game's header and action row.
///
/// 48 across, so it clears the minimum touch target on its own. With a
/// [caption] it becomes one of the labelled actions under a board.
class GameRoundButton extends StatelessWidget {
  const GameRoundButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.caption,
    this.size = 48,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final String? caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      type: MaterialType.circle,
      color: GameTheme.onGround.withValues(alpha: 0.16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, color: GameTheme.onGround, size: size * 0.5),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child:
          caption == null
              ? button
              : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button,
                  const SizedBox(height: 6),
                  Text(
                    caption!,
                    style: const TextStyle(
                      color: GameTheme.mutedOnGround,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
    );
  }
}

/// The big white pill: Play, Continue, Play again.
///
/// Disabled, it dims and stops answering, and says so to a screen reader --
/// "Waiting for Ama" is information, not an action.
class GamePrimaryButton extends StatefulWidget {
  const GamePrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  State<GamePrimaryButton> createState() => _GamePrimaryButtonState();
}

class _GamePrimaryButtonState extends State<GamePrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      container: true,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: GameMotion.of(context, GameMotion.press),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              // Dimmed through the colour, not an Opacity widget, which
              // would composite the whole pill off-screen to fade it.
              color:
                  enabled
                      ? GameTheme.tile
                      : GameTheme.tile.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: GameTheme.tileInk, size: 26),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: GameTheme.tileInk,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The quieter outlined pill beside or under a primary button.
class GameSecondaryButton extends StatelessWidget {
  const GameSecondaryButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: GameTheme.onGround.withValues(alpha: 0.5),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameTheme.onGround,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
```

`lib/features/games/platform/shell/game_scaffold.dart`

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_backdrop.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';

/// The frame every game is played in.
///
/// One header for all of them: back on the left, a small subtitle over a
/// bold title, settings on the right. The game supplies the middle and,
/// optionally, a row of round actions under it.
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    required this.theme,
    required this.title,
    required this.body,
    this.subtitle,
    this.onBack,
    this.onSettings,
    this.actions = const [],
    this.maxContentWidth = ContentWidth.form,
  });

  final GameTheme theme;
  final String title;
  final String? subtitle;
  final Widget body;
  final VoidCallback? onBack;

  /// Null hides the gear.
  final VoidCallback? onSettings;

  /// Round buttons under the body, such as Hint and Undo.
  final List<Widget> actions;

  /// The body is capped to this on a tablet and centred.
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.ground,
      body: GameBackdrop(
        theme: theme,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    GameRoundButton(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: GameStrings.back,
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: GameTheme.onGround.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 14,
                                ),
                              ),
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (onSettings != null)
                      GameRoundButton(
                        icon: Icons.settings_rounded,
                        semanticLabel: GameStrings.settings,
                        onTap: onSettings,
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: AppContentWidth(maxWidth: maxContentWidth, child: body),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final action in actions)
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: action,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_buttons_test.dart test/features/games/platform/game_scaffold_test.dart`

Expected: `All tests passed!` — 14 tests (game_buttons_test.dart 6, game_scaffold_test.dart 8). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/shell/game_backdrop.dart lib/features/games/platform/shell/game_buttons.dart lib/features/games/platform/shell/game_scaffold.dart test/features/games/platform/support/ink_on_ground.dart test/features/games/platform/game_buttons_test.dart test/features/games/platform/game_scaffold_test.dart
git commit -m "feat(games): game backdrop, buttons and play scaffold (platform phase 1, task 7)"
```


---

### Task 8: The landing page

What a player sees after choosing a game: hero art, the title, one button
that says what happens next, and the game's ways to play.

**Files:**

- Create: `lib/features/games/platform/shell/game_landing_screen.dart`
- Create: `test/features/games/platform/game_landing_test.dart`

**What to know before writing it:**

- `landingAction` is a pure function from the session's state to the button's label and whether it is enabled. The button is disabled only while waiting on the partner.
- The waiting label uses the partner's name and falls back to "your partner" while the name is still loading. Never "both of you".
- The page is a `ListView`, so the largest text size scrolls instead of overflowing.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/game_landing_test.dart`

```dart
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_landing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';

void main() {
  group('the button', () {
    test('says something in every state', () {
      for (final status in GameLandingStatus.values) {
        final action = landingAction(GameLandingState(status: status));
        expect(action.label, isNotEmpty, reason: '$status');
      }
    });

    test('reads Play, Join, Your turn and Play again when you can act', () {
      String label(GameLandingStatus s) =>
          landingAction(GameLandingState(status: s)).label;

      expect(label(GameLandingStatus.fresh), 'Play');
      expect(label(GameLandingStatus.invited), 'Join');
      expect(label(GameLandingStatus.yourTurn), 'Your turn');
      expect(label(GameLandingStatus.finished), 'Play again');
    });

    test('is only disabled while waiting on the partner', () {
      for (final status in GameLandingStatus.values) {
        expect(
          landingAction(GameLandingState(status: status)).enabled,
          status != GameLandingStatus.waiting,
          reason: '$status',
        );
      }
    });

    test('names the partner being waited for', () {
      expect(
        landingAction(
          const GameLandingState(
            status: GameLandingStatus.waiting,
            partnerName: 'Ama',
          ),
        ).label,
        'Waiting for Ama',
      );
    });

    test('falls back when the name has not loaded', () {
      for (final name in [null, '', '   ']) {
        expect(
          landingAction(
            GameLandingState(
              status: GameLandingStatus.waiting,
              partnerName: name,
            ),
          ).label,
          'Waiting for your partner',
          reason: 'name "$name"',
        );
      }
    });
  });

  group('the page', () {
    Future<void> pump(
      WidgetTester tester, {
      GameLandingState state = const GameLandingState(
        status: GameLandingStatus.fresh,
      ),
      VoidCallback? onPrimary,
      VoidCallback? onRemind,
      VoidCallback? onHowToPlay,
      double textScale = 1,
      bool withEntries = true,
    }) async {
      useSurface(tester, phone);
      await tester.pumpWidget(
        gameHost(
          GameLandingScreen(
            definition: demoGame(withEntries: withEntries),
            state: state,
            onPrimary: onPrimary,
            onRemind: onRemind,
            onHowToPlay: onHowToPlay,
          ),
          prefs: await testPrefs(),
          textScale: textScale,
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the game, its tagline and its ways to play', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Tile Tutorial'), findsOneWidget);
      expect(find.text('STARTER PACK'), findsOneWidget);
      expect(find.text('Learn how the shell fits together.'), findsOneWidget);
      expect(find.text('1. Learn the basics'), findsOneWidget);
      expect(find.text('2. Themes'), findsOneWidget);
      expect(find.text('Pick a mood'), findsOneWidget);
      expect(find.text('3. Past games'), findsOneWidget);
    });

    testWidgets('everything written on the ground can be read there', (
      tester,
    ) async {
      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.waiting,
          partnerName: 'Ama',
          caption: 'Round 3 of 10',
          canRemind: true,
        ),
        onRemind: () {},
      );

      final ink = inkOnGround(tester, of: find.byType(GameLandingScreen));
      // The title, label, tagline, caption, reminder and three entries,
      // one with a subtitle -- so the check below is checking something.
      expect(ink.length, greaterThanOrEqualTo(9));
      expect(
        ink.where((piece) => piece.contrast < 4.5).map((piece) => piece.text),
        isEmpty,
        reason: 'dark ink on the dark ground',
      );
    });

    testWidgets('pressing Play is reported', (tester) async {
      var presses = 0;
      await pump(tester, onPrimary: () => presses++);

      await tester.tap(find.byType(GamePrimaryButton));
      await tester.pump();

      expect(presses, 1);
    });

    testWidgets('the button does nothing while waiting on the partner', (
      tester,
    ) async {
      var presses = 0;
      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.waiting,
          partnerName: 'Ama',
        ),
        onPrimary: () => presses++,
      );

      expect(find.text('Waiting for Ama'), findsOneWidget);
      await tester.tap(find.byType(GamePrimaryButton), warnIfMissed: false);
      await tester.pump();

      // The control is the test above: the same tap does report when the
      // player can act.
      expect(presses, 0);
    });

    testWidgets('the caption says where the game stands', (tester) async {
      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.yourTurn,
          caption: 'Round 3 of 10',
        ),
      );

      expect(find.text('ROUND 3 OF 10'), findsOneWidget);
    });

    testWidgets('a reminder is offered only while waiting, and only when one '
        'can be sent', (tester) async {
      var reminders = 0;

      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.waiting,
          canRemind: true,
        ),
        onRemind: () => reminders++,
      );
      expect(find.text('Send a reminder'), findsOneWidget);
      await tester.tap(find.text('Send a reminder'));
      expect(reminders, 1);

      await pump(
        tester,
        state: const GameLandingState(status: GameLandingStatus.waiting),
        onRemind: () => reminders++,
      );
      expect(find.text('Send a reminder'), findsNothing);

      await pump(
        tester,
        state: const GameLandingState(
          status: GameLandingStatus.yourTurn,
          canRemind: true,
        ),
        onRemind: () => reminders++,
      );
      expect(find.text('Send a reminder'), findsNothing);
    });

    testWidgets('the help button opens how to play', (tester) async {
      var opened = 0;
      await pump(tester, onHowToPlay: () => opened++);

      await tester.tap(find.bySemanticsLabel('How to play'));

      expect(opened, 1);
    });

    testWidgets('a game with no entries shows no list', (tester) async {
      await pump(tester, withEntries: false);

      expect(find.textContaining('1. '), findsNothing);
      expect(find.text('Tile Tutorial'), findsOneWidget);
    });

    testWidgets('the largest text size scrolls instead of overflowing', (
      tester,
    ) async {
      await pump(tester, textScale: 2);

      expect(tester.takeException(), isNull);

      // Everything is still reachable: the last entry can be scrolled to.
      await tester.scrollUntilVisible(
        find.text('3. Past games'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('3. Past games'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_landing_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/shell/game_landing_screen.dart`

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_backdrop.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';

/// Where the two players stand in a game.
enum GameLandingStatus {
  /// No game in progress.
  fresh,

  /// The partner started one and is waiting for this player.
  invited,

  /// A game is in progress and this player can act.
  yourTurn,

  /// A game is in progress and the partner has to act.
  waiting,

  /// The last game is over.
  finished,
}

@immutable
class GameLandingState {
  const GameLandingState({
    required this.status,
    this.partnerName,
    this.caption,
    this.canRemind = false,
  });

  final GameLandingStatus status;

  /// Named on the button while waiting. Null falls back to "your partner".
  final String? partnerName;

  /// Where the game stands, such as "Round 3 of 10". Shown under the button.
  final String? caption;

  /// Whether a reminder can be sent right now. Only read while waiting.
  final bool canRemind;
}

/// What the landing page's one button says and whether it can be pressed.
@immutable
class GameLandingAction {
  const GameLandingAction({
    required this.label,
    required this.enabled,
    this.icon,
  });

  final String label;
  final bool enabled;
  final IconData? icon;
}

/// The button for a state.
///
/// Pure, so each of the five states is checked without building a screen.
/// The button is what makes this page about two people rather than one:
/// the same game says Play, Your turn or Waiting for Ama depending on who
/// has to move.
GameLandingAction landingAction(GameLandingState state) {
  switch (state.status) {
    case GameLandingStatus.fresh:
      return const GameLandingAction(
        label: GameStrings.play,
        enabled: true,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.invited:
      return const GameLandingAction(
        label: GameStrings.join,
        enabled: true,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.yourTurn:
      return const GameLandingAction(
        label: GameStrings.yourTurn,
        enabled: true,
        icon: Icons.play_arrow_rounded,
      );
    case GameLandingStatus.waiting:
      final name = state.partnerName?.trim();
      return GameLandingAction(
        label:
            name == null || name.isEmpty
                ? GameStrings.waitingForPartner
                : GameStrings.waitingFor(name),
        // Waiting is information, not an action: there is nothing this
        // player can do in the game until the partner moves.
        enabled: false,
      );
    case GameLandingStatus.finished:
      return const GameLandingAction(
        label: GameStrings.playAgain,
        enabled: true,
        icon: Icons.replay_rounded,
      );
  }
}

/// The page every game opens on.
///
/// The game's colour and tile art, its name, one button, and the list of
/// ways to play underneath. It scrolls as a whole, so the largest text size
/// reaches everything instead of overflowing.
class GameLandingScreen extends StatelessWidget {
  const GameLandingScreen({
    super.key,
    required this.definition,
    required this.state,
    this.onPrimary,
    this.onRemind,
    this.onBack,
    this.onHowToPlay,
  });

  final GameDefinition definition;
  final GameLandingState state;

  /// Called when the button is pressed. Never called while waiting.
  final VoidCallback? onPrimary;

  final VoidCallback? onRemind;
  final VoidCallback? onBack;
  final VoidCallback? onHowToPlay;

  @override
  Widget build(BuildContext context) {
    final action = landingAction(state);
    final entries =
        definition.entriesBuilder?.call(context) ?? const <GameEntry>[];
    final showRemind =
        state.status == GameLandingStatus.waiting &&
        state.canRemind &&
        onRemind != null;

    return Scaffold(
      backgroundColor: GameTheme.ground,
      body: GameBackdrop(
        theme: definition.theme,
        child: SafeArea(
          child: AppContentWidth(
            maxWidth: ContentWidth.form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GameRoundButton(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: GameStrings.back,
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                    ),
                    if (onHowToPlay != null)
                      GameRoundButton(
                        icon: Icons.question_mark_rounded,
                        semanticLabel: GameStrings.howToPlay,
                        onTap: onHowToPlay,
                      ),
                  ],
                ),
                SizedBox(
                  height: 220,
                  child: Center(
                    child: ExcludeSemantics(
                      child: definition.heroBuilder(context, definition.theme),
                    ),
                  ),
                ),
                Text(
                  definition.collectionLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  child: Text(
                    definition.title,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  definition.tagline,
                  style: const TextStyle(
                    color: GameTheme.mutedOnGround,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 28),
                GamePrimaryButton(
                  label: action.label,
                  icon: action.icon,
                  onTap: action.enabled ? onPrimary : null,
                ),
                if (state.caption != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    state.caption!.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: GameTheme.mutedOnGround,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
                if (showRemind) ...[
                  const SizedBox(height: 12),
                  GameSecondaryButton(
                    label: GameStrings.remind,
                    onTap: onRemind,
                  ),
                ],
                if (entries.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: GameTheme.hairline),
                  for (var i = 0; i < entries.length; i++)
                    _EntryRow(number: i + 1, entry: entries[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.number, required this.entry});

  final int number;
  final GameEntry entry;

  @override
  Widget build(BuildContext context) {
    final onTap = entry.onTap;

    return Column(
      children: [
        InkWell(
          onTap: onTap == null ? null : () => onTap(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: GameTheme.tile,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 30,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: GameTheme.tileInk,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        GameStrings.entryNumber(number, entry.title),
                        style: const TextStyle(fontSize: 17),
                      ),
                      if (entry.subtitle != null)
                        Text(
                          entry.subtitle!,
                          style: const TextStyle(
                            color: GameTheme.mutedOnGround,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: GameTheme.hairline),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_landing_test.dart`

Expected: `All tests passed!` — 14 tests (game_landing_test.dart 14). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/shell/game_landing_screen.dart test/features/games/platform/game_landing_test.dart
git commit -m "feat(games): game landing page (platform phase 1, task 8)"
```


---

### Task 9: The settings sheet

General (sound, vibration), the game's own tab when it has settings, and
Support. Rows only exist when the caller can act on them.

**Files:**

- Create: `lib/features/games/platform/shell/game_settings_sheet.dart`
- Create: `test/features/games/platform/game_settings_sheet_test.dart`

**What to know before writing it:**

- With a long game name ("Snakes and Ladders") or large text, three tabs do not fit a phone. The row scrolls, and choosing a tab that is only partly showing brings it fully into view.
- There is no Leave game unless the caller passes `onLeaveGame`: the landing page has no game in progress to leave.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/game_settings_sheet_test.dart`

```dart
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:attune/features/games/platform/shell/game_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    GameDefinition? definition,
    VoidCallback? onHowToPlay,
    VoidCallback? onReportProblem,
    VoidCallback? onLeaveGame,
    Map<String, Object> stored = const {},
    double textScale = 1,
  }) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showGameSettingsSheet(
                        context,
                        definition: definition ?? demoGame(),
                        onHowToPlay: onHowToPlay,
                        onReportProblem: onReportProblem,
                        onLeaveGame: onLeaveGame,
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
        prefs: await testPrefs(stored),
        textScale: textScale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  GamePrefs prefsOf(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(GameSettingsSheet)),
  ).read(gamePrefsProvider);

  testWidgets('opens on General, with sound and vibration', (tester) async {
    await open(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sound effects'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets('turning sound off is saved', (tester) async {
    await open(tester);
    expect(prefsOf(tester).sound, isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(prefsOf(tester).sound, isFalse);
    expect(prefsOf(tester).haptics, isTrue);
  });

  testWidgets('turning vibration off is saved', (tester) async {
    await open(tester);

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();

    expect(prefsOf(tester).haptics, isFalse);
    expect(prefsOf(tester).sound, isTrue);
  });

  testWidgets('the switches show what was stored', (tester) async {
    await open(tester, stored: {GamePrefsNotifier.soundKey: false});

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(2));
    expect(switches.first.value, isFalse);
    expect(switches.last.value, isTrue);
  });

  testWidgets('a game with its own settings gets its own tab', (tester) async {
    await open(tester, definition: demoGame(withSettings: true));

    expect(find.bySemanticsLabel('Tile Tutorial'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Tile Tutorial'));
    await tester.pumpAndSettle();

    expect(find.text('Demo game settings'), findsOneWidget);
    expect(find.text('Sound effects'), findsNothing);
  });

  testWidgets('a game without settings has no tab for them', (tester) async {
    // The control is the test above, where the same lookup finds the tab.
    await open(tester);

    expect(find.bySemanticsLabel('Tile Tutorial'), findsNothing);
    expect(find.bySemanticsLabel('General'), findsOneWidget);
    expect(find.bySemanticsLabel('Support'), findsOneWidget);
  });

  testWidgets('Support offers only what the caller can act on', (tester) async {
    final taps = <String>[];
    await open(
      tester,
      onHowToPlay: () => taps.add('how'),
      onReportProblem: () => taps.add('report'),
      onLeaveGame: () => taps.add('leave'),
    );
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('How to play'));
    await tester.tap(find.text('Report a problem'));
    await tester.tap(find.text('Leave game'));

    expect(taps, ['how', 'report', 'leave']);
  });

  testWidgets('there is no Leave game where no game is in progress', (
    tester,
  ) async {
    await open(tester, onHowToPlay: () {});
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();

    expect(find.text('How to play'), findsOneWidget);
    expect(find.text('Leave game'), findsNothing);
    expect(find.text('Report a problem'), findsNothing);
  });

  testWidgets('a tab that is only partly showing comes fully into view when '
      'chosen', (tester) async {
    await open(
      tester,
      definition: demoGame(withSettings: true),
      onLeaveGame: () {},
    );
    final support = find.bySemanticsLabel('Support');
    expect(
      tester.getRect(support).left,
      greaterThan(phone.width),
      reason:
          'the control: three tabs do not fit, so Support starts off '
          'the edge',
    );

    // Pull the row until a sliver of Support shows, and tap the sliver.
    await tester.drag(find.bySemanticsLabel('General'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    final sliver = tester.getRect(support);
    expect(sliver.left, lessThan(phone.width));
    expect(sliver.right, greaterThan(phone.width));
    await tester.tapAt(Offset(sliver.left + 12, sliver.center.dy));
    await tester.pumpAndSettle();

    expect(find.text('Leave game'), findsOneWidget);
    expect(tester.getRect(support).right, lessThanOrEqualTo(phone.width));
    expect(tester.getRect(support).left, greaterThanOrEqualTo(0));
  });

  testWidgets('the selected tab is announced as selected', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel('General')),
      matchesSemantics(
        label: 'General',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Support')),
      matchesSemantics(
        label: 'Support',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('close dismisses the sheet', (tester) async {
    await open(tester);

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(GameSettingsSheet), findsNothing);
  });

  testWidgets('the largest text size does not overflow', (tester) async {
    await open(
      tester,
      definition: demoGame(withSettings: true),
      onHowToPlay: () {},
      onReportProblem: () {},
      onLeaveGame: () {},
      textScale: 2,
    );
    expect(tester.takeException(), isNull);

    // At this size the tabs run well past the edge; the row scrolls.
    await tester.ensureVisible(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Every row is still reachable.
    await tester.scrollUntilVisible(
      find.text('Leave game'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Leave game'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_settings_sheet_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/shell/game_settings_sheet.dart`

```dart
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a game's settings.
Future<void> showGameSettingsSheet(
  BuildContext context, {
  required GameDefinition definition,
  VoidCallback? onHowToPlay,
  VoidCallback? onReportProblem,
  VoidCallback? onLeaveGame,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GameTheme.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder:
        (_) => GameSettingsSheet(
          definition: definition,
          onHowToPlay: onHowToPlay,
          onReportProblem: onReportProblem,
          onLeaveGame: onLeaveGame,
        ),
  );
}

/// Settings for the games in general, for this game, and a way to get help.
///
/// The middle tab belongs to the game and only exists when the game has
/// settings of its own. Support rows only exist when the caller can act on
/// them: there is no Leave game on a page where no game is in progress.
class GameSettingsSheet extends ConsumerStatefulWidget {
  const GameSettingsSheet({
    super.key,
    required this.definition,
    this.onHowToPlay,
    this.onReportProblem,
    this.onLeaveGame,
  });

  final GameDefinition definition;
  final VoidCallback? onHowToPlay;
  final VoidCallback? onReportProblem;
  final VoidCallback? onLeaveGame;

  @override
  ConsumerState<GameSettingsSheet> createState() => _GameSettingsSheetState();
}

class _GameSettingsSheetState extends ConsumerState<GameSettingsSheet> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final gameSettings = widget.definition.settingsBuilder;
    final tabs = <({String label, WidgetBuilder builder})>[
      (label: GameStrings.general, builder: _general),
      if (gameSettings != null)
        (label: widget.definition.title, builder: gameSettings),
      (label: GameStrings.support, builder: _support),
    ];
    final index = _index.clamp(0, tabs.length - 1);

    return DefaultTextStyle.merge(
      style: const TextStyle(color: GameTheme.onGround),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: GameTheme.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: const Text(
                          GameStrings.settings,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    GameRoundButton(
                      icon: Icons.close_rounded,
                      semanticLabel: GameStrings.close,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        _TabLabel(
                          label: tabs[i].label,
                          selected: i == index,
                          onTap: () => setState(() => _index = i),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: tabs[index].builder(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _general(BuildContext context) {
    final prefs = ref.watch(gamePrefsProvider);
    final notifier = ref.read(gamePrefsProvider.notifier);
    final accent = widget.definition.theme.primary;

    return Column(
      children: [
        _SwitchCard(
          title: GameStrings.soundEffects,
          hint: GameStrings.soundEffectsHint,
          value: prefs.sound,
          accent: accent,
          onChanged: notifier.setSound,
        ),
        const SizedBox(height: 12),
        _SwitchCard(
          title: GameStrings.haptics,
          hint: GameStrings.hapticsHint,
          value: prefs.haptics,
          accent: accent,
          onChanged: notifier.setHaptics,
        ),
      ],
    );
  }

  Widget _support(BuildContext context) {
    final rows = <({String label, IconData icon, VoidCallback onTap})>[
      if (widget.onHowToPlay != null)
        (
          label: GameStrings.howToPlay,
          icon: Icons.question_mark_rounded,
          onTap: widget.onHowToPlay!,
        ),
      if (widget.onReportProblem != null)
        (
          label: GameStrings.reportProblem,
          icon: Icons.flag_outlined,
          onTap: widget.onReportProblem!,
        ),
      if (widget.onLeaveGame != null)
        (
          label: GameStrings.leaveGame,
          icon: Icons.logout_rounded,
          onTap: widget.onLeaveGame!,
        ),
    ];

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RowCard(label: row.label, icon: row.icon, onTap: row.onTap),
          ),
      ],
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A long game name, or large text, pushes the last tab past the edge
    // of a phone. The row scrolls, and choosing a tab that is only partly
    // showing brings all of it into view.
    void select() {
      onTap();
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: GameMotion.of(context, GameMotion.settle),
        curve: GameMotion.enterCurve,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: select,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: select,
        child: Padding(
          padding: const EdgeInsets.only(right: 24, top: 8, bottom: 8),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color:
                        selected ? GameTheme.onGround : GameTheme.mutedOnGround,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  color: selected ? GameTheme.onGround : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.title,
    required this.hint,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        decoration: BoxDecoration(
          color: GameTheme.raised,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    hint,
                    style: const TextStyle(
                      color: GameTheme.mutedOnGround,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: GameTheme.tile,
              activeTrackColor: accent,
              inactiveThumbColor: GameTheme.mutedOnGround,
              inactiveTrackColor: GameTheme.hairline,
            ),
          ],
        ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GameTheme.raised,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: GameTheme.onGround, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: GameTheme.onGround,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: GameTheme.mutedOnGround,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_settings_sheet_test.dart`

Expected: `All tests passed!` — 12 tests (game_settings_sheet_test.dart 12). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/shell/game_settings_sheet.dart test/features/games/platform/game_settings_sheet_test.dart
git commit -m "feat(games): game settings sheet (platform phase 1, task 9)"
```


---

### Task 10: How to play, and the first-time tutorial

The rules as a numbered list, and a coach that walks a first-time player
through the game over the game itself.

**Files:**

- Create: `lib/features/games/platform/shell/game_how_to_play_sheet.dart`
- Create: `lib/features/games/platform/shell/game_coach.dart`
- Create: `test/features/games/platform/game_how_to_play_test.dart`
- Create: `test/features/games/platform/game_coach_test.dart`

**What to know before writing it:**

- `GameCoach` wraps the game's body, not the whole screen, so its bubble sits under the header instead of on top of the back button.
- It measures its target through screen coordinates, so a tutorial around the board can point at a button in the bar below it. `localToGlobal(..., ancestor: stack)` would assert for a target outside the stack.
- The ring ignores touches: the game underneath stays playable while the tutorial is up.
- Seen-state is per game, per device (`games.coach.seen.<gameType>`). Skip counts as seen.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/game_how_to_play_test.dart`

```dart
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_how_to_play_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    GameDefinition? definition,
    double textScale = 1,
  }) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showGameHowToPlay(
                        context,
                        definition: definition ?? demoGame(),
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
        prefs: await testPrefs(),
        textScale: textScale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the rules in order, numbered', (tester) async {
    await open(tester);

    expect(find.text('How to play'), findsOneWidget);
    final first = find.text('1. Tap a tile to pick it.');
    final second = find.text('2. Your partner answers the same question.');
    final third = find.text('3. See both answers together.');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(third, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
    expect(tester.getTopLeft(second).dy, lessThan(tester.getTopLeft(third).dy));
  });

  testWidgets('Got it closes the sheet', (tester) async {
    await open(tester);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(find.byType(GameHowToPlaySheet), findsNothing);
  });

  testWidgets('many long rules scroll, and Got it stays on screen', (
    tester,
  ) async {
    final long = GameDefinition(
      gameType: 'long',
      title: 'Long',
      collectionLabel: 'Demo',
      tagline: 'Many rules.',
      theme: const GameTheme(primary: GameColors.wordHunt),
      heroBuilder: (_, __) => const SizedBox(),
      howToPlay: [
        for (var i = 0; i < 30; i++)
          'Rule number $i says a fairly long thing about how the game works.',
      ],
    );
    await open(tester, definition: long, textScale: 2);

    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.text('Got it'));
    expect(button.bottom, lessThanOrEqualTo(phone.height));
    expect(button.top, greaterThan(0));
  });
}
```

`test/features/games/platform/game_coach_test.dart`

```dart
import 'package:attune/features/games/platform/shell/game_coach.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';

void main() {
  final target = GlobalKey();

  List<GameCoachStep> steps() => [
    const GameCoachStep(text: 'Welcome to the game.'),
    GameCoachStep(text: 'Tap this tile.', target: target),
    const GameCoachStep(text: 'That is all there is to it.'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
    List<GameCoachStep>? withSteps,
    bool force = false,
    VoidCallback? onDone,
    VoidCallback? onTargetTap,
    double textScale = 1,
  }) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: GameCoach(
            gameType: 'demo',
            steps: withSteps ?? steps(),
            force: force,
            onDone: onDone,
            child: Align(
              alignment: const Alignment(0, 0.8),
              child: GestureDetector(
                onTap: onTargetTap,
                child: SizedBox(
                  key: target,
                  width: 64,
                  height: 64,
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        prefs: await testPrefs(stored),
        textScale: textScale,
      ),
    );
    // One frame to build, one for the post-frame measurement to land.
    await tester.pump();
    await tester.pump();
  }

  bool seen(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(GameCoach)),
  ).read(gameCoachStoreProvider).seen('demo');

  testWidgets('a first-time player is shown the first step', (tester) async {
    await pump(tester);

    expect(find.text('Welcome to the game.'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('Next walks through to the last step, which has no Skip', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Tap this tile.'), findsOneWidget);
    expect(find.text('Welcome to the game.'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('That is all there is to it.'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('Got it closes the tutorial and remembers it was seen', (
    tester,
  ) async {
    var done = 0;
    await pump(tester, onDone: () => done++);
    expect(seen(tester), isFalse);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Got it'));
    await tester.pump();

    expect(find.byType(GameCoachBubble), findsNothing);
    expect(done, 1);
    expect(seen(tester), isTrue);
  });

  testWidgets('Skip closes it at once, and it still counts as seen', (
    tester,
  ) async {
    var done = 0;
    await pump(tester, onDone: () => done++);

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(find.byType(GameCoachBubble), findsNothing);
    expect(done, 1);
    expect(seen(tester), isTrue);
  });

  testWidgets('a player who has seen it is not shown it again', (tester) async {
    // The control is the first test: the same pump without the stored flag
    // does show the bubble.
    await pump(tester, stored: {GameCoachStore.key('demo'): true});

    expect(find.byType(GameCoachBubble), findsNothing);
  });

  testWidgets('seeing one game\'s tutorial does not hide another\'s', (
    tester,
  ) async {
    await pump(tester, stored: {GameCoachStore.key('another_game'): true});

    expect(find.byType(GameCoachBubble), findsOneWidget);
  });

  testWidgets('asking for it replays it even when seen', (tester) async {
    await pump(tester, stored: {GameCoachStore.key('demo'): true}, force: true);

    expect(find.text('Welcome to the game.'), findsOneWidget);
  });

  testWidgets('a game with no steps shows nothing', (tester) async {
    await pump(tester, withSteps: const []);

    expect(find.byType(GameCoachBubble), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a step with a target rings exactly that target', (tester) async {
    await pump(tester);
    expect(
      find.byKey(const ValueKey('game-coach-ring')),
      findsNothing,
      reason: 'the first step points at nothing',
    );

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();

    final ring = tester.getRect(find.byKey(const ValueKey('game-coach-ring')));
    final tile = tester.getRect(find.byKey(target));
    expect(ring, tile.inflate(5));
  });

  testWidgets('it can point at something outside the area it wraps', (
    tester,
  ) async {
    // A tutorial around the board pointing at a button in the bar below.
    useSurface(tester, phone);
    final outside = GlobalKey();
    await tester.pumpWidget(
      gameHost(
        Scaffold(
          body: Column(
            children: [
              Expanded(
                child: GameCoach(
                  gameType: 'demo',
                  steps: [
                    GameCoachStep(text: 'Stuck? Try this.', target: outside),
                  ],
                  child: const SizedBox.expand(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(key: outside, width: 48, height: 48),
              ),
            ],
          ),
        ),
        prefs: await testPrefs(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    final ring = tester.getRect(find.byKey(const ValueKey('game-coach-ring')));
    expect(ring, tester.getRect(find.byKey(outside)).inflate(5));
  });

  testWidgets('the ring goes when the step that needed it is over', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('game-coach-ring')), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('game-coach-ring')), findsNothing);
  });

  testWidgets('the game underneath still takes touches through the ring', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, onTargetTap: () => taps++);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('game-coach-ring')), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byKey(target)));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('the largest text size does not overflow the bubble', (
    tester,
  ) async {
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('Welcome to the game.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_how_to_play_test.dart test/features/games/platform/game_coach_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/shell/game_how_to_play_sheet.dart`

```dart
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';

/// Shows a game's rules, a numbered sentence each.
Future<void> showGameHowToPlay(
  BuildContext context, {
  required GameDefinition definition,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GameTheme.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => GameHowToPlaySheet(definition: definition),
  );
}

class GameHowToPlaySheet extends StatelessWidget {
  const GameHowToPlaySheet({super.key, required this.definition});

  final GameDefinition definition;

  @override
  Widget build(BuildContext context) {
    final rules = definition.howToPlay;

    return DefaultTextStyle.merge(
      style: const TextStyle(color: GameTheme.onGround),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: const Text(
                    GameStrings.howToPlay,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < rules.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              '${i + 1}. ${rules[i]}',
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.35,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GamePrimaryButton(
                  label: GameStrings.gotIt,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

`lib/features/games/platform/shell/game_coach.dart`

```dart
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One thing the tutorial says, and optionally the thing it points at.
@immutable
class GameCoachStep {
  const GameCoachStep({required this.text, this.target});

  final String text;

  /// The widget to ring and point at. Null shows the bubble alone.
  final GlobalKey? target;
}

/// Remembers, per device, which games' tutorials have been seen.
class GameCoachStore {
  GameCoachStore(this._prefs);

  final SharedPreferences _prefs;

  static String key(String gameType) => 'games.coach.seen.$gameType';

  bool seen(String gameType) => _prefs.getBool(key(gameType)) ?? false;

  Future<void> markSeen(String gameType) => _prefs.setBool(key(gameType), true);
}

final gameCoachStoreProvider = Provider<GameCoachStore>(
  (ref) => GameCoachStore(ref.watch(sharedPreferencesProvider)),
);

/// The tutorial's speech bubble.
class GameCoachBubble extends StatelessWidget {
  const GameCoachBubble({
    super.key,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.onSkip,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  /// Null hides Skip, on the last step.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: GameTheme.raised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: GameTheme.onGround, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              text,
              style: const TextStyle(
                color: GameTheme.onGround,
                fontSize: 16,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 14),
          GamePrimaryButton(label: actionLabel, onTap: onAction),
          if (onSkip != null) ...[
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label: GameStrings.skip,
              container: true,
              excludeSemantics: true,
              onTap: onSkip,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSkip,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    GameStrings.skip,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: GameTheme.mutedOnGround,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Walks a first-time player through a game, over the game itself.
///
/// Wrap the game's body with it, not the whole screen: the bubble sits at
/// the top of whatever it wraps, and around the body that is under the
/// header rather than on top of the back button.
///
/// It shows once per game per device and can be skipped at any step. The
/// game underneath stays live: the ring around a target does not take
/// touches, so the player can do the thing being described.
///
/// [force] replays it for someone who asked, whatever the store says.
class GameCoach extends ConsumerStatefulWidget {
  const GameCoach({
    super.key,
    required this.gameType,
    required this.steps,
    required this.child,
    this.force = false,
    this.onDone,
  });

  final String gameType;
  final List<GameCoachStep> steps;
  final Widget child;
  final bool force;
  final VoidCallback? onDone;

  @override
  ConsumerState<GameCoach> createState() => _GameCoachState();
}

class _GameCoachState extends ConsumerState<GameCoach> {
  final GlobalKey _stackKey = GlobalKey();

  /// The step showing, or null when the tutorial is not running.
  int? _index;
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    final seen = ref.read(gameCoachStoreProvider).seen(widget.gameType);
    if (widget.steps.isNotEmpty && (widget.force || !seen)) _index = 0;
  }

  void _advance() {
    final index = _index;
    if (index == null) return;
    if (index >= widget.steps.length - 1) {
      _finish();
    } else {
      setState(() {
        _index = index + 1;
        _targetRect = null;
      });
    }
  }

  void _finish() {
    unawaited(ref.read(gameCoachStoreProvider).markSeen(widget.gameType));
    setState(() {
      _index = null;
      _targetRect = null;
    });
    widget.onDone?.call();
  }

  /// Finds the current target on screen, in this widget's own coordinates.
  ///
  /// Runs after layout, because a target's position does not exist until
  /// then. It only rebuilds when the answer changed, so measuring every
  /// frame the tutorial is up cannot loop.
  void _measure() {
    final index = _index;
    if (!mounted || index == null) return;

    final target =
        widget.steps[index].target?.currentContext?.findRenderObject();
    final stack = _stackKey.currentContext?.findRenderObject();
    Rect? rect;
    if (target is RenderBox &&
        stack is RenderBox &&
        target.attached &&
        target.hasSize) {
      // Through screen coordinates, so the target does not have to be
      // inside this widget: a tutorial around the board can still point
      // at a button in the bar under it.
      final topLeft =
          target.localToGlobal(Offset.zero) - stack.localToGlobal(Offset.zero);
      rect = topLeft & target.size;
    }
    if (rect != _targetRect) setState(() => _targetRect = rect);
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    if (index != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
    final rect = _targetRect;
    final isLast = index != null && index >= widget.steps.length - 1;

    return Stack(
      key: _stackKey,
      // The ring may sit over something outside this widget.
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (index != null && rect != null)
          Positioned.fromRect(
            rect: rect.inflate(5),
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('game-coach-ring'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: GameTheme.onGround, width: 3),
                ),
              ),
            ),
          ),
        if (index != null && rect != null)
          Positioned(
            left: rect.right - 18,
            top: rect.bottom - 18,
            child: const IgnorePointer(
              child: Icon(
                Icons.touch_app_rounded,
                color: GameTheme.onGround,
                size: 36,
              ),
            ),
          ),
        if (index != null)
          Positioned(
            left: 16,
            right: 16,
            top: 8,
            child: GameCoachBubble(
              text: widget.steps[index].text,
              actionLabel: isLast ? GameStrings.gotIt : GameStrings.next,
              onAction: _advance,
              onSkip: isLast ? null : _finish,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_how_to_play_test.dart test/features/games/platform/game_coach_test.dart`

Expected: `All tests passed!` — 16 tests (game_how_to_play_test.dart 3, game_coach_test.dart 13). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/shell/game_how_to_play_sheet.dart lib/features/games/platform/shell/game_coach.dart test/features/games/platform/game_how_to_play_test.dart test/features/games/platform/game_coach_test.dart
git commit -m "feat(games): how-to-play sheet and first-time tutorial (platform phase 1, task 10)"
```


---

### Task 11: The completion screen

Where every game ends: a headline, one word in tiles, the two players' names,
and whatever the game wants to say about how it went.

**Files:**

- Create: `lib/features/games/platform/shell/game_complete_screen.dart`
- Create: `test/features/games/platform/game_complete_test.dart`

**What to know before writing it:**

- It names the two people; it never scores one of them (permanent product constraint: no partner scorecards).
- The win sound fires once, in a post-frame callback from `initState`, not from `build`.
- The content is centred in the space above the buttons when it fits and scrolls when it does not.

- [ ] **Step 1: Write the tests**

`test/features/games/platform/game_complete_test.dart`

```dart
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_complete_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';

void main() {
  const theme = GameTheme(primary: GameColors.thisOrThat);

  Future<FakeSoundService> pump(
    WidgetTester tester, {
    List<String> names = const ['Ama', 'Kofi'],
    Widget? summary,
    VoidCallback? onPlayAgain,
    VoidCallback? onBackToGames,
    Map<String, Object> stored = const {},
    bool reduceMotion = false,
    double textScale = 1,
    FakeSoundService? sound,
  }) async {
    useSurface(tester, phone);
    final fake = sound ?? FakeSoundService();
    await tester.pumpWidget(
      gameHost(
        GameCompleteScreen(
          theme: theme,
          headline: 'This or That',
          word: 'COMPLETE',
          names: names,
          summary: summary,
          onPlayAgain: onPlayAgain,
          onBackToGames: onBackToGames ?? () {},
        ),
        prefs: await testPrefs(stored),
        sound: fake,
        reduceMotion: reduceMotion,
        textScale: textScale,
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('spells the word one tile per letter', (tester) async {
    await pump(tester);

    expect(find.text('This or That'), findsOneWidget);
    expect(find.byType(GameTile), findsNWidgets('COMPLETE'.length));
  });

  testWidgets('names the two people who played', (tester) async {
    await pump(tester);

    expect(find.text('Ama & Kofi'), findsOneWidget);
  });

  testWidgets('a name that has not loaded is left out, not shown blank', (
    tester,
  ) async {
    await pump(tester, names: const ['Ama', '  ']);

    expect(find.text('Ama'), findsOneWidget);
    expect(find.textContaining('&'), findsNothing);
  });

  testWidgets('shows what the game has to say about the result', (
    tester,
  ) async {
    await pump(tester, summary: const Text('You matched on 7 of 10.'));

    expect(find.text('You matched on 7 of 10.'), findsOneWidget);
  });

  testWidgets('everything written on the ground can be read there', (
    tester,
  ) async {
    await pump(tester, summary: const Text('You matched on 7 of 10.'));

    final ink = inkOnGround(tester, of: find.byType(GameCompleteScreen));
    expect(
      ink.map((piece) => piece.text),
      containsAll(['This or That', 'Ama & Kofi', 'You matched on 7 of 10.']),
    );
    expect(
      ink.where((piece) => piece.contrast < 4.5).map((piece) => piece.text),
      isEmpty,
    );
  });

  testWidgets('the result sits in the middle of the space above the buttons', (
    tester,
  ) async {
    await pump(tester, onPlayAgain: () {});

    final top = tester.getRect(find.text('This or That')).top;
    final bottom = tester.getRect(find.text('Ama & Kofi')).bottom;
    final buttons = tester.getRect(find.text('Play again')).top;

    final above = top;
    final below = buttons - bottom;
    expect(above, greaterThan(100), reason: 'not pinned to the top');
    // The button's own padding sits between the two, so near, not equal.
    expect((above - below).abs(), lessThan(40));
  });

  testWidgets('both buttons report their own tap', (tester) async {
    final taps = <String>[];
    await pump(
      tester,
      onPlayAgain: () => taps.add('again'),
      onBackToGames: () => taps.add('back'),
    );

    await tester.tap(find.text('Play again'));
    await tester.tap(find.text('Back to games'));

    expect(taps, ['again', 'back']);
  });

  testWidgets('there is no Play again when the game cannot be replayed', (
    tester,
  ) async {
    // The control is the test above, where the same lookup finds it.
    await pump(tester);

    expect(find.text('Play again'), findsNothing);
    expect(find.text('Back to games'), findsOneWidget);
  });

  testWidgets('the win sound plays once, however often the screen rebuilds', (
    tester,
  ) async {
    final sound = await pump(tester);
    expect(sound.played, [AppSound.gameComplete]);

    // A rebuild with new content is not a second win.
    await pump(
      tester,
      summary: const Text('You matched on 7 of 10.'),
      sound: sound,
    );

    expect(find.text('You matched on 7 of 10.'), findsOneWidget);
    expect(sound.played, [AppSound.gameComplete]);
  });

  testWidgets('with sound switched off the screen arrives silently', (
    tester,
  ) async {
    final sound = await pump(
      tester,
      stored: {GamePrefsNotifier.soundKey: false},
    );

    expect(sound.played, isEmpty);
  });

  testWidgets('reduce motion shows the finished screen on the first frame', (
    tester,
  ) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        GameCompleteScreen(
          theme: theme,
          headline: 'This or That',
          word: 'COMPLETE',
          onBackToGames: () {},
        ),
        prefs: await testPrefs(),
        reduceMotion: true,
      ),
    );
    await tester.pump();

    expect(find.byType(GameTile), findsNWidgets('COMPLETE'.length));
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: 'nothing is still animating',
    );
  });

  testWidgets('the largest text size scrolls instead of overflowing', (
    tester,
  ) async {
    await pump(
      tester,
      summary: const Text(
        'You matched on 7 of 10, and disagreed most about mornings, '
        'holidays and what counts as being on time.',
      ),
      onPlayAgain: () {},
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Back to games'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/games/platform/game_complete_test.dart`

Expected: the run fails to compile, because the files under test do not exist yet (`Error when reading 'lib/features/games/platform/...': No such file or directory`, or `Undefined name`). A run that passes here means the test is not testing the new code.

- [ ] **Step 3: Write the code**

`lib/features/games/platform/shell/game_complete_screen.dart`

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/games/platform/feel/game_feedback.dart';
import 'package:attune/features/games/platform/feel/game_letter_tiles.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_backdrop.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where every game ends.
///
/// A headline, one word spelled in tiles, the players' names, and whatever
/// the game wants to say about how it went. It names the two people who
/// played rather than scoring either of them.
class GameCompleteScreen extends ConsumerStatefulWidget {
  const GameCompleteScreen({
    super.key,
    required this.theme,
    required this.headline,
    required this.word,
    required this.onBackToGames,
    this.names = const [],
    this.summary,
    this.onPlayAgain,
  });

  final GameTheme theme;

  /// The line over the tiles, such as "This or That".
  final String headline;

  /// The word spelled in tiles, such as "COMPLETE".
  final String word;

  /// Who played. Joined with an ampersand.
  final List<String> names;

  /// The game's own account of the result.
  final Widget? summary;

  /// Null hides Play again.
  final VoidCallback? onPlayAgain;

  final VoidCallback onBackToGames;

  @override
  ConsumerState<GameCompleteScreen> createState() => _GameCompleteScreenState();
}

class _GameCompleteScreenState extends ConsumerState<GameCompleteScreen> {
  @override
  void initState() {
    super.initState();
    // Once, when the screen arrives -- not on every rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(gameFeedbackProvider).fire(GameEvent.complete);
    });
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.names.where((name) => name.trim().isNotEmpty).toList();

    return Scaffold(
      backgroundColor: GameTheme.ground,
      body: GameBackdrop(
        theme: widget.theme,
        child: SafeArea(
          child: AppContentWidth(
            maxWidth: ContentWidth.form,
            child: Column(
              children: [
                Expanded(
                  // Centred when it fits, scrolling when it does not.
                  child: LayoutBuilder(
                    builder:
                        (context, box) => SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: box.maxHeight,
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: _content(names),
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.onPlayAgain != null) ...[
                        GamePrimaryButton(
                          label: GameStrings.playAgain,
                          icon: Icons.replay_rounded,
                          onTap: widget.onPlayAgain,
                        ),
                        const SizedBox(height: 12),
                      ],
                      GameSecondaryButton(
                        label: GameStrings.backToGames,
                        onTap: widget.onBackToGames,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(List<String> names) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 12),
        GameLetterTiles(word: widget.word, tileSize: 36),
        if (names.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(
            names.join(' & '),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
        if (widget.summary != null) ...[
          const SizedBox(height: 20),
          widget.summary!,
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests and the analyzer**

Run: `flutter test test/features/games/platform/game_complete_test.dart`

Expected: `All tests passed!` — 12 tests (game_complete_test.dart 12). No "would not hit test" warnings.

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/platform/shell/game_complete_screen.dart test/features/games/platform/game_complete_test.dart
git commit -m "feat(games): game completion screen (platform phase 1, task 11)"
```


---

### Task 12: The whole path, and the pictures

A demo game built from nothing but the shell, walked from the landing page to
the end and back with real navigation; then a picture of every shell screen
on a phone, a large phone and a tablet.

**Files:**

- Create: `test/features/games/platform/game_shell_flow_test.dart`
- Create: `test/features/games/platform/game_shell_golden_test.dart`
- Create: `test/features/games/platform/goldens/` (22 PNGs, generated in Step 3)

**What to know before writing it:**

- The pictures are for looking at. A golden compared only to itself proves the screen did not change, not that it was ever right.
- They are compared on macOS only (`skip: !Platform.isMacOS`). Text rasterises differently on the Linux CI machine. Do not remove the skip to "make CI cover it".
- `loadGameTestFonts()` loads Roboto and the Material icons from the Flutter SDK cache, so the pictures show words rather than the test font's blocks.

- [ ] **Step 1: Write the flow test and run it**

`test/features/games/platform/game_shell_flow_test.dart`

```dart
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/feel/game_feedback.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/shell/game_complete_screen.dart';
import 'package:attune/features/games/platform/shell/game_how_to_play_sheet.dart';
import 'package:attune/features/games/platform/shell/game_landing_screen.dart';
import 'package:attune/features/games/platform/shell/game_scaffold.dart';
import 'package:attune/features/games/platform/shell/game_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';

/// A game with no rules at all, built from nothing but the shell.
///
/// If the pieces only work one at a time, the first real game to use them
/// finds out. This walks the whole path a player takes -- landing, play,
/// settings, the end, and back -- with real navigation between them.
class _DemoLanding extends StatelessWidget {
  const _DemoLanding({required this.definition});

  final GameDefinition definition;

  @override
  Widget build(BuildContext context) {
    return GameLandingScreen(
      definition: definition,
      state: const GameLandingState(status: GameLandingStatus.fresh),
      onHowToPlay: () => showGameHowToPlay(context, definition: definition),
      onPrimary:
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _DemoPlay(definition: definition),
            ),
          ),
    );
  }
}

class _DemoPlay extends ConsumerWidget {
  const _DemoPlay({required this.definition});

  final GameDefinition definition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GameScaffold(
      theme: definition.theme,
      title: 'Round 1',
      subtitle: definition.title,
      onSettings:
          () => showGameSettingsSheet(
            context,
            definition: definition,
            onLeaveGame: () {
              // Close the sheet, then leave the game.
              Navigator.of(context)
                ..pop()
                ..pop();
            },
          ),
      body: Center(
        child: GameTile(
          semanticLabel: 'Finish',
          onTap: () {
            ref.read(gameFeedbackProvider).fire(GameEvent.place);
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder:
                    (context) => GameCompleteScreen(
                      theme: definition.theme,
                      headline: definition.title,
                      word: 'DONE',
                      names: const ['Ama', 'Kofi'],
                      onBackToGames: () => Navigator.of(context).pop(),
                    ),
              ),
            );
          },
          child: const Text('Finish'),
        ),
      ),
    );
  }
}

void main() {
  Future<FakeSoundService> start(WidgetTester tester) async {
    useSurface(tester, phone);
    final sound = FakeSoundService();
    await tester.pumpWidget(
      gameHost(
        _DemoLanding(definition: demoGame(withSettings: true)),
        prefs: await testPrefs(),
        sound: sound,
      ),
    );
    await tester.pump();
    return sound;
  }

  testWidgets('a player can go from the landing page to the end and back', (
    tester,
  ) async {
    final sound = await start(tester);
    expect(find.byType(GameLandingScreen), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Round 1'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Finish'));
    await tester.pumpAndSettle();
    expect(find.byType(GameCompleteScreen), findsOneWidget);
    expect(find.text('Ama & Kofi'), findsOneWidget);
    expect(sound.played, [AppSound.gameAnswer, AppSound.gameComplete]);

    await tester.tap(find.text('Back to games'));
    await tester.pumpAndSettle();
    expect(find.byType(GameLandingScreen), findsOneWidget);
    expect(find.byType(GameCompleteScreen), findsNothing);
  });

  testWidgets('how to play opens over the landing page and closes back to it', (
    tester,
  ) async {
    await start(tester);

    await tester.tap(find.bySemanticsLabel('How to play'));
    await tester.pumpAndSettle();
    expect(find.text('1. Tap a tile to pick it.'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byType(GameHowToPlaySheet), findsNothing);
    expect(find.byType(GameLandingScreen), findsOneWidget);
  });

  testWidgets('sound switched off in settings silences the rest of the game', (
    tester,
  ) async {
    final sound = await start(tester);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(GameSettingsSheet), findsNothing);

    await tester.tap(find.bySemanticsLabel('Finish'));
    await tester.pumpAndSettle();

    // The first test is the control: the same taps with sound on play two
    // sounds.
    expect(find.byType(GameCompleteScreen), findsOneWidget);
    expect(sound.played, isEmpty);
  });

  testWidgets('Leave game in settings returns to the landing page', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    // With the game's own tab in the row, Support starts past the edge.
    await tester.ensureVisible(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Support'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave game'));
    await tester.pumpAndSettle();

    expect(find.byType(GameSettingsSheet), findsNothing);
    expect(find.text('Round 1'), findsNothing);
    expect(find.byType(GameLandingScreen), findsOneWidget);
  });
}
```

Run: `flutter test test/features/games/platform/game_shell_flow_test.dart`

Expected: `All tests passed!` — 4 tests. Every piece it uses already exists, so this one passes first time; if it does not, a piece from an earlier task does not compose and that task is where the fix belongs.

- [ ] **Step 2: Write the golden test**

`test/features/games/platform/game_shell_golden_test.dart`

```dart
import 'dart:io';

import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_coach.dart';
import 'package:attune/features/games/platform/shell/game_complete_screen.dart';
import 'package:attune/features/games/platform/shell/game_how_to_play_sheet.dart';
import 'package:attune/features/games/platform/shell/game_landing_screen.dart';
import 'package:attune/features/games/platform/shell/game_scaffold.dart';
import 'package:attune/features/games/platform/shell/game_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';

/// Pictures of the shell, on a phone, a large phone and a tablet.
///
/// These are for looking at. A golden that only ever gets compared to
/// itself proves the screen did not change, not that it was ever right:
/// open the PNGs when they are regenerated.
void main() {
  setUpAll(loadGameTestFonts);

  // Text is drawn slightly differently on each operating system, so a
  // picture made on a Mac does not match pixel for pixel on the Linux CI
  // machine. These are compared where they are made. Everything a golden
  // would catch that a machine can check -- ink colour, layout, overflow --
  // has its own test that runs everywhere.
  final comparedHere = Platform.isMacOS;

  final coachTarget = GlobalKey();

  Widget play({bool coach = false}) {
    final board = Center(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (final (i, letter) in 'ATTUNE'.split('').indexed)
            SizedBox(
              key: i == 2 ? coachTarget : null,
              width: 68,
              height: 73,
              child: GameTile(
                onTap: () {},
                selected: i == 4,
                color: i == 4 ? GameColors.wordHunt : GameTheme.tile,
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: i == 4 ? Colors.white : GameTheme.tileInk,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return GameScaffold(
      theme: const GameTheme(primary: GameColors.wordHunt),
      title: 'Round 3 of 10',
      subtitle: 'Tile Tutorial',
      onSettings: () {},
      actions: [
        GameRoundButton(
          icon: Icons.lightbulb_outline_rounded,
          semanticLabel: 'Hint',
          caption: 'Hint',
          onTap: () {},
        ),
        GameRoundButton(
          icon: Icons.undo_rounded,
          semanticLabel: 'Undo',
          caption: 'Undo',
          onTap: () {},
        ),
      ],
      body:
          coach
              ? GameCoach(
                gameType: 'demo',
                steps: [
                  GameCoachStep(
                    text: 'Tap a tile to pick it.',
                    target: coachTarget,
                  ),
                ],
                child: board,
              )
              : board,
    );
  }

  Widget sheetHost(Future<void> Function(BuildContext) open) => Builder(
    builder:
        (context) => GameLandingScreen(
          definition: demoGame(withSettings: true),
          state: const GameLandingState(status: GameLandingStatus.fresh),
          onPrimary: () => open(context),
        ),
  );

  final screens = <String, ({Widget Function() build, bool opensSheet})>{
    'landing_fresh': (
      build:
          () => GameLandingScreen(
            definition: demoGame(),
            state: const GameLandingState(status: GameLandingStatus.fresh),
            onPrimary: () {},
            onHowToPlay: () {},
          ),
      opensSheet: false,
    ),
    'landing_waiting': (
      build:
          () => GameLandingScreen(
            definition: demoGame(color: GameColors.truthOrDare),
            state: const GameLandingState(
              status: GameLandingStatus.waiting,
              partnerName: 'Ama',
              caption: 'Round 3 of 10',
              canRemind: true,
            ),
            onPrimary: () {},
            onRemind: () {},
            onHowToPlay: () {},
          ),
      opensSheet: false,
    ),
    'play': (build: play, opensSheet: false),
    'play_coach': (build: () => play(coach: true), opensSheet: false),
    'settings': (
      build:
          () => sheetHost(
            (context) => showGameSettingsSheet(
              context,
              definition: demoGame(withSettings: true),
              onHowToPlay: () {},
              onLeaveGame: () {},
            ),
          ),
      opensSheet: true,
    ),
    'how_to_play': (
      build:
          () => sheetHost(
            (context) => showGameHowToPlay(context, definition: demoGame()),
          ),
      opensSheet: true,
    ),
    'complete': (
      build:
          () => GameCompleteScreen(
            theme: const GameTheme(primary: GameColors.thisOrThat),
            headline: 'This or That',
            word: 'COMPLETE',
            names: const ['Ama', 'Kofi'],
            summary: const Text(
              'You matched on 7 of 10.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            onPlayAgain: () {},
            onBackToGames: () {},
          ),
      opensSheet: false,
    ),
  };

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    for (final MapEntry(key: surface, value: size) in goldenSurfaces.entries) {
      testWidgets('$name on a $surface', (tester) async {
        useSurface(tester, size);
        await tester.pumpWidget(
          gameHost(screen.build(), prefs: await testPrefs()),
        );
        await tester.pumpAndSettle();
        if (screen.opensSheet) {
          await tester.tap(find.byType(GamePrimaryButton));
          await tester.pumpAndSettle();
        }

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/shell_$name.$surface.png'),
        );
      }, skip: !comparedHere);
    }
  }

  testWidgets('landing at the largest text size on a phone', (tester) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameHost(
        GameLandingScreen(
          definition: demoGame(),
          state: const GameLandingState(status: GameLandingStatus.yourTurn),
          onPrimary: () {},
          onHowToPlay: () {},
        ),
        prefs: await testPrefs(),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/shell_landing_large_text.phone.png'),
    );
  }, skip: !comparedHere);
}
```

- [ ] **Step 3: Generate the pictures**

Run: `flutter test test/features/games/platform/game_shell_golden_test.dart --update-goldens`

Expected: `All tests passed!` — 22 tests, and `ls test/features/games/platform/goldens | wc -l` prints `22`.

- [ ] **Step 4: Open the pictures and look at them**

Open every `.phone.png`, plus `shell_landing_fresh.tablet.png`, `shell_complete.tablet.png` and `shell_landing_large_text.phone.png`. Each should match this:

| File | What it should show |
|---|---|
| `shell_landing_fresh.*.png` | Green fading to near-black. Back and ? at the top, PLAY in four white tiles, "STARTER PACK", the title in large white, the tagline, a white Play pill, then three numbered rows each with a white play disc. Every word is readable. |
| `shell_landing_waiting.*.png` | Red. The button reads "Waiting for Ama" and is dimmed. Under it "ROUND 3 OF 10", then an outlined "Send a reminder". |
| `shell_play.*.png` | Header: back, "Tile Tutorial" over "Round 3 of 10", gear. Six tiles spelling ATTUNE with the N tile filled green. Hint and Undo with captions at the bottom right. |
| `shell_play_coach.*.png` | As above, with the bubble directly under the header (not covering it), a white ring around the third tile and a hand at its corner. |
| `shell_settings.*.png` | A sheet over the dimmed landing page: "Settings", a close button, tabs General / Tile Tutorial / Support with General underlined, two cards with green switches. |
| `shell_how_to_play.*.png` | A sheet: "How to play", three numbered rules, a white "Got it" pill. |
| `shell_complete.*.png` | Orange. "This or That", COMPLETE in eight tiles, "Ama & Kofi", "You matched on 7 of 10." — together in the middle of the screen, not pinned to the top. Play again and Back to games at the bottom. |
| `shell_landing_large_text.phone.png` | Everything at twice the size, nothing clipped or overlapping; the letters in the PLAY tiles are the same size as at normal text. |
| `*.tablet.png` | The same content in a centred column about 550 wide, not stretched across the screen. |

For every picture check: no dark text on the dark ground; no word clipped; no element overlapping another; proportions that look like a phone screen, not a stretched one. If anything is wrong, fix the widget in the task that owns it, add a test that fails without the fix, and regenerate. Report what you saw, picture by picture, in your task report — "looks right" is not a report.

- [ ] **Step 5: Run without `--update-goldens`**

Run: `flutter test test/features/games/platform/game_shell_golden_test.dart`

Expected: `All tests passed!` — 22 tests.

- [ ] **Step 6: Commit**

```bash
git add test/features/games/platform/game_shell_flow_test.dart test/features/games/platform/game_shell_golden_test.dart test/features/games/platform/goldens
git commit -m "test(games): shell flow test and phone-pinned goldens (platform phase 1, task 12)"
```


---

### Task 13: Close the phase

No new code. Confirm the phase did what it said and nothing else.

- [ ] **Step 1: Run every platform test**

Run: `flutter test test/features/games/platform`

Expected: `All tests passed!` — 136 tests.

- [ ] **Step 2: Run the suites around it**

Run: `flutter test test/features/games test/core/ui`

Expected: `All tests passed!` — 887 tests (the 751 that were there before, plus 136). If one of the known flakes fails, re-run that file on its own.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/games/platform test/features/games/platform`

Expected: `No issues found!`

Run: `flutter analyze lib/features/games test/features/games`

Expected: `102 issues found.` — the same 102 that were there before this phase, all in older files. A higher number means this phase added one.

- [ ] **Step 4: Confirm nothing else changed**

Run: `git diff --stat 9207703b -- . ':!lib/features/games/platform' ':!test/features/games/platform' ':!docs'`

Expected: no output.

Run: `grep -rnE "[0-9)]\.(w|h|r|sp)\b" lib/features/games/platform; grep -rnE "MaskFilter|saveLayer|BackdropFilter|ImageFilter|Opacity\(" lib/features/games/platform`

Expected: no output from either (no ScreenUtil units, no blur, no `Opacity` widget).

- [ ] **Step 5: Report**

Report the test counts, the analyzer result, and that the diff outside the two directories is empty. Phase 2's plan is written next; nothing merges to `main`.

---

## Review focus

For whoever reviews a task or the phase:

1. **Tests that cannot fail.** A loop or filter over a collection that might be empty; an assertion of absence with no positive control; a finder that matches the container rather than what moved. For any test you doubt, break the code it guards and see whether it goes red.
2. **Missed taps.** No `warnIfMissed: false` except the one disabled-button test in `game_landing_test.dart`, and `useSurface` still sets `hitTestWarningShouldBeFatal`.
3. **Screen readers.** Every hand-built control: `container: true`, a label, and an `onTap` on the `Semantics` itself.
4. **Text colour.** No `Material` below `GameBackdrop`. Every screen with text on the ground has an `inkOnGround` test.
5. **The pictures.** Open them. Compare with the table in Task 12.
6. **Scope.** Nothing outside the two directories. No ScreenUtil. No blur.

## What phase 1 leaves for later

- No route, hub, or real game uses the shell yet (phase 2).
- The tablet layout is a capped, top-anchored column. Whether the lower half of a tall tablet wants more is a judgement for the device gate.
- Sounds are still the synthesized placeholders; a licensed pack replaces files, not code.
- The shell's text is English-only until the `.arb` files are free to edit.
