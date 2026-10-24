# Stories Wave 3 — The App Shell Keeps the App Mounted Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the privacy cover and the Safety lock's return check from tearing down the Router and Navigator, so pushed routes, sheets, dialogs, scroll positions, the story reel and camera, and in-progress posts survive inactive/resume and app switches. Media, cameras, recordings and read receipts must still stop while Attune is not on screen.

**Architecture:**
- `AppPrivacyCover`, and `SafetyLockGate` while it checks a return, wrap the app in one new widget, `KeepMountedCover`: `Stack[Offstage(offstage: obscured) > TickerMode(enabled: !obscured) > ExcludeSemantics(excluding: obscured) > child, if (obscured) cover]`. The tree has the same shape whether or not it is obscured, so the child's State is never rebuilt. The PIN `locked` state is still a full replacement, and a cold-start `checking` still builds nothing.
- Nothing is unmounted any more when Attune leaves the screen. A new core provider, `appContentVisibleProvider`, is the one signal for "Attune's content is on screen right now": the lifecycle is `resumed` (read in the lifecycle callback itself, not from a frame) **and** the lock is open (pushed in by `SafetyLockGate`). Every player, camera, recorder and read-receipt path that must stop when unseen listens to it.
- One small helper, `VisibleOnlyPlayback`, covers the video players that start on their own.

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), flutter_riverpod 2.6.1, go_router, video_player 2.10.1 (its own `_VideoAppLifeCycleObserver` pauses only on `paused`, and auto-resumes on `resumed`), camera 0.11, record 6 (via `VoiceRecorderService`), audioplayers 6 (via `VoicePlaybackController`), flutter_test.

**Spec:**
- `docs/reviews/2026-10-23-stories-robustness-review.md`: Wave 3 = S1, Critical/High row #16.
- `docs/reviews/2026-10-23-stories-review/07b_verification_server.md`: §1a (V7 evidence), the G7 fix design, and the five "G7 regression risks".
- `docs/reviews/2026-10-23-stories-review/05_security_privacy.md`: finding #1.

## Global Constraints

- **This is core shell code above every route.** Every change is minimal, and each task names its regression risk. Touch only the files a task lists. No refactors beyond the lines shown.
- **Work in the main working tree on `main`.**
  - The user has unrelated uncommitted edits. Wave 1 (reel) and Wave 2 (posting/camera) story work is also uncommitted.
  - Never revert, stash, stage, `git checkout` or reformat any of it.
  - Files this plan edits that are already dirty (edit surgically; keep every existing line you do not need to change):
    - `lib/features/chat/presentation/screens/chat_screen.dart` (user)
    - `lib/features/chat/presentation/screens/capture_camera_screen.dart` (Wave 2)
    - `lib/features/stories/presentation/screens/story_camera_screen.dart` (Wave 2)
    - `lib/features/stories/presentation/screens/story_reel_screen.dart` (Wave 1)
    - `test/features/stories/capture_camera_test.dart` (Wave 2)
    - `test/features/stories/story_reel_test.dart` (Wave 1)
    - `test/features/stories/story_review_test.dart` (untracked, Wave 2)
- **No commits.** Every "Commit" step of the standard template is replaced by "Run tests". Nothing is staged.
- **Never `dart format` a pre-existing file.** The repo uses an older formatter, and formatting reflows whole files. Run `dart format` only on files this plan creates (marked "Create").
- **TDD.** Write the test, run it, and **see it fail** (or fail to compile) before writing production code. A test that already passes is labelled "regression guard" and says why.
- **State via Riverpod.** No new dependencies. `video_player_platform_interface` is already a direct dependency (`pubspec.yaml:217`).
- **Design tokens:** spacing uses `Spacing.*` (`lib/app/theme/design_tokens.dart`). Copy is plain English, sentence case.
- **SQL:** none.
- **End state:** the whole-suite `flutter test` is green, and `flutter analyze` shows no new issue in any touched file.

## Review Focus

Five conditions the spec implies but does not spell out, most likely first. Each is pinned by a test in its owning task.

1. **A return that ends at the PIN screen (PIN "every open").**
   - Between resume and the lock decision, nothing may play sound, re-open the camera, mark a message read or show presence. Before this wave that window was safe only because everything was unmounted.
   - Tests: Task 3 (the signal never reads "visible" during the check), Task 6 (ephemeral clip), Task 7 (review preview), Task 9 (reel and streak viewer), Task 10 (camera), Task 11 (read receipts).
2. **The iOS first-use permission alert is an `inactive`.**
   - Camera, microphone and location prompts all trigger it. The story camera route and its review must survive it.
   - A voice recording that is still starting behind the microphone alert must not be cut.
   - Tests: Task 2 (a pageless route survives `inactive`) and Task 8 (a start in flight is left alone).
3. **The keyboard is up when Control Centre is pulled down.** A focused composer keeps its text and its focus across `inactive → resumed`. Test: Task 2.
4. **Quick exit right after a return.**
   - Kept routes and sheets go with the decoy; nothing comes back.
   - With a PIN, the next return shows only the lock, and unlocking leaves the decoy.
   - Test: Task 4.
5. **A notification tapped from Notification Centre while Attune is in the foreground.**
   - This is `inactive` only, with the lock open. Before this wave the Navigator was unmounted, so the tap was parked in `_pendingTap` with nothing to replay it.
   - Now the Navigator stays mounted and the tap navigates behind the cover, while deferral during the lock check is still keyed on the lock state.
   - Test: Task 4.

## Spec rulings made by this plan

- **What stays a full replacement:**
  - `locked` still swaps the app out for `PinLockScreen`. After unlock, pages are rebuilt fresh and pageless routes are gone. This is secure and deliberate.
  - A **cold-start** `checking` still builds nothing (review I5): keep-mounted applies only to a subtree that has already been shown since the last lock.
- **The single visibility signal:**
  - It is `appContentVisibleProvider` in `lib/core/services/app_content_visibility.dart`.
  - The lock half is *pushed* by `SafetyLockGate` (`setLockOpen`), so core never imports the safety feature, and a test without the gate sees only the lifecycle.
  - It is decided in the lifecycle callback, because iOS can go `inactive → hidden` before another frame is drawn, so a frame-driven signal (TickerMode) would miss the pause.
- **Media policy:**
  - Everything with sound pauses in every state but `resumed`. `inactive` is included: the cover is up from `inactive` on.
  - This overrides the streak viewer's documented "inactive alone leaves it playing", which never ran in practice because the cover unmounted the viewer.
  - Full-screen viewers resume on return only once the lock is open: the story reel, the streak viewer, the ephemeral video viewer, and the story and streak review previews.
  - Inline chat videos and voice notes stay paused; a tap plays them again (as WhatsApp does).
  - Pausing at `inactive` also stops video_player's own auto-resume, which only resumes what was playing at `paused`.
- **Voice recording in progress when Attune leaves the screen:**
  - It is locked (if it was still held) and paused. It is kept for the person to resume, send or delete, and is never sent or discarded by a blip.
  - This matches Wave 2's "an interrupted take is kept" ruling for the camera.
  - A recording still starting (the first-use microphone alert) is left alone.
- **Shared camera:** Wave 2's release-on-inactive is kept as it is. Only the re-open waits for the signal.
- **Read receipts and presence** wait for the lock to open, as well as for `resumed`.
- **Understand sheet:**
  - Its result is still cleared on `inactive` / `hidden` (spec §6.3).
  - The open sheet now shows "This read was cleared when you left Attune, to keep it private." with **Read it again**. Nothing is re-requested on its own: the person may have handed the phone over, and each read costs an AI call.
- **Ask Attune drafts** now survive a blip. No spec clears them on lifecycle; they were only lost to the teardown.
- **Notification taps:**
  - `shouldDeferNotificationTap` is unchanged, and stays keyed on the lock state.
  - While only the cover is up, a tap now navigates behind it instead of waiting forever.
- **`RelationshipLifecycleWatcher` relied on the remount.**
  - Its test says "A fresh mount, as after every resume". The remount ran `_check()` on every return; without it, the lock-reopen listener's 5-minute throttle would hide an ending for up to 5 minutes.
  - It now forces the check on each lock reopen, which keeps today's behaviour of one lifecycle read per return (Task 5).
- **Dead code: nothing is removed.**
  - `message_bubble.dart:1897-1906` (`route.completed` frees the row when a Navigator is torn down) is still reachable: the PIN lock replaces the tree, and quick exit `go`es.
  - `story_camera_screen.dart`'s dispose cleanup of the review take, chat's persisted drafts, and the streak viewer's spend-at-teardown are still needed for kill, lock and quick exit.
  - Only the comments that claim the subtree is unmounted are corrected: `safety_lock_controller.dart:116-119`, `app_privacy_cover.dart:57-62`, `safety_lock_gate.dart:8-11`, `app_shell.dart:13-14`, and the two test comments in `relationship_lifecycle_watcher_test.dart`.
- **Out of scope:**
  - `EphemeralCameraScreen` has its own `CameraController` with no lifecycle handling, but no caller navigates to it (`grep -rn ephemeralCamera lib` finds only the route). It is not touched, and is reported to the owner.
  - `VideoTrimScreen` never calls `play()`.
  - `_prepareAndEnqueue` "without mounted" was done by Wave 2 Task 16 (`StoryPostPipeline`). Task 13 verifies it.

## Regression risks (highest first)

1. **Freshness after a long background.**
   - Before this wave, every return re-created every `autoDispose` provider the screens watched, so data refetched "for free".
   - These surfaces already refetch on resume by themselves:
     - Chat (`onAppResumed`);
     - Together and Timeline (`togetherChangeSignalProvider` has an `onResume` emit);
     - Planning (`planningChangeSignalProvider`);
     - Stories (`story_providers.dart` lifecycle);
     - Home (observer);
     - presence; the couple map; games; feature flags; both outboxes.
   - **No resume or realtime refresh:** `appreciationJarProvider`, `winCardsProvider`, `quietStateProvider`, `pulse` and the reflection journal. These may now show data from before the switch until the person navigates.
   - No blanket refresh is added (it would also refetch on every Control Centre pull). Task 13's device check lists them, and any one found stale is a separate follow-up.
2. **Shell widgets that ran code on remount:**
   - `RelationshipLifecycleWatcher` is fixed in Task 5.
   - `NewDeviceWatcher` is a non-autoDispose Notifier already driven by lock reopen (unaffected).
   - `QuickExitZone` and `ShareIntakeListener` have no remount logic.
3. **Above every route, everything runs offstage while covered.**
   - It still lays out, and timers keep running; tickers are muted.
   - A route transition in flight finishes after resume.
   - A widget that starts sound from a `Timer` with no visibility check would now sound behind the cover. The audit in Tasks 6–10 covers every `VideoPlayerController`, `CameraController`, `AudioRecorder` and voice `AudioPlayer` in `lib/`.
4. **Keyboard and focus.** A focused field keeps focus, so the keyboard comes back on resume instead of being dismissed. This is intended (Review Focus 3), but it is a visible change.
5. **Screen readers.** VoiceOver/TalkBack focus is lost while covered (`ExcludeSemantics`) and lands on the first element on return. This is the same as before, when the subtree was rebuilt.

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `lib/core/services/app_content_visibility.dart` (create) | `AppContentVisibility` notifier + `appContentVisibleProvider` | 1 |
| `lib/core/widgets/keep_mounted_cover.dart` (create) | `KeepMountedCover` | 2 |
| `lib/core/services/app_privacy_cover.dart` (modify) | Cover keeps the child mounted; comments | 2 |
| `lib/features/safety/presentation/widgets/safety_lock_gate.dart` (modify) | Return check keeps a shown subtree mounted; pushes lock state; doc | 3 |
| `lib/features/safety/presentation/safety_lock_controller.dart` (modify, comment only) | Stale "unmounts" comment | 3 |
| `lib/app/app_shell.dart` (modify, comment only) | Shell doc | 3 |
| `lib/features/relationships/presentation/widgets/relationship_lifecycle_watcher.dart` (modify) | Force the check on every lock reopen | 5 |
| `lib/core/services/media/visible_only_playback.dart` (create) | `VisibleOnlyPlayback` | 6 |
| `lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart` (modify) | Plays only while visible | 6 |
| `lib/features/chat/presentation/widgets/video_message_player.dart` (modify) | Pauses when hidden | 6 |
| `lib/features/stories/presentation/screens/story_camera_screen.dart` (modify) | Review preview plays only while visible | 7 |
| `lib/features/chat/presentation/screens/streak_camera_screen.dart` (modify) | Review preview plays only while visible | 7 |
| `lib/features/chat/presentation/state/voice_playback_controller.dart` (modify) | Pause on every non-resumed state | 8 |
| `lib/features/chat/presentation/widgets/chat_text_field.dart` (modify) | Recording in progress: lock + pause on leave | 8 |
| `lib/features/stories/presentation/screens/story_reel_screen.dart` (modify) | Foreground = visibility signal | 9 |
| `lib/features/chat/presentation/screens/streak_viewer_screen.dart` (modify) | Away = not visible | 9 |
| `lib/features/chat/presentation/screens/capture_camera_screen.dart` (modify) | Re-open only when visible | 10 |
| `lib/features/chat/presentation/screens/chat_screen.dart` (modify) | View-active needs the lock open | 11 |
| `lib/features/ai_assistant/presentation/providers/ai_assistant_providers.dart` (modify) | `clearedWhileAway` | 12 |
| `lib/features/ai_assistant/presentation/screens/understand_sheet.dart` (modify) | Idle "Read it again" state | 12 |
| `test/helpers/state_probe.dart` (create) | `StateProbe`, `semanticLabels` | 2 |
| `test/helpers/recording_video_platform.dart` (create) | `RecordingVideoPlatform` | 6 |
| `test/core/services/app_content_visibility_test.dart` (create) | Task 1 | 1 |
| `test/core/services/app_privacy_cover_test.dart` (modify, add a group) | Task 2 | 2 |
| `test/app/app_shell_keep_mounted_test.dart` (create) | Shell integration | 2, 3, 4 |
| `test/features/safety/safety_lock_gate_test.dart` (modify, add a group) | Task 3 | 3 |
| `test/features/relationships/relationship_lifecycle_watcher_test.dart` (modify) | Task 5 | 5 |
| `test/core/services/media/visible_only_playback_test.dart` (create) | Task 6 | 6 |
| `test/features/chat/media_visibility_test.dart` (create) | Ephemeral viewer + inline video | 6 |
| `test/features/stories/story_review_test.dart` (modify, add a test) | Task 7 | 7 |
| `test/features/chat/voice_playback_controller_test.dart` (modify, add tests) | Task 8 | 8 |
| `test/features/chat/voice_record_away_test.dart` (create) | Task 8 | 8 |
| `test/features/stories/story_reel_test.dart` (modify, add a test) | Task 9 | 9 |
| `test/features/chat/streak_viewer_lifecycle_test.dart` (modify, add tests) | Task 9 | 9 |
| `test/features/stories/capture_camera_test.dart` (modify, add a test) | Task 10 | 10 |
| `test/features/chat/chat_screen_view_active_test.dart` (modify, add a test) | Task 11 | 11 |
| `test/features/ai_assistant/understand_sheet_test.dart` (modify, add a test) | Task 12 | 12 |

