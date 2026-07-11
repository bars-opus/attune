# Chat Typing Indicator — Implementation Plan (Plan 3 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a WhatsApp-style "partner is typing" indicator in chat — three breathing dots that appear while the partner composes and auto-clear when they stop or their message arrives — transported over ephemeral Realtime Broadcast (no database writes, partner-only, privacy-clean).

**Architecture:** Typing is an ephemeral signal sent as a Realtime Broadcast event on the chat's existing `chat:{relationshipId}` channel — it never touches Postgres and is only seen by the two partners on the channel. A universal `BreathingDots` primitive (`lib/core/ui/presence/`) renders the animation. A `TypingController` throttles outgoing "typing" events (~1 per 2s) while composing and auto-expires the incoming indicator (~5s after the last event, or immediately when a message arrives). No migration, no worker, no DB schema change.

**Tech Stack:** Flutter, `supabase_flutter ^2.1.0` Realtime Broadcast (`sendBroadcastMessage` / `onBroadcast` on `RealtimeChannel`), existing chat realtime channel, Riverpod.

**Scope of this plan (Plan 3):** Spec §3.3 typing indicator (the deferred half). **Deferred:** Plan 4 = rituals + the grouped "Chat feel" settings section.

## Global Constraints

- **Ephemeral only:** typing is a Realtime Broadcast event — never written to the database, never persisted, never in an outbox. (Design decision; privacy-clean.)
- **Partner-only:** the signal is scoped to the `chat:{relationshipId}` channel both partners already subscribe to; no third party can see it.
- **Content-blind:** the typing event carries only `{senderId, typing: bool}` — never draft text, never message content. (Spec §1.1.)
- **Throttled, not per-keystroke:** while composing, send at most one "typing: true" every ~2 seconds. (WhatsApp-style; avoids channel spam.)
- **Auto-expire:** the receiver hides the indicator ~5 seconds after the last "typing" event, and immediately when a message from that partner arrives. Never a stuck indicator.
- **Own events ignored:** a client never shows its own typing echo (filter on `senderId != me`).
- **Reduce-motion:** `BreathingDots` respects `reduceMotionOf` (static dots, no animation) — reuse the toolkit helper. (Spec §2, §11.4.)
- **Universal primitive, feature composition:** `BreathingDots` lives in `lib/core/ui/presence/` with no chat knowledge; the chat composes it. No `lib/features/` import inside `lib/core/ui/`. (Plan 1 §5 principle.)
- **Fail-safe:** a broadcast send/receive failure never blocks messaging; a missing/stale typing signal simply shows no indicator.
- **Injectable/testable:** typing send + receive go through the repository interface so a fake can drive tests without a live channel.

---

### Task 1: BreathingDots universal primitive

**Files:**
- Create: `lib/core/ui/presence/breathing_dots.dart`
- Test: `test/core/ui/breathing_dots_test.dart`

**Interfaces:**
- Consumes: `reduceMotionOf` from `lib/core/ui/motion/reduce_motion.dart` (Plan 1).
- Produces:
  - `class BreathingDots extends StatefulWidget` with
    `BreathingDots({Key? key, int count = 3, double size = 7, Color? color, Duration period = const Duration(milliseconds: 1200)})`.
    Three dots that pulse opacity in a staggered wave while mounted; under
    reduce-motion they render static at a mid opacity.

