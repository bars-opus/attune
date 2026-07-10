# Chat Sounds — Implementation Plan (Plan 2 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add soft, warm send/receive sounds to chat — default on, one settings toggle, muted by the OS silent switch/DND — so the chat has an audible signature, without ever double-firing or playing when backgrounded.

**Architecture:** A universal injectable `SoundService` in `lib/core/ui/feedback/` (beside `haptics.dart`), backed by `audioplayers`, preloading two short clips and playing them on the same event hooks the haptics already use. A `SoundPreference` (backed by the existing `sharedPreferencesProvider`) gates playback via one settings toggle. iOS uses the "ambient" audio context so the hardware silent switch mutes sounds automatically. Placeholder assets ship now; professionally-designed audio swaps in before launch by replacing two files.

**Tech Stack:** Flutter, `audioplayers`, existing `sharedPreferencesProvider` (`lib/core/providers/shared_prefs_provider.dart`), existing `hapticsProvider` pattern (`lib/core/ui/feedback/haptics.dart`).

**Scope of this plan (Plan 2):** Spec §3.6 (send/receive sounds, system now + placeholder assets) and the sound half of §4 (settings toggle). **Deferred:** Plan 3 = typing presence; Plan 4 = rituals + the full "Chat feel" settings group (this plan adds only the message-sounds toggle).

## Global Constraints

- **Default on, one toggle:** a single "Message sounds" preference, default `true`. (Spec §3.6, §4.)
- **Silent switch / DND respected:** iOS uses the `ambient` audio context so the hardware silent switch and DND mute chat sounds; Android inherits normal media-volume behavior. No sound plays when the OS says silent. (Spec §3.6.)
- **No double-fire:** a send plays at most one send sound; optimistic→canonical reconciliation must NOT re-play. The receive sound reuses `_maybeReceiveHaptic`'s already-guarded "genuinely new partner message while viewing" logic, so it inherits the same once-only, foreground-only, own-message-excluded gating. (Spec §3.6.)
- **Never on backgrounded receive:** receive sound only when the chat is foregrounded/visible (same `_isViewActive` gate as the receive haptic). (Spec §3.6, §9.2.)
- **Content-blind:** sounds fire on send/receive events only, never on message content. (Spec §1.1.)
- **Injectable + testable:** playback goes through an interface with a fake, so tests assert call counts with no real audio device. (Spec §5.3.)
- **Fail-safe:** audio init or playback failure is a silent no-op and never blocks send/receive. (Spec §5.4.)
- **Reuse, don't duplicate:** `SoundService` lives beside `haptics.dart`; the toggle uses the existing `sharedPreferencesProvider`, not a new prefs mechanism.
- **Placeholder assets are explicitly temporary:** committed under `assets/sounds/` and swapped for pro audio before launch (tracked as a gate item).

---

### Task 1: Add audioplayers dependency and the sounds asset folder

**Files:**
- Modify: `pubspec.yaml` (dependencies + assets)
- Create: `assets/sounds/chat_send.wav` (placeholder), `assets/sounds/chat_receive.wav` (placeholder)
- Create: `assets/sounds/README.md`

**Interfaces:**
- Produces: the `audioplayers` package available for import; two asset paths
  `assets/sounds/chat_send.wav` and `assets/sounds/chat_receive.wav`
  registered in the bundle.

**Note:** WAV (not MP3) is used for placeholders because a valid WAV can be
generated deterministically with the Python stdlib, with no ffmpeg dependency.
`audioplayers` plays WAV fine. Real pro assets may be WAV or MP3 later; keep the
filenames stable (see README).

- [ ] **Step 1: Add the dependency**

Add under `dependencies:` in `pubspec.yaml` (alphabetical-ish, near other feature deps):

```yaml
  audioplayers: ^6.1.0
```

- [ ] **Step 2: Register the assets folder**

In `pubspec.yaml`, extend the existing `assets:` list (currently
`assets/images/` and `assets/config/`):