## Before you start

- [ ] **Baseline.** Run the suites this wave touches and record the pass counts. Everything must pass before Task 1. If anything already fails, stop and report it; do not fix it under this plan.

```bash
cd /Users/user/attune
flutter test test/core/services test/app test/features/safety test/features/relationships \
  test/features/ai_assistant test/features/stories test/features/chat test/core/notifications
```
Expected: all pass.

---

### Task 1: One signal for "Attune's content is on screen" (`appContentVisibleProvider`)

**Regression risk:** none on its own. It is a new provider that nothing reads until later tasks.

**Files:**
- Create: `lib/core/services/app_content_visibility.dart`
- Test: `test/core/services/app_content_visibility_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class AppContentVisibility extends Notifier<bool>` with `void setLockOpen(bool open)`.
  - `final appContentVisibleProvider = NotifierProvider<AppContentVisibility, bool>(...)`. Its value is `true` only when the lifecycle is `resumed` (or `null`, as in some tests) **and** the last `setLockOpen` was `true` (default `true`).
  - Values change synchronously inside the lifecycle callback and inside `setLockOpen`, and equal values are not re-emitted.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/services/app_content_visibility_test.dart
// Stories Wave 3: the shell keeps the app mounted behind the privacy cover
// and the Safety lock check, so anything that must stop when unseen asks
// this one signal instead of relying on being unmounted.
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void go(WidgetTester t, List<AppLifecycleState> states) {
    for (final s in states) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
  }

  ProviderContainer container(WidgetTester t) {
    // Registered first so it runs last (LIFO), after the listener is gone.
    addTearDown(
      () => t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('on screen while resumed with the lock open', (t) async {
    final c = container(t);
    expect(c.read(appContentVisibleProvider), isTrue);
  });

  testWidgets('off screen in every state but resumed, decided in the '
      'lifecycle callback itself (no frame needed)', (t) async {
    final c = container(t);
    final seen = <bool>[];
    c.listen<bool>(
      appContentVisibleProvider,
      (_, v) => seen.add(v),
      fireImmediately: true,
    );
    go(t, [AppLifecycleState.inactive]);
    expect(
      c.read(appContentVisibleProvider),
      isFalse,
      reason: 'iOS can hide before another frame is drawn',
    );
    go(t, [AppLifecycleState.hidden, AppLifecycleState.paused]);
    expect(c.read(appContentVisibleProvider), isFalse);
    go(t, [AppLifecycleState.hidden, AppLifecycleState.inactive]);
    expect(c.read(appContentVisibleProvider), isFalse);
    go(t, [AppLifecycleState.resumed]);
    expect(c.read(appContentVisibleProvider), isTrue);
    expect(seen, [true, false, true], reason: 'one change each way');
  });

  testWidgets('a lock being checked keeps it off through a resume; opening '
      'the lock shows the app', (t) async {
    final c = container(t);
    final seen = <bool>[];
    c.listen<bool>(
      appContentVisibleProvider,
      (_, v) => seen.add(v),
      fireImmediately: true,
    );
    go(t, [AppLifecycleState.inactive]);
    c.read(appContentVisibleProvider.notifier).setLockOpen(false);
    go(t, [AppLifecycleState.resumed]);
    expect(c.read(appContentVisibleProvider), isFalse);
    c.read(appContentVisibleProvider.notifier).setLockOpen(true);
    expect(c.read(appContentVisibleProvider), isTrue);
    expect(seen, [true, false, true]);
  });

  testWidgets('opening the lock while Attune is still not resumed does not '
      'show it', (t) async {
    final c = container(t);
    expect(c.read(appContentVisibleProvider), isTrue);
    go(t, [AppLifecycleState.inactive]);
    c.read(appContentVisibleProvider.notifier).setLockOpen(false);
    c.read(appContentVisibleProvider.notifier).setLockOpen(true);
    expect(c.read(appContentVisibleProvider), isFalse);
    go(t, [AppLifecycleState.resumed]);
    expect(c.read(appContentVisibleProvider), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/services/app_content_visibility_test.dart`
Expected: FAIL (compile error: `app_content_visibility.dart` does not exist).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/services/app_content_visibility.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether Attune's content is on screen right now: the app is resumed (the
/// privacy cover is down) and the Safety lock is open (not checking, not
/// locked).
///
/// The shell keeps the app's subtree mounted behind the privacy cover and
/// during the lock's return check (stories Wave 3; 07b G7), so leaving the
/// screen no longer disposes anything. Whatever must stop when nobody can
/// see it -- media with sound, a camera, a recording, read receipts --
/// listens to this instead of relying on being unmounted.
///
/// The lifecycle half is decided in the lifecycle callback itself, not
/// from a rebuilt frame: iOS can go from inactive to hidden before another
/// frame is drawn. The lock half is pushed in by `SafetyLockGate`
/// ([setLockOpen]), so core does not depend on the safety feature and a
/// test without the gate sees only the lifecycle.
class AppContentVisibility extends Notifier<bool> {
  bool _lockOpen = true;

  @override
  bool build() {
    final listener = AppLifecycleListener(onStateChange: (_) => _sync());
    ref.onDispose(listener.dispose);
    return _compute();
  }

  bool _compute() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    return foreground && _lockOpen;
  }

  void _sync() {
    final next = _compute();
    if (next != state) state = next;
  }

  /// Called by `SafetyLockGate` on every lock state change: open, or not
  /// (checking a return, or locked).
  void setLockOpen(bool open) {
    _lockOpen = open;
    _sync();
  }
}

final appContentVisibleProvider =
    NotifierProvider<AppContentVisibility, bool>(AppContentVisibility.new);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart format lib/core/services/app_content_visibility.dart test/core/services/app_content_visibility_test.dart && flutter test test/core/services/app_content_visibility_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Run tests** (replaces Commit)

Run: `flutter analyze lib/core/services/app_content_visibility.dart test/core/services/app_content_visibility_test.dart`
Expected: No issues found.

---

### Task 2: The privacy cover keeps the app mounted (`KeepMountedCover`)

**Regression risk: HIGH (core shell, above every route).**
- After this task nothing under the cover is unmounted on `inactive`, `hidden` or `paused`.
- The snapshot stays safe, because `Offstage` never paints.
- Media keeps running until Tasks 6–10, so run Tasks 2–10 as one block before any device build.
- Pinned by `app_privacy_cover_test`, `understand_sheet_test:355-385` and `assistant_notice_test`, all of which must stay green unchanged.

**Files:**
- Create: `lib/core/widgets/keep_mounted_cover.dart`
- Create: `test/helpers/state_probe.dart`
- Create: `test/app/app_shell_keep_mounted_test.dart` (inactive group; Tasks 3 and 4 add groups)
- Modify: `lib/core/services/app_privacy_cover.dart:1-14` (header, one paragraph added) and `:55-71` (`build`)
- Test: `test/core/services/app_privacy_cover_test.dart` (add one group; existing tests unchanged)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `KeepMountedCover({Key? key, required bool obscured, required Widget cover, required Widget child})` (StatelessWidget).
  - `StateProbe(String label)`: a Scaffold whose centre `TextButton` reads `'$label $taps'`, where taps start at 0 for a fresh State.
  - `List<String> semanticLabels(WidgetTester tester)`.
  - The cover's overlay key stays `Key('app_privacy_cover_overlay')`.

- [ ] **Step 1: Write the test helpers (Create)**

```dart
// test/helpers/state_probe.dart
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// A screen whose State counts taps: "LABEL n". A fresh State shows 0, so a
/// test can tell a kept screen from a rebuilt one (stories Wave 3).
class StateProbe extends StatefulWidget {
  const StateProbe(this.label, {super.key});

  final String label;

  @override
  State<StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<StateProbe> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => setState(() => _taps++),
        child: Text('${widget.label} $_taps'),
      ),
    ),
  );
}

/// Every semantics label currently on screen. Call with semantics enabled
/// (`tester.ensureSemantics()`).
List<String> semanticLabels(WidgetTester tester) {
  final out = <String>[];
  void visit(SemanticsNode node) {
    out.add(node.label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  return out;
}
```

- [ ] **Step 2: Write the failing cover tests** (append inside `main()` of `test/core/services/app_privacy_cover_test.dart`, and add the import `import '../../helpers/state_probe.dart';`)

```dart
  group('kept mounted behind the cover (stories Wave 3; 07b G7)', () {
    const toBackground = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    const toForeground = [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ];

    testWidgets('the app keeps its State across inactive -> resumed and a '
        'full background', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AppPrivacyCover(child: StateProbe('APP'))),
      );
      await tester.tap(find.text('APP 0'));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('APP 1'), findsNothing, reason: 'not on screen');
      expect(
        find.text('APP 1', skipOffstage: false),
        findsOneWidget,
        reason: 'but still mounted',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('APP 1'), findsOneWidget, reason: 'same State');

      for (final s in [...toBackground, ...toForeground]) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
      expect(find.text('APP 1'), findsOneWidget);
    });

    testWidgets('while covered the app is not in semantics, not ticking and '
        'not tappable', (tester) async {
      final semantics = tester.ensureSemantics();
      bool? ticking;
      await tester.pumpWidget(
        MaterialApp(
          home: AppPrivacyCover(
            child: Builder(
              builder: (context) {
                ticking = TickerMode.of(context);
                return const StateProbe('APP');
              },
            ),
          ),
        ),
      );
      expect(ticking, isTrue);
      expect(semanticLabels(tester).any((l) => l.contains('APP 0')), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(ticking, isFalse, reason: 'animations stop behind the cover');
      expect(
        semanticLabels(tester).any((l) => l.contains('APP')),
        isFalse,
        reason: 'a screen reader cannot reach the hidden app',
      );
      await tester.tap(find.byKey(const Key('app_privacy_cover_overlay')));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(ticking, isTrue);
      expect(
        find.text('APP 0'),
        findsOneWidget,
        reason: 'a tap on the cover never reaches the app',
      );
      semantics.dispose();
    });
  });
```

- [ ] **Step 3: Write the failing shell tests (Create)** `test/app/app_shell_keep_mounted_test.dart`. Tasks 3 and 4 append groups to this file.

```dart
// Stories Wave 3 (07b G7): the privacy cover and the Safety lock's return
// check hide the app without unmounting it. Mirrors the real shell's order
// (SafetyLockGate > AppPrivacyCover > QuickExitZone > Router); the order is
// pinned against lib/app/app_shell.dart in Task 4's group.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/services/app_privacy_cover.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/safety/presentation/widgets/safety_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../helpers/state_probe.dart';

final _user = User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'a',
  createdAt: '2026-01-01T00:00:00Z',
);

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const StateProbe('HOME')),
    GoRoute(path: '/page', builder: (_, __) => const StateProbe('PAGE')),
    GoRoute(
      path: '/list',
      builder:
          (_, __) => Scaffold(
            body: ListView.builder(
              itemCount: 200,
              itemExtent: 50,
              itemBuilder: (_, i) => Text('Item $i'),
            ),
          ),
    ),
    GoRoute(
      path: RouteNames.neutralScreen,
      name: 'neutralScreen',
      builder: (_, __) => const Scaffold(body: Text('DECOY')),
    ),
  ],
);

