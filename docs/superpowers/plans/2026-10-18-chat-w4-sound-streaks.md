# Chat Wave 4 — Sounds, Streaks & Games-in-Chat Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chat chirps never pause the person's music or break the silent switch, a streak view is only spent once the clip has actually been shown (and replays refuse to open after the 30-minute window), a failed streak upload says so, and a partner's game move gives live, quiet feedback in the transcript — plus the remaining motion/haptic/preview polish from review 06.

**Architecture:** One `AudioSessionCoordinator` (new, `lib/core/ui/feedback/audio_session.dart`) owns every audio-context decision: UI chirps use an explicit `AudioContext` (Android: no audio focus + notification stream; iOS: ambient), voice-note playback *borrows* the session (transient focus / playback category) and hands it back when it stops, and on iOS the chirp context is re-asserted before every chirp because `AVAudioSession` is process-global and `audioplayers_darwin` applies even per-player contexts globally. Streak viewing gets a client "presented" gate plus a server read gate (`streak_clips_for_viewing` RPC + tightened RLS). Game-move feedback is detected by `sort_at` advancing on a known card (`GameMoveLedger` in the list, `_maybePartnerMoveHaptic` in `ChatState`), and arrivals are time-boxed (`PendingArrivals`) so nothing animates minutes late.

**Tech Stack:** Flutter 3.29, Riverpod 2.6, audioplayers 6.6.0 (platform_interface 7.1.1, android 5.2.1, darwin 6.4.0), video_player, Supabase PG17 (local scratch DB `attune_spec3a`), package:clock.