```yaml
  assets:
    - assets/images/
    - assets/config/
    - assets/sounds/
```

- [ ] **Step 3: Create placeholder audio files (Python, no ffmpeg needed)**

Generate two short, soft sine-tone WAVs with the Python stdlib:

```bash
python3 - <<'PY'
import wave, struct, math, os
os.makedirs('assets/sounds', exist_ok=True)
def tone(path, freq, secs=0.18, rate=44100, amp=0.25):
    n = int(rate * secs)
    with wave.open(path, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        frames = bytearray()
        for i in range(n):
            # simple attack/decay envelope so it's a soft blip, not a click
            env = min(1.0, i / (0.02 * rate)) * min(1.0, (n - i) / (0.05 * rate))
            s = amp * env * math.sin(2 * math.pi * freq * i / rate)
            frames += struct.pack('<h', int(s * 32767))
        w.writeframes(bytes(frames))
tone('assets/sounds/chat_send.wav', 660.0)      # brighter, outgoing
tone('assets/sounds/chat_receive.wav', 520.0)   # softer, incoming
print('wrote placeholders')
PY
```

Confirm both files exist and are non-empty (`ls -l assets/sounds/`). These are
deliberately plain placeholders — real warm audio comes later (see README). The
rest of the plan (service, toggle, wiring, tests with the fake) does not depend
on these files' content, so if generation somehow fails, still proceed and note
it as DONE_WITH_CONCERNS.

- [ ] **Step 4: Document the placeholder status**

Create `assets/sounds/README.md`:

```markdown
# Chat sounds

`chat_send.wav` and `chat_receive.wav` are **placeholder** sine tones.

Before launch they must be replaced with the professionally-designed, warm,
short (~150–250ms) send/receive sounds approved in cultural/clinical review
(see the chat delight spec §3.6 and §7). Keep the same filenames so no code
changes are needed to swap them (real files may be .wav or re-encoded MP3 —
if switching to .mp3, update the two paths in
`lib/core/ui/feedback/sound_service.dart`).
```

- [ ] **Step 5: Resolve dependencies**

Run: `flutter pub get`
Expected: resolves with `audioplayers` added; no errors.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock assets/sounds/
git commit -m "chore(chat-sounds): add audioplayers + placeholder sound assets"
```

---

### Task 2: SoundService interface + fake (injectable, testable)

**Files:**
- Create: `lib/core/ui/feedback/sound_service.dart`
- Test: `test/core/ui/sound_service_test.dart`

**Interfaces:**
- Produces:
  - `enum ChatSound { send, receive }`
  - `abstract class SoundService { Future<void> preload(); void play(ChatSound sound); }`
  - `class FakeSoundService implements SoundService { final List<ChatSound> played = []; int preloadCount = 0; }`
  - `final soundServiceProvider = Provider<SoundService>(...)` — real impl added in Task 3; for now this task only needs the interface + fake. (Task 3 replaces the provider body.)

**Context:** This task defines the contract and the fake so later wiring tasks
can be tested without audio. The real `audioplayers`-backed impl is a separate
task so the interface can be reviewed in isolation.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/sound_service_test.dart
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FakeSoundService records played sounds and preloads', () async {
    final s = FakeSoundService();
    await s.preload();
    s.play(ChatSound.send);
    s.play(ChatSound.receive);
    s.play(ChatSound.send);
    expect(s.preloadCount, 1);
    expect(s.played, [ChatSound.send, ChatSound.receive, ChatSound.send]);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/sound_service_test.dart`
Expected: FAIL — `sound_service.dart` / symbols not found.

- [ ] **Step 3: Write minimal implementation (interface + fake only)**