/// The real quick-exit flag (prefs + keystore mocks), a real PIN store, and
/// a sign-out the test can count.
class _World {
  _World(this.router);
  final GoRouter router;
  bool signedIn = true;
  int signOuts = 0;
  final pins = SafetyPinStore(
    hasher: (p) async => hashPin(p, iterations: 1000),
    verifier: (p, e) async => verifyPinHash(p, e),
  );
  SafetyLockDeps get deps => SafetyLockDeps(
    quickExitFlag: QuickExitService.requiresSafetyUnlock,
    clearQuickExitFlag: QuickExitService.clearSafetyUnlockRequired,
    pins: pins,
    signOut: () async {
      signOuts++;
      signedIn = false;
    },
    signedIn: () => signedIn,
    leaveDecoy: () {
      final path = router.routerDelegate.currentConfiguration.uri.path;
      if (path == RouteNames.neutralScreen) router.go('/');
    },
  );
}

typedef _Shell = ({GoRouter router, _World w, ProviderContainer c});

Future<_Shell> _pump(WidgetTester t) async {
  final router = _router();
  final w = _World(router);
  final c = ProviderContainer(
    overrides: [
      safetyLockDepsProvider.overrideWithValue(w.deps),
      currentUserProvider.overrideWithValue(_user),
    ],
  );
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        routerConfig: router,
        builder:
            (context, child) => SafetyLockGate(
              child: AppPrivacyCover(
                child: QuickExitZone(router: router, child: child!),
              ),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (router: router, w: w, c: c);
}

NavigatorState _nav(_Shell s) =>
    s.router.routerDelegate.navigatorKey.currentState!;

const _blip = [AppLifecycleState.inactive, AppLifecycleState.resumed];
const _appSwitch = [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

Future<void> _drive(WidgetTester t, List<AppLifecycleState> states) async {
  for (final s in states) {
    t.binding.handleAppLifecycleStateChanged(s);
  }
  await t.pumpAndSettle();
}

/// Pushes the GoRouter page and a pageless route over it, one tap each.
Future<void> _openPageAndPageless(WidgetTester t, _Shell s) async {
  s.router.push('/page');
  await t.pumpAndSettle();
  await t.tap(find.text('PAGE 0'));
  await t.pump();
  _nav(s).push(
    MaterialPageRoute<void>(builder: (_) => const StateProbe('PAGELESS')),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('PAGELESS 0'));
  await t.pump();
}

/// Pops the pageless route: the page below must still be the kept one.
Future<void> _expectBothKept(WidgetTester t, _Shell s) async {
  expect(find.text('PAGELESS 1'), findsOneWidget);
  _nav(s).pop();
  await t.pumpAndSettle();
  expect(find.text('PAGE 1'), findsOneWidget);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('an inactive blip (Control Centre, a call, Face ID, a permission '
      'alert)', () {
    testWidgets('a GoRouter page and a pageless route keep their State', (
      t,
    ) async {
      final s = await _pump(t);
      await _openPageAndPageless(t, s);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(find.text('PAGELESS 1'), findsNothing, reason: 'covered');
      expect(find.text('PAGELESS 1', skipOffstage: false), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      await _expectBothKept(t, s);
    });

    testWidgets('a bottom sheet stays open and a list keeps its scroll', (
      t,
    ) async {
      final s = await _pump(t);
      s.router.push('/list');
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView), const Offset(0, -1000));
      await t.pumpAndSettle();
      expect(find.text('Item 0'), findsNothing);
      showModalBottomSheet<void>(
        context: _nav(s).context,
        builder: (_) => const SizedBox(height: 200, child: Text('SHEET')),
      );
      await t.pumpAndSettle();
      await _drive(t, _blip);
      expect(find.text('SHEET'), findsOneWidget);
      _nav(s).pop();
      await t.pumpAndSettle();
      expect(find.text('Item 0'), findsNothing, reason: 'scroll kept');
      expect(find.text('Item 20'), findsOneWidget);
    });

    testWidgets('a focused text field keeps its text and its focus '
        '(Review Focus 3)', (t) async {
      final s = await _pump(t);
      _nav(s).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: TextField(autofocus: true)),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'half a thought');
      await _drive(t, _blip);
      expect(find.text('half a thought'), findsOneWidget);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `flutter test test/core/services/app_privacy_cover_test.dart test/app/app_shell_keep_mounted_test.dart`
Expected:
- The 4 existing cover tests PASS.
- The 2 new cover tests FAIL: "APP 1 … skipOffstage: false" finds nothing, and `ticking` stays `true`.
- The 3 shell tests FAIL ("PAGELESS 1" not found after resume).

- [ ] **Step 5: Write `KeepMountedCover` (Create)**

```dart
// lib/core/widgets/keep_mounted_cover.dart
import 'package:flutter/widgets.dart';

/// Shows [cover] over [child] while [obscured], without unmounting [child]
/// (stories Wave 3; 07b G7). The child keeps its State -- the Router, its
/// pages and pageless routes, sheets, dialogs, scroll positions and text
/// fields -- across an incoming call, Control Centre or an app switch.
///
/// While obscured the child is Offstage (laid out, but never painted or
/// hit-tested, so an OS snapshot and default finders see only the cover),
/// under TickerMode(false) (its animations stop) and ExcludeSemantics (a
/// screen reader cannot reach it). Media, cameras, recordings and read
/// receipts still have to stop themselves: see appContentVisibleProvider.
///
/// The tree has the same shape whether or not [obscured], so toggling it
/// never rebuilds [child]'s State.
class KeepMountedCover extends StatelessWidget {
  const KeepMountedCover({
    super.key,
    required this.obscured,
    required this.cover,
    required this.child,
  });

  final bool obscured;
  final Widget cover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // Non-directional, so it needs no Directionality above the Router.
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: obscured,
          child: TickerMode(
            enabled: !obscured,
            child: ExcludeSemantics(excluding: obscured, child: child),
          ),
        ),
        if (obscured) cover,
      ],
    );
  }
}
```

- [ ] **Step 6: Use it in `AppPrivacyCover`**

In `lib/core/services/app_privacy_cover.dart`, add `import 'package:attune/core/widgets/keep_mounted_cover.dart';` after the `material.dart` import. Then replace the whole `build` method (lines 55–71, starting at its `@override`) with:

```dart
  @override
  Widget build(BuildContext context) {
    // Kept mounted, not swapped out (stories Wave 3; 07b G7). Returning the
    // cover *instead of* the child unmounted the Router, so every inactive
    // -- a call, Control Centre, Face ID, a permission alert -- closed the
    // story camera and reel, every sheet and dialog, and reset the chat.
    // Offstage never paints the child, so the OS snapshot and widget
    // finders still see only the neutral cover. See KeepMountedCover.
    return KeepMountedCover(
      obscured: _obscured,
      cover: ColoredBox(
        key: const Key('app_privacy_cover_overlay'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: const _NeutralCoverContent(),
      ),
      child: widget.child,
    );
  }
```

Append to the file's header comment (after line 14, before the `import`):

```dart
//
// Since stories Wave 3 the app stays mounted (offstage) behind the cover,
// so nothing is disposed when Attune leaves the screen: whatever must stop
// when unseen listens to appContentVisibleProvider.
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `dart format lib/core/widgets/keep_mounted_cover.dart test/helpers/state_probe.dart test/app/app_shell_keep_mounted_test.dart && flutter test test/core/services/app_privacy_cover_test.dart test/app/app_shell_keep_mounted_test.dart test/features/ai_assistant/understand_sheet_test.dart test/features/ai_assistant/assistant_notice_test.dart`
Expected: all PASS.
- The existing "secret content … findsNothing" tests pass because finders skip offstage widgets.
- `understand_sheet_test`'s backgrounding test passes unchanged.

- [ ] **Step 8: Run tests** (replaces Commit)

Run: `flutter test test/core test/app test/features/safety`
Expected: all PASS.

---

### Task 3: The lock's return check keeps a shown app mounted, and tells the signal

**Regression risk: HIGH (security gate above every route).**
- `locked` must still replace everything, and a cold-start `checking` must still build nothing.
- Every existing `safety_lock_gate_test` assertion stays as it is. The "deep link while locked" test still sees `navigatorKey.currentState == null` while locked.

**Files:**
- Modify: `lib/features/safety/presentation/widgets/safety_lock_gate.dart` (imports; doc `:8-11`; new field; `build` `:58-79`)
- Modify (comment only): `lib/features/safety/presentation/safety_lock_controller.dart:116-119`
- Modify (comment only): `lib/app/app_shell.dart:13-14`
- Test: `test/features/safety/safety_lock_gate_test.dart` (add a group)
- Test: `test/app/app_shell_keep_mounted_test.dart` (add a group)

**Interfaces:**
- Consumes (Task 1): `appContentVisibleProvider`, `AppContentVisibility.setLockOpen(bool)`.
- Consumes (Task 2): `KeepMountedCover`, `StateProbe`.
- Produces:
  - The checking cover's key is `Key('safety_lock_checking_cover')`.
  - The gate calls `setLockOpen(state == SafetyLockState.open)` on every lock change.

- [ ] **Step 1: Write the failing gate tests.** Add these imports to `test/features/safety/safety_lock_gate_test.dart`:

```dart
import 'package:attune/core/services/app_content_visibility.dart';

import '../../helpers/state_probe.dart';
```

Then append this group at the end of `main()`. It reuses the file's `_World`, `_type` and `background`.

```dart
  group('a return keeps a shown app mounted behind the check '
      '(stories Wave 3; 07b G7)', () {
    Future<ProviderContainer> pumpProbe(WidgetTester t, _World w) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [safetyLockDepsProvider.overrideWithValue(w.deps)],
          child: const MaterialApp(
            home: SafetyLockGate(child: StateProbe('APP')),
          ),
        ),
      );
      await t.pumpAndSettle();
      return ProviderScope.containerOf(t.element(find.byType(SafetyLockGate)));
    }

    Future<void> holdTheCheck(WidgetTester t, _World w) async {
      w.flagGate = Completer<void>();
      for (final s in background) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await t.pump();
    }

    testWidgets('no PIN: hidden while checking, the same State after', (
      t,
    ) async {
      final w = _World();
      await pumpProbe(t, w);
      await t.tap(find.text('APP 0'));
      await t.pump();
      await holdTheCheck(t, w);
      expect(find.text('APP 1'), findsNothing, reason: 'nothing paints');
      expect(find.text('APP 1', skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(const Key('safety_lock_checking_cover')),
        findsOneWidget,
      );
      w.flagGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('APP 1'), findsOneWidget);
    });

    testWidgets('a PIN not asked on every open: the same State after', (
      t,
    ) async {
      final w = _World();
      await pumpProbe(t, w);
      await w.pins.setPin('2468');
      await t.tap(find.text('APP 0'));
      await t.pump();
      await holdTheCheck(t, w);
      w.flagGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('APP 1'), findsOneWidget);
    });

    testWidgets('a PIN asked on every open still replaces the app: nothing '
        'of it survives the lock', (t) async {
      final w = _World();
      await pumpProbe(t, w);
      await w.pins.setPin('2468');
      await w.pins.setEveryOpen(true);
      await t.tap(find.text('APP 0'));
      await t.pump();
      for (final s in background) {
        t.binding.handleAppLifecycleStateChanged(s);
      }
      await t.pumpAndSettle();
      expect(find.text('Enter PIN'), findsOneWidget);
      expect(find.text('APP 1', skipOffstage: false), findsNothing);
      await _type(t, '2468');
      expect(find.text('APP 0'), findsOneWidget, reason: 'built fresh');
    });

    testWidgets('cold start: the app is not built until the first check '
        'ends (review I5)', (t) async {
      final w = _World()..flagGate = Completer<void>();
      await t.pumpWidget(
        ProviderScope(
          overrides: [safetyLockDepsProvider.overrideWithValue(w.deps)],
          child: const MaterialApp(
            home: SafetyLockGate(child: StateProbe('APP')),
          ),
        ),
      );
      await t.pump();
      expect(find.text('APP 0', skipOffstage: false), findsNothing);
      w.flagGate!.complete();
      await t.pumpAndSettle();
      expect(find.text('APP 0'), findsOneWidget);
    });

    testWidgets('the visibility signal never reads "on screen" between '
        'leaving and the lock opening (Review Focus 1)', (t) async {
      final w = _World();
      final c = await pumpProbe(t, w);
      final seen = <bool>[];
      c.listen<bool>(
        appContentVisibleProvider,
        (_, v) => seen.add(v),
        fireImmediately: true,
      );
      await holdTheCheck(t, w);
      expect(seen, [true, false], reason: 'resumed, but the lock is checking');
      w.flagGate!.complete();
      await t.pumpAndSettle();
      expect(seen, [true, false, true]);
    });

    testWidgets('during the check a Navigator exists, yet a notification tap '
        'still waits: deferral keys on the lock (07b G7 risk 4)', (t) async {
      final w = _World();
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, __) => const Text('HOME'))],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [safetyLockDepsProvider.overrideWithValue(w.deps)],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => SafetyLockGate(child: child!),
          ),
        ),
      );
      await t.pumpAndSettle();
      final c = ProviderScope.containerOf(
        t.element(find.byType(SafetyLockGate)),
      );
      await holdTheCheck(t, w);
      expect(router.routerDelegate.navigatorKey.currentState, isNotNull);
      expect(
        shouldDeferNotificationTap(
          state: c.read(safetyLockProvider),
          path: '/',
          navigatorReady: true,
        ),
        isTrue,
      );
      w.flagGate!.complete();
      await t.pumpAndSettle();
    });
  });