**Context:** Generic "someone is doing something" indicator — chat's typing view
is the first consumer, but it knows nothing about chat. Loops while mounted;
stops (disposes controller) when removed from the tree.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/breathing_dots_test.dart
import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the requested number of dots', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BreathingDots(count: 3)),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    // Each dot is an AnimatedBuilder-wrapped container; assert 3 dot widgets.
    expect(find.byType(BreathingDots), findsOneWidget);
    expect(
      find.byKey(const ValueKey('breathing_dot_0')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('breathing_dot_2')), findsOneWidget);
    // stop the loop so the test can settle
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduce-motion renders without a running animation ticker',
      (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: Scaffold(body: BreathingDots())),
    ));
    // With reduce-motion the dots are static; pumpAndSettle must not time out.
    await tester.pumpAndSettle();
    expect(find.byType(BreathingDots), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/breathing_dots_test.dart`
Expected: FAIL — `BreathingDots` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/presence/breathing_dots.dart
import 'package:flutter/material.dart';

import '../motion/reduce_motion.dart';

/// A row of dots that pulse in a staggered wave — a generic "someone is doing
/// something" indicator (chat typing is the first consumer). Loops while
/// mounted. Under OS reduce-motion the dots are static.
class BreathingDots extends StatefulWidget {
  const BreathingDots({
    super.key,
    this.count = 3,
    this.size = 7,
    this.color,
    this.period = const Duration(milliseconds: 1200),
  });

  final int count;
  final double size;
  final Color? color;
  final Duration period;

  @override
  State<BreathingDots> createState() => _BreathingDotsState();
}

class _BreathingDotsState extends State<BreathingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.period);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotionOf(context)) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _opacityFor(int index) {
    if (reduceMotionOf(context)) return 0.6;
    // Stagger each dot by a fraction of the period.
    final phase = (_ctrl.value + index / widget.count) % 1.0;
    // Triangle wave 0.3 -> 1.0 -> 0.3
    final wave = 1.0 - (phase - 0.5).abs() * 2;
    return 0.3 + 0.7 * wave;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.count, (i) {
            return Padding(
              key: ValueKey('breathing_dot_$i'),
              padding: EdgeInsets.symmetric(horizontal: widget.size * 0.25),
              child: Opacity(
                opacity: _opacityFor(i),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/breathing_dots_test.dart`
Expected: PASS (both).

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/presence/breathing_dots.dart test/core/ui/breathing_dots_test.dart
git commit -m "feat(core/ui): BreathingDots presence primitive"
```

---

### Task 2: Repository — typing broadcast send + receive on the shared channel

**Files:**
- Modify: `lib/features/chat/data/repositories/chat_repository.dart` (interface)
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart`
- Test: none in this task (the send/receive is exercised through the controller
  in Task 3 with a fake; a live-channel unit test would require a real socket).
  Note this in the report.

**Interfaces:**
- Produces (on `ChatRepository`):
  - `void sendTyping(String relationshipId, {required bool typing});`
  - `Stream<TypingEvent> watchTyping(String relationshipId);`
  - `class TypingEvent { final String senderId; final bool typing; const TypingEvent(this.senderId, this.typing); }`
    (define in `chat_repository.dart`).

**Context:** The chat already opens a channel `chat:{relationshipId}` inside
`watchConversationEvents`, recreating it per call and removing it on cancel. To
put typing broadcast on the SAME channel, refactor so the repository owns one
channel per relationship and both `watchConversationEvents` and `watchTyping`
attach to it. Typing uses Realtime Broadcast (`sendBroadcastMessage` /
`onBroadcast`), which never hits the DB.

The current `watchConversationEvents` creates `_channels[relationshipId]` and
returns a stream whose `onCancel` removes the channel. Change it so:
- a private `_channelFor(relationshipId)` lazily creates and subscribes the
  channel with BOTH the postgres_changes handlers AND an `onBroadcast(event:
  'typing')` handler that pushes to a per-relationship `TypingEvent`
  broadcast StreamController;
- `watchConversationEvents` and `watchTyping` both return streams derived from
  that one channel;
- the channel is torn down only when BOTH streams are done (or on `dispose()`),
  tracked with a simple ref count OR by keeping the channel alive for the
  relationship until `dispose()` (simpler — the controller cancels its
  subscriptions; the repo cleans channels in `dispose()`). Prefer the simpler
  "channel lives until dispose()" approach and note it.

- [ ] **Step 1: Add the interface**

In `chat_repository.dart`, add near the other `Stream`/typedef declarations:

```dart
/// An ephemeral typing signal from a relationship member. Never persisted.
class TypingEvent {
  const TypingEvent(this.senderId, this.typing);
  final String senderId;
  final bool typing;
}
```

Add to the `abstract class ChatRepository` methods:

```dart
  /// Broadcasts an ephemeral typing signal to the other member over Realtime
  /// (no DB write). Best-effort; failures never block messaging.
  void sendTyping(String relationshipId, {required bool typing});

  /// Ephemeral typing events from the partner on this relationship's channel.
  Stream<TypingEvent> watchTyping(String relationshipId);
```

- [ ] **Step 2: Refactor the Supabase repo to share one channel**

In `supabase_chat_repository.dart`, replace the `watchConversationEvents` method
and add channel-sharing plumbing. Add these fields near `_channels`:

```dart
  // Per-relationship invalidation + typing streams sharing one channel.
  final Map<String, StreamController<void>> _eventControllers = {};
  final Map<String, StreamController<TypingEvent>> _typingControllers = {};
```

Add a private channel factory and update the two watch methods:

```dart
  RealtimeChannel _channelFor(String relationshipId) {
    final existing = _channels[relationshipId];
    if (existing != null) return existing;

    final events = _eventControllers.putIfAbsent(
      relationshipId,
      () => StreamController<void>.broadcast(),
    );
    final typing = _typingControllers.putIfAbsent(
      relationshipId,
      () => StreamController<TypingEvent>.broadcast(),
    );

    final channel = _supabase
        .channel('chat:$relationshipId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'relationship_id',
            value: relationshipId,
          ),
          callback: (_) => events.add(null),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'relationships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: relationshipId,
          ),
          callback: (_) => events.add(null),
        )
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            // Supabase broadcast nests the sent data under a `payload` key on
            // the receiving side; be robust to both the nested and flat shape.
            final data = (payload['payload'] is Map)
                ? Map<String, dynamic>.from(payload['payload'] as Map)
                : payload;
            final senderId = data['senderId'];
            final isTyping = data['typing'];
            if (senderId is String && isTyping is bool) {
              typing.add(TypingEvent(senderId, isTyping));
            }
          },
        )
        .subscribe();

    _channels[relationshipId] = channel;
    return channel;
  }

  @override
  Stream<void> watchConversationEvents(String relationshipId) {
    _channelFor(relationshipId);
    return _eventControllers[relationshipId]!.stream;
  }

  @override
  Stream<TypingEvent> watchTyping(String relationshipId) {
    _channelFor(relationshipId);
    return _typingControllers[relationshipId]!.stream;
  }

  @override
  void sendTyping(String relationshipId, {required bool typing}) {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final channel = _channelFor(relationshipId);
    // Fire-and-forget; a broadcast failure must never block messaging.
    try {
      channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'senderId': user.id, 'typing': typing},
      );
    } catch (_) {
      // ignore — typing is best-effort
    }
  }
```

Update `dispose()` to also close the new controllers:

```dart
  @override
  Future<void> dispose() async {
    for (final channel in _channels.values) {
      await _supabase.removeChannel(channel);
    }
    _channels.clear();
    for (final c in _eventControllers.values) {
      await c.close();
    }
    _eventControllers.clear();
    for (final c in _typingControllers.values) {
      await c.close();
    }
    _typingControllers.clear();
    _signedUrlCache.clear();
  }
```

Remove the old `watchConversationEvents` body (the one that created a local
`StreamController` and set `controller.onCancel`). Ensure `dart:async` is
imported (it already is).

**API confirmed against `realtime_client 2.7.3` (resolved):**
`onBroadcast({required String event, required void Function(Map<String, dynamic> payload) callback})`
and `sendBroadcastMessage({required String event, required Map<String, dynamic> payload})`
(returns `Future<ChannelResponse>` — keep it fire-and-forget, do NOT await into
the caller). Use these exact signatures.

**The one thing the fake can't verify — payload nesting:** the receive-side
`onBroadcast` payload shape (nested `payload['payload']` vs flat) can only be
confirmed against a live channel, not the fake. The callback above handles both
shapes defensively, so the code is correct either way — but note in your report
that the real send→receive round-trip (whether the partner's `typing:true`
actually arrives) is a **manual on-device verification item**, like the sound
mute check in Plan 2. The fake-driven tests verify the controller/UI logic, not
the wire format.

- [ ] **Step 3: Update the fake repository (test harness)**

In `test/features/chat/support/chat_test_harness.dart`, add to
`FakeChatRepository`:

```dart
  final _typingController = StreamController<TypingEvent>.broadcast();
  final List<({bool typing})> sentTyping = [];

  @override
  void sendTyping(String relationshipId, {required bool typing}) {
    sentTyping.add((typing: typing));
  }

  @override
  Stream<TypingEvent> watchTyping(String relationshipId) =>
      _typingController.stream;

  /// Test helper: simulate the partner's typing event arriving.
  void emitPartnerTyping(String senderId, bool typing) {
    _typingController.add(TypingEvent(senderId, typing));
  }
```

Add `import` for `TypingEvent` (it's exported from `chat_repository.dart`,
already imported). Close `_typingController` in the fake's `dispose()`.

- [ ] **Step 4: Verify it compiles + existing realtime tests still pass**

Run: `flutter analyze lib/features/chat/data/ test/features/chat/support/`
Expected: no errors.
Run: `flutter test test/features/chat/chat_edge_cases_test.dart`
Expected: PASS — the realtime-merge / reconnect tests still work (they use
`watchConversationEvents`, whose observable behavior is unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart test/features/chat/support/chat_test_harness.dart
git commit -m "feat(chat): typing broadcast send/receive on the shared realtime channel"
```

---

### Task 3: TypingController — throttle out, auto-expire in

**Files:**
- Create: `lib/features/chat/presentation/state/typing_controller.dart`
- Test: `test/features/chat/typing_controller_test.dart`

**Interfaces:**
- Consumes: `chatRepositoryProvider` (from `chat_state.dart`), `TypingEvent`
  (Task 2), `currentUserProvider`.
- Produces:
  - `class TypingState { final bool partnerTyping; const TypingState(this.partnerTyping); }`
  - `class TypingController extends StateNotifier<TypingState>` with:
    - `void onComposingChanged(bool hasText)` — called by the composer; on the
      first "hasText" (or every ~2s while it stays true) broadcasts
      `typing: true` (throttled); when hasText goes false, broadcasts
      `typing: false` and cancels the throttle.
    - `void onSent()` — broadcasts `typing: false` immediately (message sent).
    - internally subscribes to `watchTyping`, ignores own `senderId`, sets
      `partnerTyping = true` on a partner `typing:true`, and starts/refreshes a
      ~5s expiry timer that flips it back to false; a partner `typing:false`
      clears it immediately.
  - `final typingControllerProvider = StateNotifierProvider.autoDispose.family<TypingController, TypingState, String>(...)` keyed by relationshipId.
- Constants: `static const _throttle = Duration(seconds: 2); static const _expiry = Duration(seconds: 5);`

**Context:** This is the brain of the feature. Throttling out prevents channel
spam; the expiry timer in guarantees the indicator never sticks. It reads the
current user to ignore its own echoed broadcast. It must also clear
`partnerTyping` when a message from the partner arrives — but rather than couple
to the message stream, the simplest correct approach is: the expiry timer
(5s) plus the explicit `typing:false` the sender emits on `onSent()` cover it.
(The sender always emits `typing:false` on send, so the receiver clears
promptly.)

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/typing_controller_test.dart
import 'package:attune/features/chat/presentation/state/typing_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  test('partner typing:true sets partnerTyping, auto-expires after 5s',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    // Reading the provider constructs the controller and starts its
    // watchTyping subscription.
    container.read(typingControllerProvider(relId));

    repo.emitPartnerTyping('partner', true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(typingControllerProvider(relId)).partnerTyping, isTrue);

    // after ~5s with no further events, it clears
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(
        container.read(typingControllerProvider(relId)).partnerTyping, isFalse);
  });

  test('own typing echo is ignored', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    container.read(typingControllerProvider(relId));

    repo.emitPartnerTyping(userId, true); // our own id
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
        container.read(typingControllerProvider(relId)).partnerTyping, isFalse);
  });

  test('partner typing:false clears immediately', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    container.read(typingControllerProvider(relId));

    repo.emitPartnerTyping('partner', true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.emitPartnerTyping('partner', false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
        container.read(typingControllerProvider(relId)).partnerTyping, isFalse);
  });

  test('composing throttles typing:true to at most one per 2s window',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final controller = container.read(typingControllerProvider(relId).notifier);

    controller.onComposingChanged(true);
    controller.onComposingChanged(true);
    controller.onComposingChanged(true);
    // Only one typing:true should have been sent in the immediate window.
    final trues = repo.sentTyping.where((e) => e.typing).length;
    expect(trues, 1);
  });

  test('onSent broadcasts typing:false', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final controller = container.read(typingControllerProvider(relId).notifier);

    controller.onComposingChanged(true);
    controller.onSent();
    expect(repo.sentTyping.last.typing, isFalse);
  });
}
```

(The timing tests use real `Future.delayed` waits — the ~5s expiry test waits
6s of wall-clock, which is acceptable for a handful of tests. No `fake_async`
needed.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/typing_controller_test.dart`
Expected: FAIL — `typing_controller.dart` not found.

- [ ] **Step 3: Implement**

```dart
// lib/features/chat/presentation/state/typing_controller.dart
import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TypingState {
  const TypingState(this.partnerTyping);
  final bool partnerTyping;
}

/// Owns the ephemeral typing signal for one relationship: throttles outgoing
/// "typing" broadcasts while composing, and auto-expires the incoming
/// partner-typing indicator so it never sticks.
class TypingController extends StateNotifier<TypingState> {
  TypingController(this.ref, this.relationshipId)
    : super(const TypingState(false)) {
    _repository = ref.read(chatRepositoryProvider);
    _myId = ref.read(currentUserProvider)?.id;
    _sub = _repository.watchTyping(relationshipId).listen(_onPartnerEvent);
  }

  final Ref ref;
  final String relationshipId;
  late final ChatRepository _repository;
  String? _myId;
  StreamSubscription<TypingEvent>? _sub;

  Timer? _throttle; // gates outgoing typing:true
  Timer? _expiry; // clears incoming partnerTyping
  bool _composing = false;

  static const _throttle_ = Duration(seconds: 2);
  static const _expiry_ = Duration(seconds: 5);

  void onComposingChanged(bool hasText) {
    if (hasText) {
      if (!_composing) {
        _composing = true;
        _sendTyping(true);
        _startThrottle();
      }
      // while composing, the throttle timer re-sends periodically
    } else {
      if (_composing) {
        _composing = false;
        _throttle?.cancel();
        _throttle = null;
        _sendTyping(false);
      }
    }
  }

  void onSent() {
    _composing = false;
    _throttle?.cancel();
    _throttle = null;
    _sendTyping(false);
  }

  void _startThrottle() {
    _throttle?.cancel();
    _throttle = Timer.periodic(_throttle_, (_) {
      if (_composing) {
        _sendTyping(true);
      } else {
        _throttle?.cancel();
        _throttle = null;
      }
    });
  }

  void _sendTyping(bool typing) {
    _repository.sendTyping(relationshipId, typing: typing);
  }

  void _onPartnerEvent(TypingEvent event) {
    if (event.senderId == _myId) return; // ignore own echo
    if (event.typing) {
      if (mounted) state = const TypingState(true);
      _expiry?.cancel();
      _expiry = Timer(_expiry_, () {
        if (mounted) state = const TypingState(false);
      });
    } else {
      _expiry?.cancel();
      _expiry = null;
      if (mounted) state = const TypingState(false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _throttle?.cancel();
    _expiry?.cancel();
    // Best-effort: tell the partner we stopped when the view goes away.
    if (_composing) _repository.sendTyping(relationshipId, typing: false);
    super.dispose();
  }
}

final typingControllerProvider = StateNotifierProvider.autoDispose
    .family<TypingController, TypingState, String>((ref, relationshipId) {
  return TypingController(ref, relationshipId);
});
```

**Naming note:** the constant names `_throttle_`/`_expiry_` are ugly to avoid a
clash with the `_throttle`/`_expiry` Timer fields. The implementer may rename to
`_throttleInterval` / `_expiryDuration` for clarity — keep the values (2s / 5s).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/typing_controller_test.dart`
Expected: PASS (all).
Run: `flutter analyze lib/features/chat/presentation/state/typing_controller.dart`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/state/typing_controller.dart test/features/chat/typing_controller_test.dart
git commit -m "feat(chat): TypingController (throttled out, auto-expiring in)"
```

---

### Task 4: Wire the composer to emit typing; show the indicator

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart`
- Test: `test/features/chat/typing_indicator_widget_test.dart`

**Interfaces:**
- Consumes: `typingControllerProvider` (Task 3), `BreathingDots` (Task 1).

**Context:** Two wirings in `chat_screen.dart`:
1. **Emit:** the composer's text controller already has a draft listener
   (`_onDraftChanged` → `_persistDraft`). In that same listener, call
   `ref.read(typingControllerProvider(relationshipId).notifier)
   .onComposingChanged(_controller.text.trim().isNotEmpty)`. And in `_send()`
   (or `_sendDraftText`), call `...onSent()` so typing clears on send.
2. **Show:** render a typing row (partner avatar-adjacent or just above the
   composer) with `BreathingDots` when
   `ref.watch(typingControllerProvider(relationshipId)).partnerTyping` is true.
   Place it between the message list and the composer, keyed
   `ValueKey('typing_indicator')`, so it appears/disappears without disturbing
   the list.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/chat/typing_indicator_widget_test.dart
import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('shows BreathingDots when the partner is typing', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ChatScreen(conversation: convo)),
    ));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byType(BreathingDots), findsNothing);

    repo.emitPartnerTyping('partner', true);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(BreathingDots), findsOneWidget);

    // teardown: unmount before dispose (Riverpod timer flake pattern)
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/typing_indicator_widget_test.dart`
Expected: FAIL — no `BreathingDots` shown.

- [ ] **Step 3: Implement — emit + show**

Add imports to `chat_screen.dart`:

```dart
import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:attune/features/chat/presentation/state/typing_controller.dart';
```

In the draft-change listener (`_onDraftChanged`), after the existing persist
call, add:

```dart
ref
    .read(typingControllerProvider(widget.conversation.relationshipId).notifier)
    .onComposingChanged(_controller.text.trim().isNotEmpty);
```

In `_send()` (right where the send already fires haptic/sound), add:

```dart
ref
    .read(typingControllerProvider(widget.conversation.relationshipId).notifier)
    .onSent();
```

In `build()`, between the `Expanded(_MessageList...)` and the composer, insert a
typing row:

```dart
Consumer(
  builder: (context, ref, _) {
    final typing = ref
        .watch(typingControllerProvider(conversation.relationshipId))
        .partnerTyping;
    if (!typing) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('typing_indicator'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Text(
            '${conversation.name} is typing',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          const BreathingDots(size: 6),
        ],
      ),
    );
  },
),
```

**Note:** `chat_screen.dart`'s state class must have access to `ref` in
`_onDraftChanged` — it's a `ConsumerState`, so `ref` is available. Read the file
to place the calls correctly (the composer only shows when `conversation.canSend`,
so typing emission naturally stops in read-only chats).

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/typing_indicator_widget_test.dart`
Expected: PASS.
Run: `flutter test test/features/chat/`
Expected: all pass (no regression in existing chat tests).
Run: `flutter analyze lib/features/chat/`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/typing_indicator_widget_test.dart
git commit -m "feat(chat): emit typing while composing; show partner typing indicator"
```

---

### Task 5: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (errors only gate)**

Run: `flutter analyze lib/ test/ 2>&1 | grep -E "error •|error -" || echo "no errors"`
Expected: `no errors`.

- [ ] **Step 2: Presence primitive + typing tests**

Run: `flutter test test/core/ui/ test/features/chat/typing_controller_test.dart test/features/chat/typing_indicator_widget_test.dart`
Expected: all pass.

- [ ] **Step 3: Full chat suite (no regressions)**

Run: `flutter test test/features/chat/`
Expected: all pass.

- [ ] **Step 4: Whole repo suite**

Run: `flutter test`
Expected: all pass.

- [ ] **Step 5: Commit checkpoint**

```bash
git commit --allow-empty -m "test: verify chat typing indicator full suite green (Plan 3)"
```

---

## Deferred to follow-on plans

- **Plan 4 — Rituals + "Chat feel" settings group** (Spec §3.7, §4).

## Self-review notes

- **Spec coverage:** §3.3 typing indicator → Tasks 1 (dots), 2 (transport), 3
  (timing brain), 4 (wiring). No migration/worker — ephemeral broadcast.
- **Ephemeral/partner-only/content-blind:** the broadcast payload is
  `{senderId, typing}` only (Task 2); never persisted; scoped to the shared
  channel. Verified by construction.
- **Throttle + auto-expire:** throttle ≤1 typing:true / 2s (Task 3 test);
  5s expiry timer clears a stuck indicator (Task 3 test); sender emits
  typing:false on send (Task 3 `onSent`, wired in Task 4).
- **Own-echo ignored:** `senderId == _myId` filter (Task 3 test).
- **Reduce-motion:** `BreathingDots` static under reduce-motion (Task 1 test).
- **Universal primitive:** `BreathingDots` in `lib/core/ui/presence/`, no chat
  import (Task 1).
- **Fail-safe:** `sendTyping` try/caught, best-effort (Task 2); a missing signal
  just shows nothing.
- **Type consistency:** `TypingEvent(senderId, typing)`, `sendTyping(rel, typing:)`,
  `watchTyping(rel)`, `TypingController.{onComposingChanged,onSent}`,
  `TypingState.partnerTyping`, `typingControllerProvider`, `BreathingDots`,
  `FakeChatRepository.{emitPartnerTyping,sentTyping}` used consistently across
  tasks.