```dart
// lib/core/ui/feedback/sound_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chat UI sounds. Content-blind — these are event sounds, not tied to
/// message content.
enum ChatSound { send, receive }

/// Injectable one-shot sound player. Universal (any feature can use it); chat
/// is the first consumer. Playback failures are silent no-ops and never block
/// the caller.
abstract class SoundService {
  /// Preloads the clips so the first play has no cold-start latency.
  Future<void> preload();

  /// Plays [sound] if audio is available. Never throws.
  void play(ChatSound sound);
}

/// Test double: records calls, plays nothing.
class FakeSoundService implements SoundService {
  final List<ChatSound> played = [];
  int preloadCount = 0;

  @override
  Future<void> preload() async => preloadCount++;

  @override
  void play(ChatSound sound) => played.add(sound);
}

/// Overridden in app startup / by the real impl (Task 3). Throwing default so a
/// missing override is caught in tests rather than silently no-op'ing.
final soundServiceProvider = Provider<SoundService>((ref) {
  throw UnimplementedError('soundServiceProvider must be overridden');
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/sound_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/feedback/sound_service.dart test/core/ui/sound_service_test.dart
git commit -m "feat(core/ui): SoundService interface + fake"
```

---

### Task 3: Real audioplayers-backed SoundService + provider wiring

**Files:**
- Modify: `lib/core/ui/feedback/sound_service.dart` (add `AudioPlayerSoundService`, real provider)
- Modify: `lib/main.dart` (preload at startup)
- Test: `test/core/ui/sound_service_test.dart` (add a construction/no-throw test)

**Interfaces:**
- Consumes: `audioplayers` (Task 1), `ChatSound`/`SoundService` (Task 2).
- Produces:
  - `class AudioPlayerSoundService implements SoundService` — one `AudioPlayer`
    per sound, `AudioContextConfig(... )` set so iOS uses the ambient category
    (silent switch mutes), preloaded from `AssetSource`.
  - `soundServiceProvider` now returns `AudioPlayerSoundService`.

**Context:** `audioplayers` v6 sets the audio context globally via
`AudioPlayer.global.setAudioContext(...)`. The ambient/mixWithOthers config on
iOS makes the hardware silent switch and DND mute the sound — exactly the
required behavior. Each `ChatSound` gets its own preloaded `AudioPlayer` in
`ReleaseMode.stop` so rapid sends don't clip each other.

- [ ] **Step 1: Write the failing test**

```dart
// add to test/core/ui/sound_service_test.dart
import 'package:audioplayers/audioplayers.dart'; // ensure resolves

// ... existing test above ...

  test('AudioPlayerSoundService constructs and play() never throws '
      'even before preload', () {
    final s = AudioPlayerSoundService();
    // Must not throw synchronously in a headless test (no audio device).
    expect(() => s.play(ChatSound.send), returnsNormally);
    s.dispose();
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/sound_service_test.dart`
Expected: FAIL — `AudioPlayerSoundService` not defined.

- [ ] **Step 3: Implement the real service**

Add to `lib/core/ui/feedback/sound_service.dart` (top of file, alongside the
existing riverpod import):

```dart
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

// ... keep existing enum, abstract class, FakeSoundService ...

/// Real player. One preloaded AudioPlayer per sound. iOS uses the ambient audio
/// context so the hardware silent switch / DND mute chat sounds automatically.
class AudioPlayerSoundService implements SoundService {
  AudioPlayerSoundService();

  // AssetSource paths are relative to the `assets/` prefix already declared in
  // pubspec, so they start at `sounds/…`.
  static const _assets = {
    ChatSound.send: 'sounds/chat_send.wav',
    ChatSound.receive: 'sounds/chat_receive.wav',
  };

  final Map<ChatSound, AudioPlayer> _players = {};
  bool _ready = false;
  bool _preloading = false;

  @override
  Future<void> preload() async {
    if (_ready || _preloading) return;
    _preloading = true;
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          // Ambient = respect the silent switch, don't interrupt other audio.
          route: AudioContextConfigRoute.system,
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
      for (final entry in _assets.entries) {
        final player = AudioPlayer()
          ..setReleaseMode(ReleaseMode.stop)
          ..setPlayerMode(PlayerMode.lowLatency);
        await player.setSource(AssetSource(entry.value));
        _players[entry.key] = player;
      }
      _ready = true;
    } catch (e) {
      // Audio unavailable (e.g. test host, missing assets) — stay a no-op.
      _ready = false;
      if (kDebugMode) debugPrint('[sound] preload failed: silent no-op');
    } finally {
      _preloading = false;
    }
  }

  @override
  void play(ChatSound sound) {
    // Lazily preload if startup didn't (so the feature works even without an
    // explicit preload); the first play may be silent while it warms up, but
    // subsequent plays are ready. Never awaits, never throws into the caller.
    if (!_ready) {
      unawaited(preload());
      return;
    }
    final player = _players[sound];
    if (player == null) return;
    player.seek(Duration.zero).then((_) => player.resume()).catchError((_) {});
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }
}
```