```

- [ ] **Step 2: Write the failing shell tests.** Append inside `main()` of `test/app/app_shell_keep_mounted_test.dart`:

```dart
  group('an app switch (through the lock check)', () {
    testWidgets('no PIN: the page and the pageless route keep their State', (
      t,
    ) async {
      final s = await _pump(t);
      await _openPageAndPageless(t, s);
      await _drive(t, _appSwitch);
      await _expectBothKept(t, s);
    });

    testWidgets('a PIN not asked on every open: State kept', (t) async {
      final s = await _pump(t);
      await s.w.pins.setPin('2468');
      await _openPageAndPageless(t, s);
      await _drive(t, _appSwitch);
      await _expectBothKept(t, s);
    });

    testWidgets('a PIN asked on every open: the lock replaces the app; after '
        'unlock the page is rebuilt fresh and the pageless route is gone', (
      t,
    ) async {
      final s = await _pump(t);
      await s.w.pins.setPin('2468');
      await s.w.pins.setEveryOpen(true);
      await _openPageAndPageless(t, s);
      await _drive(t, _appSwitch);
      expect(find.text('Enter PIN'), findsOneWidget);
      expect(find.text('PAGELESS 1', skipOffstage: false), findsNothing);
      expect(s.router.routerDelegate.navigatorKey.currentState, isNull);
      for (final d in '2468'.split('')) {
        await t.tap(find.widgetWithText(InkResponse, d).first);
        await t.pump();
      }
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.text('PAGELESS 0'), findsNothing);
      expect(find.text('PAGE 0'), findsOneWidget);
    });
  });
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/safety/safety_lock_gate_test.dart test/app/app_shell_keep_mounted_test.dart`
Expected:
- All existing tests PASS.
- New FAILS:
  - "no PIN…" and "a PIN not asked…" (`skipOffstage: false` finds nothing; "APP 0" after the check);
  - "visibility signal…" (`seen` is `[true, false, true]` before the check ends);
  - "during the check a Navigator exists…" (`currentState` is null);
  - the shell group's first two tests.
- "every open" and "cold start" may already PASS. They are regression guards for the parts that must not change.

- [ ] **Step 4: Implement the gate.** In `safety_lock_gate.dart`:

Add the imports:

```dart
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/widgets/keep_mounted_cover.dart';
```

Replace the doc comment at lines 8–11 with:

```dart
/// Root gate above the Navigator (Spec 2; research 06 §3 F2): while the
/// PIN is required the app's subtree -- the Navigator included -- is not in
/// the tree at all, so no deep link, notification tap or widget launch can
/// show it. A tap that arrives meanwhile is replayed on unlock (review I5).
/// While a return from the background is being checked, an app that was
/// already shown stays mounted behind a plain cover (stories Wave 3; 07b
/// G7), and notification taps still wait: shouldDeferNotificationTap keys
/// on the lock state, not on whether a Navigator exists.
```

Add a field to `_SafetyLockGateState` after `bool _wentBackground = false;`:

```dart
  /// The app has been shown since the last lock (or the cold start). While
  /// true, a return's `checking` hides it behind a cover but keeps it
  /// mounted (stories Wave 3); `locked` replaces it and clears this, so the
  /// PIN screen never has the app behind it.
  bool _shown = false;
```

Replace the second `ref.listen` and the `switch` in `build` (lines 66–78). Keep the `currentUserProvider` listen above them unchanged:

```dart
    ref.listen(safetyLockProvider, (prev, next) {
      // What is kept mounted behind the check -- media, cameras, read
      // receipts -- waits for the lock to open (stories Wave 3).
      ref
          .read(appContentVisibleProvider.notifier)
          .setLockOpen(next == SafetyLockState.open);
      if (next == SafetyLockState.open && prev != SafetyLockState.open) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _replay());
      }
    });
    final state = ref.watch(safetyLockProvider);
    if (state == SafetyLockState.locked) {
      _shown = false;
      return const PinLockScreen();
    }
    if (state == SafetyLockState.checking && !_shown) {
      // Cold start: the Router is not built until the check ends (I5).
      return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
    }
    final open = state == SafetyLockState.open;
    if (open) _shown = true;
    return KeepMountedCover(
      obscured: !open,
      cover: ColoredBox(
        key: const Key('safety_lock_checking_cover'),
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child: widget.child,
    );
```

- [ ] **Step 5: Correct the stale comments.**

In `safety_lock_controller.dart`, replace lines 116–119 with:

```dart
/// Whether Attune may show itself (Spec 2; research 06 §3 F2). Decided at
/// cold start and on every return from the background, in a provider, so
/// the decision lives outside everything the gate hides or replaces.
/// Every failure fails closed: signed out, or locked (review C2, I1).
```

In `app_shell.dart`, replace lines 13–14 with:

```dart
///   SafetyLockGate       -- replaces everything while the PIN is required;
///                          while a return is checked it hides the app but
///                          keeps it mounted (stories Wave 3).
///   AppPrivacyCover      -- neutral cover while not resumed; the app stays
///                          mounted, offstage, behind it (stories Wave 3).
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/safety test/app test/core/notifications test/features/relationships/lifecycle_wiring_test.dart test/features/safety/quick_exit_wiring_test.dart`
Expected: all PASS. `lifecycle_wiring_test` and `quick_exit_wiring_test` read `app_shell.dart` by `indexOf('SafetyLockGate(')` etc.; only comments changed.

- [ ] **Step 7: Run tests** (replaces Commit)

Run: `flutter test test/core test/app test/features/safety test/features/ai_assistant`
Expected: all PASS.

---

### Task 4: Shell regression guards: quick exit from every state, notification taps, shell order

**Regression risk:** none (tests only). These are **regression guards**: after Tasks 2–3 they should pass at once. If one fails, that is a real regression in Task 2 or 3. Fix it there; do not change the test.

**Files:**
- Test: `test/app/app_shell_keep_mounted_test.dart` (add a group; add `import 'dart:io';` at the top)

**Interfaces:**
- Consumes: Task 2/3 harness (`_pump`, `_drive`, `_nav`, `_blip`, `_appSwitch`), `QuickExitService`, `shouldDeferNotificationTap`.
- Produces: nothing.

- [ ] **Step 1: Write the guards.** Append inside `main()`:

```dart
  group('quick exit and notification taps still work from every state '
      '(Review Focus 4, 5)', () {
    Future<void> tripleTap(WidgetTester t) async {
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 400));
    }

    testWidgets('over a kept pageless route and sheet after a blip: only the '
        'decoy remains', (t) async {
      final s = await _pump(t);
      _nav(s).push(
        MaterialPageRoute<void>(builder: (_) => const StateProbe('MAP')),
      );
      await t.pumpAndSettle();
      showModalBottomSheet<void>(
        context: _nav(s).context,
        builder: (_) => const SizedBox(height: 200, child: Text('SHEET')),
      );
      await t.pumpAndSettle();
      await _drive(t, _blip);
      await tripleTap(t);
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.text('SHEET', skipOffstage: false), findsNothing);
      expect(find.text('MAP 0', skipOffstage: false), findsNothing);
    });

    testWidgets('after an app switch through the check (PIN set)', (t) async {
      final s = await _pump(t);
      await s.w.pins.setPin('2468');
      s.router.push('/page');
      await t.pumpAndSettle();
      await _drive(t, _appSwitch);
      await tripleTap(t);
      expect(find.text('DECOY'), findsOneWidget);
    });

    testWidgets('no PIN: the decoy survives a blip; the next app switch signs '
        'out (F2 (6))', (t) async {
      final s = await _pump(t);
      await tripleTap(t);
      await _drive(t, _blip);
      expect(find.text('DECOY'), findsOneWidget, reason: 'no check on a blip');
      expect(s.w.signOuts, 0);
      await _drive(t, _appSwitch);
      expect(s.w.signOuts, 1);
    });

    testWidgets('with a PIN: the next return shows only the PIN screen, and '
        'unlocking leaves the decoy', (t) async {
      final s = await _pump(t);
      await s.w.pins.setPin('2468');
      await tripleTap(t);
      await _drive(t, _appSwitch);
      expect(find.text('Enter PIN'), findsOneWidget);
      expect(find.text('DECOY', skipOffstage: false), findsNothing);
      for (final d in '2468'.split('')) {
        await t.tap(find.widgetWithText(InkResponse, d).first);
        await t.pump();
      }
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.text('HOME 0'), findsOneWidget);
    });

    testWidgets('while only the cover is up the Navigator stays mounted, so a '
        'tap from Notification Centre is no longer parked for want of one', (
      t,
    ) async {
      final s = await _pump(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(s.router.routerDelegate.navigatorKey.currentContext, isNotNull);
      expect(
        shouldDeferNotificationTap(
          state: s.c.read(safetyLockProvider),
          path: '/',
          navigatorReady: true,
        ),
        isFalse,
        reason: 'lock open: the tap navigates, behind the cover',
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
    });

    test('the real shell keeps the order this suite mirrors', () {
      final src = File('lib/app/app_shell.dart').readAsStringSync();
      final gate = src.indexOf('SafetyLockGate(');
      final cover = src.indexOf('AppPrivacyCover(');
      final zone = src.indexOf('QuickExitZone(');
      expect(gate, greaterThan(-1));
      expect(gate < cover && cover < zone, isTrue);
    });
  });
```

- [ ] **Step 2: Run them**

Run: `dart format test/app/app_shell_keep_mounted_test.dart && flutter test test/app/app_shell_keep_mounted_test.dart`
Expected: all PASS (guards). Before Tasks 2–3, the first two and the Navigator test would fail, so these pin the new behaviour.

- [ ] **Step 3: Run tests** (replaces Commit)

Run: `flutter test test/features/safety test/app`
Expected: all PASS.

---

### Task 5: The relationship watcher asks again on every return (it relied on the remount)

**Regression risk: medium (Spec 3a ending sheet).**
- Before this wave, every return remounted the watcher, and `initState` ran `_check()` with a fresh throttle.
- Kept mounted, only the lock-reopen listener runs, and its 5-minute throttle would hide a partner's ending for up to 5 minutes.
- Forcing the check keeps today's behaviour: one lifecycle read per return.

**Files:**
- Modify: `lib/features/relationships/presentation/widgets/relationship_lifecycle_watcher.dart:96-98`
- Test: `test/features/relationships/relationship_lifecycle_watcher_test.dart` (one helper line, two stale comments, one test)

**Interfaces:**
- Consumes: `lifecycleLockOpenProvider` (unchanged).
- Produces: nothing new.

- [ ] **Step 1: Write the failing test.**

In the test file, add a top-level provider above `_pump`:

```dart
/// The lock state as the watcher sees it; a test flips it to play a return.
final _lockOpen = StateProvider<bool>((_) => true);
```

In `_pump`, change the override line `lifecycleLockOpenProvider.overrideWith((ref) => true),` to:

```dart
        lifecycleLockOpenProvider.overrideWith((ref) => ref.watch(_lockOpen)),
```

Replace the stale comment in `_pump` ("A fresh mount, as after every resume (the privacy cover unmounts the app's subtree); …") with:

```dart
  // A fresh mount, as after a cold start or a PIN unlock (the lock replaces
  // the app's subtree); re-pumping the same tree would keep the old State.
```

In the IMP-2 test, replace "The privacy cover unmounts everything on inactive: the sheet is gone without the person having read it." with:

```dart
    // The PIN lock replaces everything: the sheet is gone without the
    // person having read it.