**Spec:** `docs/reviews/2026-10-18-chat-robustness-review.md` (issues #39–#43) and `docs/reviews/2026-10-18-chat-review/06_motion_sound_streaks_games.md` (H-1, H-2, M-3, M-5, M-6, M-7, M-8, L-10–L-15) with verifier notes in `docs/reviews/2026-10-18-chat-review/V2_media_motion_server_verify.md`; chat rules in `lib/architecture/CHAT_SYSTEM_SPEC.md`.

## Global Constraints

- Work on main in the existing working tree (the owner has other uncommitted work; never revert or reformat it). NO COMMITS: replace every "Commit" step with "Checkpoint: run this task's tests and `flutter analyze <touched files>` filtered with `grep -E '^\s*(error|warning) '`; no commit (the owner commits)".
- Never run `dart format` on pre-existing files (repo uses an older formatter; reflowing is a regression). Only new files may be formatted.
- Test-first: every fix starts with a failing test that reproduces the verified failure scenario; watch it fail for the right reason, then fix.
- Flutter tests: `flutter test <path>`; reuse existing harnesses (test/features/chat/support/chat_test_harness.dart, FakeChatRepository, fake cache backends, FakeHaptics). Update old tests only where they encode the wrong behaviour, and say so.
- SQL: new migrations only (never edit an existing migration). Use ONLY your assigned timestamp range (20261019140000–20261019149999). Apply locally with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/<file>.sql`; contract tests in supabase/tests/<name>_contracts.sql in the existing style (BEGIN … RAISE EXCEPTION 'CONTRACT VIOLATED: …' … ROLLBACK; see supabase/tests/home_card_order_contracts.sql and chat_system_contracts.sql), run with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/<file>.sql`. Include a mutation check for each key rule (temporarily break the rule in a transaction and show the contract fails). NEVER use the attune_test database. Never touch the live project; deploying migrations/functions is an owner step — list them at the end under "Owner deploy steps".
- Edge functions (Deno/TS): follow existing patterns in supabase/functions; if the function has Deno tests, add tests; otherwise extract pure logic into a testable module with a Deno test (`deno test` if available — check `which deno`; if not available, say so and make the logic testable via SQL or Dart instead). (This plan touches no edge function.)
- Owner-only steps (Xcode capabilities, OneSignal dashboard settings, App Store / Apple developer portal) are listed explicitly as "Owner step" with exact instructions; the plan still makes every file change that can be made in the repo (e.g. entitlements/Info.plist edits).
- Display dates via MyDateFormat; user-facing copy plain and warm; respect reduceMotionOf for animations; haptics via hapticsProvider.
- Don't touch ATTUNE_SOUL.md / ATTUNE_THESIS.md. Don't read .env/credentials/keychain.
- Execution order across plans: 1a → 1b → 2 → 3 → 4, sequential on the same tree. Later plans must not assume line numbers from before earlier plans ran; say which files you share with other plans in a "Shared files" note.

### Shared files (this plan runs LAST — read the current file before each edit; nothing below cites line numbers)

| File | Also touched by | How to merge |
|---|---|---|
| `lib/features/chat/presentation/state/voice_playback_controller.dart` (created by Plan 2 Task 7) and `test/features/chat/support/fake_voice_engine.dart` (Plan 2) | Plan 2 owns them: `VoicePlaybackEngine` (abstract), `AudioPlayersVoiceEngine`, `VoicePlaybackEngine.setAudioContext` (the seam Plan 2 left for this plan), `VoicePlaybackController` (`_startFresh` calls `_engine.setAudioContext(AudioContextConfig(respectSilence: false).build())` once; `toggle/pause/stop/_onComplete/_onEnginePlaying/_fail/dispose`), `FakeVoiceEngine` (`contexts`, `nextPlayError`; `buildChatContainer` default-overrides the engine with it), `voicePlaybackEngineProvider`, `voicePlaybackControllerProvider`. | Task 3 edits ONLY the controller file (not `voice_message_player.dart`, which after Plan 2 is a stateless view with no player): that one `setAudioContext` call becomes `AudioSessionCoordinator.beginPlayback(_engine.setAudioContext)` and the session is returned at every transition. `grep -rn "respectSilence" lib/` must return nothing after Task 3. |
| `lib/features/chat/presentation/widgets/voice_message_player.dart` | Plan 2 (becomes a `ConsumerWidget` view of the controller) | Not edited here. |
| `lib/core/ui/feedback/sound_service.dart` | — | Task 2 rewrites `preload`/`play`/constructor/provider. |
| `lib/features/chat/presentation/screens/chat_screen.dart` | Plans 1a (Task 5 `onRetry` gating, Task 7 lifecycle, Task 8 RouteAware, Task 9 draft), 2 (Task 3 `_attachImage`, Task 7 voice stop in `initState`/`dispose`, Task 9 `onCancelSend:`), 3 (Task 3 `_send`/`_sendDraftText` over-limit refusal via `_refuseOverLimitDraft`, Task 7 drops the `ValueListenableBuilder` around `MessageBubble(`, Task 8 `MeasureSize`/`bottomOverlayHeight`, Task 9 `KeyedSubtree` row keys + `findChildIndexCallback`, Task 10 `_syncArrivals` gains the `_awayFromBottom`/`_unseenWhileAway` block + pill + divider, Task 13 `_jumpToMessage`/`_scrollUntilBuilt`/`_nearestBuiltRow`) | Tasks 7, 8, 9, 10, 11, 12 each change one named function/callback (`_syncArrivals` — Task 7 shows the POST-plan-3 body, `itemBuilder`'s `MakeRoom`/`SettleIn` keys, `_scrollToLatest`, `_tryEnsureMessageVisible`, the typing `AnimatedSwitcher`, `_send`, `_sendStagedGame`, the `onReact:` handler, the `MessageBubble(` construction). Edit by function name; never re-introduce `_pendingArrivalIds` or the `ValueListenableBuilder`. |
| `lib/features/chat/presentation/state/chat_state.dart` | Plans 1a/1b (#1–#9: outbox, realtime batch, `reconcileWindow`, `_init` rewritten but its baseline fold kept verbatim), 2, 3 (`starredMessagesProvider`, `loadMoreMessages({limit})`, `ensureMessageLoaded`) | Task 7 changes only `_maybeReceiveHaptic` and the baseline fold in `_init`, and adds one private map + one private method. |
| `lib/features/chat/presentation/widgets/message_bubble.dart` | Plan 2 (Task 9 `onCancelSend`), Plan 3 (Task 1 edited label, Task 4 `LinkifiedMessageText` + `onCopyLink`, Task 5 decode size, Task 7 `build` split into hoisted `content`/`footer` + `shell(revealOffset)`, Task 11 reveal tick) | Tasks 5, 6, 10, 12 add parameters and edit the streak/game branches of `_BubbleBody`, the `_BubbleBody(` construction (now inside the hoisted `content` Column) and the `onLongPress:` lambda (now inside `shell`). Same names, new nesting — grep, don't assume position. |
| `test/features/chat/support/chat_test_harness.dart` | all plans (1a: `getMessagesCalls`, `serverUpdatedAt`, typed `emitRealtime`; 3: `editHistory`, `hiddenFromPages`, `seedIncoming(editedAt/replyToMessageId/quotedText)`) | Task 7 adds two more optional parameters to `FakeChatRepository.seedIncoming` (additive only). |
| `test/features/chat/voice_playback_audio_context_test.dart` | Plan 2 Task 7 re-points its two player assertions at `voice_playback_controller.dart` | Tasks 2 and 3 replace all three tests (they pin the OLD context strings). |
| `lib/core/ui/motion/motion_tokens.dart` | — | Task 8 adds one constant. |

## Rulings — items from 06 that get no task here (with evidence)

- **M-4 typing/staged-game/reply strips cover the newest message** → issue **#33, plan 3**. Not planned here.
- **M-9 timestamp-reveal drag rebuilds every bubble** → issue **#38, plan 3**. Not planned here.
- **M-7 second half (scroll-to-bottom pill / "new messages")** → issue **#32, plan 3**. This plan only time-boxes late arrivals (Task 8) so they never animate under the finger regardless of what plan 3 adds.
- **L-12 maxLength / keeping a too-long draft in the composer** → issue **#35, plan 3**. Task 11 here only moves the send chirp/haptic *behind* the validity check and adds the missing chirp to `_sendStagedGame`. The `StreakCameraScreen` chirp-on-bail case is not planned: the camera is only reachable through the `streakCamera` route pushed from the composer of a sendable conversation (`lib/app/routing/app_router.dart`), and `_playSound(AppSound.streakSend)` fires after `sendStreakMessage` has been handed the file; if the owner ever sees a chirp with no bubble in device testing, await the controller call and chirp on its result.
- **L-13 "offline game card still opens"** → only partially planned (Task 12 fixes the read-only-transcript `viewerId` and the loading-vs-error label). Opening a card whose session stream has not loaded needs the game type, which lives only on `game_sessions` (the message row carries `game_session_id` + the display name in `content`; `gameTypeDisplayName` has no inverse) — a server/data-model change outside this wave. Recorded as a follow-up.
- **L-15 "Expressive moments" barely perceptible** → not planned. It is polish, not robustness, the toggle *is* honoured (`chatExpressivenessProvider` drives `kShimmerSweepExpressive` and `kCascadeStepExpressiveMs`), and the copy lives in `lib/features/settings/screens/settings_screen.dart`, which is in the owner's uncommitted working set (`git status` at planning time). Suggested owner follow-up: soften the copy to "Slightly livelier first-of-day and catch-up animations".
- **M-5 server-side suggestion (trail `sort_at - 1 µs`)** → not needed: `move_game_card` rewrites the card's `sort_at` to `clock_timestamp()` *after* `leave_game_trail` copies the old `sort_at`, so the trail never ties with the card. The live defs (`pg_get_functiondef` on `attune_spec3a`) confirm this. Client-side M-5 (card teleports, trail animates mid-history, no haptic) is **#43 → Task 7**.
- **iOS music resuming after a voice note** (`audioplayers_darwin` calls `AVAudioSession.setActive(false)` without `.notifyOthersOnDeactivation`, `AudioContext.swift:25`) → not in #40's scope (#40 is "chirps respect the silent switch and mix; voice note borrows the session and gives it back"). Recorded as an optional owner follow-up (a 10-line Swift method on the existing `attune/recording_haptics`-style channel).
- **`streak_clips` has `anon SELECT` granted** (`information_schema.role_table_grants` on `attune_spec3a`) — RLS `relationship_chat_open(...)` returns false without `auth.uid()`, so anon reads nothing; Spec 3b's lockdown migration owns grants. Not touched here.

## Review Focus

Five conditions the spec implies but no task below exercises by test; each gets a pinning test in the owning task (marked "Review Focus" in the step):

1. **A chirp fires while a voice note is playing (iOS)** — the coordinator must NOT yank the session back to ambient under the voice note; the chirp plays under the borrowed session and ambient returns when the note ends. → Task 1 test "a chirp during a held playback leaves the session alone".
2. **Two voice notes overlap begin/end (fast pause/play or cross-bubble auto-pause)** — the hold count must never go negative and ambient must be restored exactly once the last hold ends. → Task 1 test "holds are counted, not boolean".
3. **Streak video that never reaches its first frame** (controller `initialize()` hangs, user backs out) — nothing spent, result `null`. → Task 4 test 3.
4. **Streak whose clips the server says are gone** (`fetchClips` returns `[]`) — the view IS still "spent" (RPC returns 0) so the bubble syncs to "Opened" on both sides; this must keep working with the presented gate. → Task 4 keeps `streak_viewer_pop_test.dart` green and adds an explicit test.
5. **A partner move on a card already at the bottom and already on the partner's side** (session game answered twice) — `move_game_card` still bumps `sort_at`; the ledger must report a move (settle in place) and the haptic fire once, without a duplicate "receive" chirp. → Task 7 ledger test "a card that only re-sorts in place still counts as a move" and ChatState test "a moved card never doubles as a new partner message".

## File Structure

**Create**
- `lib/core/ui/feedback/audio_session.dart` — `AppAudioContexts`, `AudioSessionPort` (+ `AudioplayersSessionPort`, `FakeAudioSessionPort`), `AudioSessionCoordinator`, `audioSessionProvider`.
- `lib/features/chat/domain/utils/streak_replay_window.dart` — `kStreakReplayWindow`, `streakViewsAvailable(Message, DateTime)`.
- `lib/features/chat/presentation/widgets/pending_arrivals.dart` — `PendingArrivals` (time-boxed arrival ledger).
- `lib/features/chat/presentation/widgets/game_move_ledger.dart` — `GameMoveLedger` (detects a card whose `sortAt` advanced; per-card move revision).
- `supabase/migrations/20261019140000_streak_replay_window_read_gate.sql` — `expire_streak_clips`, `streak_clips_for_viewing`, tightened `streak_clips_members_read`.
- `supabase/tests/streak_replay_window_contracts.sql`.
- Tests: `test/core/ui/audio_session_coordinator_test.dart`, `test/features/chat/streak_viewer_presented_gate_test.dart`, `test/features/chat/streak_replay_window_test.dart`, `test/features/chat/pending_arrivals_test.dart`, `test/features/chat/game_move_ledger_test.dart`, `test/features/chat/game_move_haptic_test.dart`, `test/features/chat/reduce_motion_gaps_test.dart`, `test/features/chat/message_actions_haptics_test.dart`, `test/features/chat/send_feedback_after_validation_test.dart`, `test/features/chat/game_card_viewer_test.dart`.

**Modify**
- `lib/core/ui/feedback/sound_service.dart` — explicit chirp context via the coordinator; iOS re-assert per chirp; `createPlayer` test seam.
- `lib/features/chat/presentation/state/voice_playback_controller.dart` (Plan 2's) — the controller borrows/returns the session through Plan 2's `engine.setAudioContext` seam (`FakeVoiceEngine` already records the context; not edited).
- `supabase/migrations/20261019140010_streak_replay_window_read_gate_grants.sql`, `scripts/local_pg_grants.sql` (one `\i` line) — grants for Task 5's functions, in the repo's grants-file convention.
- `lib/features/chat/presentation/screens/streak_viewer_screen.dart` — presented gate, close affordance, photo frame signal, image-provider test seam.
- `lib/features/chat/data/repositories/streak_repository.dart` — `fetchClips` via RPC.
- `lib/features/chat/presentation/widgets/streak_bubble.dart` — failed state.
- `lib/features/chat/presentation/widgets/message_bubble.dart` — streak branch (window mirror, failed state), `onActionsOpened`, `viewerUserId`.
- `lib/features/chat/presentation/state/chat_state.dart` — `_maybePartnerMoveHaptic`, game rows excluded from the receive-haptic fold.
- `lib/features/chat/presentation/screens/chat_screen.dart` — `_syncArrivals` (ledger + time-box + trails), arrival keys, reduce-motion sites, haptics, send chirp ordering, `viewerUserId`.
- `lib/features/games/presentation/widgets/game_message_bubble.dart` — error label.
- `lib/features/chat/presentation/widgets/streak_record_button.dart` — reduce-motion entrance.
- `lib/features/chat/domain/utils/conversation_preview.dart`, `lib/features/chat/data/repositories/supabase_chat_repository.dart` — preview labels, search excludes trails.
- `lib/core/ui/motion/motion_tokens.dart` — `kArrivalAnimationWindow`.
- Tests updated because they encoded the old behaviour: `test/features/chat/voice_playback_audio_context_test.dart` (asserted `respectSilence:` strings), `test/features/chat/streak_repository_test.dart` ("fetchClips selects no caption or budget columns" — now an RPC), `test/features/chat/streak_bubble_test.dart` (additive), `test/features/chat/conversation_preview_test.dart` (additive), `test/features/chat/support/chat_test_harness.dart` (additive).

---

### Task 1: AudioSessionCoordinator (#39, #40 core)

**Files:**
- Create: `lib/core/ui/feedback/audio_session.dart`
- Test: `test/core/ui/audio_session_coordinator_test.dart`

**Interfaces:**
- Consumes: `package:audioplayers` `AudioContext`, `AudioContextAndroid`, `AudioContextIOS`, `AndroidAudioFocus`, `AndroidUsageType`, `AndroidContentType`, `AVAudioSessionCategory`, `AudioPlayer.global.setAudioContext`.
- Produces (used by Tasks 2 and 3):
  - `abstract final class AppAudioContexts { static final AudioContext chirp; static final AudioContext voiceNote; }`
  - `typedef PlayerContextSetter = Future<void> Function(AudioContext context);` (callers pass `player.setAudioContext`)
  - `abstract class AudioSessionPort { Future<void> setGlobalContext(AudioContext context); }`, `class AudioplayersSessionPort`, `class FakeAudioSessionPort { final List<AudioContext> globalContexts; }`
  - `class AudioSessionCoordinator { AudioSessionCoordinator({required AudioSessionPort port, TargetPlatform? platform}); bool get playbackHeld; Future<void> applyChirpGlobalContext(); Future<void> configureChirpPlayer(PlayerContextSetter set); Future<void> beforeChirp(PlayerContextSetter set); Future<void> beginPlayback(PlayerContextSetter set); Future<void> endPlayback(); }`
  - `final audioSessionProvider = Provider<AudioSessionCoordinator>`

Why explicit contexts and not `AudioContextConfig(focus: …)`: the reviewer's suggested `AudioContextConfigFocus.none` does not exist (the enum is `gain | duckOthers | mixWithOthers`, `audio_context_config.dart` in audioplayers_platform_interface 7.1.1), `mixWithOthers` + `respectSilence` fails `validateIOS()`, and `buildIOS()` returns `null` off-iOS so a test can never see the iOS side. `AudioContext(android: …, iOS: …)` is deterministic on every platform.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/ui/audio_session_coordinator_test.dart
import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what a caller's `player.setAudioContext` would have received.
class _Recorder {
  final List<AudioContext> contexts = [];
  Future<void> set(AudioContext context) async => contexts.add(context);
}

void main() {
  group('AppAudioContexts', () {
    test('chirps request no Android audio focus and sit on the '
        'notification stream', () {
      // AUDIOFOCUS_GAIN (the package default) is permanent: Spotify gets
      // AUDIOFOCUS_LOSS and never resumes. FocusManager.kt skips the
      // request entirely for AUDIOFOCUS_NONE.
      final android = AppAudioContexts.chirp.android;
      expect(android.audioFocus, AndroidAudioFocus.none);
      expect(android.usageType, AndroidUsageType.notificationCommunicationInstant);
      expect(android.contentType, AndroidContentType.sonification);
    });

    test('chirps are ambient on iOS (silent switch mutes, mixes with others)',
        () {
      expect(AppAudioContexts.chirp.iOS.category, AVAudioSessionCategory.ambient);
      expect(AppAudioContexts.chirp.iOS.options, isEmpty);
    });

    test('a voice note takes TRANSIENT focus on Android and playback on iOS',
        () {
      // Transient, not gain: the music app resumes when the note ends.
      expect(AppAudioContexts.voiceNote.android.audioFocus,
          AndroidAudioFocus.gainTransient);
      expect(AppAudioContexts.voiceNote.android.usageType, AndroidUsageType.media);
      expect(AppAudioContexts.voiceNote.iOS.category,
          AVAudioSessionCategory.playback);
    });
  });

  group('AudioSessionCoordinator', () {
    test('preload sets the chirp context globally and per player', () async {
      final port = FakeAudioSessionPort();
      final session = AudioSessionCoordinator(port: port);
      final player = _Recorder();

      await session.applyChirpGlobalContext();
      await session.configureChirpPlayer(player.set);

      expect(port.globalContexts, [AppAudioContexts.chirp]);
      expect(player.contexts, [AppAudioContexts.chirp]);
    });

    test('on iOS every chirp re-asserts ambient first', () async {
      // AVAudioSession is process-global; audioplayers_darwin applies even a
      // per-player context to the shared session, and video_player upgrades
      // it to playback whenever a video is created. Nothing else ever puts
      // ambient back, so the chirp has to.
      final session = AudioSessionCoordinator(
        port: FakeAudioSessionPort(),
        platform: TargetPlatform.iOS,
      );
      final player = _Recorder();
      await session.beforeChirp(player.set);
      await session.beforeChirp(player.set);
      expect(player.contexts, [AppAudioContexts.chirp, AppAudioContexts.chirp]);
    });

    test('on Android the per-player context persists, so a chirp sets nothing',
        () async {
      final session = AudioSessionCoordinator(
        port: FakeAudioSessionPort(),
        platform: TargetPlatform.android,
      );
      final player = _Recorder();
      await session.beforeChirp(player.set);
      expect(player.contexts, isEmpty);
    });

    test('a voice note borrows the session and gives it back', () async {
      final port = FakeAudioSessionPort();
      final session = AudioSessionCoordinator(
        port: port,
        platform: TargetPlatform.iOS,
      );
      final voice = _Recorder();

      await session.beginPlayback(voice.set);
      expect(voice.contexts, [AppAudioContexts.voiceNote]);
      expect(session.playbackHeld, isTrue);

      await session.endPlayback();
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts, [AppAudioContexts.chirp],
          reason: 'ambient must be restored the moment playback ends');
    });

    test('a chirp during a held playback leaves the session alone', () async {
      // Review Focus 1: a receive chirp mid-voice-note must not flip the
      // session to ambient under the note (which would mute it on silent).
      final session = AudioSessionCoordinator(
        port: FakeAudioSessionPort(),
        platform: TargetPlatform.iOS,
      );
      await session.beginPlayback((_) async {});
      final chirp = _Recorder();
      await session.beforeChirp(chirp.set);
      expect(chirp.contexts, isEmpty);
    });

    test('holds are counted, not boolean', () async {
      // Review Focus 2: two overlapping notes (cross-bubble auto-pause races
      // the next play) release ambient once, after the LAST end; a stray
      // extra end never drives the count negative.
      final port = FakeAudioSessionPort();
      final session = AudioSessionCoordinator(
        port: port,
        platform: TargetPlatform.iOS,
      );
      await session.beginPlayback((_) async {});
      await session.beginPlayback((_) async {});
      await session.endPlayback();
      expect(port.globalContexts, isEmpty);
      expect(session.playbackHeld, isTrue);
      await session.endPlayback();
      expect(port.globalContexts, [AppAudioContexts.chirp]);
      await session.endPlayback(); // stray
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts, [AppAudioContexts.chirp]);
    });

    test('a failed beginPlayback does not leave a phantom hold', () async {
      final session = AudioSessionCoordinator(
        port: FakeAudioSessionPort(),
        platform: TargetPlatform.iOS,
      );
      await expectLater(
        session.beginPlayback((_) async => throw Exception('no plugin')),
        throwsException,
      );
      expect(session.playbackHeld, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/core/ui/audio_session_coordinator_test.dart`
Expected: compile error — `Target of URI doesn't exist: 'package:attune/core/ui/feedback/audio_session.dart'`.

- [ ] **Step 3: Implement the coordinator**

```dart
// lib/core/ui/feedback/audio_session.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sets one player's audio context — callers pass `player.setAudioContext`.
/// A closure rather than an [AudioPlayer] so the coordinator (and its tests)
/// never need a real platform player.
typedef PlayerContextSetter = Future<void> Function(AudioContext context);

/// The only two audio sessions this app asks for. Explicit [AudioContext]s,
/// not [AudioContextConfig]: the config helper has no "no focus" option, its
/// iOS half is null off-iOS, and `respectSilence` cannot be combined with
/// `mixWithOthers` — so it can express neither of these correctly.
abstract final class AppAudioContexts {
  /// UI chirps. Android: AUDIOFOCUS_NONE (FocusManager.kt skips the focus
  /// request entirely, so music keeps playing) on the notification stream
  /// (muted by silent/vibrate ring mode) as a sonification. iOS: ambient —
  /// muted by the silent switch, mixes with other apps' audio.
  static final AudioContext chirp = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notificationCommunicationInstant,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  /// A voice note the person deliberately tapped: plays through the silent
  /// switch. Android takes TRANSIENT focus (the music app pauses and resumes
  /// when the note ends; AUDIOFOCUS_GAIN is permanent and Spotify never comes
  /// back from it). iOS: playback.
  static final AudioContext voiceNote = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
  );
}

/// The process-wide audio session. Injectable so the coordinator's rules can
/// be tested without a platform channel.
abstract class AudioSessionPort {
  Future<void> setGlobalContext(AudioContext context);
}

class AudioplayersSessionPort implements AudioSessionPort {
  const AudioplayersSessionPort();

  @override
  Future<void> setGlobalContext(AudioContext context) =>
      AudioPlayer.global.setAudioContext(context);
}

class FakeAudioSessionPort implements AudioSessionPort {
  final List<AudioContext> globalContexts = [];

  @override
  Future<void> setGlobalContext(AudioContext context) async =>
      globalContexts.add(context);
}

/// Single owner of "which audio session are we in".
///
/// Chirps and voice notes used to each set their own context and never
/// coordinate: on iOS `audioplayers_darwin` applies a per-player context to
/// the SHARED AVAudioSession (its own log says so), so one voice note left
/// every later chirp on the playback category — audible through the silent
/// switch and pausing other apps' music until restart. On Android the
/// package default (AUDIOFOCUS_GAIN) made every chirp request permanent
/// focus, which stops the person's music for good.
class AudioSessionCoordinator {
  AudioSessionCoordinator({required this.port, TargetPlatform? platform})
    : _platform = platform;

  final AudioSessionPort port;
  final TargetPlatform? _platform;
  TargetPlatform get _target => _platform ?? defaultTargetPlatform;

  int _playbackHolds = 0;

  /// True while at least one voice note holds the session.
  bool get playbackHeld => _playbackHolds > 0;

  /// App start / sound preload: the default for every player created later.
  Future<void> applyChirpGlobalContext() =>
      port.setGlobalContext(AppAudioContexts.chirp);

  /// Once per preloaded chirp player. On Android this is what actually
  /// decides focus/stream per player; on iOS it (re)applies the global.
  Future<void> configureChirpPlayer(PlayerContextSetter set) =>
      set(AppAudioContexts.chirp);

  /// Immediately before a chirp plays.
  ///
  /// iOS only: AVAudioSession is global and anything (a voice note, a video
  /// message, the streak viewer — video_player upgrades the category to
  /// playback when it creates a player) may have left it on playback, and
  /// nothing else ever puts ambient back. Skipped while a voice note holds
  /// the session: the chirp then plays under the borrowed session rather
  /// than muting the note someone is listening to. Android keeps the
  /// per-player context from [configureChirpPlayer], so nothing to do.
  Future<void> beforeChirp(PlayerContextSetter set) async {
    if (_target != TargetPlatform.iOS || playbackHeld) return;
    await set(AppAudioContexts.chirp);
  }

  /// A voice note is about to play: borrow the session.
  Future<void> beginPlayback(PlayerContextSetter set) async {
    _playbackHolds++;
    try {
      await set(AppAudioContexts.voiceNote);
    } catch (_) {
      _playbackHolds--;
      rethrow;
    }
  }

  /// The voice note paused, completed, failed or was disposed: give the
  /// session back once the LAST hold is released. Counted, not boolean —
  /// cross-bubble auto-pause can overlap the next bubble's play.
  Future<void> endPlayback() async {
    if (_playbackHolds == 0) return;
    _playbackHolds--;
    if (_playbackHolds > 0) return;
    await port.setGlobalContext(AppAudioContexts.chirp);
  }
}

final audioSessionProvider = Provider<AudioSessionCoordinator>(
  (ref) => AudioSessionCoordinator(port: const AudioplayersSessionPort()),
);
```

Format this new file only: `dart format lib/core/ui/feedback/audio_session.dart test/core/ui/audio_session_coordinator_test.dart`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/ui/audio_session_coordinator_test.dart`
Expected: `All tests passed!` (10 tests).

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/core/ui/feedback/audio_session.dart test/core/ui/audio_session_coordinator_test.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

### Task 2: Chirps go through the coordinator (#39, #40)

**Files:**
- Modify: `lib/core/ui/feedback/sound_service.dart` (`AudioPlayerSoundService.preload`, `play`, constructor, `soundServiceProvider`)
- Modify: `test/features/chat/voice_playback_audio_context_test.dart` (its "SoundService still keeps UI chirps on the silent switch" test asserts the literal `respectSilence: true` — that string disappears; the test is rewritten to assert the behaviour through `AppAudioContexts`)
- Test: `test/core/ui/sound_service_test.dart` (add)

**Interfaces:**
- Consumes: Task 1 (`AudioSessionCoordinator`, `audioSessionProvider`, `FakeAudioSessionPort`).
- Produces: `AudioPlayerSoundService({AudioSessionCoordinator? session, AudioPlayer Function()? createPlayer})` — `createPlayer` defaults to `AudioPlayer.new`; tests pass a factory that throws so no platform player is ever constructed on the host (an `AudioPlayer()` on a plugin-less host completes its `creatingCompleter` with an error that the unawaited `..setReleaseMode` cascade would surface as an unhandled async error); `soundServiceProvider` now reads `audioSessionProvider`.

- [ ] **Step 1: Write the failing tests**

Append to `test/core/ui/sound_service_test.dart` (inside `main`, after the existing tests):

```dart
  test('preload puts the whole process on the chirp context first', () async {
    // The global context is applied BEFORE any player is created. The
    // factory throws so the per-asset guard swallows every clip and no
    // platform player exists on this host; the global call is what counts.
    final port = FakeAudioSessionPort();
    final s = AudioPlayerSoundService(
      session: AudioSessionCoordinator(port: port),
      createPlayer: () => throw StateError('no audio on the test host'),
    );
    await s.preload();
    expect(port.globalContexts, [AppAudioContexts.chirp]);
    s.dispose();
  });

  test('every preloaded chirp player gets the chirp context itself', () async {
    // Android decides focus/stream PER PLAYER from the player's own
    // context; the global default only seeds players created later.
    final seen = <AudioContext>[];
    final port = FakeAudioSessionPort();
    final s = AudioPlayerSoundService(
      session: AudioSessionCoordinator(port: port),
      createPlayer: () => _ContextOnlyPlayer(seen),
    );
    await s.preload();
    // One per AppSound value, before any setSource (which throws here).
    expect(seen.length, AppSound.values.length);
    expect(seen.toSet(), {AppAudioContexts.chirp});
    s.dispose();
  });

  test('the sound service no longer builds contexts from the config helper', () {
    // AudioContextConfig has no "no focus" option and its default
    // (focus: gain) is what paused the person's music on Android. Every
    // context must come from AppAudioContexts.
    final source =
        File('lib/core/ui/feedback/sound_service.dart').readAsStringSync();
    expect(source, isNot(contains('AudioContextConfig(')));
    expect(source, contains('AppAudioContexts'));
  });
```

Add the imports at the top of that test file:

```dart
import 'dart:io';

import 'package:attune/core/ui/feedback/audio_session.dart';
import 'package:audioplayers/audioplayers.dart';
```

and, above `main`, a player double that records only the context and refuses everything else (so `setSource` lands in the per-asset guard exactly as a missing clip would):

```dart
/// Records setAudioContext; every other platform call throws, so preload's
/// per-asset guard skips the clip without a real player ever existing.
class _ContextOnlyPlayer implements AudioPlayer {
  _ContextOnlyPlayer(this.seen);
  final List<AudioContext> seen;

  @override
  Future<void> setAudioContext(AudioContext ctx) async => seen.add(ctx);

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {}

  @override
  Future<void> setPlayerMode(PlayerMode mode) async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} unused on the test host');
}
```

(`setSource` goes through `noSuchMethod` and throws — that is the point. A class with a `noSuchMethod` override satisfies `implements AudioPlayer` without listing every member.)

Replace the test `'SoundService still keeps UI chirps on the silent switch'` in `test/features/chat/voice_playback_audio_context_test.dart` with:

```dart
  test('UI chirps stay on the silent switch and off other apps\' audio', () {
    // The fix must not swing the other way: notification blips stay muted
    // when the phone is silenced (iOS ambient), and never take Android
    // audio focus.
    expect(AppAudioContexts.chirp.iOS.category, AVAudioSessionCategory.ambient);
    expect(AppAudioContexts.chirp.android.audioFocus, AndroidAudioFocus.none);
  });
```

with imports `package:attune/core/ui/feedback/audio_session.dart` and `package:audioplayers/audioplayers.dart` added. (Its two voice-player tests are rewritten in Task 3.)

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/core/ui/sound_service_test.dart`
Expected: compile error `The named parameter 'session' isn't defined` / `'createPlayer' isn't defined` (new tests) and, once that compiles, `Expected: not contains 'AudioContextConfig('` for the source test.

- [ ] **Step 3: Implement**

In `lib/core/ui/feedback/sound_service.dart`:

Add the import `import 'package:attune/core/ui/feedback/audio_session.dart';`.

Replace the `AudioPlayerSoundService` constructor line and add the fields:

```dart
class AudioPlayerSoundService implements SoundService {
  AudioPlayerSoundService({
    AudioSessionCoordinator? session,
    AudioPlayer Function()? createPlayer,
  }) : _session =
           session ??
           AudioSessionCoordinator(port: const AudioplayersSessionPort()),
       _createPlayer = createPlayer ?? AudioPlayer.new;

  /// Owns every audio-context decision; see AudioSessionCoordinator.
  final AudioSessionCoordinator _session;

  /// Test seam: a host with no audio plugin hands in a player double.
  final AudioPlayer Function() _createPlayer;
```

Replace the body of `preload()`'s `try` block (the comment block about `respectSilence`, the `AudioPlayer.global.setAudioContext(...)` call and the per-asset loop) with:

```dart
    try {
      // Chirps never take Android audio focus and are ambient on iOS. The
      // old AudioContextConfig(respectSilence: true) silently defaulted to
      // AUDIOFOCUS_GAIN, which stopped the person's music permanently.
      await _session.applyChirpGlobalContext();
      for (final entry in _assets.entries) {
        // Per-asset guard: a missing clip (e.g. game_*.wav not yet added) loads
        // nothing for that key and is skipped, without aborting the others.
        try {
          final player =
              _createPlayer()
                ..setReleaseMode(ReleaseMode.stop)
                ..setPlayerMode(PlayerMode.lowLatency);
          // Per player: on Android this is the context that actually
          // governs focus and stream for this player.
          await _session.configureChirpPlayer(player.setAudioContext);
          await player.setSource(AssetSource(entry.value));
          _players[entry.key] = player;
        } catch (_) {
          if (kDebugMode) {
            debugPrint('[sound] ${entry.value} unavailable: silent no-op');
          }
        }
      }
      // Ready if at least one clip loaded; play() no-ops any missing key.
      _ready = true;
    } catch (e) {
```

Replace the last statement of `play()` (`player.seek(Duration.zero).then((_) => player.resume()).catchError((_) {});`) with:

```dart
    // iOS re-asserts ambient before each chirp (AVAudioSession is global and
    // a voice note / video may have moved it); Android is a no-op here.
    _session
        .beforeChirp(player.setAudioContext)
        .then((_) => player.seek(Duration.zero))
        .then((_) => player.resume())
        .catchError((_) {});
```

Also update the class doc comment (`/// Real player. One preloaded AudioPlayer per sound. iOS uses the ambient audio context …`) to: `/// Real player. One preloaded AudioPlayer per sound, on AppAudioContexts.chirp (no Android focus, iOS ambient) via the AudioSessionCoordinator.`

Replace `soundServiceProvider`:

```dart
final soundServiceProvider = Provider<SoundService>((ref) {
  final service = AudioPlayerSoundService(
    session: ref.read(audioSessionProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/core/ui/sound_service_test.dart test/features/chat/voice_playback_audio_context_test.dart test/features/chat/send_sound_test.dart test/features/chat/receive_sound_test.dart test/features/games/paint_ball_sound_test.dart test/features/settings/sound_preference_test.dart`
Expected: `All tests passed!` (the two voice-player tests in `voice_playback_audio_context_test.dart` still pass at this point because the voice player is unchanged until Task 3).

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/core/ui/feedback/sound_service.dart test/core/ui/sound_service_test.dart test/features/chat/voice_playback_audio_context_test.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

**Device check (owner, after deploy):** Android — play Spotify, send and receive a message in chat: music keeps playing at full volume. iOS — silent switch on, send a message: no chirp; switch off: chirp, Spotify keeps playing.

---

### Task 3: Voice notes borrow the session and give it back (#40)

**Plan 2 ran first.** The voice `AudioPlayer` no longer lives in a widget: Plan 2 Task 7 created `lib/features/chat/presentation/state/voice_playback_controller.dart` with `VoicePlaybackEngine` (abstract, already exposing `Future<void> setAudioContext(AudioContext)` as the seam for this task), `AudioPlayersVoiceEngine`, and `VoicePlaybackController`, whose `_startFresh` makes exactly one audio-context call — `await _engine.setAudioContext(AudioContextConfig(respectSilence: false).build());` (the per-player iOS leak #40 describes) — and whose other transitions are explicit (`toggle` resume branch, `pause`, `stop`, `_onComplete`, `_onEnginePlaying(false)`, `_fail`, `dispose`). Plan 2's `test/features/chat/support/fake_voice_engine.dart` has `FakeVoiceEngine` (`calls`, `contexts`, `nextPlayError`, `completionsController`, `playingController`) and `buildChatContainer` default-overrides `voicePlaybackEngineProvider` with it. `voice_message_player.dart` is a stateless view and is not touched here. So this task replaces that ONE call with `AudioSessionCoordinator.beginPlayback(_engine.setAudioContext)` and returns the session at every transition. If `grep -n "class AudioPlayersVoiceEngine" lib/features/chat/presentation/state/voice_playback_controller.dart` finds nothing, Plan 2 Task 7 has not run — stop; this plan's order assumption is broken.

**Files:**
- Modify: `lib/features/chat/presentation/state/voice_playback_controller.dart` (`VoicePlaybackController` constructor + `_acquireSession`/`_releaseSession` at every transition; `voicePlaybackControllerProvider`). The engine interface, `AudioPlayersVoiceEngine` and `FakeVoiceEngine` are NOT edited (Plan 2 already gave them `setAudioContext`).
- Modify: `test/features/chat/voice_playback_audio_context_test.dart` (after Plan 2 its two player tests read the controller file and assert `setAudioContext` + `respectSilence: false`; rewritten below)
- Test: `test/features/chat/voice_playback_controller_test.dart` (add one group), `test/features/chat/voice_message_player_test.dart` (add one widget test)

**Interfaces:**
- Consumes: Task 1 `audioSessionProvider`, `AudioSessionCoordinator.beginPlayback/endPlayback/playbackHeld/beforeChirp`, `FakeAudioSessionPort`, `PlayerContextSetter`; Plan 2 `VoicePlaybackEngine.setAudioContext`, `FakeVoiceEngine` (`contexts`, `calls`, `nextPlayError`, `completionsController`, `playingController`), `voicePlaybackEngineProvider`, `voicePlaybackControllerProvider`, `voicePlaybackStallAfterProvider`.
- Produces: `VoicePlaybackController({…, required AudioSessionCoordinator session})`; the provider passes `session: ref.watch(audioSessionProvider)`.
- Invariant: one `beginPlayback` per start/resume, one `endPlayback` per pause/complete/playing-false/stop/fail/dispose, never two in a row either way (`_holdsSession` latch) — a leaked hold keeps every later chirp on the playback category until restart.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/chat/voice_playback_controller_test.dart` (it already has `engine`, `container`, `controller`, `state`, `url()`, `tick()` from Plan 2; add imports `package:attune/core/ui/feedback/audio_session.dart`, `package:audioplayers/audioplayers.dart` and `package:flutter/foundation.dart`):

```dart
  group('audio session (chat review #40)', () {
    late FakeAudioSessionPort port;
    late AudioSessionCoordinator session;

    setUp(() {
      port = FakeAudioSessionPort();
      session = AudioSessionCoordinator(
        port: port,
        platform: TargetPlatform.iOS,
      );
      container = ProviderContainer(overrides: [
        voicePlaybackEngineProvider.overrideWithValue(engine),
        voicePlaybackStallAfterProvider.overrideWithValue(
            const Duration(milliseconds: 60)),
        audioSessionProvider.overrideWithValue(session),
      ]);
      addTearDown(container.dispose);
    });

    test('play borrows the voice-note context on the engine; completion '
        'returns it and ambient comes back', () async {
      await controller.toggle('m1', url);
      expect(engine.contexts, [AppAudioContexts.voiceNote]);
      expect(session.playbackHeld, isTrue);
      expect(port.globalContexts, isEmpty, reason: 'nothing restored yet');

      engine.completionsController.add(null);
      await tick();
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts, [AppAudioContexts.chirp],
          reason: 'the chirp context is restored the moment the note ends');
    });

    test('pause returns the session; resume borrows it again — once each',
        () async {
      await controller.toggle('m1', url);
      await controller.toggle('m1', url); // pause
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts, [AppAudioContexts.chirp]);
      await controller.toggle('m1', url); // resume
      expect(session.playbackHeld, isTrue);
      expect(engine.contexts.length, 2);
    });

    test('stop (leaving the chat) and an OS pause both return it', () async {
      await controller.toggle('m1', url);
      await controller.stop();
      expect(session.playbackHeld, isFalse);

      await controller.toggle('m1', url);
      engine.playingController.add(false); // interruption reported
      await tick();
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts.length, 2);
    });

    test('a play that fails to start never leaves a hold behind', () async {
      engine.nextPlayError = Exception('no codec');
      await controller.toggle('m1', url);
      expect(state.failedMessageId, 'm1');
      expect(session.playbackHeld, isFalse);
      expect(port.globalContexts, [AppAudioContexts.chirp]);
    });

    test('a chirp during a voice note does not yank the session (Review '
        'Focus 1, end to end)', () async {
      await controller.toggle('m1', url);
      final chirp = <AudioContext>[];
      await session.beforeChirp((c) async => chirp.add(c));
      expect(chirp, isEmpty);
    });

    test('disposing mid-playback returns the session', () async {
      await controller.toggle('m1', url);
      container.dispose();
      await tick();
      expect(session.playbackHeld, isFalse);
    });
  });
```

Append to `test/features/chat/voice_message_player_test.dart` (its `_wrap` already default-overrides `voicePlaybackEngineProvider` with a `FakeVoiceEngine` and takes `overrides:`; add imports `package:attune/core/ui/feedback/audio_session.dart` and, if missing, `support/fake_voice_engine.dart`) — the bubble-level proof that a tap and a failed start are paired with exactly one borrow/return:

```dart
/// Counts session borrows/returns without a platform player.
class _SpySession extends AudioSessionCoordinator {
  _SpySession() : super(port: FakeAudioSessionPort());
  int begins = 0;
  int ends = 0;

  @override
  Future<void> beginPlayback(PlayerContextSetter set) async {
    begins++;
    await super.beginPlayback(set); // FakeVoiceEngine records the context
  }

  @override
  Future<void> endPlayback() async {
    ends++;
    await super.endPlayback();
  }
}

testWidgets('a play that fails to start returns the borrowed session', (
  tester,
) async {
  // The engine refuses the first play — the "failed start" path. The
  // session must be borrowed once and returned once; a hold left behind
  // would keep every later chirp on the playback category (audible on
  // silent, pausing music) until restart.
  final engine = FakeVoiceEngine()..nextPlayError = Exception('no codec');
  final session = _SpySession();
  await tester.pumpWidget(
    _wrap(
      VoiceMessagePlayer(
        messageId: 'v1',
        resolveAudioUrl: () async => 'https://example.com/v1.m4a',
        durationMs: 3000,
        waveform: const [10, 20, 30],
      ),
      overrides: [
        voicePlaybackEngineProvider.overrideWithValue(engine),
        audioSessionProvider.overrideWithValue(session),
      ],
    ),
  );
  await tester.tap(find.byIcon(Icons.play_arrow_rounded));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  expect(session.begins, 1);
  expect(session.ends, 1, reason: 'a failed start must release the hold');
  expect(session.playbackHeld, isFalse);
  expect(find.text('That voice message could not play'), findsOneWidget);
});
```

Replace the two voice-player tests in `test/features/chat/voice_playback_audio_context_test.dart` (after Plan 2 they read `lib/features/chat/presentation/state/voice_playback_controller.dart` and assert `setAudioContext` + `respectSilence: false`) with:

```dart
  test('the voice controller borrows the session instead of setting a context', () {
    // One owner for the audio session. A per-player playback context on iOS
    // is applied to the SHARED AVAudioSession and nothing restored ambient,
    // so one voice note broke every later chirp's silent-switch behaviour.
    final controllerSrc =
        File(
          'lib/features/chat/presentation/state/voice_playback_controller.dart',
        ).readAsStringSync();
    expect(controllerSrc, isNot(contains('AudioContextConfig(')));
    expect(controllerSrc, isNot(contains('respectSilence')));
    expect(controllerSrc, contains('beginPlayback(_engine.setAudioContext)'));
    expect(controllerSrc, contains('endPlayback'));
  });

  test('playback failures surface instead of reading as silence', () {
    final controllerSrc =
        File(
          'lib/features/chat/presentation/state/voice_playback_controller.dart',
        ).readAsStringSync();
    expect(controllerSrc, contains('catch'));
    expect(controllerSrc, isNot(contains('catch (_)')));
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/chat/voice_playback_controller_test.dart test/features/chat/voice_message_player_test.dart test/features/chat/voice_playback_audio_context_test.dart`
Expected: controller group — `Expected: [voiceNote] Actual: [<the respectSilence context>]` on the first test and `Expected: <true> Actual: <false>` on `playbackHeld`; widget test — `Expected: <1> Actual: <0>` on `session.begins`; the source test fails on `isNot(contains('AudioContextConfig('))`.

- [ ] **Step 3: Implement**

`voice_playback_controller.dart`:

1. Add `import 'package:attune/core/ui/feedback/audio_session.dart';`.
2. `VoicePlaybackController`: constructor gains `required AudioSessionCoordinator session,` → `_session = session,`; field `final AudioSessionCoordinator _session;` and:

```dart
  /// Whether this controller currently holds the audio session. Paired
  /// strictly: one begin per start/resume, one end per pause/complete/
  /// playing-false/stop/fail/dispose — a leaked hold keeps every later chirp
  /// on the playback category (audible on silent, pausing music) until
  /// restart.
  bool _holdsSession = false;

  Future<void> _acquireSession() async {
    if (_holdsSession) return;
    _holdsSession = true;
    try {
      await _session.beginPlayback(_engine.setAudioContext);
    } catch (_) {
      _holdsSession = false; // the coordinator already dropped its count
      rethrow;
    }
  }

  void _releaseSession() {
    if (!_holdsSession) return;
    _holdsSession = false;
    unawaited(_session.endPlayback());
  }
```

   Call sites (each is one line, by name):
   - `_startFresh`: replace the comment block beginning `// Per-player context, because SoundService sets a PROCESS-WIDE one` and the statement `await _engine.setAudioContext(AudioContextConfig(respectSilence: false).build());` with `await _acquireSession();` (same `try`, so a failure lands in the same `_fail`).
   - `toggle`, resume branch: inside the existing `try {` before `await _engine.resume();` add `await _acquireSession();`.
   - `pause()`: after `state = state.copyWith(isPlaying: false);` add `_releaseSession();`.
   - `stop()`: after `_publishCurrent(null);` add `_releaseSession();` (before the `if (!hadMessage) return;` — a stale hold must go even when no message is current).
   - `_onComplete()`: after `_publishCurrent(null);` add `_releaseSession();`.
   - `_onEnginePlaying(bool playing)`: inside the `if (!playing && state.isPlaying) {` block, after `_publishCurrent(null);` add `_releaseSession();`.
   - `_fail(...)`: after `_publishCurrent(null);` add `_releaseSession();`.
   - `dispose()`: before `unawaited(_engine.dispose());` add `_releaseSession();`.
   - The stall watchdog goes through `pause()`, so it is covered.
3. `voicePlaybackControllerProvider`: add `session: ref.watch(audioSessionProvider),` to the `VoicePlaybackController(` construction.
4. The `catch (_)` rule: Plan 2's controller already names every error; keep it that way (the `_acquireSession` catch above rethrows and is a `catch (_) {` with a body, so write it exactly as shown — `catch (_) {` followed by a newline, never `catch (_) {}` on one line, which is the string the source test forbids). If the analyzer or the test complains, use `catch (error) { _holdsSession = false; rethrow; }` instead.

Update the Plan 2 controller doc comment's first paragraph by appending: `Also the only place the voice-note audio session is borrowed and returned (chat review #40): the AudioSessionCoordinator restores the chirp context when the last hold ends.`

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chat/voice_playback_controller_test.dart test/features/chat/voice_message_player_test.dart test/features/chat/voice_playback_audio_context_test.dart test/features/chat/voice_playback_fidelity_test.dart test/features/chat/voice_local_path_fallback_test.dart test/features/chat/voice_signed_url_freshness_test.dart test/features/chat/chat_screen_header_test.dart`
Expected: `All tests passed!` — the chat-screen suites build the controller through the provider with Plan 2's default `FakeVoiceEngine`; `audioSessionProvider`'s default (`AudioplayersSessionPort`) only touches a channel in `endPlayback`, which those tests reach via `stop()` on screen dispose. If any of them reports a `MissingPluginException` from `AudioPlayer.global.setAudioContext`, add `audioSessionProvider.overrideWith((ref) => AudioSessionCoordinator(port: FakeAudioSessionPort()))` to `buildChatContainer`'s default overrides in `chat_test_harness.dart` (next to Plan 2's `voicePlaybackEngineProvider` override) and to `voice_message_player_test.dart`'s `_wrap`, and say so in the checkpoint.

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/presentation/state/voice_playback_controller.dart test/features/chat/voice_playback_controller_test.dart test/features/chat/voice_message_player_test.dart test/features/chat/voice_playback_audio_context_test.dart | grep -E '^\s*(error|warning) '`; expected no output. Also `grep -rn "respectSilence\|AudioContextConfig(" lib/` → nothing. No commit (the owner commits).

**Device check (owner):** iOS, silent switch on: play a voice note (audible), let it finish, send a message: no chirp. Android with Spotify: voice note pauses music, music resumes when the note ends.

---

### Task 4: A streak view is spent only once the clip has been presented (#41)

**Files:**
- Modify: `lib/features/chat/presentation/screens/streak_viewer_screen.dart`
- Test: `test/features/chat/streak_viewer_presented_gate_test.dart` (create)
- Keep green: `test/features/chat/streak_viewer_pop_test.dart`, `test/features/chat/streak_viewer_photo_test.dart`, `test/features/chat/streak_viewer_states_test.dart`

**Interfaces:**
- Produces: `StreakViewerScreen({…, ImageProvider Function(String url)? imageProviderBuilder})` test seam (default `NetworkImage`); `@visibleForTesting bool get hasPresentedForTest`.
- Semantics: the view is spent iff `_hasPresented || _clipsGone` (server returned no clips → spend is a budget sync and returns 0, keeping both bubbles on "Opened").

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/chat/streak_viewer_presented_gate_test.dart
//
// A view-once item is consumed when the media is actually shown — never by a
// tap or a back gesture on the loading screen (H-1 / issue #41).
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/presentation/screens/streak_viewer_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/chat_test_harness.dart';

class _GatedStreakRepository implements StreakRepository {
  _GatedStreakRepository({this.clips = const [], this.gate, this.error});

  final List<StreakClip> clips;
  final Completer<void>? gate; // fetchClips waits on this when set
  final Object? error; // fetchClips throws this when set
  int markViewedCalls = 0;

  @override
  Future<int> markViewed(String messageId) async {
    markViewedCalls++;
    return 0;
  }

  @override
  Future<List<StreakClip>> fetchClips(String messageId) async {
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return clips;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Signing can be held open so the viewer sits on its spinner with clips
/// already fetched.
class _GatedSigningRepository extends FakeChatRepository {
  _GatedSigningRepository({required super.currentUserId, this.signingGate});
  final Completer<void>? signingGate;

  @override
  Future<String?> createSignedMediaUrl(
    String mediaKey, {
    bool forceRefresh = false,
  }) async {
    if (signingGate != null) await signingGate!.future;
    return 'https://signed.test/$mediaKey?token=abc';
  }
}

/// Same shape as streak_viewer_photo_test's fake: every video is
/// "initialized" as soon as its event stream is listened to.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({this.initialize = true});
  final bool initialize;
  int _next = 0;
  final Map<int, StreamController<VideoEvent>> _controllers = {};

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose(int playerId) async {
    await _controllers.remove(playerId)?.close();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    final controller = StreamController<VideoEvent>.broadcast(
      onListen: () {
        if (!initialize) return; // never reaches its first frame
        Future.microtask(() {
          _controllers[id]?.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(seconds: 4),
              size: const Size(720, 1280),
            ),
          );
        });
      },
    );
    _controllers[id] = controller;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _controllers[playerId]!.stream;
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} unused');
}

const _videoClip = StreakClip(
  index: 0,
  mediaUrl: 'chat/clip-0',
  durationMs: 4000,
  mediaKind: StreakClipKind.video,
);
const _photoClip = StreakClip(
  index: 0,
  mediaUrl: 'chat/photo-0',
  durationMs: 0,
  mediaKind: StreakClipKind.photo,
);

/// 1x1 transparent PNG — decodable by the test engine.
final Uint8List _onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  late VideoPlayerPlatform original;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  /// Pushes the viewer as a real route and captures its pop result.
  Future<ValueNotifier<int?>> open(
    WidgetTester tester, {
    required FakeChatRepository chatRepo,
    required StreakRepository streakRepo,
    ImageProvider Function(String url)? imageProviderBuilder,
  }) async {
    final result = ValueNotifier<int?>(-1);
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(chatRepo),
        streakRepositoryProvider.overrideWithValue(streakRepo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      result.value = await Navigator.of(context).push<int>(
                        MaterialPageRoute<int>(
                          builder:
                              (_) => StreakViewerScreen(
                                messageId: 'm1',
                                imageProviderBuilder: imageProviderBuilder,
                              ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return result;
  }

  testWidgets('tapping while the clips are still loading spends nothing', (
    tester,
  ) async {
    // 2-3 s of black screen + spinner reads as "nothing happened", so people
    // tap it. That tap used to call _finish -> markViewed -> clips deleted:
    // the only view burnt, "Opened" on both phones, nobody saw it.
    final gate = Completer<void>();
    final streakRepo = _GatedStreakRepository(clips: [_videoClip], gate: gate);
    final result = await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();

    expect(streakRepo.markViewedCalls, 0);
    expect(find.byType(StreakViewerScreen), findsNothing);
    expect(result.value, isNull, reason: 'null keeps the bubble\'s count');
    gate.complete();
  });

  testWidgets('the back gesture while loading spends nothing either', (
    tester,
  ) async {
    final gate = Completer<void>();
    final streakRepo = _GatedStreakRepository(clips: [_videoClip], gate: gate);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );

    // System back: PopScope(canPop:false) routes it through _finish.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(streakRepo.markViewedCalls, 0);
    expect(find.byType(StreakViewerScreen), findsNothing);
    gate.complete();
  });

  testWidgets('clips fetched but still signing: still nothing is spent', (
    tester,
  ) async {
    final signing = Completer<void>();
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: _GatedSigningRepository(currentUserId: 'me', signingGate: signing),
      streakRepo: streakRepo,
    );
    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
    signing.complete();
  });

  testWidgets('a video that never reaches its first frame spends nothing', (
    tester,
  ) async {
    // Review Focus 3.
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(initialize: false);
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(VideoPlayer), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
  });

  testWidgets('once the video is on screen, closing spends exactly one view', (
    tester,
  ) async {
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(VideoPlayer), findsOneWidget);
    await tester.pump(); // the post-frame "presented" latch

    await tester.tap(find.byType(VideoPlayer));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
  });

  testWidgets('a photo counts as presented once its first frame decodes', (
    tester,
  ) async {
    final streakRepo = _GatedStreakRepository(clips: [_photoClip]);
    final provider = MemoryImage(_onePixelPng);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
      imageProviderBuilder: (_) => provider,
    );
    // Let the engine decode the PNG off the fake clock, then paint it.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('streak-photo-view')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('streak-photo-view')));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
  });

  testWidgets('a photo whose bytes never arrive is not spent', (tester) async {
    // The default NetworkImage gets HTTP 400 from the test host: errorBuilder
    // path. Nothing painted, nothing spent, and the person is told.
    final streakRepo = _GatedStreakRepository(clips: [_photoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text("Couldn't load this streak. Try again in a moment."), findsOneWidget);
    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
  });

  testWidgets('a fetch failure never spends', (tester) async {
    final streakRepo = _GatedStreakRepository(error: Exception('offline'));
    final result = await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me'),
      streakRepo: streakRepo,
    );
    await tester.pump();
    expect(find.text('This streak is no longer available.'), findsOneWidget);
    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
    expect(result.value, isNull);
  });

  testWidgets('clips the server says are gone still sync the budget', (
    tester,
  ) async {
    // Review Focus 4: an empty fetch is the server saying "spent/expired".
    // Spending here returns 0 and flips both bubbles to Opened; it must
    // survive the presented gate.
    final streakRepo = _GatedStreakRepository(clips: const []);
    final result = await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me'),
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
    expect(result.value, 0);
  });

  testWidgets('there is an explicit Close control while loading', (
    tester,
  ) async {
    final gate = Completer<void>();
    final streakRepo = _GatedStreakRepository(clips: [_videoClip], gate: gate);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(StreakViewerScreen), findsNothing);
    expect(streakRepo.markViewedCalls, 0);
    gate.complete();
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/streak_viewer_presented_gate_test.dart`
Expected: compile error `The named parameter 'imageProviderBuilder' isn't defined`; after temporarily stubbing it you would see `Expected: <0> Actual: <1>` on `markViewedCalls` for the loading-tap test — that is the bug.

- [ ] **Step 3: Implement**

In `streak_viewer_screen.dart`:

Constructor and fields:

```dart
  const StreakViewerScreen({
    super.key,
    required this.messageId,
    this.imageHoldDuration = kStoryImageHoldDuration,
    this.imageProviderBuilder,
  });

  /// Test seam: how a signed photo URL becomes an [ImageProvider].
  /// Production uses [NetworkImage]; tests hand in a decodable
  /// [MemoryImage] so the "first frame shown" signal can be exercised.
  final ImageProvider Function(String url)? imageProviderBuilder;
```

State fields (next to `_unavailable`):

```dart
  /// True once a clip has actually been SHOWN: a video's first frame is on
  /// screen, or a photo's first frame decoded. Until then, leaving costs
  /// nothing — a tap or back gesture on the black loading screen used to
  /// spend the recipient's only view.
  bool _hasPresented = false;

  /// The server returned no clips: spent or expired. Spending is then a
  /// budget sync (the RPC answers 0) that flips both bubbles to Opened.
  bool _clipsGone = false;

  /// A photo whose bytes never arrived. Shown in words, never spent.
  bool _loadFailed = false;

  bool get _spendAllowed => _hasPresented || _clipsGone;

  @visibleForTesting
  bool get hasPresentedForTest => _hasPresented;
```

In `_load()`, change the empty branch:

```dart
      if (clips.isEmpty) {
        setState(() {
          _clipsGone = true;
          _unavailable = true;
        });
        return;
      }
```

In `_playAt`, the `signed == null` branch no longer finishes (signing can fail for transient reasons; closing without spending is what `_finish` now does):

```dart
    if (signed == null) {
      // Signing failed (transient, or the key is gone). Say so and let the
      // person leave; nothing is spent because nothing was shown.
      if (mounted) setState(() => _unavailable = true);
      return;
    }
```

Photo branch — replace the `setState` that sets `_imageUrl` to also keep the generation for the frame signal; and in `build`, replace `Image.network(imageUrl, …)` with:

```dart
              else if (imageUrl != null)
                Center(
                  child: Image(
                    key: const ValueKey('streak-photo-view'),
                    image: (widget.imageProviderBuilder ?? _networkImage)(
                      imageUrl,
                    ),
                    fit: BoxFit.contain,
                    // The moment a frame exists the person has SEEN it;
                    // that is when a view becomes spendable.
                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                      if (frame != null || wasSynchronouslyLoaded) {
                        _hasPresented = true;
                      }
                      return child;
                    },
                    // Not an app-visible error banner, but not a silent black
                    // hold either: the hold timer still advances, nothing is
                    // spent, and the person is told why.
                    errorBuilder: (_, __, ___) {
                      if (!_loadFailed) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _loadFailed = true);
                        });
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                )
```

with the helper at file bottom:

```dart
ImageProvider _networkImage(String url) => NetworkImage(url);
```

Video branch — after the existing `setState(() { _controller = controller; _imageUrl = null; _index = index; });` add:

```dart
    // Presented = the first frame has been painted, not merely decoded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) _hasPresented = true;
    });
```

`_finish`:

```dart
  Future<void> _finish() async {
    // Nothing was shown (still loading, signing failed, bytes never came)
    // and the server has not said the clips are gone: leaving is free.
    if (!_spendAllowed) {
      _close();
      return;
    }
    await _spendView();
    _close();
  }
```

`build` — add the load-failed branch BETWEEN the video branch and the photo branch (`_imageUrl` stays set after a failed decode, so a branch placed after `imageUrl != null` would never be reached), and a close control to the Stack:

```dart
              if (controller != null && controller.value.isInitialized)
                Center(/* unchanged video branch */)
              else if (_loadFailed)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      "Couldn't load this streak. Try again in a moment.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                )
              else if (imageUrl != null)
                Center(/* the Image(...) branch above */)
              else if (_unavailable)
```

(`streak_viewer_states_test` keeps passing: `controller.value.isInitialized` still precedes `CircularProgressIndicator` in the source, and no `if (_loading)` appears.)

and, as the last child of the `Stack`:

```dart
              // An explicit way out while loading, so the black screen does
              // not invite a guess-tap. Same exit as everything else.
              Positioned(
                top: 8,
                left: 4,
                child: SafeArea(
                  child: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => unawaited(_finish()),
                  ),
                ),
              ),
```

Update the class doc comment's first paragraph to: `/// Plays a streak's clips in order, then spends one view — but only if a clip was actually presented (first frame on screen). Backing out of a still-loading viewer costs nothing.`

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chat/streak_viewer_presented_gate_test.dart test/features/chat/streak_viewer_pop_test.dart test/features/chat/streak_viewer_photo_test.dart test/features/chat/streak_viewer_states_test.dart test/features/chat/streak_view_budget_test.dart`
Expected: `All tests passed!` — note `streak_viewer_states_test` asserts `src.indexOf('controller.value.isInitialized') < src.indexOf('CircularProgressIndicator')` and `isNot(contains('if (_loading)'))`; the branch order above preserves both. If the photo test's `MemoryImage` has not decoded after the `runAsync` delay, raise the delay to 300 ms before changing anything else.

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/presentation/screens/streak_viewer_screen.dart test/features/chat/streak_viewer_presented_gate_test.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

### Task 5: The 30-minute replay window gates the READ, not just the finish (M-8)

**Files:**
- Create: `supabase/migrations/20261019140000_streak_replay_window_read_gate.sql` (functions + policy)
- Create: `supabase/migrations/20261019140010_streak_replay_window_read_gate_grants.sql` (REVOKE/GRANT only — the repo keeps grants in a sibling `*_grants.sql` that `scripts/local_pg_grants.sql` replays after its blanket local grant; see `20261018100100_relationship_lifecycle_grants.sql`)
- Modify: `scripts/local_pg_grants.sql` (append one `\i` line)
- Create: `supabase/tests/streak_replay_window_contracts.sql`
- Create: `lib/features/chat/domain/utils/streak_replay_window.dart`
- Modify: `lib/features/chat/data/repositories/streak_repository.dart` (`fetchClips`)
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (`_BubbleBody` streak branch: `final remaining = …`)
- Modify: `test/features/chat/streak_repository_test.dart` (its "fetchClips selects no caption or budget columns" test asserts a `.from('streak_clips').select(...)` shape; it is rewritten for the RPC)
- Test: `test/features/chat/streak_replay_window_test.dart` (create)

**Interfaces:**
- SQL: `public.streak_clips_for_viewing(p_message_id uuid) RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)` SECURITY DEFINER, EXECUTE → authenticated. `public.expire_streak_clips(p_message_id uuid)` internal (no EXECUTE for anon/authenticated). `mark_streak_viewed` is **unchanged** (its contracts in `streak_contracts.sql` keep passing; the finish-time check stays as the last line of defence).
- Dart: `const Duration kStreakReplayWindow = Duration(minutes: 30); int streakViewsAvailable(Message message, DateTime now);`

- [ ] **Step 1: Write the failing SQL contract test**

```sql
-- supabase/tests/streak_replay_window_contracts.sql
-- Replays are readable for 30 minutes after the first view, and not a second
-- longer (review 06 M-8). Until 20261019140000 the window was checked only
-- when the viewer FINISHED, so an expired replay played in full once more.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('6a000000-0000-0000-0000-0000000000a1'),
  ('6a000000-0000-0000-0000-0000000000b2'),
  ('6a000000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('6a000000-0000-0000-0000-0000000000a1', '+233260000001', 'Window A'),
  ('6a000000-0000-0000-0000-0000000000b2', '+233260000002', 'Window B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('6b000000-0000-0000-0000-000000000001',
        '6a000000-0000-0000-0000-0000000000a1',
        '6a000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- A streak from A to B with [p_left] views, first viewed [p_viewed_ago] ago
-- (NULL = never viewed). Returns the message id.
--
-- content is a placeholder word, not '' and not a media_url:
-- messages_payload_present needs content OR media_url, and a media_url on
-- insert trips the upload-intent trigger ("Chat media upload intent is
-- invalid or expired"). Same shape as streak_contracts.sql's fixtures.
CREATE FUNCTION pg_temp.streak(p_left int, p_viewed_ago interval, p_key text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_msg uuid;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content, media_type,
     streak_views_remaining, viewed_at)
  VALUES ('6b000000-0000-0000-0000-000000000001',
          '6a000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent', 'streak', p_left,
          CASE WHEN p_viewed_ago IS NULL THEN NULL ELSE now() - p_viewed_ago END)
  RETURNING id INTO v_msg;
  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, p_key, 3000);
  RETURN v_msg;
END $$;

-- 1. Recipient, never viewed: the clips come back.
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(3, NULL, 'chat/w1');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: first view got % clips', v_n; END IF;
END $$;

-- 2. Recipient, viewed 10 minutes ago with budget left: replay is readable.
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(2, interval '10 minutes', 'chat/w2');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: in-window replay got % clips', v_n; END IF;
END $$;

-- 3. Recipient, viewed 31 minutes ago with budget left: NOTHING is readable,
--    the clips are destroyed, the budget reads 0 and the object is queued.
DO $$
DECLARE v_msg uuid; v_n int; v_left int;
BEGIN
  v_msg := pg_temp.streak(2, interval '31 minutes', 'chat/w3');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expired replay got % clips', v_n; END IF;
  IF EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_msg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expired clips survived the read';
  END IF;
  SELECT streak_views_remaining INTO v_left FROM public.messages WHERE id = v_msg;
  IF v_left <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expired budget reads %', v_left; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                 WHERE bucket_id = 'message-media' AND object_name = 'chat/w3') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expired object was not queued for deletion';
  END IF;
END $$;

-- 4. Recipient with no budget: nothing.
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(0, interval '1 minute', 'chat/w4');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: spent streak got % clips', v_n; END IF;
END $$;

-- 5. Sender: readable until the recipient opens it, then not.
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(1, NULL, 'chat/w5');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: sender replay before open got %', v_n; END IF;
  UPDATE public.messages SET viewed_at = now() WHERE id = v_msg;
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: sender replay after open got %', v_n; END IF;
END $$;

-- 6. A non-member cannot read or probe.
DO $$
DECLARE v_msg uuid; v_ok boolean := false;
BEGIN
  v_msg := pg_temp.streak(1, NULL, 'chat/w6');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM count(*) FROM public.streak_clips_for_viewing(v_msg);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  IF v_ok THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a non-member read a streak'; END IF;
END $$;

-- 7. The table itself agrees: direct SELECT under RLS shows nothing past
--    the window, something inside it, and the sender still writes clips.
DO $$
DECLARE v_in uuid; v_out uuid; v_n int;
BEGIN
  v_in := pg_temp.streak(2, interval '10 minutes', 'chat/w7in');
  v_out := pg_temp.streak(2, interval '31 minutes', 'chat/w7out');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_in;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: RLS hid an in-window clip'; END IF;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_out;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: RLS exposed an expired clip'; END IF;
  -- The sender's attach path (INSERT policy) is untouched.
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000a1');
  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_in, 1, 'chat/w7in-1', 1000);
  RESET ROLE;
END $$;

-- 8. Mutation check: a function WITHOUT the window branch fails contract 3.
SAVEPOINT mutate_fn;
CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
  FROM public.streak_clips c WHERE c.message_id = p_message_id ORDER BY c.clip_index $$;
DO $$
DECLARE v_msg uuid; v_n int; v_failed boolean := false;
BEGIN
  v_msg := pg_temp.streak(2, interval '31 minutes', 'chat/w8');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 0 THEN v_failed := true; END IF;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 3 passed without the window check';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutate_fn;

-- 9. Mutation check: a permissive read policy fails contract 7.
SAVEPOINT mutate_rls;
DROP POLICY streak_clips_members_read ON public.streak_clips;
CREATE POLICY streak_clips_members_read ON public.streak_clips FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.messages m
                 WHERE m.id = streak_clips.message_id
                   AND public.relationship_chat_open(m.relationship_id)));
DO $$
DECLARE v_out uuid; v_n int;
BEGIN
  v_out := pg_temp.streak(2, interval '31 minutes', 'chat/w9');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_out;
  RESET ROLE;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: the permissive policy still hid the expired clip';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutate_rls;

ROLLBACK;
```

- [ ] **Step 2: Run to verify it fails**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/streak_replay_window_contracts.sql`
Expected: `ERROR:  function public.streak_clips_for_viewing(uuid) does not exist` at contract 1.

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261019140000_streak_replay_window_read_gate.sql
--
-- Streak replays: readable for 30 minutes after the first view, then gone.
--
-- mark_streak_viewed enforced the window only when the viewer FINISHED, so
-- an expired replay played in full once more and only then was destroyed
-- (review 06 M-8). This gates the READ: the client fetches clips through
-- streak_clips_for_viewing, which returns rows only while the streak is
-- viewable for this caller and destroys an expired one on the spot, and
-- the table's own SELECT policy mirrors the same rule so a direct read
-- cannot bypass it. mark_streak_viewed is unchanged: it remains the budget
-- owner and the last line of defence at finish time.

-- Shared destroy step (mark_streak_viewed inlines the same three
-- statements; kept identical). Internal: nobody calls this directly.
CREATE OR REPLACE FUNCTION public.expire_streak_clips(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.queue_media_deletion('message-media', media_url)
  FROM public.streak_clips WHERE message_id = p_message_id;

  DELETE FROM public.streak_clips WHERE message_id = p_message_id;
  UPDATE public.messages SET streak_views_remaining = 0
  WHERE id = p_message_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_msg public.messages%ROWTYPE;
  v_member boolean := false;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_msg FROM public.messages WHERE id = p_message_id;
  IF FOUND THEN
    SELECT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_msg.relationship_id
        AND (r.user_a = v_user OR r.user_b = v_user)
        AND public.relationship_chat_open_for(r.id, v_user)
    ) INTO v_member;
  END IF;
  IF NOT v_member THEN
    -- Same answer for "someone else's" and "does not exist": no oracle.
    RAISE EXCEPTION 'Streak unavailable';
  END IF;

  IF v_msg.sender_id = v_user THEN
    -- The sender may replay until the recipient has opened it.
    IF v_msg.viewed_at IS NOT NULL THEN RETURN; END IF;
  ELSE
    IF COALESCE(v_msg.streak_views_remaining, 0) <= 0 THEN RETURN; END IF;
    IF v_msg.viewed_at IS NOT NULL
       AND v_msg.viewed_at < now() - interval '30 minutes' THEN
      -- Expired by time with plays left: destroy now, before anything is
      -- handed out, and report nothing.
      PERFORM public.expire_streak_clips(p_message_id);
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
    SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
    FROM public.streak_clips c
    WHERE c.message_id = p_message_id
    ORDER BY c.clip_index;
END;
$$;

-- The table agrees with the RPC. The INSERT policy (sender attaches clips)
-- is untouched.
DROP POLICY IF EXISTS streak_clips_members_read ON public.streak_clips;
CREATE POLICY streak_clips_members_read ON public.streak_clips
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = streak_clips.message_id
        AND public.relationship_chat_open(m.relationship_id)
        AND CASE
              WHEN m.sender_id = auth.uid() THEN m.viewed_at IS NULL
              ELSE COALESCE(m.streak_views_remaining, 0) > 0
                   AND (m.viewed_at IS NULL
                        OR m.viewed_at > now() - interval '30 minutes')
            END
    )
  );
```

And the grants file:

```sql
-- supabase/migrations/20261019140010_streak_replay_window_read_gate_grants.sql
-- Grants for 20261019140000: clients read clips only through the gated RPC;
-- the destroy step runs only inside it (and inside mark_streak_viewed).
REVOKE ALL ON FUNCTION public.expire_streak_clips(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.streak_clips_for_viewing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.streak_clips_for_viewing(uuid) TO authenticated;
```

Append to `scripts/local_pg_grants.sql` (after the last `\i` line, same comment style):

```
-- Chat W4 (#40/M-8): streak replay window read gate.
\i supabase/migrations/20261019140010_streak_replay_window_read_gate_grants.sql
```

Apply: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019140000_streak_replay_window_read_gate.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019140010_streak_replay_window_read_gate_grants.sql`
Expected: `CREATE FUNCTION`, `CREATE FUNCTION`, `DROP POLICY`, `CREATE POLICY`; then `REVOKE`, `REVOKE`, `GRANT`. Verify: `psql -X -d attune_spec3a -Atc "select has_function_privilege('authenticated','public.expire_streak_clips(uuid)','EXECUTE'), has_function_privilege('authenticated','public.streak_clips_for_viewing(uuid)','EXECUTE'), has_function_privilege('anon','public.streak_clips_for_viewing(uuid)','EXECUTE')"` → `f|t|f`.

- [ ] **Step 4: Run the contracts**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/streak_replay_window_contracts.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/streak_contracts.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/streak_photo_contracts.sql`
Expected: each ends with `ROLLBACK` and no `CONTRACT VIOLATED` / `MUTATION NOT DETECTED` output; exit code 0. (The `PERFORM * FROM …` in contract 6 — if PL/pgSQL rejects it, use `PERFORM count(*) FROM public.streak_clips_for_viewing(v_msg);`.)

- [ ] **Step 5: Write the failing Dart tests**

```dart
// test/features/chat/streak_replay_window_test.dart
import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/utils/streak_replay_window.dart';
import 'package:flutter_test/flutter_test.dart';

Message _streak({
  required bool isMine,
  required int remaining,
  DateTime? viewedAt,
}) => Message(
  id: 's1',
  clientMessageId: 'c1',
  relationshipId: 'r1',
  senderId: isMine ? 'me' : 'partner',
  content: '',
  createdAt: DateTime(2026, 10, 19, 10),
  status: MessageStatus.delivered,
  isMine: isMine,
  mediaType: 'streak',
  streakViewsRemaining: remaining,
  viewedAt: viewedAt,
);

void main() {
  final now = DateTime(2026, 10, 19, 12);

  test('an unopened streak keeps its full budget', () {
    expect(streakViewsAvailable(_streak(isMine: false, remaining: 3), now), 3);
  });

  test('inside the window the replay budget stands', () {
    final m = _streak(
      isMine: false,
      remaining: 2,
      viewedAt: now.subtract(const Duration(minutes: 29)),
    );
    expect(streakViewsAvailable(m, now), 2);
  });

  test('past the window the bubble reads Opened without a tap', () {
    // "Play 2x" used to stay up until the person tapped and the server
    // refused — by which time the clip had already played once more.
    final m = _streak(
      isMine: false,
      remaining: 2,
      viewedAt: now.subtract(kStreakReplayWindow),
    );
    expect(streakViewsAvailable(m, now), 0);
  });

  test('the window never governs the sender', () {
    final m = _streak(
      isMine: true,
      remaining: 2,
      viewedAt: now.subtract(const Duration(hours: 2)),
    );
    expect(streakViewsAvailable(m, now), 2);
  });

  test('the streak bubble reads the budget through the window rule', () {
    final src =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();
    expect(src, contains('streakViewsAvailable(message'));
  });

  test('clips are fetched through the gated RPC, never the table', () {
    final src =
        File(
          'lib/features/chat/data/repositories/streak_repository.dart',
        ).readAsStringSync();
    final fetch = src.substring(src.indexOf('fetchClips('));
    expect(fetch, contains("'streak_clips_for_viewing'"));
    expect(fetch, contains('.rpc('));
    expect(fetch, isNot(contains(".from('streak_clips')")));
  });
}
```

In `test/features/chat/streak_repository_test.dart`, replace the test `'fetchClips selects no caption or budget columns'` with:

```dart
  test('fetchClips goes through streak_clips_for_viewing', () {
    // The RPC is what enforces "readable only inside the 30-minute replay
    // window"; a direct table read would hand out an expired clip.
    final src =
        File(
          'lib/features/chat/data/repositories/streak_repository.dart',
        ).readAsStringSync();
    expect(src, contains("'streak_clips_for_viewing'"));
    expect(src, isNot(contains(".from('streak_clips')\n        .select")));
  });
```

Run: `flutter test test/features/chat/streak_replay_window_test.dart test/features/chat/streak_repository_test.dart`
Expected: compile error on the missing `streak_replay_window.dart`; then the two source tests fail.

- [ ] **Step 6: Implement the Dart side**

```dart
// lib/features/chat/domain/utils/streak_replay_window.dart
import 'package:attune/features/chat/domain/entities/message.dart';

/// How long a recipient may replay a streak after first opening it. Mirrors
/// `streak_clips_for_viewing` / `mark_streak_viewed` on the server, which
/// own the rule; this only keeps the bubble honest between refreshes.
const Duration kStreakReplayWindow = Duration(minutes: 30);

/// Views the RECIPIENT can still take at [now]. The sender's budget is not
/// theirs to spend, so the window never applies to them.
int streakViewsAvailable(Message message, DateTime now) {
  final remaining = message.streakViewsRemaining ?? 0;
  if (message.isMine) return remaining;
  final viewedAt = message.viewedAt;
  if (viewedAt != null && !now.difference(viewedAt).isNegative &&
      now.difference(viewedAt) >= kStreakReplayWindow) {
    return 0;
  }
  return remaining;
}
```

`dart format lib/features/chat/domain/utils/streak_replay_window.dart test/features/chat/streak_replay_window_test.dart` (new files only).

In `streak_repository.dart`, replace `fetchClips`:

```dart
  /// The clips of one streak, in playback order — through the gated RPC.
  ///
  /// `streak_clips_for_viewing` returns rows only while the streak is
  /// viewable for THIS caller (recipient: budget left and inside the
  /// 30-minute replay window; sender: not yet opened) and destroys an
  /// expired one before answering. A direct table read handed out an
  /// expired replay and only the finish-time RPC said no — after it had
  /// played.
  Future<List<StreakClip>> fetchClips(String messageId) async {
    final result = await _safeClient.rpc(
      'streak_clips_for_viewing',
      params: {'p_message_id': messageId},
    );
    final rows = (result as List?) ?? const [];
    return rows
        .map((row) => StreakClip.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList();
  }
```

In `message_bubble.dart`, `_BubbleBody` streak branch: add `import 'package:attune/features/chat/domain/utils/streak_replay_window.dart';` and replace `final remaining = message.streakViewsRemaining ?? 0;` with:

```dart
      // Past the 30-minute replay window the row reads Opened on its own;
      // the server refuses the read anyway, this just stops offering it.
      final remaining = streakViewsAvailable(message, DateTime.now());
```

- [ ] **Step 7: Run to verify it passes**

Run: `flutter test test/features/chat/streak_replay_window_test.dart test/features/chat/streak_repository_test.dart test/features/chat/streak_bubble_test.dart test/features/chat/streak_view_budget_test.dart test/features/chat/streak_viewer_presented_gate_test.dart`
Expected: `All tests passed!`

- [ ] **Step 8: Checkpoint**

Run this task's tests + the three psql files (two migrations, then the contracts) and `flutter analyze lib/features/chat/domain/utils/streak_replay_window.dart lib/features/chat/data/repositories/streak_repository.dart lib/features/chat/presentation/widgets/message_bubble.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

### Task 6: A failed streak upload says "Not sent", never "Sending…" (#42)

**Files:**
- Modify: `lib/features/chat/presentation/widgets/streak_bubble.dart`
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (`_BubbleBody` gets `onRetry`; streak branch passes `isFailed`/`onRetry`)
- Test: `test/features/chat/streak_bubble_test.dart` (add), `test/features/chat/message_bubble_test.dart` (add)

**Interfaces:**
- `StreakBubble({…, bool isFailed = false, VoidCallback? onRetry})`; `_BubbleBody({…, VoidCallback? onRetry})`.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/chat/streak_bubble_test.dart` inside `main`:

```dart
  testWidgets('a failed upload reads "Not sent" with no spinner', (
    tester,
  ) async {
    // After the automatic attempts ran out the body still spun "Sending…"
    // forever under a footer that said Failed — Retry.
    var retried = false;
    await tester.pumpWidget(
      _wrap(
        StreakBubble(
          viewsRemaining: 1,
          hasBeenPlayed: false,
          isMine: true,
          isSending: true, // the row still has its _local_ id
          isFailed: true,
          onRetry: () => retried = true,
          onTap: () {},
        ),
      ),
    );

    expect(find.text('Sending…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Not sent. Tap to retry'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

    await tester.tap(find.text('Not sent. Tap to retry'));
    await tester.pump();
    expect(retried, isTrue);
  });

  testWidgets('the failed glyph uses the theme error colour', (tester) async {
    await tester.pumpWidget(
      _wrap(
        StreakBubble(
          viewsRemaining: 1,
          hasBeenPlayed: false,
          isMine: true,
          isFailed: true,
          onTap: () {},
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded));
    final context = tester.element(find.byType(StreakBubble));
    expect(icon.color, Theme.of(context).colorScheme.error);
  });
```

Append to `test/features/chat/message_bubble_test.dart` inside `main` (uses its `_pump` helper):

```dart
  testWidgets('a failed streak row shows Not sent, not a spinner', (
    tester,
  ) async {
    var retried = false;
    final failedStreak = Message(
      id: '_local_streak-1',
      clientMessageId: 'streak-1',
      relationshipId: 'r1',
      senderId: 'me',
      content: '',
      createdAt: DateTime(2026, 7, 1, 15, 4),
      status: MessageStatus.failed,
      isMine: true,
      mediaType: 'streak',
      streakViewsRemaining: 1,
    );
    await _pump(
      tester,
      MessageBubble(message: failedStreak, onRetry: () => retried = true),
    );

    expect(find.text('Sending…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Not sent. Tap to retry'), findsOneWidget);
    // The footer's own Retry still works alongside the body's.
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Not sent. Tap to retry'));
    await tester.pump();
    expect(retried, isTrue);
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/chat/streak_bubble_test.dart test/features/chat/message_bubble_test.dart`
Expected: compile error `The named parameter 'isFailed' isn't defined` (streak_bubble_test); the message_bubble test fails with `Expected: no matching candidates Actual: … 'Sending…'`.

- [ ] **Step 3: Implement**

`streak_bubble.dart` — constructor and fields:

```dart
  const StreakBubble({
    super.key,
    required this.viewsRemaining,
    required this.hasBeenPlayed,
    required this.onTap,
    this.isMine = false,
    this.openedByRecipient = false,
    this.isSending = false,
    this.isFailed = false,
    this.onRetry,
    this.foregroundColor,
    this.metadataColor,
    this.accentColor,
  });

  /// The upload gave up (automatic attempts exhausted). Wins over
  /// [isSending]: a failed row still carries its optimistic id.
  final bool isFailed;

  /// Tapping the failed state retries; null renders it inert.
  final VoidCallback? onRetry;
```

In `build`, insert before `if (isSending) {`:

```dart
    if (isFailed) {
      // Plain words and the error colour, never a spinner: "Failed" in the
      // UI means "will not send without you" (CHAT_SYSTEM_SPEC §3.3).
      final errorColor = colorScheme.error;
      return InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: errorColor),
              const SizedBox(width: 6),
              Text(
                'Not sent. Tap to retry',
                style: textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
```

`message_bubble.dart`:
- `_BubbleBody` constructor: add `this.onRetry,` and field `/// Retries a failed send (streak body offers it inline).\n  final VoidCallback? onRetry;`
- where `MessageBubble.build` constructs `_BubbleBody(` (the branch after `else` under the emoji-artwork check — inside the hoisted `content` Column after Plan 3 Task 7), add `onRetry: onRetry,`.
- streak branch: change `isSending: message.id.startsWith('_local_'),` to

```dart
          // An optimistic row has no server id yet; the upload is still
          // in flight behind this bubble — unless it has given up.
          isSending: message.id.startsWith('_local_') && !message.isFailed,
          isFailed: message.isFailed,
          onRetry: onRetry,
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chat/streak_bubble_test.dart test/features/chat/message_bubble_test.dart test/features/chat/chat_streak_retry_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/presentation/widgets/streak_bubble.dart lib/features/chat/presentation/widgets/message_bubble.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

### Task 7: A partner's game move arrives like a message — settles into place with a light haptic; the trail never animates (#43, M-5)

**Files:**
- Create: `lib/features/chat/presentation/widgets/game_move_ledger.dart`
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`_maybeReceiveHaptic`, the baseline fold in `_init`, new `_maybePartnerMoveHaptic`)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_MessageListState`: `_syncArrivals`, the `itemBuilder` arrival branch, the `MakeRoom`/`SettleIn` keys)
- Modify: `test/features/chat/support/chat_test_harness.dart` (`seedIncoming` gains `sortAt`, `gameSessionId`)
- Test: `test/features/chat/game_move_ledger_test.dart`, `test/features/chat/game_move_haptic_test.dart` (create)

**Interfaces:**
- `class GameMoveLedger { Set<String> sync(Iterable<Message> messages); int revisionOf(String clientMessageId); }` — `sync` returns the client ids of game cards whose `presentationSortAt` advanced since the previous call (first sight of a card is a baseline, not a move). `revisionOf` increments once per move.
- `FakeChatRepository.seedIncoming({…, DateTime? sortAt, String? gameSessionId})`.
- Design decision (brief): haptic `light()` only, no receive chirp — a move is not a message. `_maybeReceiveHaptic` now ignores `isGame`/`isGameTrail` rows so a moved card can never double as a "new partner message" (today it does whenever the card's `createdAt` is newer than the last partner text).

- [ ] **Step 1: Write the failing ledger tests**

```dart
// test/features/chat/game_move_ledger_test.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/game_move_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

Message _game(String id, DateTime sortAt, {bool isMine = true}) => Message(
  id: id,
  clientMessageId: 'c-$id',
  relationshipId: 'r1',
  senderId: isMine ? 'me' : 'partner',
  content: 'Snakes and Ladders',
  createdAt: DateTime(2026, 10, 19, 9),
  sortAt: sortAt,
  status: MessageStatus.delivered,
  isMine: isMine,
  mediaType: 'game',
  gameSessionId: 's-$id',
);

Message _text(String id, DateTime at) => Message(
  id: id,
  clientMessageId: 'c-$id',
  relationshipId: 'r1',
  senderId: 'partner',
  content: 'hi',
  createdAt: at,
  status: MessageStatus.delivered,
  isMine: false,
);

void main() {
  final t0 = DateTime(2026, 10, 19, 9);
  final t1 = DateTime(2026, 10, 19, 10);

  test('first sight of a card is a baseline, not a move', () {
    final ledger = GameMoveLedger();
    expect(ledger.sync([_game('g1', t0), _text('m1', t0)]), isEmpty);
    expect(ledger.revisionOf('c-g1'), 0);
  });

  test('a card whose sortAt advanced is reported once, with a new revision',
      () {
    final ledger = GameMoveLedger();
    ledger.sync([_game('g1', t0)]);
    expect(ledger.sync([_game('g1', t1, isMine: false)]), {'c-g1'});
    expect(ledger.revisionOf('c-g1'), 1);
    // The same snapshot again is not a second move.
    expect(ledger.sync([_game('g1', t1, isMine: false)]), isEmpty);
    expect(ledger.revisionOf('c-g1'), 1);
  });

  test('a card that only re-sorts in place still counts as a move', () {
    // Review Focus 5: move_game_card bumps sort_at even when the card is
    // already on the actor's side (a session game answered twice).
    final ledger = GameMoveLedger();
    ledger.sync([_game('g1', t0, isMine: false)]);
    expect(ledger.sync([_game('g1', t1, isMine: false)]), {'c-g1'});
  });

  test('non-game rows and an older sortAt are ignored', () {
    final ledger = GameMoveLedger();
    ledger.sync([_game('g1', t1), _text('m1', t0)]);
    expect(ledger.sync([_game('g1', t0), _text('m1', t1)]), isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/game_move_ledger_test.dart`
Expected: compile error — `game_move_ledger.dart` does not exist.

- [ ] **Step 3: Implement the ledger**

```dart
// lib/features/chat/presentation/widgets/game_move_ledger.dart
import 'package:attune/features/chat/domain/entities/message.dart';

/// Notices a game card that MOVED.
///
/// `move_game_card` keeps the card's id/client id/created_at and rewrites
/// only `sender_id` and `sort_at`, so the identity-based arrival tracker
/// never sees a move: the card teleported from mid-history to the bottom
/// with no motion. A move is a card whose presentationSortAt is later than
/// the last one this ledger saw for it. First sight is a baseline.
class GameMoveLedger {
  final Map<String, DateTime> _sortAt = {};
  final Map<String, int> _revision = {};

  /// Client ids of cards that moved since the previous [sync].
  Set<String> sync(Iterable<Message> messages) {
    final moved = <String>{};
    for (final message in messages) {
      if (!message.isGame) continue;
      final id = message.clientMessageId;
      final previous = _sortAt[id];
      _sortAt[id] = message.presentationSortAt;
      if (previous != null && message.presentationSortAt.isAfter(previous)) {
        _revision[id] = (_revision[id] ?? 0) + 1;
        moved.add(id);
      }
    }
    return moved;
  }

  /// How many times [clientMessageId] has moved. Part of the row's motion
  /// key, so each move gets a fresh SettleIn/MakeRoom (they decide once).
  int revisionOf(String clientMessageId) => _revision[clientMessageId] ?? 0;
}
```

`dart format` the new file and its test. Run: `flutter test test/features/chat/game_move_ledger_test.dart` → `All tests passed!`

- [ ] **Step 4: Write the failing ChatState haptic test**

First extend the harness. In `test/features/chat/support/chat_test_harness.dart`, `FakeChatRepository.seedIncoming`: add parameters `DateTime? sortAt,` and `String? gameSessionId,` after `String messageOrigin = 'user',` and two row entries after `'message_origin': messageOrigin,`:

```dart
      // Games: a moved card keeps its id/created_at and advances sort_at.
      'sort_at': (sortAt ?? createdAt).toUtc().toIso8601String(),
      'game_session_id': gameSessionId,
```

(`Message.fromRow` already reads `sort_at` and `game_session_id`; existing callers are unaffected because `sort_at` defaults to `created_at`.)

```dart
// test/features/chat/game_move_haptic_test.dart
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  final t0 = DateTime.now().subtract(const Duration(minutes: 10));

  test('a partner move while the chat is in view fires one light haptic '
      'and no receive chirp', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final haptics = FakeHaptics();
    final sound = FakeSoundService();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    // An older partner text, so the moved card is NOT the first-ever
    // partner row (that path has its own baseline semantics).
    repo.seedIncoming(
      id: 'p0',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'your turn soon',
      createdAt: t0.subtract(const Duration(hours: 1)),
    );
    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'Snakes and Ladders',
      createdAt: t0,
      mediaType: 'game',
      gameSessionId: 's1',
    );
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        hapticsProvider.overrideWithValue(haptics),
        soundServiceProvider.overrideWithValue(sound),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.setViewActive(true);

    // The partner plays: same id/created_at, new sender and sort_at.
    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'Snakes and Ladders',
      createdAt: t0,
      sortAt: DateTime.now(),
      mediaType: 'game',
      gameSessionId: 's1',
    );
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(haptics.lightCount, 1);
    expect(haptics.selectionCount, 0,
        reason: 'a move is not a new message (Review Focus 5)');
    expect(sound.played, isEmpty);
  });

  test('a partner move while backgrounded is silent', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final haptics = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'Snakes and Ladders',
      createdAt: t0,
      mediaType: 'game',
      gameSessionId: 's1',
    );
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [hapticsProvider.overrideWithValue(haptics)],
    );
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.setViewActive(false);

    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'Snakes and Ladders',
      createdAt: t0,
      sortAt: DateTime.now(),
      mediaType: 'game',
      gameSessionId: 's1',
    );
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(haptics.lightCount, 0);
  });

  test('my own move gives no haptic', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final haptics = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'Snakes and Ladders',
      createdAt: t0,
      mediaType: 'game',
      gameSessionId: 's1',
    );
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [hapticsProvider.overrideWithValue(haptics)],
    );
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.setViewActive(true);

    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'Snakes and Ladders',
      createdAt: t0,
      sortAt: DateTime.now(),
      mediaType: 'game',
      gameSessionId: 's1',
    );
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(haptics.lightCount, 0);
  });
}
```

Run: `flutter test test/features/chat/game_move_haptic_test.dart`
Expected: first test fails `Expected: <1> Actual: <0>` on `lightCount` (and, depending on history, `selectionCount` 1 — the spurious receive feedback the fix removes).

- [ ] **Step 5: Implement in ChatState**

In `chat_state.dart`, next to `_lastPartnerMessageId`:

```dart
  /// sortAt of every canonical game card we have seen, by message id. A
  /// partner's move keeps the card's id and advances sort_at
  /// (move_game_card), so a later sortAt on a known, now partner-owned card
  /// IS the move — the only live signal the transcript gets.
  final Map<String, DateTime> _gameCardSortAt = {};
```

Replace `_maybeReceiveHaptic` and add `_maybePartnerMoveHaptic`:

```dart
  void _maybeReceiveHaptic() {
    _maybePartnerMoveHaptic();
    // Game cards and trails are excluded: a moved card keeps an old
    // createdAt yet flips to !isMine, and a trail is a new row at an old
    // position — neither is a new message, and either used to fire the
    // receive chirp depending on what else was in history.
    final newestPartner = state.messages
        .where(
          (m) =>
              !m.isMine &&
              !m.id.startsWith('_local_') &&
              !m.isGame &&
              !m.isGameTrail,
        )
        .fold<Message?>(
          null,
          (best, m) =>
              best == null || m.createdAt.isAfter(best.createdAt) ? m : best,
        );
    final id = newestPartner?.id;
    if (id == null) return;
    final isNew = _hasSeededPartnerBaseline && id != _lastPartnerMessageId;
    _lastPartnerMessageId = id;
    if (isNew && _isViewActive) {
      ref.read(hapticsProvider).selection();
      if (ref.read(messageSoundsEnabledProvider)) {
        ref.read(soundServiceProvider).play(ChatSound.receive);
      }
    }
  }

  /// One light haptic when the partner moves a game while the chat is in
  /// view. Quieter than a message on purpose: no chirp. Content-blind —
  /// keys off sortAt and isMine only.
  void _maybePartnerMoveHaptic() {
    var partnerMoved = false;
    for (final m in state.messages) {
      if (!m.isGame || m.id.startsWith('_local_')) continue;
      final previous = _gameCardSortAt[m.id];
      _gameCardSortAt[m.id] = m.sortAt;
      if (previous != null && m.sortAt.isAfter(previous) && !m.isMine) {
        partnerMoved = true;
      }
    }
    if (partnerMoved && _hasSeededPartnerBaseline && _isViewActive) {
      ref.read(hapticsProvider).light();
    }
  }
```

In `_init`, the baseline fold that seeds `_lastPartnerMessageId` (`.where((m) => !m.isMine && !m.id.startsWith('_local_'))`) gets the same two exclusions: `.where((m) => !m.isMine && !m.id.startsWith('_local_') && !m.isGame && !m.isGameTrail)`.

Run: `flutter test test/features/chat/game_move_haptic_test.dart test/features/chat/receive_haptic_test.dart test/features/chat/receive_sound_test.dart` → `All tests passed!`

- [ ] **Step 6: Wire the list (settle at the new slot; trails never animate)**

In `chat_screen.dart`, `_MessageListState`:

Add import `import 'package:attune/features/chat/presentation/widgets/game_move_ledger.dart';` and the field next to `_arrivalTracker`:

```dart
  /// Cards that moved (sort_at advanced) get a fresh motion key so they
  /// settle into their new slot like an arrival; see GameMoveLedger.
  final GameMoveLedger _gameMoves = GameMoveLedger();
```

Replace `_syncArrivals`. After Plan 3 Task 10 it already has the `_awayFromBottom` / `_unseenWhileAway` block (the scroll-to-latest pill's badge) — that block is KEPT; only the arrival set is reshaped before it. (Task 8 edits this same function once more — apply Task 8 on top of this shape.)

```dart
  void _syncArrivals(ChatState state) {
    // Copy: the tracker returns a const set on its baseline frames.
    final arrivals = <String>{
      ..._arrivalTracker.sync(
        state.messages.map((message) => message.clientMessageId),
        initialLoading: state.isLoading,
        loadingMore: state.isLoadingMore,
      ),
    };
    // A trail is a marker of where a card WAS (leave_game_trail inserts a
    // new row at the card's old sort_at). It is never an arrival: it used
    // to slide/fade in twenty messages up, where nobody was looking.
    for (final message in state.messages) {
      if (message.isGameTrail && arrivals.remove(message.clientMessageId)) {
        widget.animatedMessageIds.add(message.clientMessageId);
      }
    }
    // A moved card re-arrives at its new slot.
    for (final id in _gameMoves.sync(state.messages)) {
      widget.animatedMessageIds.remove(id);
      arrivals.add(id);
    }
    _pendingArrivalIds.addAll(arrivals);
    // Plan 3 (#32): partner rows that landed while the reader was scrolled
    // up feed the pill's badge. A moved card counts too — the partner did
    // something down there.
    if (_awayFromBottom && arrivals.isNotEmpty) {
      final byClientId = {
        for (final m in state.messages) m.clientMessageId: m,
      };
      _unseenWhileAway +=
          arrivals.where((id) => byClientId[id]?.isMine == false).length;
    }
  }
```

(If `_awayFromBottom` does not exist in the file, Plan 3 Task 10 has not run — stop and check the execution order rather than dropping the block.)

In the `itemBuilder`, where the row is wrapped — the `MakeRoom(` has no key and `SettleIn(key: ValueKey(message.clientMessageId), …)`. (Plan 3 Task 9 wrapped the whole row in `KeyedSubtree(key: ValueKey('row-${message.id}'))` for `findChildIndexCallback`; that outer key is untouched — a moved card keeps its message id, so the sliver reuses its element and only the inner motion keys below change.) Both decide "animate or not" once per State, so a moved card (reparented via its GlobalKey) must get a NEW State. Change to:

```dart
                      child: MakeRoom(
                        key: _motionKey(message.clientMessageId, 'room'),
                        animate: shouldAnimate,
                        child: SettleIn(
                          key: _motionKey(message.clientMessageId, 'settle'),
```

and add the helper method on `_MessageListState`:

```dart
  /// Stable per row, fresh per game move. Revision 0 keeps the plain
  /// client-id key every existing test and flight lookup relies on.
  Key _motionKey(String clientMessageId, String slot) {
    final revision = _gameMoves.revisionOf(clientMessageId);
    if (revision == 0) {
      return slot == 'settle'
          ? ValueKey(clientMessageId)
          : ValueKey('$slot:$clientMessageId');
    }
    return ValueKey('$slot:$clientMessageId#move$revision');
  }
```

- [ ] **Step 7: Run the list tests**

Run: `flutter test test/features/chat/message_list_animation_test.dart test/features/chat/message_arrival_tracker_test.dart test/features/chat/first_of_day_shimmer_test.dart test/features/chat/reconnect_cascade_test.dart test/features/chat/game_trail_golden_test.dart test/features/chat/game_staged_wiring_test.dart`
Expected: `All tests passed!` (golden unchanged: a trail's *appearance* is untouched, only whether it animates).

- [ ] **Step 8: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/presentation/widgets/game_move_ledger.dart lib/features/chat/presentation/state/chat_state.dart lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/support/chat_test_harness.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

**Device check (owner):** two phones, Snakes invite from A; B plays a move while A's chat is open: on A the card slides down into the bottom slot with a light tap; the "Snakes and Ladders" trail line simply appears in place with no motion; no chirp.

---

### Task 8: Arrivals are time-boxed, so nothing animates minutes later under the finger (M-7)

**Files:**
- Create: `lib/features/chat/presentation/widgets/pending_arrivals.dart`
- Modify: `lib/core/ui/motion/motion_tokens.dart` (add `kArrivalAnimationWindow`)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_MessageListState._pendingArrivalIds` → `PendingArrivals`; `_syncArrivals`; `itemBuilder` `shouldAnimate`)
- Test: `test/features/chat/pending_arrivals_test.dart` (create)

**Interfaces:**
- `const Duration kArrivalAnimationWindow = Duration(milliseconds: 1500);`
- `class PendingArrivals { PendingArrivals({Duration window = kArrivalAnimationWindow}); void add(Iterable<String> ids, DateTime now); bool take(String id, DateTime now); bool get isEmpty; }` — `take` removes the id and returns true only if it was added within `window` of `now`.
- Why time instead of scroll position: a row that is not built when it arrives (user scrolled up, screen covered by a game/media route, app backgrounded with the chat open) stays pending indefinitely today, then opens its slot with `MakeRoom` whenever it is finally built — mid-fling, under the finger. iMessage semantics: a message that arrived while you were away is simply there. Plan 3 (#32) adds the "new messages" pill; this makes the late replay impossible regardless.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/chat/pending_arrivals_test.dart
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/features/chat/presentation/widgets/pending_arrivals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 10, 19, 12);

  test('an arrival built within the window animates once', () {
    final pending = PendingArrivals();
    pending.add(['a'], t0);
    expect(pending.take('a', t0.add(const Duration(milliseconds: 200))), isTrue);
    expect(pending.take('a', t0.add(const Duration(milliseconds: 300))), isFalse,
        reason: 'consumed');
  });

  test('an arrival first built after the window is simply there', () {
    // The user was three screens up re-reading; two minutes later they
    // fling down and the rows used to open their slots under the finger.
    final pending = PendingArrivals();
    pending.add(['late'], t0);
    expect(
      pending.take('late', t0.add(kArrivalAnimationWindow + const Duration(milliseconds: 1))),
      isFalse,
    );
    expect(pending.isEmpty, isTrue, reason: 'expired ids are dropped');
  });

  test('re-adding a pending id does not extend its window', () {
    final pending = PendingArrivals();
    pending.add(['a'], t0);
    pending.add(['a'], t0.add(const Duration(seconds: 5)));
    expect(pending.take('a', t0.add(const Duration(seconds: 5, milliseconds: 100))), isFalse);
  });

  test('unknown ids are never arrivals', () {
    expect(PendingArrivals().take('x', t0), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/pending_arrivals_test.dart`
Expected: compile error — missing file and `kArrivalAnimationWindow`.

- [ ] **Step 3: Implement**

Append to `lib/core/ui/motion/motion_tokens.dart`:

```dart

/// How long after a message arrives its one-time arrival animation may still
/// play. A row first built later than this (the reader was scrolled up, in a
/// game, or backgrounded) is simply there — iMessage never replays an arrival
/// minutes late under your finger.
const Duration kArrivalAnimationWindow = Duration(milliseconds: 1500);
```

```dart
// lib/features/chat/presentation/widgets/pending_arrivals.dart
import 'package:attune/core/ui/motion/motion_tokens.dart';

/// Arrivals waiting for their row to be built, each stamped with when it
/// arrived. The arrival animation is a "just now" gesture: past
/// [window] the id is dropped and the row renders settled.
class PendingArrivals {
  PendingArrivals({this.window = kArrivalAnimationWindow});

  final Duration window;
  final Map<String, DateTime> _since = {};

  /// Records [ids] as arrived at [now]. An id already pending keeps its
  /// original stamp.
  void add(Iterable<String> ids, DateTime now) {
    for (final id in ids) {
      _since.putIfAbsent(id, () => now);
    }
  }

  /// Consumes [id]. True only if it was pending and still inside [window].
  bool take(String id, DateTime now) {
    final since = _since.remove(id);
    if (since == null) return false;
    return now.difference(since) <= window;
  }

  bool get isEmpty => _since.isEmpty;
}
```

`dart format` both new files. In `chat_screen.dart`, `_MessageListState`:
- add imports `import 'package:attune/features/chat/presentation/widgets/pending_arrivals.dart';` and `import 'package:clock/clock.dart';`
- replace `final Set<String> _pendingArrivalIds = <String>{};` with `final PendingArrivals _pendingArrivals = PendingArrivals();`
- in `_syncArrivals` (Task 7 shape) replace the line `_pendingArrivalIds.addAll(arrivals);` (just above Plan 3's `if (_awayFromBottom && …)` block) with `_pendingArrivals.add(arrivals, clock.now());`
- in the `itemBuilder`, replace `_pendingArrivalIds.remove(message.clientMessageId) &&` with `_pendingArrivals.take(message.clientMessageId, clock.now()) &&`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chat/pending_arrivals_test.dart test/features/chat/message_list_animation_test.dart test/features/chat/first_of_day_shimmer_test.dart test/features/chat/reconnect_cascade_test.dart test/features/chat/live_message_motion_test.dart`
Expected: `All tests passed!` (`clock.now()` outside a `withClock` zone is wall time; the widget tests build arrivals within the same pump, well inside 1.5 s).

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/presentation/widgets/pending_arrivals.dart lib/core/ui/motion/motion_tokens.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

### Task 9: Reduce-motion gaps (L-11)

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (typing `AnimatedSwitcher` durations; `_scrollToLatest`; `_tryEnsureMessageVisible`)
- Modify: `lib/features/chat/presentation/widgets/streak_record_button.dart` (both `TweenAnimationBuilder` entrances)
- Test: `test/features/chat/reduce_motion_gaps_test.dart` (create)

**Interfaces:** none new; `reduceMotionOf(context)` (`lib/core/ui/motion/reduce_motion.dart`).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/chat/reduce_motion_gaps_test.dart
import 'dart:io';

import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

Widget _reduced(Widget child) => MaterialApp(
  builder:
      (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: app!,
      ),
  home: child,
);

void main() {
  testWidgets('the record disc does not spring under Reduce Motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _reduced(
        Scaffold(
          body: Center(
            child: StreakRecordButton(
              progress: 0.2,
              isRecording: true,
              onPressStart: () {},
              onPressEnd: () {},
            ),
          ),
        ),
      ),
    );
    final fill = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('streak-record-fill-entrance')),
    );
    final arc = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('streak-record-arc-entrance')),
    );
    expect(fill.duration, Duration.zero);
    expect(arc.duration, Duration.zero);
  });

  testWidgets('the typing bubble does not pop/scale under Reduce Motion', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(_reduced(ChatScreen(conversation: convo))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    repo.emitPartnerTyping('partner', true);
    await tester.pump();

    final switcher = tester.widget<AnimatedSwitcher>(
      find.ancestor(
        of: find.byKey(const ValueKey('typing_indicator')),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  test('scroll helpers jump instead of animating under Reduce Motion', () {
    // The two scroll sites take a BuildContext and a ScrollController the
    // widget test cannot reach without a full-size transcript; pinned at
    // source: each must branch on reduceMotionOf.
    final src =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();
    final scrollToLatest = src.substring(
      src.indexOf('void _scrollToLatest()'),
      src.indexOf('Future<void> _openPulse()'),
    );
    expect(scrollToLatest, contains('reduceMotionOf(context)'));
    expect(scrollToLatest, contains('jumpTo(0)'));

    final ensure = src.substring(
      src.indexOf('bool _tryEnsureMessageVisible('),
      src.indexOf('Future<void> _jumpToMessage('),
    );
    expect(ensure, contains('reduceMotionOf(context)'));
    expect(ensure, contains('Duration.zero'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/reduce_motion_gaps_test.dart`
Expected: `Expected: Duration:<0:00:00.000000> Actual: Duration:<0:00:00.260000>` for the record disc; same for the switcher; the source test fails on `reduceMotionOf`.

- [ ] **Step 3: Implement**

`streak_record_button.dart`: add `import 'package:attune/core/ui/motion/reduce_motion.dart';`. In `build`, before the widget tree is returned, compute

```dart
    // Spec §2: no spring/scale under Reduce Motion — the disc and arc appear.
    final entrance =
        reduceMotionOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260);
```

and replace both `duration: const Duration(milliseconds: 260),` (keys `streak-record-fill-entrance` and `streak-record-arc-entrance`) with `duration: entrance,`.

`chat_screen.dart`:
- typing `AnimatedSwitcher` (inside the `Consumer` builder that watches `typingControllerProvider(...).partnerTyping`): before `return SizedBox(` add `final reduceMotion = reduceMotionOf(context);` and change `duration: const Duration(milliseconds: 260),` → `duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 260),` and `reverseDuration: const Duration(milliseconds: 180),` → `reverseDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),`. (`reduce_motion.dart` is already imported in this file.)
- `_scrollToLatest`:

```dart
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (reduceMotionOf(context)) {
        _scrollController.jumpTo(0);
        return;
      }
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }
```

- `_tryEnsureMessageVisible`: `duration: const Duration(milliseconds: 400),` → `duration: reduceMotionOf(context) ? Duration.zero : const Duration(milliseconds: 400),`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chat/reduce_motion_gaps_test.dart test/features/chat/streak_record_button_test.dart test/features/chat/typing_indicator_widget_test.dart test/features/chat/chat_screen_initial_jump_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/presentation/widgets/streak_record_button.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

### Task 10: Haptics on long-press menu and reaction pick (L-10)

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (new `onActionsOpened` param, invoked in the `onLongPress:` lambda)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`MessageBubble(` construction: `onActionsOpened:`; the `onReact:` handler)
- Test: `test/features/chat/message_actions_haptics_test.dart` (create)

**Interfaces:** `MessageBubble({…, VoidCallback? onActionsOpened})` — fired exactly when the focused action menu is about to open.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/chat/message_actions_haptics_test.dart
import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('opening the long-press menu reports onActionsOpened once', (
    tester,
  ) async {
    // Swipe-to-reply, send, receive and game-send all have a tactile beat;
    // long-press opened the menu + snapshot in silence.
    var opened = 0;
    final message = Message(
      id: 'm1',
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'partner',
      content: 'hold me',
      createdAt: DateTime(2026, 7, 1, 15, 4),
      status: MessageStatus.delivered,
      isMine: false,
    );
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              currentUserId: 'me',
              onActionsOpened: () => opened++,
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('hold me'));
    await tester.pump();
    expect(opened, 1);
  });

  test('the chat screen wires both haptics through hapticsProvider', () {
    // The reaction pick funnels through the screen's onReact handler (quick
    // bar and full picker alike), which is where the selection click goes.
    final src =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();
    expect(
      src,
      contains('onActionsOpened: () => ref.read(hapticsProvider).light()'),
    );
    final onReact = src.substring(
      src.indexOf('onReact: (emoji) async {'),
      src.indexOf('onReact: (emoji) async {') + 400,
    );
    expect(onReact, contains('ref.read(hapticsProvider).selection();'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/message_actions_haptics_test.dart`
Expected: compile error `The named parameter 'onActionsOpened' isn't defined`.

- [ ] **Step 3: Implement**

`message_bubble.dart` — add constructor param `this.onActionsOpened,` (after `this.onRemoveReaction,`) and the field:

```dart
  /// Fired when the long-press action menu is about to open — the screen
  /// gives it a light haptic (hapticsProvider); the bubble stays stateless.
  final VoidCallback? onActionsOpened;
```

In the `onLongPress:` lambda (after Plan 3 Task 7 it lives inside `MessageBubble.build`'s local `Widget shell(double revealOffset)` — same text, deeper nesting; find it with `grep -n 'onLongPress:' message_bubble.dart`), change the body from `(bubbleRect, bubbleSnapshot) => showFocusedActionMenu(` to a block:

```dart
                                ? (bubbleRect, bubbleSnapshot) {
                                  onActionsOpened?.call();
                                  showFocusedActionMenu(
                                    context: context,
                                    … (unchanged arguments) …
                                  );
                                }
```

(i.e. wrap the existing call in braces, prefix `onActionsOpened?.call();`, add the closing `;` and `}`).

`chat_screen.dart` — in the `MessageBubble(` construction inside the `itemBuilder`, add `onActionsOpened: () => ref.read(hapticsProvider).light(),` next to `onReact:`; and make the first statement of the `onReact: (emoji) async {` body `ref.read(hapticsProvider).selection();`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chat/message_actions_haptics_test.dart test/features/chat/chat_screen_message_actions_test.dart test/features/chat/message_bubble_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

### Task 11: The send chirp means "accepted" (L-12, chirp half)

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_send`, `_sendStagedGame`)
- Test: `test/features/chat/send_feedback_after_validation_test.dart` (create)

**Interfaces:** `Message.isValidContent(String)` / `Message.maxContentRunes` (existing); Plan 3 Task 3's `_ChatScreenState._refuseOverLimitDraft(String) → bool`. Shared with plan 3 (#35): plan 3 owns refusing/keeping an over-long draft AND already placed `if (_refuseOverLimitDraft(text)) return;` in `_send()` above the haptic/chirp (its composer formatter also clamps typed/pasted text at 10,000 code points). This task pins that ordering with a regression test — the draft is set on the controller directly, the one path that bypasses the formatter — and adds the missing send chirp to a staged game. Do NOT add a second, silent `isValidContent` return in `_send`: it would run before plan 3's snackbar and break `chat_screen_draft_limit_test` ("the person must be told").

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/send_feedback_after_validation_test.dart
import 'dart:io';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('a message the controller will refuse gets no chirp or haptic',
      (tester) async {
    // 12k characters: sendMessage returns silently on !isValidContent, yet
    // the "sent" chirp played and the composer emptied — nothing said no.
    // Plan 3 fixed the refusal; this pins that it sits ABOVE the feedback.
    // The draft is written to the controller directly (as _appendToComposer
    // and the translator do) because plan 3's input formatter would clamp
    // tester.enterText to 10,000 code points and make the case vacuous.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final sound = FakeSoundService();
    final haptics = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        soundServiceProvider.overrideWithValue(sound),
        hapticsProvider.overrideWithValue(haptics),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(MaterialApp(home: ChatScreen(conversation: convo))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 30));

    final tooLong = 'a' * (Message.maxContentRunes + 2000);
    final field = find.byType(TextField).first;
    tester.widget<TextField>(field).controller!.value = TextEditingValue(
      text: tooLong,
      selection: TextSelection.collapsed(offset: tooLong.length),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 30));

    expect(sound.played, isEmpty);
    expect(haptics.lightCount, 0);
    expect(repo.sendCallCount, 0);
    expect(find.textContaining('10,000 characters'), findsOneWidget,
        reason: 'plan 3 tells the person; the refusal must not go silent');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });

  test('a staged game plays the send chirp on success', () {
    // _sendStagedGame confirmed with haptics.selection() only; the chirp
    // that every other send gets was missing. Source-pinned: staging a
    // game needs the invites provider chain, which has no fake here.
    final src =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();
    final body = src.substring(
      src.indexOf('Future<void> _sendStagedGame('),
      src.indexOf('_scrollToLatest();', src.indexOf('Future<void> _sendStagedGame(')),
    );
    expect(body, contains('ref.read(soundServiceProvider).play(ChatSound.send)'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/send_feedback_after_validation_test.dart`
Expected: the first test PASSES already (plan 3 Task 3 put `_refuseOverLimitDraft` above the haptic in `_send`; this test is the cross-plan regression guard — to see it bite, temporarily move that `if` line below the chirp and watch `Expected: empty Actual: [AppSound.chatSend]`, then put it back); the source test fails on the missing staged-game chirp.

- [ ] **Step 3: Implement**

`_send()` needs no change: confirm with `grep -n '_refuseOverLimitDraft(text)' chat_screen.dart` that the refusal line precedes `ref.read(hapticsProvider).light();` in `_send`. If it does not (plan 3 drifted), move it there — do not add a second check.

In `_sendStagedGame`, replace `ref.read(hapticsProvider).selection();` (the line right after `// from the conversation they chose to send it in.`) with:

```dart
    ref.read(hapticsProvider).selection();
    if (ref.read(messageSoundsEnabledProvider)) {
      ref.read(soundServiceProvider).play(ChatSound.send);
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chat/send_feedback_after_validation_test.dart test/features/chat/chat_screen_draft_limit_test.dart test/features/chat/send_sound_test.dart test/features/chat/send_feedback_test.dart test/features/chat/game_staged_wiring_test.dart`
Expected: `All tests passed!` (`chat_screen_draft_limit_test.dart` is plan 3's — it must still see the "too long" snackbar).

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

### Task 12: Game card — right viewer in read-only transcripts, honest error label (L-13 partial)

**Files:**
- Modify: `lib/features/games/presentation/widgets/game_message_bubble.dart` (label when `session.hasError`)
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (new `viewerUserId` param → `_BubbleBody.viewerId`)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`MessageBubble(` construction: `viewerUserId:`)
- Test: `test/features/chat/game_card_viewer_test.dart` (create)

**Interfaces:** `MessageBubble({…, String? viewerUserId})` — who is reading, independent of whether actions are allowed (`currentUserId` is null for read-only conversations and optimistic rows on purpose; it gates actions, not perspective).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/chat/game_card_viewer_test.dart
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/widgets/game_message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

const _won = GameCardState(
  gameType: 'snakes_and_ladders',
  status: 'completed',
  currentTurnUserId: null,
  winnerUserId: 'me',
  currentRound: null,
  totalRounds: null,
);

Message _gameCard() => Message(
  id: 'g1',
  clientMessageId: 'c-g1',
  relationshipId: 'r1',
  senderId: 'me',
  content: 'Snakes and Ladders',
  createdAt: DateTime(2026, 7, 1),
  status: MessageStatus.delivered,
  isMine: true,
  mediaType: 'game',
  gameSessionId: 's1',
);

void main() {
  testWidgets('a read-only transcript still phrases the card for its reader',
      (tester) async {
    // currentUserId is null for ended relationships (actions off), so the
    // card compared the winner against '' and a game you won read
    // "You lost" in Previous Relationships.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameCardProvider.overrideWith((ref, id) => Stream.value(_won)),
        ],
        child: withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: _gameCard(),
                currentUserId: null,
                viewerUserId: 'me',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You won!'), findsOneWidget);
    expect(find.text('You lost'), findsNothing);
  });

  testWidgets('a session that fails to load says so instead of "…"', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gameCardProvider.overrideWith(
            (ref, id) => Stream<GameCardState?>.error(Exception('offline')),
          ),
        ],
        child: withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: GameMessageBubble(
                sessionId: 's1',
                viewerId: 'me',
                viewerIsSender: true,
                fallbackLabel: 'Snakes and Ladders',
                onTap: (_, __, ___) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Snakes and Ladders'), findsOneWidget);
    expect(find.text("Couldn't load right now"), findsOneWidget);
    expect(find.text('…'), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/chat/game_card_viewer_test.dart`
Expected: compile error `The named parameter 'viewerUserId' isn't defined`; the second test fails with `'…'` found.

- [ ] **Step 3: Implement**

`game_message_bubble.dart` — replace the `label` computation:

```dart
    final label =
        session.hasError
            // Offline / stream error: the card is still a record of a game,
            // not a mystery. (Opening it needs the game type, which only
            // the session carries — a follow-up.)
            ? "Couldn't load right now"
            : state == null
            ? '…'
            : gameCardLabel(
              state: state,
              viewerId: viewerId,
              viewerIsSender: viewerIsSender,
              partnerName: partnerNameOr(ref, fallback: 'your partner'),
            );
```

`message_bubble.dart` — add `this.viewerUserId,` to the `MessageBubble` constructor (after `this.currentUserId,`) and the field:

```dart
  /// Who is reading. Unlike [currentUserId] it is NOT nulled for read-only
  /// conversations or optimistic rows: those gate actions, not perspective
  /// (a game card must still say "You won" in Previous Relationships).
  final String? viewerUserId;
```

and in the `_BubbleBody(` construction (inside the hoisted `content` Column after Plan 3 Task 7) change `viewerId: currentUserId,` to `viewerId: viewerUserId ?? currentUserId,`.

`chat_screen.dart` — in the `MessageBubble(` construction add `viewerUserId: ref.read(currentUserProvider)?.id,` next to `currentUserId:`.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chat/game_card_viewer_test.dart test/features/games/game_card_surface_test.dart test/features/chat/game_card_no_duplicate_title_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/features/games/presentation/widgets/game_message_bubble.dart lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/screens/chat_screen.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

### Task 13: Conversations preview labels games and places; search skips trails (L-14)

**Files:**
- Modify: `lib/features/chat/domain/utils/conversation_preview.dart`
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart` (`searchMessages`)
- Test: `test/features/chat/conversation_preview_test.dart` (add), `test/features/chat/supabase_chat_repository_test.dart` (add)

- [ ] **Step 1: Write the failing tests**

Append to `test/features/chat/conversation_preview_test.dart` inside `main` (uses its `_withLast`/`_message` helpers):

```dart
  test('a game card previews as a game, with its name', () {
    expect(
      conversationPreviewText(
        _withLast(_message(mediaType: 'game', content: 'Snakes and Ladders')),
      ),
      'Game: Snakes and Ladders',
    );
  });

  test('a trail previews the same way, never as bare text', () {
    expect(
      conversationPreviewText(
        _withLast(_message(mediaType: 'game_trail', content: 'Snakes and Ladders')),
      ),
      'Game: Snakes and Ladders',
    );
  });

  test('a place previews as a place', () {
    expect(
      conversationPreviewText(
        _withLast(_message(mediaType: 'place', content: 'Checked in at Osu')),
      ),
      'Place: Checked in at Osu',
    );
  });
```

Append to `test/features/chat/supabase_chat_repository_test.dart` (add `import 'dart:io';`):

```dart
  test('search excludes game trails without dropping plain text rows', () {
    // Each trail row carries the game's name as content, so "snakes"
    // returned the card plus every trail. `.neq` alone would also drop
    // every row whose media_type is NULL (plain text) — SQL three-valued
    // logic — hence the explicit `is.null` alternative.
    final src =
        File(
          'lib/features/chat/data/repositories/supabase_chat_repository.dart',
        ).readAsStringSync();
    final body = src.substring(
      src.indexOf('Future<List<Message>> searchMessages('),
      src.indexOf('Future<', src.indexOf('Future<List<Message>> searchMessages(') + 10),
    );
    expect(body, contains(".or('media_type.is.null,media_type.neq.game_trail')"));
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/chat/conversation_preview_test.dart test/features/chat/supabase_chat_repository_test.dart`
Expected: `Expected: 'Game: Snakes and Ladders' Actual: 'Snakes and Ladders'` (×2), `Expected: 'Place: …'`, and the search source test fails.

- [ ] **Step 3: Implement**

`conversation_preview.dart` — extend the labels map:

```dart
  const labels = <String, String>{
    'image': 'Photo',
    'video': 'Video',
    'audio': 'Voice message',
    'streak': 'Streak',
    // content holds the game's display name (written by post_game_message),
    // so the caption rule below yields "Game: Snakes and Ladders".
    'game': 'Game',
    'game_trail': 'Game',
    'place': 'Place',
  };
```

`supabase_chat_repository.dart` — in `searchMessages`, after `.ilike('content', '%$escaped%')` add:

```dart
        // Trails repeat the game's name at every move; only the card should
        // match. `.or` with `is.null` keeps plain-text rows (NULL media_type),
        // which a bare `.neq` would silently drop.
        .or('media_type.is.null,media_type.neq.game_trail')
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/chat/conversation_preview_test.dart test/features/chat/supabase_chat_repository_test.dart test/features/chat/conversations_screen_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Checkpoint**

Run this task's tests and `flutter analyze lib/features/chat/domain/utils/conversation_preview.dart lib/features/chat/data/repositories/supabase_chat_repository.dart | grep -E '^\s*(error|warning) '`; expected no output. No commit (the owner commits).

---

## Final verification (after Task 13)

Run: `flutter test test/core/ui test/features/chat test/features/games test/features/settings`
Expected: `All tests passed!`

Run: `flutter analyze lib/core/ui/feedback lib/core/ui/motion lib/features/chat lib/features/games/presentation/widgets/game_message_bubble.dart | grep -E '^\s*(error|warning) '`
Expected: no output.

Run the SQL contract files once more against `attune_spec3a` (Task 5 Step 4 command). Expected: exit 0, no `CONTRACT VIOLATED`. Also `grep -rn "respectSilence\|AudioContextConfig(" lib/` → nothing.

## Owner deploy steps

1. `supabase db push` (or apply, in this order) `supabase/migrations/20261019140000_streak_replay_window_read_gate.sql` then `20261019140010_streak_replay_window_read_gate_grants.sql` to the live project — they create `expire_streak_clips` (internal), `streak_clips_for_viewing` (EXECUTE → authenticated) and replace the `streak_clips_members_read` policy. Deploy BEFORE shipping the client build that calls the RPC (the old client keeps working: its table read is simply gated). These are the only migrations in this plan's range (20261019140000–20261019149999); plans 1a/1b/2 use 1000xx/1100xx/1200xx and plan 3 has none, so the timestamps stay unique and ordered.
2. No edge-function or OneSignal changes in this plan. No Xcode capability changes.
3. Device checks (two phones): Android music + chirps (Task 2), iOS silent switch + voice note (Task 3), streak loading-tap/back (Task 4), replay after 30 min reads "Opened" and refuses to open (Task 5), failed streak upload in airplane mode (Task 6), partner game move settles with a light tap and the trail appears without motion (Task 7), scroll up → receive two messages → fling down: rows are simply there (Task 8), iOS Reduce Motion on: typing bubble and record disc appear without spring (Task 9).
4. Optional follow-ups recorded in Rulings: iOS `notifyOthersOnDeactivation` for music resume after a voice note; "Expressive" settings copy; offline-openable game cards (needs game type on the message row).

## Self-review

- **Spec coverage:** #39 → T1/T2; #40 → T1/T2/T3; #41 → T4; #42 → T6; #43 → T7. 06 remainder: M-7 → T8 (+ ruling for the pill), M-8 → T5, L-10 → T10, L-11 → T9, L-12 → T11 (+ ruling), L-13 → T12 (+ ruling), L-14 → T13, L-15 → ruling, M-4/M-9 → rulings (plan 3). Every item mapped.
- **Placeholder scan:** no TBD/TODO; every code step has code; the two "if plan 2/3 changed X" notes name the grep and the exact alternative action rather than deferring.
- **Type consistency:** `PlayerContextSetter`, `AppAudioContexts.chirp/voiceNote`, `AudioSessionCoordinator.{applyChirpGlobalContext, configureChirpPlayer, beforeChirp, beginPlayback, endPlayback, playbackHeld}`, `FakeAudioSessionPort.globalContexts` used identically in T1–T3; `AudioPlayerSoundService(session:, createPlayer:)` (T2); `VoicePlaybackController(session:)` + `_acquireSession`/`_releaseSession` over Plan 2's `VoicePlaybackEngine.setAudioContext` / `FakeVoiceEngine.contexts` (T3); `GameMoveLedger.sync/revisionOf` in T7 ledger + list; `PendingArrivals.add/take` in T8; `StreakBubble.isFailed/onRetry` and `_BubbleBody.onRetry` in T6; `MessageBubble.onActionsOpened` (T10) and `viewerUserId` (T12); `streakViewsAvailable` (T5); `seedIncoming(sortAt:, gameSessionId:)` (T7); `_refuseOverLimitDraft` consumed from Plan 3 (T11).
- **Cross-plan order:** T3 edits only Plan 2's controller (its engine seam and fake already exist), never the pre-plan-2 widget; T7's `_syncArrivals` is Plan 3's post-Task-10 body plus the game reshaping; T8 swaps one line inside it; T10/T12 edit lambdas Plan 3 Task 7 moved into `shell`/`content`; T11 relies on Plan 3's refusal ordering instead of adding its own.
- **Review Focus:** 1 → T1 "a chirp during a held playback leaves the session alone"; 2 → T1 "holds are counted, not boolean"; 3 → T4 "a video that never reaches its first frame"; 4 → T4 "clips the server says are gone still sync the budget" + pop tests; 5 → T7 ledger "re-sorts in place" + haptic test's `selectionCount == 0`.