Replace the throwing `soundServiceProvider` body with:

```dart
final soundServiceProvider = Provider<SoundService>((ref) {
  final service = AudioPlayerSoundService();
  ref.onDispose(service.dispose);
  return service;
});
```

**Note for the implementer:** if `AudioContextConfig`'s field names differ in
the resolved `audioplayers` version, use the equivalent that selects the iOS
ambient category + mixWithOthers (read the package's `AudioContextConfig` doc).
The required behavior is: silent switch mutes; do not interrupt other audio. If
you must adjust the config shape to compile, keep that behavior and note the
exact API you used in your report.

- [ ] **Step 4: Preload at startup**

`lib/main.dart` uses `runApp(ProviderScope(overrides: [...], child: ...))` — a
declarative scope, NOT an explicit `ProviderContainer` you can `.read()` in
`main()`. So trigger the preload from inside the widget tree, from the first
widget that has a `ref`.

Read `lib/main.dart` to find the root app widget (the `child:` of
`ProviderScope`). If it's a `ConsumerStatefulWidget`, add to its `initState`:

```dart
// fire-and-forget preload so first send/receive has no cold-start latency
WidgetsBinding.instance.addPostFrameCallback((_) {
  ref.read(soundServiceProvider).preload();
});
```

If the root is a plain `StatelessWidget`/`ConsumerWidget`, the smallest safe
change is to wrap the existing home/first route in a tiny `Consumer` that calls
`preload()` once (guard with a top-level `bool` so it runs a single time), OR
convert the root to `ConsumerStatefulWidget`. Prefer the least invasive option
that runs `preload()` exactly once after first frame. **This is shared startup
code (main.dart) — make the minimal change, do not restructure app init.** Note
exactly what you changed in your report. Add
`import 'package:attune/core/ui/feedback/sound_service.dart';` and, if needed,
`import 'dart:async';` for `unawaited`.

If you cannot make a clean minimal change to `main.dart`, report
DONE_WITH_CONCERNS and skip the startup preload: `play()` lazily self-preloads
(Step 3's implementation), so the feature still works — the startup preload only
removes the first-play warm-up latency. Flag it so a follow-up wires it, but do
not force an invasive main.dart change to get it.

- [ ] **Step 5: Run tests**

Run: `flutter test test/core/ui/sound_service_test.dart`
Expected: PASS (fake test + the new no-throw construction test).
Run: `flutter analyze lib/core/ui/feedback/`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/core/ui/feedback/sound_service.dart lib/main.dart test/core/ui/sound_service_test.dart
git commit -m "feat(core/ui): audioplayers-backed SoundService (ambient, preloaded)"
```

---

### Task 4: Message-sounds preference (default on, persisted)

**Files:**
- Create: `lib/features/settings/data/sound_preference.dart`
- Test: `test/features/settings/sound_preference_test.dart`

**Interfaces:**
- Consumes: `sharedPreferencesProvider` from
  `lib/core/providers/shared_prefs_provider.dart` (a
  `Provider<SharedPreferences>`).
- Produces:
  - `class SoundPreferenceNotifier extends StateNotifier<bool>` — reads/writes
    the `chat_message_sounds_enabled` key, default `true`.
  - `final messageSoundsEnabledProvider = StateNotifierProvider<SoundPreferenceNotifier, bool>(...)`.

**Context:** Mirrors the existing `LocaleNotifier` StateNotifier + prefs pattern
in `lib/core/providers/locale_provider.dart`. Default is `true` (sounds on).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/settings/sound_preference_test.dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to enabled, persists a toggle', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    expect(container.read(messageSoundsEnabledProvider), isTrue);

    await container.read(messageSoundsEnabledProvider.notifier).setEnabled(false);
    expect(container.read(messageSoundsEnabledProvider), isFalse);
    expect(prefs.getBool('chat_message_sounds_enabled'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/sound_preference_test.dart`
Expected: FAIL — `sound_preference.dart` / provider not found.

- [ ] **Step 3: Implement**

```dart
// lib/features/settings/data/sound_preference.dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kMessageSoundsKey = 'chat_message_sounds_enabled';

/// Persists the "Message sounds" toggle. Default on (Spec §3.6).
class SoundPreferenceNotifier extends StateNotifier<bool> {
  SoundPreferenceNotifier(this._prefs)
    : super(_prefs.getBool(_kMessageSoundsKey) ?? true);

  final SharedPreferences _prefs;

  Future<void> setEnabled(bool value) async {
    state = value;
    await _prefs.setBool(_kMessageSoundsKey, value);
  }

  Future<void> toggle() => setEnabled(!state);
}

final messageSoundsEnabledProvider =
    StateNotifierProvider<SoundPreferenceNotifier, bool>((ref) {
  return SoundPreferenceNotifier(ref.watch(sharedPreferencesProvider));
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/settings/sound_preference_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/data/sound_preference.dart test/features/settings/sound_preference_test.dart
git commit -m "feat(settings): persisted message-sounds preference (default on)"
```

---

### Task 5: Play the send sound (gated by the toggle)

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_send`, ~line 121, beside the existing send haptic)
- Test: `test/features/chat/send_sound_test.dart`

**Interfaces:**
- Consumes: `soundServiceProvider` + `FakeSoundService` (Tasks 2/3),
  `messageSoundsEnabledProvider` (Task 4).

**Context:** In `_send()`, right where the send haptic fires
(`ref.read(hapticsProvider).light();`), also play the send sound IF the toggle
is on. One send → one sound. The empty-text guard already above the haptic means
no sound on empty input.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/send_sound_test.dart
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('sending plays exactly one send sound when enabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fakeSound = FakeSoundService();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        soundServiceProvider.overrideWithValue(fakeSound),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ChatScreen(conversation: convo)),
    ));
    await tester.pump(const Duration(milliseconds: 30));

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 30));

    expect(fakeSound.played, [ChatSound.send]);

    // teardown: unmount before dispose (Riverpod timer flake pattern)
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('sending plays no sound when the toggle is off', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'chat_message_sounds_enabled': false});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fakeSound = FakeSoundService();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        soundServiceProvider.overrideWithValue(fakeSound),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ChatScreen(conversation: convo)),
    ));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 30));

    expect(fakeSound.played, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/send_sound_test.dart`
Expected: FAIL — no sound played yet.

- [ ] **Step 3: Implement — play the send sound**

In `chat_screen.dart`, add imports:

```dart
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
```

In `_send()`, right after the existing send haptic line, add:

```dart
if (ref.read(messageSoundsEnabledProvider)) {
  ref.read(soundServiceProvider).play(ChatSound.send);
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/send_sound_test.dart`
Expected: PASS (both).
Run: `flutter test test/features/chat/send_feedback_test.dart`
Expected: PASS (haptic test unaffected).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/send_sound_test.dart
git commit -m "feat(chat): play send sound (gated by message-sounds toggle)"
```

---

### Task 6: Play the receive sound (reuses the guarded receive path)

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`_maybeReceiveHaptic`, ~line 335-349)
- Test: `test/features/chat/receive_sound_test.dart`

**Interfaces:**
- Consumes: `soundServiceProvider` (Tasks 2/3), `messageSoundsEnabledProvider` (Task 4).

**Context:** `_maybeReceiveHaptic()` already computes exactly when to signal a
genuinely-new partner message while the view is active (own-message excluded,
first-load excluded, backgrounded excluded). Add the sound at the SAME point the
haptic fires so it inherits all that gating and the no-double-fire guarantee.
Rename is optional; keep the method name to minimize churn, but the sound plays
beside `ref.read(hapticsProvider).selection();`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/receive_sound_test.dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_test_harness.dart';

void main() {
  test('a new partner message while viewing plays one receive sound', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fakeSound = FakeSoundService();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        soundServiceProvider.overrideWithValue(fakeSound),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.setViewActive(true);

    repo.seedIncoming(
      id: 'p1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hey',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(fakeSound.played, [ChatSound.receive]);
  });

  test('no receive sound while backgrounded', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fakeSound = FakeSoundService();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        soundServiceProvider.overrideWithValue(fakeSound),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // NOT setViewActive(true) → backgrounded.

    repo.seedIncoming(
      id: 'p1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hey',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(fakeSound.played, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/receive_sound_test.dart`
Expected: FAIL — no receive sound played.

- [ ] **Step 3: Implement — play beside the receive haptic**

In `chat_state.dart` add import:

```dart
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
```

In `_maybeReceiveHaptic`, at the point where it currently does
`ref.read(hapticsProvider).selection();` (inside the `if (isNew && _isViewActive)`
block), add the sound beside it:

```dart
if (isNew && _isViewActive) {
  ref.read(hapticsProvider).selection();
  if (ref.read(messageSoundsEnabledProvider)) {
    ref.read(soundServiceProvider).play(ChatSound.receive);
  }
}
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/receive_sound_test.dart`
Expected: PASS (both).
Run: `flutter test test/features/chat/receive_haptic_test.dart`
Expected: PASS (haptic tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/state/chat_state.dart test/features/chat/receive_sound_test.dart
git commit -m "feat(chat): play receive sound on new partner message while viewing"
```

---

### Task 7: "Message sounds" toggle in settings

**Files:**
- Modify: `lib/features/settings/screens/settings_screen.dart`
- Test: `test/features/settings/sound_toggle_widget_test.dart`

**Interfaces:**
- Consumes: `messageSoundsEnabledProvider` (Task 4).

**Context:** Add a `SwitchListTile` row to the settings screen bound to
`messageSoundsEnabledProvider`. `SettingsScreen` is a `StatelessWidget` at
`settings_screen.dart:91` and **requires a `currentUserId` constructor arg**
(`final String currentUserId;`). To read the provider, either wrap just the new
row in a `Consumer` (least invasive — no signature change) or convert the whole
screen to `ConsumerWidget`. Prefer the `Consumer`-wrapped row to keep the change
surgical. Follow the screen's existing row styling. The widget test must
construct `SettingsScreen(currentUserId: 'test-user')`.

- [ ] **Step 1: Read the screen and write the failing test**

First read `lib/features/settings/screens/settings_screen.dart` to match its
row style and confirm how to obtain `ref`.

```dart
// test/features/settings/sound_toggle_widget_test.dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('toggling the Message sounds switch flips the preference',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: SettingsScreen(currentUserId: 'test-user'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(container.read(messageSoundsEnabledProvider), isTrue);

    await tester.tap(find.byKey(const ValueKey('message_sounds_switch')));
    await tester.pumpAndSettle();

    expect(container.read(messageSoundsEnabledProvider), isFalse);
  });
}
```

**Note:** the settings screen may render sections that hit providers/services
not overridden here. If `pumpAndSettle` throws because an unrelated section
requires a provider, the minimal fix is to `find` and tap the switch after a
bounded `pump` rather than `pumpAndSettle`, or override the specific failing
provider. Read the screen first and keep the test focused on the switch row.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/sound_toggle_widget_test.dart`
Expected: FAIL — no such switch.