```

Append the test:

```dart
  testWidgets('kept mounted across a return (stories Wave 3): every reopen of '
      'the lock asks again, even within 5 minutes', (t) async {
    final w = await _pump(t, null);
    expect(w.service.fetches, 1);
    final c = ProviderScope.containerOf(
      t.element(find.byType(RelationshipLifecycleWatcher)),
    );
    // The partner ends it while this phone is in the background.
    w.service.value = _l();
    c.read(_lockOpen.notifier).state = false; // the return's lock check
    await t.pump();
    c.read(_lockOpen.notifier).state = true;
    await t.pumpAndSettle();
    expect(w.service.fetches, 2);
    expect(find.text('Ama has ended your shared space.'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/relationships/relationship_lifecycle_watcher_test.dart`
Expected: the new test FAILS (`fetches` is 1: throttled). The existing tests PASS.

- [ ] **Step 3: Implement.** In `relationship_lifecycle_watcher.dart`, replace

```dart
    ref.listen<bool>(lifecycleLockOpenProvider, (prev, next) {
      if (next && prev == false) _check();
    });
```

with

```dart
    ref.listen<bool>(lifecycleLockOpenProvider, (prev, next) {
      // Every return from the background passes the lock check (checking
      // -> open). The shell keeps this widget mounted across it now
      // (stories Wave 3), so this is "the next open": ask again, as the
      // fresh mount on every return used to.
      if (next && prev == false) _check(force: true);
    });
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/relationships`
Expected: all PASS.

- [ ] **Step 5: Run tests** (replaces Commit)

Run: `flutter test test/features/relationships test/app`
Expected: all PASS.

---

### Task 6: Videos that start on their own play only while Attune is on screen

**Regression risk: medium (chat media).**
- The ephemeral viewer used to play to its end behind the cover and be marked viewed. Inline chat videos kept their sound under the cover.
- `video_message_player_test`, `ephemeral_video_viewer_screen_test` and `chat_state_send_ephemeral_video_message_test` must stay green.

**Files:**
- Create: `lib/core/services/media/visible_only_playback.dart`
- Create: `test/helpers/recording_video_platform.dart`
- Create: `test/core/services/media/visible_only_playback_test.dart`
- Create: `test/features/chat/media_visibility_test.dart`
- Modify: `lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart` (imports; field; `initState` `:70-99`)
- Modify: `lib/features/chat/presentation/widgets/video_message_player.dart` (import; `build` listener near `:252`)

**Interfaces:**
- Consumes (Task 1): `appContentVisibleProvider`.
- Produces:
  - `class VisibleOnlyPlayback { VisibleOnlyPlayback({required bool Function() isVisible}); void start(VideoPlayerController controller); void onVisibility(bool visible); void clear(); }`.
  - `start` plays now if visible, else on the next `onVisibility(true)`.
  - `onVisibility(false)` pauses a playing controller and owes a play.
  - `onVisibility(true)` plays only what it owes, so a pause the person chose stays.
  - `clear` forgets the controller (call before disposing or replacing it).
  - `RecordingVideoPlatform({Completer<void>? initGate})` with `final List<String> calls`, which records `'play'` and `'pause'`.

- [ ] **Step 1: Write the test platform (Create)** `test/helpers/recording_video_platform.dart`. This is a public copy of `streak_viewer_lifecycle_test.dart`'s private `_RecordingVideoPlatform`; leave that one alone.

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Records play/pause. A playing clip reports 0.5 s of progress; [initGate]
/// holds the "initialized" event back until the test completes it.
class RecordingVideoPlatform extends VideoPlayerPlatform {
  RecordingVideoPlatform({this.initGate});
  final Completer<void>? initGate;
  final List<String> calls = [];
  final Set<int> _playing = {};
  final Map<int, StreamController<VideoEvent>> _streams = {};
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {
    _playing.remove(playerId);
    await _streams.remove(playerId)?.close();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    _streams[id] = StreamController<VideoEvent>.broadcast(
      onListen: () async {
        if (initGate != null) await initGate!.future;
        _streams[id]?.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 4),
            size: const Size(720, 1280),
          ),
        );
      },
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
    _playing.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
    _playing.remove(playerId);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async =>
      _playing.contains(playerId)
          ? const Duration(milliseconds: 500)
          : Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} unused');
}
```

- [ ] **Step 2: Write the failing unit test (Create)** `test/core/services/media/visible_only_playback_test.dart`

```dart
import 'dart:io';

import 'package:attune/core/services/media/visible_only_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../../helpers/recording_video_platform.dart';

void main() {
  late VideoPlayerPlatform original;
  late RecordingVideoPlatform platform;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    platform = RecordingVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  Future<VideoPlayerController> ready() async {
    final c = VideoPlayerController.file(File('/tmp/visible_only.mp4'));
    await c.initialize();
    platform.calls.clear();
    return c;
  }

  testWidgets('starts at once while Attune is on screen', (t) async {
    final c = await ready();
    VisibleOnlyPlayback(isVisible: () => true).start(c);
    await t.pump();
    expect(platform.calls, contains('play'));
    await c.dispose();
  });

  testWidgets('started while off screen, it waits for the return', (t) async {
    final c = await ready();
    final p = VisibleOnlyPlayback(isVisible: () => false)..start(c);
    await t.pump();
    expect(platform.calls, isNot(contains('play')));
    p.onVisibility(true);
    await t.pump();
    expect(platform.calls, contains('play'));
    await c.dispose();
  });

  testWidgets('leaving pauses it; coming back plays it again', (t) async {
    final c = await ready();
    final p = VisibleOnlyPlayback(isVisible: () => true)..start(c);
    await t.pump();
    platform.calls.clear();
    p.onVisibility(false);
    await t.pump();
    expect(platform.calls, ['pause']);
    expect(c.value.isPlaying, isFalse);
    p.onVisibility(true);
    await t.pump();
    expect(platform.calls, contains('play'));
    await c.dispose();
  });

  testWidgets('a pause the person chose stays paused on return', (t) async {
    final c = await ready();
    final p = VisibleOnlyPlayback(isVisible: () => true)..start(c);
    await t.pump();
    await c.pause();
    platform.calls.clear();
    p
      ..onVisibility(false)
      ..onVisibility(true);
    await t.pump();
    expect(platform.calls, isNot(contains('play')));
    await c.dispose();
  });

  testWidgets('clear() forgets the controller', (t) async {
    final c = await ready();
    final p = VisibleOnlyPlayback(isVisible: () => true)..start(c);
    await t.pump();
    p
      ..onVisibility(false)
      ..clear();
    platform.calls.clear();
    p.onVisibility(true);
    await t.pump();
    expect(platform.calls, isEmpty);
    await c.dispose();
  });
}
```

- [ ] **Step 3: Write the failing screen tests (Create)** `test/features/chat/media_visibility_test.dart`

```dart
// Stories Wave 3: the chat and its viewers stay mounted behind the privacy
// cover and the lock check, so a video must stop itself while Attune is
// not on screen.
import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/video_message_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../helpers/recording_video_platform.dart';
import 'support/chat_test_harness.dart';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  late VideoPlayerPlatform original;
  late RecordingVideoPlatform platform;

  setUp(() {
    original = VideoPlayerPlatform.instance;
    platform = RecordingVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  void life(WidgetTester t, AppLifecycleState s) =>
      t.binding.handleAppLifecycleStateChanged(s);

  Future<({ProviderContainer container, FakeChatRepository repo})> openViewer(
    WidgetTester tester,
  ) async {
    addTearDown(() => life(tester, AppLifecycleState.resumed));
    final repo = FakeChatRepository(currentUserId: userId);
    final conversation = activeConversation(relId);
    repo.conversationOverride = conversation;
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    container.read(chatControllerProvider(conversation).notifier);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, _) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => context.push('/viewer'),
                  child: const Text('open'),
                ),
              ),
        ),
        GoRoute(
          path: '/viewer',
          builder:
              (_, __) => EphemeralVideoViewerScreen(
                messageId: 'm1',
                videoUrl: '/tmp/local/clip.mp4',
                conversation: conversation,
              ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    return (container: container, repo: repo);
  }

  group('ephemeral video viewer', () {
    testWidgets('pauses while Attune is off screen and carries on after; '
        'nothing is marked viewed meanwhile', (tester) async {
      final v = await openViewer(tester);
      expect(platform.calls, contains('play'));
      platform.calls.clear();
      life(tester, AppLifecycleState.inactive);
      await tester.pump();
      expect(platform.calls, contains('pause'), reason: 'no sound behind it');
      await tester.pump(const Duration(seconds: 10));
      life(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.calls, contains('play'));
      expect(v.repo.markVideoViewedCalls, isEmpty);
    });

    testWidgets('a clip that opens while Attune is off screen waits to start', (
      tester,
    ) async {
      final init = Completer<void>();
      platform = RecordingVideoPlatform(initGate: init);
      VideoPlayerPlatform.instance = platform;
      await openViewer(tester);
      life(tester, AppLifecycleState.inactive);
      init.complete();
      await tester.pump();
      await tester.pump();
      expect(platform.calls, isNot(contains('play')));
      life(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.calls, contains('play'));
    });

    testWidgets('a return that stops at the lock check waits for the lock '
        '(Review Focus 1)', (tester) async {
      final v = await openViewer(tester);
      platform.calls.clear();
      life(tester, AppLifecycleState.inactive);
      v.container.read(appContentVisibleProvider.notifier).setLockOpen(false);
      life(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.calls, isNot(contains('play')));
      v.container.read(appContentVisibleProvider.notifier).setLockOpen(true);
      await tester.pump();
      expect(platform.calls, contains('play'));
    });
  });

  testWidgets('an inline chat video stops when Attune leaves the screen and '
      'stays stopped on return (a tap plays it again)', (tester) async {
    addTearDown(() => life(tester, AppLifecycleState.resumed));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: VideoMessagePlayer(
              messageId: 'm1',
              videoUrl: '/tmp/local/inline.mp4',
              thumbnailUrl: null,
              durationMs: 4000,
              width: 720,
              height: 1280,
              autoPlay: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.calls, contains('play'));
    platform.calls.clear();
    life(tester, AppLifecycleState.inactive);
    await tester.pump();
    expect(platform.calls, contains('pause'));
    life(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls, isNot(contains('play')));
    expect(
      tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller.value
          .isPlaying,
      isFalse,
    );
  });
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `flutter test test/core/services/media/visible_only_playback_test.dart test/features/chat/media_visibility_test.dart`
Expected:
- The unit test FAILS to compile (no `visible_only_playback.dart`).
- The screen tests FAIL: no `'pause'` on `inactive`; the clip plays while off screen; it plays during the check.

- [ ] **Step 5: Write `VisibleOnlyPlayback` (Create)**

```dart
// lib/core/services/media/visible_only_playback.dart
import 'dart:async';

import 'package:video_player/video_player.dart';

/// Plays a video only while Attune's content is on screen
/// (appContentVisibleProvider; stories Wave 3). [start] plays now when
/// visible, or on the next return. Leaving pauses it, and coming back plays
/// it again, but only what this paused or was asked to start: a pause the
/// person chose stays theirs.
///
/// Pausing at the first `inactive` also stops video_player's own
/// lifecycle observer from resuming it on `resumed` (it resumes only what
/// was playing at `paused`), which would otherwise play behind the Safety
/// lock check.
class VisibleOnlyPlayback {
  VisibleOnlyPlayback({required bool Function() isVisible})
    : _isVisible = isVisible;

  final bool Function() _isVisible;
  VideoPlayerController? _controller;
  bool _owed = false;

  void start(VideoPlayerController controller) {
    _controller = controller;
    _owed = true;
    if (_isVisible()) _playOwed();
  }

  void onVisibility(bool visible) {
    final controller = _controller;
    if (controller == null) return;
    if (!visible) {
      if (controller.value.isPlaying) {
        _owed = true;
        unawaited(controller.pause().catchError((Object _) {}));
      }
      return;
    }
    if (_owed) _playOwed();
  }

  /// The controller is going away (disposed or replaced): forget it.
  void clear() {
    _controller = null;
    _owed = false;
  }

  void _playOwed() {
    _owed = false;
    unawaited(_controller!.play().catchError((Object _) {}));
  }
}
```

- [ ] **Step 6: Wire the ephemeral viewer.** In `ephemeral_video_viewer_screen.dart`:

Add the imports:

```dart
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/services/media/visible_only_playback.dart';
```

Add the field after `StreamSubscription<void>? _screenshotSubscription;`:

```dart
  /// The clip plays only while Attune is on screen (stories Wave 3: this
  /// route now stays mounted behind the privacy cover and the lock check,
  /// where it could otherwise play to its end, unseen, and be marked
  /// viewed).
  late final VisibleOnlyPlayback _playback = VisibleOnlyPlayback(
    isVisible: () => ref.read(appContentVisibleProvider),
  );
```

In `initState`, insert directly after `super.initState();`:

```dart
    ref.listenManual<bool>(
      appContentVisibleProvider,
      (_, visible) => _playback.onVisibility(visible),
    );
```

Then, inside the `.then((_) { … })`, replace `controller.play();` with `_playback.start(controller);`.

- [ ] **Step 7: Wire the inline player.** In `video_message_player.dart`:

Add the import `import 'package:attune/core/services/app_content_visibility.dart';`.

In `build`, directly after the existing `ref.listen<String?>(currentlyPlayingVideoMessageIdProvider, …);` statement, add:

```dart
    // Stories Wave 3: the chat stays mounted behind the privacy cover and
    // the lock check, so a playing video stops itself when Attune is not on
    // screen. It stays stopped: a tap plays it again, as for a voice note.
    ref.listen<bool>(appContentVisibleProvider, (_, visible) {
      if (!visible && _isPlaying) {
        _controller?.pause();
        setState(() => _isPlaying = false);
      }
    });
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `dart format lib/core/services/media/visible_only_playback.dart test/helpers/recording_video_platform.dart test/core/services/media/visible_only_playback_test.dart test/features/chat/media_visibility_test.dart && flutter test test/core/services/media/visible_only_playback_test.dart test/features/chat/media_visibility_test.dart test/features/chat/video_message_player_test.dart test/features/chat/ephemeral_video_viewer_screen_test.dart test/features/chat/chat_state_send_ephemeral_video_message_test.dart`
Expected: all PASS.

- [ ] **Step 9: Run tests** (replaces Commit)

Run: `flutter test test/features/chat test/core`
Expected: all PASS.

---

### Task 7: The story and streak review previews play only while Attune is on screen

**Regression risk: medium (shared camera embedders).**
- The looping preview of your own take used to keep its sound behind the cover, and a preview that finished opening behind a permission alert played in the background.
- These must stay green: `story_review_test`, `story_camera_test`, `streak_camera_contract_test`, `streak_camera_photo_test`, `streak_camera_test`, `streak_lock_test`.
- Ruling: the streak preview is covered by `VisibleOnlyPlayback`'s unit tests plus those suites, because the streak contract harness is private and must not be edited. Task 13's device check covers it on a phone.

**Files:**
- Modify: `lib/features/stories/presentation/screens/story_camera_screen.dart` (imports; field + `initState`; `_startPreview` `:166-184`; `_disposePreview` `:186-190`)
- Modify: `lib/features/chat/presentation/screens/streak_camera_screen.dart` (imports; field + `initState`; `_startPreview` `:259-277`; `_disposePreview` `:279-284`)
- Test: `test/features/stories/story_review_test.dart` (add one test)

**Interfaces:**
- Consumes (Task 1): `appContentVisibleProvider`. Consumes (Task 6): `VisibleOnlyPlayback`, `RecordingVideoPlatform`.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test.** Add to `test/features/stories/story_review_test.dart`:

```dart
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../helpers/recording_video_platform.dart';
```

Skip any of these imports the file already has. Then add, inside `main()`:

```dart
  testWidgets('a video take\'s looping preview stops while Attune is off '
      'screen, and plays again only once the lock is open (stories Wave 3)', (
    tester,
  ) async {
    final video = RecordingVideoPlatform();
    final originalVideo = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = video;
    addTearDown(() => VideoPlayerPlatform.instance = originalVideo);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.runAsync(
      () => File('${dir.path}/clip.mp4').writeAsBytes(List.filled(128, 1)),
    );
    await open(tester);
    // Past the 300 ms photo threshold, then record.
    final hold = await tester.startGesture(
      tester.getCenter(find.byType(StreakRecordButton)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await hold.up();
    await tester.pump();
    await settleIo(tester, 30);
    expect(share, findsOneWidget, reason: 'the take is on review');
    expect(video.calls, contains('play'));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(StoryCameraScreen)),
    );
    video.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(video.calls, contains('pause'));
    container.read(appContentVisibleProvider.notifier).setLockOpen(false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(video.calls, isNot(contains('play')), reason: 'lock check');
    container.read(appContentVisibleProvider.notifier).setLockOpen(true);
    await tester.pump();
    expect(video.calls, contains('play'));
  });
```

If the take does not reach review with this hold, copy the exact hold sequence from `capture_camera_test.dart`'s "a call mid-hold keeps the take recorded so far". Do not change the assertions.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/stories/story_review_test.dart`
Expected: the new test FAILS at `contains('pause')` (only video_player's own `paused` observer exists). The existing tests PASS.

- [ ] **Step 3: Wire the story camera.** In `story_camera_screen.dart`:

Add the imports:

```dart
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/services/media/visible_only_playback.dart';
```

Add after `VideoPlayerController? _preview;`:

```dart
  /// The preview loops only while Attune is on screen (stories Wave 3).
  late final VisibleOnlyPlayback _previewPlayback = VisibleOnlyPlayback(
    isVisible: () => ref.read(appContentVisibleProvider),
  );

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(
      appContentVisibleProvider,
      (_, visible) => _previewPlayback.onVisibility(visible),
    );
  }
```

In `_startPreview`, delete `await controller.play();` from the `try` block (keep `initialize()` and `setLooping(true)`). Then replace the final `setState(() => _preview = controller);` with:

```dart
    setState(() => _preview = controller);
    _previewPlayback.start(controller);
```

In `_disposePreview`, add `_previewPlayback.clear();` as its first line.

- [ ] **Step 4: Wire the streak camera.** Make the same additions to `streak_camera_screen.dart`:
- Add the two imports.
- Add the field `_previewPlayback` (same initializer) and an `initState` with the same `listenManual`.
- In `_startPreview`, replace

```dart
    await controller.setLooping(true);
    await controller.play();
    setState(() => _previewController = controller);
```

with

```dart
    await controller.setLooping(true);
    setState(() => _previewController = controller);
    // Plays only while Attune is on screen (stories Wave 3).
    _previewPlayback.start(controller);
```

- In `_disposePreview`, add `_previewPlayback.clear();` as its first line.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/stories/story_review_test.dart test/features/stories/story_camera_test.dart test/features/chat/streak_camera_contract_test.dart test/features/chat/streak_camera_photo_test.dart test/features/chat/streak_camera_test.dart test/features/chat/streak_lock_test.dart`
Expected: all PASS.

- [ ] **Step 6: Run tests** (replaces Commit)

Run: `flutter test test/features/stories test/features/chat`
Expected: all PASS.

---

### Task 8: Voice notes and voice recordings stop when Attune leaves the screen

**Regression risk: medium (chat composer, every voice note).**
- Playback used to pause only on `paused`, and the chat's teardown hid that.
- A recording in progress used to be disposed (lost) by the teardown; now it would keep the microphone live behind the cover.
- These must stay green: `voice_playback_*_test`, `voice_record_*_test`, `voice_recording_bar*_test`, `chat_text_field_test`, `chat_text_field_ai_mode_test`.

**Files:**
- Modify: `lib/features/chat/presentation/state/voice_playback_controller.dart:641-649` (`didChangeAppLifecycleState`)
- Modify: `lib/features/chat/presentation/widgets/chat_text_field.dart` (a field, `initState` `:780`, `dispose` `:859`, a new `_onAppAway`)
- Test: `test/features/chat/voice_playback_controller_test.dart` (add 2 tests after `:240`)
- Test: `test/features/chat/voice_record_away_test.dart` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks. These are lifecycle-only; neither resumes on its own, so the lock half is not needed.
- Produces: nothing new.

- [ ] **Step 1: Write the failing playback tests.** Add after the test "backgrounding the app pauses (no background playback)" (`voice_playback_controller_test.dart:235-240`):

```dart
  test('an inactive blip pauses too: the privacy cover is up and the chat '
      'stays mounted behind it (stories Wave 3)', () async {
    await controller.toggle('m1', url);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tick();
    expect(state.isPlaying, isFalse);
  });

  test('coming back does not start the note again on its own', () async {
    await controller.toggle('m1', url);
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tick();
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tick();
    expect(state.isPlaying, isFalse);
  });
```

- [ ] **Step 2: Write the failing recording tests (Create)** `test/features/chat/voice_record_away_test.dart`

```dart
// Stories Wave 3: the chat stays mounted behind the privacy cover, so a
// recording in progress is no longer disposed when Attune leaves the
// screen. It is locked and paused, kept for the person to resume, send or
// delete, and the microphone stops.
import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _PausableRecorder extends VoiceRecorderService {
  _PausableRecorder({this.startDelay = Duration.zero});

  final Duration startDelay;
  bool started = false, stopped = false, cancelled = false, paused = false;
  int resumes = 0;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start() async {
    if (startDelay > Duration.zero) await Future<void>.delayed(startDelay);
    started = true;
  }

  @override
  Future<VoiceRecording> stop() async {
    stopped = true;
    return const VoiceRecording(
      localPath: '/tmp/fake.m4a',
      durationMs: 1200,
      waveform: <int>[1, 2, 3],
    );
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
    resumes++;
  }

  @override
  bool get isPaused => paused;

  @override
  Duration get elapsed => const Duration(seconds: 1);

  @override
  void dispose() {}
}

Widget _harness(_PausableRecorder recorder, {VoidCallback? onRecorded}) {
  return withScreenUtil(
    MaterialApp(
      home: Scaffold(
        body: ChatTextField(
          controller: TextEditingController(),
          onSend: () {},
          showVoiceMessage: true,
          recorderFactory: () => recorder,
          onVoiceMessageRecorded: (_) => onRecorded?.call(),
        ),
      ),
    ),
  );
}

void main() {
  final mic = find.byIcon(Icons.mic_none_rounded);
  void life(WidgetTester t, AppLifecycleState s) =>
      t.binding.handleAppLifecycleStateChanged(s);

  testWidgets('a locked recording is paused and kept when Attune leaves the '
      'screen, and does not listen again on its own', (t) async {
    addTearDown(() => life(t, AppLifecycleState.resumed));
    final r = _PausableRecorder();
    var recorded = false;
    await t.pumpWidget(_harness(r, onRecorded: () => recorded = true));
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 60));
    await g.moveBy(const Offset(0, -120)); // past the lock threshold
    await t.pump(const Duration(milliseconds: 60));
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
    expect(r.paused, isFalse);

    life(t, AppLifecycleState.inactive);
    await t.pump();
    expect(r.paused, isTrue, reason: 'the microphone stops behind the cover');
    life(t, AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 100));
    expect(r.paused, isTrue);
    expect(r.resumes, 0);
    expect(r.stopped || r.cancelled || recorded, isFalse, reason: 'kept');
  });

  testWidgets('a held recording interrupted by a call is locked and paused: '
      'never sent and never lost', (t) async {
    addTearDown(() => life(t, AppLifecycleState.resumed));
    final r = _PausableRecorder();
    var recorded = false;
    await t.pumpWidget(_harness(r, onRecorded: () => recorded = true));
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 120));
    expect(r.started, isTrue);

    life(t, AppLifecycleState.inactive);
    await t.pump();
    await g.cancel(); // the system takes the touch
    await t.pump(const Duration(milliseconds: 100));
    life(t, AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 100));
    expect(r.paused, isTrue);
    expect(r.stopped, isFalse);
    expect(r.cancelled, isFalse);
    expect(recorded, isFalse);
  });

  testWidgets('regression guard: the first-use microphone alert (an inactive '
      'while starting) leaves the recording alone (Review Focus 2)', (t) async {
    addTearDown(() => life(t, AppLifecycleState.resumed));
    final r = _PausableRecorder(startDelay: const Duration(milliseconds: 300));
    var recorded = false;
    await t.pumpWidget(_harness(r, onRecorded: () => recorded = true));
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 50));
    life(t, AppLifecycleState.inactive);
    await t.pump();
    life(t, AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 400));
    expect(r.started, isTrue);
    expect(r.paused, isFalse);
    await g.up();
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(r.stopped, isTrue);
    expect(recorded, isTrue);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/chat/voice_playback_controller_test.dart test/features/chat/voice_record_away_test.dart`
Expected:
- The first new playback test FAILS (still playing after `inactive`). The second may pass: it is a guard against auto-resume.
- Recording: the first two FAIL (`paused` is false). The third PASSES (labelled guard).

- [ ] **Step 4: Implement playback.** Replace the body of `VoicePlaybackController.didChangeAppLifecycleState` (keep the `@override` and the two ignore comment lines above the signature):

```dart
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Any state but resumed (stories Wave 3): the privacy cover is up from
    // `inactive` on and the chat stays mounted behind it, so nothing else
    // stops a note playing to a covered screen. It does not resume itself.
    if (lifecycle != AppLifecycleState.resumed &&
        (state.isPlaying || state.isLoading)) {
      unawaited(pause());
    }
  }
```

- [ ] **Step 5: Implement recording.** In `chat_text_field.dart`, inside `_ChatTextFieldState`:

Add after `bool _isPaused = false;` (`:703`):

```dart
  /// Leaving the screen pauses a recording in progress (stories Wave 3).
  late final AppLifecycleListener _lifecycle;
```

In `initState`, after `widget.controller.addListener(_onChanged);`:

```dart
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) _onAppAway();
      },
    );
```

In `dispose`, add `_lifecycle.dispose();` directly after `widget.controller.removeListener(_onChanged);`.

Add this method directly above `_togglePause` (`:1295`):

```dart
  /// Stories Wave 3: the chat stays mounted behind the privacy cover now,
  /// so leaving Attune no longer disposes, and loses, a recording. One in
  /// progress is locked (if still held) and paused instead -- kept for the
  /// person to resume, send or delete -- and the microphone stops. A
  /// recording still starting is left alone: the first-use microphone
  /// alert is itself an `inactive`.
  void _onAppAway() {
    if (!_isRecording || _startInFlight) return;
    if (_stage != VoiceRecordingStage.locked) _lockRecording();
    if (!(_recorder?.isPaused ?? true)) unawaited(_togglePause());
  }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `dart format test/features/chat/voice_record_away_test.dart && flutter test test/features/chat/voice_playback_controller_test.dart test/features/chat/voice_record_away_test.dart test/features/chat/voice_record_gesture_test.dart test/features/chat/voice_record_feedback_test.dart test/features/chat/voice_recording_bar_test.dart test/features/chat/chat_text_field_test.dart test/features/chat/chat_text_field_ai_mode_test.dart`
Expected: all PASS.

- [ ] **Step 7: Run tests** (replaces Commit)