- [ ] **Step 3: Implement — add the toggle row**

Keep `SettingsScreen` a `StatelessWidget` (it takes `currentUserId`); wrap just
the new row in a `Consumer` so no signature/type change is needed. Add this
where other settings rows are listed, styled to match the screen's existing
rows:

```dart
Consumer(
  builder: (context, ref, _) => SwitchListTile(
    key: const ValueKey('message_sounds_switch'),
    title: const Text('Message sounds'),
    subtitle: const Text('Play a sound when you send or receive a message'),
    secondary: const Icon(Icons.volume_up_outlined),
    value: ref.watch(messageSoundsEnabledProvider),
    onChanged: (_) =>
        ref.read(messageSoundsEnabledProvider.notifier).toggle(),
  ),
),
```

Add imports:
`import 'package:flutter_riverpod/flutter_riverpod.dart';` and
`import 'package:attune/features/settings/data/sound_preference.dart';`.
Match the surrounding widgets' spacing/section placement (read the file first).

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/settings/sound_toggle_widget_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/settings/`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/screens/settings_screen.dart test/features/settings/sound_toggle_widget_test.dart
git commit -m "feat(settings): Message sounds toggle row"
```

---

### Task 8: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (errors only gate)**

Run: `flutter analyze lib/ test/ 2>&1 | grep -E "error •|error -" || echo "no errors"`
Expected: `no errors`.