Run: `flutter test test/features/chat test/core/services/media`
Expected: all PASS.

---

### Task 9: The story reel and the streak viewer wait for the lock, and pause on any blip

**Regression risk: medium (Wave 1 reel; streak views).**
- The reel's lifecycle pause becomes live with this wave (07b G7 risk 2). It must also hold through the lock check.
- The streak viewer now also pauses on `inactive`, overriding its comment "inactive alone leaves it playing", which never ran in practice. Its photo hold no longer runs out behind the cover.
- These must stay green: every `story_reel_*_test` and `streak_viewer_*_test`.

**Files:**
- Modify: `lib/features/stories/presentation/screens/story_reel_screen.dart` (import; remove `_lifecycleListener` field `:472` and its dispose line `:1525`; `initState` `:495-500`)
- Modify: `lib/features/chat/presentation/screens/streak_viewer_screen.dart` (import; mixin `:78`; `_away` doc `:96-100`; `initState` `:162`; replace `didChangeAppLifecycleState` `:165-193` with `_setAway`; `dispose` `:525`)
- Test: `test/features/stories/story_reel_test.dart` (one test in the "backgrounding mid-item…" group)
- Test: `test/features/chat/streak_viewer_lifecycle_test.dart` (two tests)

**Interfaces:**
- Consumes (Task 1): `appContentVisibleProvider`, `setLockOpen`.
- Produces: nothing new. The reel's `_setForeground(bool)` and the viewer's new `_setAway(bool)` are private.

- [ ] **Step 1: Write the failing reel test.** Add `import 'package:attune/core/services/app_content_visibility.dart';` to `story_reel_test.dart`. Then add inside `group('backgrounding mid-item pauses rather than skipping', …)`:

```dart
    testWidgets(
      'a return that stops at the Safety lock check stays paused until the '
      'lock opens (stories Wave 3)',
      (tester) async {
        final items = [
          _item(
            id: 'v',
            createdAt: DateTime.utc(2026, 9, 1),
            mediaType: 'video',
          ),
          _item(id: 'after', createdAt: DateTime.utc(2026, 9, 2)),
        ];
        final gateway = _FakeReelGateway(items: items);
        final playerFactory = _FakePlayerFactory();
        await tester.pumpWidget(
          _harness(gateway: gateway, videoPlayerFactory: playerFactory.factory),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final player = playerFactory.players.single;
        expect(player.isPlaying, isTrue);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(StoryReelScreen)),
        );
        final binding = TestWidgetsFlutterBinding.instance;
        for (final s in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          binding.handleAppLifecycleStateChanged(s);
          await tester.pump();
        }
        expect(player.isPlaying, isFalse);
        // What SafetyLockGate does on a return: the lock is being checked.
        container.read(appContentVisibleProvider.notifier).setLockOpen(false);
        for (final s in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          binding.handleAppLifecycleStateChanged(s);
          await tester.pump();
        }
        expect(
          player.isPlaying,
          isFalse,
          reason: 'nothing plays behind the PIN check',
        );
        container.read(appContentVisibleProvider.notifier).setLockOpen(true);
        await tester.pump();
        expect(player.isPlaying, isTrue);
        expect(gateway.markViewedCalls, ['v']);
      },
    );
```

- [ ] **Step 2: Write the failing streak viewer tests.** Add `import 'package:attune/core/services/app_content_visibility.dart';` to `streak_viewer_lifecycle_test.dart`. Then add inside `main()`, after the existing tests:

```dart
  testWidgets('an inactive blip alone pauses too: the privacy cover is up '
      '(stories Wave 3)', (tester) async {
    final streaks = _StreakRepo([_videoClip]);
    await open(tester, streaks);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(controllerOf(tester).value.isPlaying, isTrue);
    platform.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(platform.calls, contains('pause'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls, contains('play'));
    expect(streaks.spends, 1);
  });

  testWidgets('a return that stops at the Safety lock check stays paused '
      'until the lock opens (stories Wave 3)', (tester) async {
    final streaks = _StreakRepo([_videoClip]);
    await open(tester, streaks);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StreakViewerScreen)),
    );
    platform.calls.clear();
    await background(tester);
    container.read(appContentVisibleProvider.notifier).setLockOpen(false);
    await foreground(tester);
    expect(platform.calls, isNot(contains('play')));
    container.read(appContentVisibleProvider.notifier).setLockOpen(true);
    await tester.pump();
    expect(platform.calls, contains('play'));
    expect(find.byType(StreakViewerScreen), findsOneWidget);
  });
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/stories/story_reel_test.dart test/features/chat/streak_viewer_lifecycle_test.dart`
Expected:
- Reel: the new test FAILS (playing during the check).
- Streak: "an inactive blip…" FAILS (no `'pause'`); "a return that stops…" FAILS (`'play'` during the check).
- Every existing test PASSES.

- [ ] **Step 4: Implement the reel.** In `story_reel_screen.dart`:
- Add `import 'package:attune/core/services/app_content_visibility.dart';`.
- Delete the field `AppLifecycleListener? _lifecycleListener;` and the line `_lifecycleListener?.dispose();` in `dispose`.
- In `initState`, replace

```dart
    _lifecycleListener = AppLifecycleListener(
      onResume: () => _setForeground(true),
      onPause: () => _setForeground(false),
      onInactive: () => _setForeground(false),
      onHide: () => _setForeground(false),
    );
```

with

```dart
    // Stories Wave 3: the shell keeps this route mounted behind the privacy
    // cover and the Safety lock check, so "foreground" is whether Attune's
    // content is on screen (resumed AND the lock open), not the lifecycle
    // alone: a return that ends at the PIN screen must not play.
    ref.listenManual<bool>(
      appContentVisibleProvider,
      (_, visible) => _setForeground(visible),
    );
```

- [ ] **Step 5: Implement the streak viewer.** In `streak_viewer_screen.dart`:
- Add `import 'package:attune/core/services/app_content_visibility.dart';`.
- First confirm with `grep -n "WidgetsBindingObserver\|didChange" lib/features/chat/presentation/screens/streak_viewer_screen.dart` that lifecycle is the only observer use. Then change `extends ConsumerState<StreakViewerScreen> with WidgetsBindingObserver {` to `extends ConsumerState<StreakViewerScreen> {`, and delete `WidgetsBinding.instance.addObserver(this);` (`:162`) and `WidgetsBinding.instance.removeObserver(this);` (`:525`).
- Replace the `_away` doc (`:96-99`) with:

```dart
  /// Attune's content is not on screen: any lifecycle state but resumed
  /// (the privacy cover is up from `inactive` on) or the Safety lock check
  /// (stories Wave 3). Nothing plays and no hold runs until it is back
  /// (final review M-3): a clip sounding over the home screen, or a photo's
  /// hold running out behind the cover, is a view nobody is watching.
```

- In `initState`, where `addObserver` was, add:

```dart
    ref.listenManual<bool>(
      appContentVisibleProvider,
      (_, visible) => _setAway(!visible),
    );
```

- Replace the whole `didChangeAppLifecycleState` override and its doc comment (`:165-193`) with:

```dart
  /// Away: pause the clip and hold the timers. Back: carry on where it
  /// stopped. Not a close -- the view was spent at presentation, so closing
  /// would cost the recipient their (often only) view for a phone call;
  /// the app's PIN lock / quick exit, not this screen, decide whether the
  /// person who comes back may see it. Since stories Wave 3 an inactive
  /// blip (a pulled-down shade, an incoming-call banner) counts as away:
  /// the privacy cover is up, so nobody is watching.
  void _setAway(bool away) {
    if (away) {
      if (_away) return;
      _away = true;
      _imageHoldTimer?.pause();
      _loadTimeoutTimer?.pause();
      final controller = _controller;
      if (controller != null && controller.value.isPlaying) {
        unawaited(controller.pause());
      }
      return;
    }
    if (!_away) return;
    _away = false;
    _imageHoldTimer?.resume();
    _loadTimeoutTimer?.resume();
    _resumeClip();
  }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/stories test/features/chat/streak_viewer_lifecycle_test.dart test/features/chat/streak_viewer_photo_test.dart test/features/chat/streak_viewer_pop_test.dart test/features/chat/streak_viewer_presented_gate_test.dart test/features/chat/streak_viewer_states_test.dart test/features/chat/streak_view_budget_test.dart`
Expected: all PASS.

- [ ] **Step 7: Run tests** (replaces Commit)

Run: `flutter test test/features/stories test/features/chat`
Expected: all PASS.

---

### Task 10: The shared camera re-opens only once Attune is on screen (verify Wave 2, add the lock half)

**Regression risk: medium (shared camera: stories and streaks).**
- Verified: Wave 2 Task 14 already releases the camera on `inactive` / `hidden` / `paused` and re-initialises on `resumed` (`capture_camera_screen.dart:388-399`, `_suspend` / `_resume`, both idempotent). That is not duplicated.
- The gap is the lock check. A return with a PIN asked on every open would re-open the camera, and light the camera indicator, behind the PIN screen.
- The shared-camera gate must stay green: `capture_camera_test`, `streak_camera_contract_test`, `streak_camera_test`, `streak_camera_photo_test`, `streak_lock_test`. `streak_camera_test.dart:51-61` pins the literal `enableAudio: true`; it is not touched.

**Files:**
- Modify: `lib/features/chat/presentation/screens/capture_camera_screen.dart` (import; `initState` `:243-245`; `didChangeAppLifecycleState` `:395-396`)
- Test: `test/features/stories/capture_camera_test.dart` (one test in `group('lifecycle (01 #15, Review Focus 4)', …)`)

**Interfaces:**
- Consumes (Task 1): `appContentVisibleProvider`, `setLockOpen`.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test.** Add `import 'package:attune/core/services/app_content_visibility.dart';` to `capture_camera_test.dart`. Then add inside the lifecycle group (it reuses `background`, `foreground`, `writeFile`, `pumpToReady`, `fakes`):

```dart
    testWidgets('a return that stops at the Safety lock check re-opens the '
        'camera only once the lock opens (stories Wave 3)', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      await pumpToReady(
        tester,
        const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CaptureCameraScreen)),
      );
      background(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.disposeCalls, 1);

      container.read(appContentVisibleProvider.notifier).setLockOpen(false);
      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.createCalls, 1, reason: 'no camera behind the PIN check');

      container.read(appContentVisibleProvider.notifier).setLockOpen(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.createCalls, 2);
      expect(find.byType(StreakRecordButton), findsOneWidget);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/stories/capture_camera_test.dart`
Expected: the new test FAILS (`createCalls` is 2 during the check). The existing tests PASS.

- [ ] **Step 3: Implement.** In `capture_camera_screen.dart`:

Add `import 'package:attune/core/services/app_content_visibility.dart';`.

In `initState`, insert directly **before** `WidgetsBinding.instance.addObserver(this);`. Registering the provider's lifecycle listener first means it updates before this screen's observer reads it.

```dart
    // Stories Wave 3: the shell keeps this screen mounted through the
    // Safety lock's return check, so the camera re-opens when Attune is on
    // screen again, not merely resumed. Release stays on the lifecycle.
    ref.listenManual<bool>(appContentVisibleProvider, (_, visible) {
      if (visible) unawaited(_resume());
    });
```

In `didChangeAppLifecycleState`, replace

```dart
      case AppLifecycleState.resumed:
        unawaited(_resume());
```

with

```dart
      case AppLifecycleState.resumed:
        // Behind the lock check: the listener above re-opens it.
        if (ref.read(appContentVisibleProvider)) unawaited(_resume());
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/stories/capture_camera_test.dart test/features/chat/streak_camera_contract_test.dart test/features/chat/streak_camera_test.dart test/features/chat/streak_camera_photo_test.dart test/features/chat/streak_lock_test.dart test/features/stories/story_camera_test.dart test/features/stories/story_review_test.dart`
Expected: all PASS.

- [ ] **Step 5: Run tests** (replaces Commit)

Run: `flutter test test/features/stories test/features/chat`
Expected: all PASS.

---

### Task 11: Read receipts and presence wait for the lock to open

**Regression risk: medium (chat read state; `chat_screen.dart` has the user's uncommitted edits).**
- Two additive edits only.
- Before this wave the chat was unmounted during the check. Kept mounted, a return with a PIN asked on every open would mark messages read, and show "in the chat" presence, behind the PIN screen.
- `chat_screen_view_active_test` and every `chat_screen_*_test` must stay green.

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (import; `initState` near `:210`; `_syncViewActive` `:372-373`)
- Test: `test/features/chat/chat_screen_view_active_test.dart` (one test)

**Interfaces:**
- Consumes (Task 1): `appContentVisibleProvider`, `setLockOpen`.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test.** Add `import 'package:attune/core/services/app_content_visibility.dart';` to the test file. Then add inside `main()` (it reuses `pumpChat`, `setLifecycle`, `tearDownChat`):

```dart
  testWidgets(
    'a return that stops at the Safety lock check keeps presence and read '
    'receipts off until the lock opens (stories Wave 3)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = await pumpChat(tester, repo);
      expect(repo.presenceCalls.last, relId);

      await setLifecycle(tester, 'AppLifecycleState.paused');
      await tester.pump(const Duration(milliseconds: 50));
      // What SafetyLockGate does on a return: the lock is being checked.
      container.read(appContentVisibleProvider.notifier).setLockOpen(false);
      await setLifecycle(tester, 'AppLifecycleState.resumed');
      await tester.pump(const Duration(milliseconds: 50));

      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'are you there?',
        createdAt: DateTime.now(),
      );
      repo.emitRealtime();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        repo.presenceCalls.last,
        isNull,
        reason: 'the PIN check is on screen, not the chat',
      );
      expect(repo.markReadCalls, isEmpty, reason: 'nobody has seen it');

      container.read(appContentVisibleProvider.notifier).setLockOpen(true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.presenceCalls.last, relId);
      await tester.pump(const Duration(milliseconds: 700));
      expect(repo.markReadCalls, isNotEmpty);

      await tearDownChat(tester, container);
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/chat_screen_view_active_test.dart`
Expected: the new test FAILS (`presenceCalls.last == relId` during the check). The existing tests PASS.

- [ ] **Step 3: Implement.** In `chat_screen.dart` (surgical; the user's edits stay):

Add `import 'package:attune/core/services/app_content_visibility.dart';` with the other `package:attune/core/...` imports.

In `initState`, insert directly **before** `WidgetsBinding.instance.addObserver(this);`:

```dart
    // Stories Wave 3: the shell keeps this screen mounted behind the privacy
    // cover and the Safety lock check, so presence and read receipts also
    // wait for the lock to open (a return that ends at the PIN screen must
    // not mark anything read).
    ref.listenManual<bool>(
      appContentVisibleProvider,
      (_, __) => _syncViewActive(),
    );
```

In `_syncViewActive`, change

```dart
        .setViewActive(_isForeground && isCurrentRoute);
```

to

```dart
        .setViewActive(
          _isForeground &&
              isCurrentRoute &&
              ref.read(appContentVisibleProvider),
        );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/chat/chat_screen_view_active_test.dart test/features/chat/voice_playback_chat_route_test.dart`
Then: `flutter test test/features/chat`
Expected: all PASS.

- [ ] **Step 5: Run tests** (replaces Commit)

Run: `flutter test test/features/chat test/features/stories`
Expected: all PASS.

---

### Task 12: The Understand sheet shows a calm idle state when its read was cleared

**Regression risk: low (one sheet).**
- The result is still cleared on `inactive` / `hidden` (spec §6.3; `understand_sheet_test:355-385` stays green).
- The sheet's static source test bans `Copy`, `Send`, `share…`, `Clipboard`, `[Pp]lanning` and `[Cc]omposer` anywhere in `understand_sheet.dart`, comments included. The new code and copy below avoid all of them.

**Files:**
- Modify: `lib/features/ai_assistant/presentation/providers/ai_assistant_providers.dart:227-282` (`UnderstandResultNotifier`)
- Modify: `lib/features/ai_assistant/presentation/screens/understand_sheet.dart` (imports; `_UnderstandSheetState` gains `_readAgain`; the `data:` branch `:161-164`; a new `_ClearedNotice`)
- Test: `test/features/ai_assistant/understand_sheet_test.dart` (one test in `group('backgrounding while open …')`)

**Interfaces:**
- Consumes: nothing from earlier tasks. Task 2 is what keeps the sheet open behind the cover.
- Produces: `UnderstandResultNotifier.clearedWhileAway` (`bool`). It is set when the lifecycle cleared the result, and reset by `requestUnderstand` and `clear()`.

- [ ] **Step 1: Write the failing test.** Add inside `group('backgrounding while open (spec §6.3 + Task 1 privacy cover)', …)`:

```dart
    testWidgets('the sheet stays open behind the cover and, on return, '
        'offers to read it again instead of a blank body (stories Wave 3)', (
      tester,
    ) async {
      final gateway = _FakeAiAssistantGateway()
        ..nextInvokeResult = _okResponse();
      await _pumpSheet(tester, gateway: gateway);
      expect(find.text('They might be tired.'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.byType(UnderstandSheet), findsOneWidget);
      expect(find.text('They might be tired.'), findsNothing);
      expect(find.text('Read it again'), findsOneWidget);
      expect(
        gateway.invokeCallCount,
        1,
        reason: 'nothing is asked again on its own',
      );

      await tester.tap(find.text('Read it again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(gateway.invokeCallCount, 2);
      expect(find.text('They might be tired.'), findsOneWidget);
      expect(find.text('Read it again'), findsNothing);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/ai_assistant/understand_sheet_test.dart`
Expected: the new test FAILS ("Read it again" not found; the body is an empty `SizedBox`). The existing tests PASS.

- [ ] **Step 3: Implement the notifier.** In `UnderstandResultNotifier`:

Add as the first member:

```dart
  /// The result on screen was cleared because Attune left the screen
  /// (inactive or hidden). The sheet stays open behind the privacy cover
  /// now (stories Wave 3), so it shows "Read it again" instead of an empty
  /// body. Reset by the next request and by [clear].
  bool clearedWhileAway = false;
```

In `build`, change the listener to `onInactive: _clearWhileAway, onHide: _clearWhileAway,`, and add below `_clearForBackground`:

```dart
  void _clearWhileAway() {
    clearedWhileAway = true;
    _clearForBackground();
  }
```

In `requestUnderstand`, add `clearedWhileAway = false;` as the first statement. In `clear()`, add `clearedWhileAway = false;` as the first statement.

The relationship-change listener keeps calling `_clearForBackground` (no "Read it again" for another pairing).

- [ ] **Step 4: Implement the sheet.** In `understand_sheet.dart`:

Add the imports:

```dart
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
```

Add to `_UnderstandSheetState` below `_handleDismiss`:

```dart
  void _readAgain() {
    unawaited(
      ref
          .read(understandResultProvider.notifier)
          .requestUnderstand(
            requestId: _requestId,
            messageId: widget.message.id,
            utcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
          ),
    );
  }
```

In `build`'s `data:` branch, replace

```dart
                if (result == null) {
                  return const SizedBox.shrink();
                }
```

with

```dart
                if (result == null) {
                  // Cleared when Attune left the screen; the sheet now stays
                  // open behind the privacy cover (stories Wave 3).
                  if (ref
                      .read(understandResultProvider.notifier)
                      .clearedWhileAway) {
                    return _ClearedNotice(onReadAgain: _readAgain);
                  }
                  return const SizedBox.shrink();
                }
```

Add this class above `_ResultBody`:

```dart
/// The read was cleared when Attune left the screen. Nothing is asked again
/// on its own: the person may have handed the phone over.
class _ClearedNotice extends StatelessWidget {
  const _ClearedNotice({required this.onReadAgain});

  final VoidCallback onReadAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This read was cleared when you left Attune, to keep it private.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Spacing.md),
        OutlinedButton(
          onPressed: onReadAgain,
          child: const Text('Read it again'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/ai_assistant`
Expected: all PASS, including the static source guarantees test.

- [ ] **Step 6: Run tests** (replaces Commit)

Run: `flutter test test/features/ai_assistant test/core/services`
Expected: all PASS.

---

### Task 13: Whole-wave verification and the device check

**Files:** none changed. Report only.

- [ ] **Step 1: Verify Wave 2's posting independence (07b G7, last clause).**

Run: `grep -n "if (!mounted) return;" lib/features/stories/presentation/screens/story_camera_screen.dart` and `flutter test test/features/stories/story_post_pipeline_test.dart`
Expected:
- The pipeline test passes.
- Share's queueing runs in `StoryPostPipeline`, not behind a `mounted` check after `confirmSend`. If a `mounted` check still sits between the take and the enqueue, report it; do not fix it here.

- [ ] **Step 2: The audit is complete.**

Run: `grep -rn "VideoPlayerController\.\|CameraController(\|AudioRecorder(\|AppLifecycleListener(\|didChangeAppLifecycleState" lib`
Expected: every hit is one of:
- handled in this plan (Tasks 6–12);
- Wave 2's camera;
- a provider-level resume refresh;
- `EphemeralCameraScreen` (unreachable, reported);
- `VideoTrimScreen` (never plays);
- a game screen's resume refresh.

Report any other hit.

- [ ] **Step 3: Format check on created files only**

Run: `dart format --set-exit-if-changed lib/core/services/app_content_visibility.dart lib/core/widgets/keep_mounted_cover.dart lib/core/services/media/visible_only_playback.dart test/helpers/state_probe.dart test/helpers/recording_video_platform.dart test/core/services/app_content_visibility_test.dart test/core/services/media/visible_only_playback_test.dart test/app/app_shell_keep_mounted_test.dart test/features/chat/media_visibility_test.dart test/features/chat/voice_record_away_test.dart`
Expected: exit 0.

- [ ] **Step 4: Analyze every touched file**

Run: `flutter analyze lib/core lib/app/app_shell.dart lib/features/safety lib/features/relationships/presentation/widgets/relationship_lifecycle_watcher.dart lib/features/chat/presentation lib/features/stories/presentation lib/features/ai_assistant/presentation test/app test/core test/helpers`
Expected: no new errors or warnings. Compare any info against `git diff` to confirm it is not on a changed line.

- [ ] **Step 5: Whole suite**

Run: `flutter test`
Expected: all PASS. If a test outside this plan fails, read it for one of these patterns:
- it assumed the subtree unmounts on `inactive` (e.g. a finder with `skipOffstage: false` expecting nothing);
- it assumed media keeps playing on `inactive`;
- it assumed a fresh State after resume.

Report the test and the assumption. Change a pre-existing test only if it encodes the teardown this wave removes, and state that in the report.

- [ ] **Step 6: Device check (iOS and Android, release-like build).** Record pass or fail for each:
  1. **Control Centre:**
     - over the partner's story reel: it pauses, and resumes on the same story;
     - over the story camera: the camera comes back live;
     - over a story review: the take and the preview are kept, and the sound stops while covered.
  2. **First story camera use:** the camera, microphone and location alerts appear over the camera, and the camera is still open after answering.
  3. **Incoming call during a reel video, a streak clip, an ephemeral clip, an inline chat video and a voice note:** all silent during the call. Afterwards, the viewers carry on, while the inline video and the voice note wait for a tap.
  4. **Voice note being recorded (locked, then held) and Control Centre pulled:** the recording is paused and kept; it can be resumed, sent or deleted.
  5. **App switch and back, no PIN:** chat scroll position, an open message-actions sheet, Ask Attune's typed draft, and a typed composer with the keyboard up are all kept.
  6. **PIN "every open" set; leave from a playing reel or video and return:**
     - no sound, and no camera indicator, before the PIN screen;
     - the partner's chat shows no "Seen" until unlocked.
  7. **Quick exit (triple tap):**
     - from the reel, the camera review and a bottom sheet: only the decoy;
     - an inactive blip keeps the decoy;
     - with a PIN, the next return shows only the PIN screen.
  8. **Notification Centre pulled down inside Attune and a chat push tapped:** opens that chat on return.
  9. **App-switcher thumbnail on both platforms:** shows only the neutral cover.
  10. **Freshness after 10+ minutes in another app** (partner makes changes meanwhile):
      - These should be fresh without navigating: Chat, Together, Planning, Timeline, Stories rings, Home.
      - Report which of these are stale: appreciation jar, wins cards, quiet state, Pulse, the reflection journal (Regression risk 1; follow-up, not fixed here).
  11. **Partner ends the relationship while this phone is in the background:** the ending sheet shows on the next return (Task 5).
  12. **VoiceOver/TalkBack on:** after a return, focus lands in the app and nothing reads while covered.

- [ ] **Step 7: Report.** List:
  - the pass counts (baseline vs end);
  - any pre-existing test changed and why;
  - the device-check results;
  - the stale surfaces found in item 10;
  - the `EphemeralCameraScreen` note.

---

## Self-review (done while writing; the executor need not repeat it)

- **Spec coverage:**
  - G7 design: Tasks 2 and 3. Locked stays a replacement: Task 3, guard.
  - Snapshot (Offstage): Task 2.
  - Risk 1 (camera): Task 10 (Wave 2 verified, lock half added).
  - Risk 2 (media): Tasks 6–9.
  - Risk 3 (Understand): Task 12.
  - Risk 4 (taps): Tasks 3 and 4.
  - Risk 5 (re-runs): every task's Step "Run tests", plus Task 13.
  - Pushed route survives inactive → resumed and paused → resumed, with and without a PIN: Tasks 2 and 3.
  - Cover hides from finders and semantics: Task 2.
  - Quick exit from every state: Task 4.
  - Stale comments: Tasks 2, 3 and 5.
  - Dead code: ruled, none removed.
- **Names used across tasks:** `appContentVisibleProvider`, `AppContentVisibility.setLockOpen`, `KeepMountedCover(obscured:, cover:, child:)`, `VisibleOnlyPlayback(isVisible:)` (`start` / `onVisibility` / `clear`), `StateProbe`, `semanticLabels`, `RecordingVideoPlatform(initGate:)`, `Key('safety_lock_checking_cover')`, `Key('app_privacy_cover_overlay')`, `clearedWhileAway`.