- [ ] **Step 2: Sound + settings tests**

Run: `flutter test test/core/ui/ test/features/settings/`
Expected: all pass.

- [ ] **Step 3: Full chat suite (no regressions)**

Run: `flutter test test/features/chat/`
Expected: all pass (existing 50 + send_sound + receive_sound).

- [ ] **Step 4: Whole repo suite**

Run: `flutter test`
Expected: all pass.

- [ ] **Step 5: Commit checkpoint**

```bash
git commit --allow-empty -m "test: verify chat sounds full suite green (Plan 2)"
```

---

## Deferred to follow-on plans

- **Plan 3 — Typing presence** (Spec §3.3 typing).
- **Plan 4 — Rituals + full "Chat feel" settings group** (Spec §3.7, §4): the
  haptics on/off and expressive-moments toggles join the message-sounds toggle
  in a grouped "Chat feel" section.

## Production gate (carry forward)

- [ ] **Replace placeholder sounds** (`assets/sounds/chat_send.wav`,
  `chat_receive.wav`) with professionally-designed warm audio, approved in the
  Ghanaian/West-African cultural review and clinical tone review the Chat Spec
  requires (Spec §3.6, §7). Keep the same `.wav` filenames → no code change (if
  re-encoding to `.mp3`, update the two paths in `sound_service.dart`).

## Self-review notes

- **Spec coverage:** §3.6 send/receive sounds → Tasks 5,6; system + placeholder
  assets → Tasks 1–3; silent-switch respect → Task 3 (ambient context); default-
  on single toggle (§4 sound half) → Tasks 4,7. Pro-asset swap → gate item.
- **No double-fire:** receive sound reuses `_maybeReceiveHaptic`'s guarded path
  (Task 6); send sound sits after the empty-text guard (Task 5). Tested.
- **Backgrounded exclusion:** receive-sound test asserts no sound without
  `setViewActive(true)` (Task 6).
- **Injectable/testable:** `FakeSoundService` used in every wiring test; real
  service proven not to throw headless (Task 3).
- **Type consistency:** `ChatSound.{send,receive}`, `SoundService.{preload,play}`,
  `soundServiceProvider`, `FakeSoundService.played`, `messageSoundsEnabledProvider`,
  `SoundPreferenceNotifier.{setEnabled,toggle}` used consistently across tasks.
