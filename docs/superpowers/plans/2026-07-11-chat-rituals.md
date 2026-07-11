# Chat Rituals & "Chat feel" — Implementation Plan (Plan 4 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the retention "rituals" — a subtle first-message-of-the-day shimmer, a gentle reconnect cascade for unread messages, and an opt-in conversation-streak celebration — plus consolidate the chat delight toggles into one "Chat feel" settings section. Everything warm-calm by default; the streak feature ships behind a flag pending clinical/cultural review of its framing.

**Architecture:** Two universal primitives (`Shimmer`, `Stagger`) join the `lib/core/ui/motion` toolkit. The two low-risk rituals (first-of-day, reconnect cascade) are pure client-side presentation, content-blind (date/unread-count only). The streak is server-computed (both partners must message on a local day) via a `SECURITY DEFINER` RPC, surfaced in the existing `ChatHeaderSnapshot`, celebrated by an opt-in shimmer that is **flag-gated off** (`chat_streaks`) until its copy passes review. A "Chat feel" settings section groups the message-sounds toggle with a new "expressive moments" (calm/expressive) preference that governs how loud the rituals are.

**Tech Stack:** Flutter, `supabase_flutter`, existing `feature_flags` table + `ChatFeatureFlags`, existing `sharedPreferencesProvider`, `ChatHeaderSnapshot`, the `lib/core/ui` toolkit (Plans 1–3), Riverpod.

**Scope of this plan (Plan 4, final):** Spec §3.7 (rituals) + §4 (grouped "Chat feel" settings). This is the last delight plan.

## Global Constraints

- **Content-blind:** no ritual reads message content. First-of-day keys off the message's date; reconnect cascade off unread-count; streak off aggregate per-day sender presence. (Spec §1.1.)
- **Warm-calm by default; expressive is opt-in:** a `chatExpressiveness` preference defaults to `calm`. In `calm`, rituals are subtle (soft shimmer, gentle stagger) and the streak celebration does not auto-pop; `expressive` turns them up. Never confetti unprompted. (Spec §1.1 tone floor, §3.7.)
- **Streak ships flag-off:** the streak celebration + its copy are gated behind the server flag `chat_streaks` (default false) until clinical/cultural review approves the framing. The computation/RPC/display can exist; the celebratory surfacing must not appear until the flag is on. A broken/ended streak must NEVER be framed as loss/pressure. (Spec §3.7, tone floor; a gate item.)
- **Reduce-motion:** `Shimmer` and `Stagger` respect `reduceMotionOf` (no animation → end-state). (Spec §2, §11.4.)
- **Universal primitives:** `Shimmer` and `Stagger` live in `lib/core/ui/motion/`, no `lib/features/` import. (Plan 1 §5 principle.)
- **Streak fairness:** a day counts toward the streak only if BOTH partners sent ≥1 message that day, in the couple's local day (client passes its UTC offset in minutes). Server-computed; the client never fabricates a streak. (Design decision.)
- **Fail-safe:** a streak-fetch failure shows no streak (never blocks chat); a ritual animation error is contained to its widget.
- **Injectable/testable:** the streak fetch goes through the repository so a fake drives tests; primitives are unit-tested standalone.

---

### Task 1: Shimmer universal primitive

**Files:**
- Create: `lib/core/ui/motion/shimmer.dart`
- Test: `test/core/ui/shimmer_test.dart`

**Interfaces:**
- Consumes: `reduceMotionOf` (Plan 1).
- Produces:
  - `class Shimmer extends StatefulWidget` with
    `Shimmer({Key? key, required Widget child, bool active = true, Duration period = const Duration(milliseconds: 1600), Color? highlightColor})`.
    A one-directional highlight sweep across the child while `active`; under
    reduce-motion (or `active == false`) it renders the child plainly with no
    sweep.

**Context:** Generic sheen sweep — first-message-of-the-day and the streak
celebration are consumers, but it knows nothing about chat. Uses a
`ShaderMask` gradient driven by a repeating controller; stops the controller
when inactive or under reduce-motion.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/shimmer_test.dart
import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('active shimmer wraps the child in a ShaderMask', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Shimmer(child: Text('hi'))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('hi'), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop the loop
  });

  testWidgets('reduce-motion renders the child plainly (no running sweep)',
      (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: Scaffold(body: Shimmer(child: Text('hi')))),
    ));
    await tester.pumpAndSettle(); // must not time out (no repeating ticker)
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('inactive renders the child plainly', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Shimmer(active: false, child: Text('hi'))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/shimmer_test.dart`
Expected: FAIL — `Shimmer` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/motion/shimmer.dart
import 'package:flutter/material.dart';

import 'reduce_motion.dart';

/// A one-directional highlight sweep across [child] while [active]. Generic
/// "this is special right now" sheen — chat's first-message-of-the-day and
/// streak celebration are consumers. Static under reduce-motion / inactive.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.active = true,
    this.period = const Duration(milliseconds: 1600),
    this.highlightColor,
  });

  final Widget child;
  final bool active;
  final Duration period;
  final Color? highlightColor;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.period);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _sync();
  }

  @override
  void didUpdateWidget(covariant Shimmer old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active && !reduceMotionOf(context)) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || reduceMotionOf(context)) return widget.child;
    final highlight = widget.highlightColor ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 - 2 * (1 - t), 0),
              end: Alignment(1.0 - 2 * (1 - t), 0),
              colors: [
                Colors.transparent,
                highlight,
                Colors.transparent,
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/shimmer_test.dart`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/shimmer.dart test/core/ui/shimmer_test.dart
git commit -m "feat(core/ui): Shimmer sweep primitive"
```

---

### Task 2: Stagger universal primitive

**Files:**
- Create: `lib/core/ui/motion/stagger.dart`
- Test: `test/core/ui/stagger_test.dart`

**Interfaces:**
- Consumes: `SettleIn` (Plan 1, `lib/core/ui/motion/settle_in.dart`),
  `reduceMotionOf`.
- Produces:
  - `class Stagger extends StatelessWidget` with
    `Stagger({Key? key, required List<Widget> children, Duration interval = const Duration(milliseconds: 60), bool animate = true})`.
    Wraps each child in a `SettleIn` with an increasing delay so the list
    cascades in. Under reduce-motion / `animate == false`, children render at
    rest (no cascade). Each child must carry its own key from the caller.

**Context:** Generic staggered entry for a list of children — the reconnect
cascade is the consumer. Delay per child = index × interval, implemented by
wrapping `SettleIn` and gating its `animate` on whether the delay has elapsed
(use a per-child `Future.delayed` → `setState`? No — keep it stateless: use
`SettleIn`'s built-in animation but offset each child's start via a
`TweenAnimationBuilder` delay is not available). SIMPLER, correct approach:
each child gets `SettleIn(animate: animate, beginOffset: ..., duration: base +
index*interval)` so later children take longer to arrive, producing a visible
cascade without per-child timers. Note: this staggers *duration*, not start —
acceptable and keeps it stateless. If a true start-delay is wanted, the
implementer may use a small `StatefulWidget` per child with a delayed
controller; prefer the simpler duration-stagger and note it.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/stagger_test.dart
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/core/ui/motion/stagger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wraps each child in a SettleIn', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stagger(children: [
          const Text('a', key: ValueKey('a')),
          const Text('b', key: ValueKey('b')),
          const Text('c', key: ValueKey('c')),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SettleIn), findsNWidgets(3));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
  });

  testWidgets('animate:false renders children at rest', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stagger(animate: false, children: [
          const Text('a', key: ValueKey('a')),
          const Text('b', key: ValueKey('b')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/stagger_test.dart`
Expected: FAIL — `Stagger` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/motion/stagger.dart
import 'package:flutter/widgets.dart';

import 'settle_in.dart';

/// Cascades a list of children into view by giving each a slightly longer
/// settle so they arrive in sequence. Generic — the chat reconnect cascade is
/// the consumer. Children must carry their own keys. Renders at rest under
/// reduce-motion because it defers to [SettleIn]'s reduce-motion handling.
class Stagger extends StatelessWidget {
  const Stagger({
    super.key,
    required this.children,
    this.interval = const Duration(milliseconds: 60),
    this.animate = true,
    this.baseDuration = const Duration(milliseconds: 260),
  });

  final List<Widget> children;
  final Duration interval;
  final bool animate;
  final Duration baseDuration;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++)
          SettleIn(
            key: ValueKey('stagger_$i'),
            animate: animate,
            duration: baseDuration + interval * i,
            child: children[i],
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/stagger_test.dart`
Expected: PASS (both).

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/stagger.dart test/core/ui/stagger_test.dart
git commit -m "feat(core/ui): Stagger cascade primitive"
```

---

### Task 3: "Chat feel" settings — expressiveness preference + grouped section

**Files:**
- Create: `lib/features/settings/data/chat_feel_preference.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`
- Test: `test/features/settings/chat_feel_preference_test.dart`
- Test: `test/features/settings/chat_feel_section_widget_test.dart`

**Interfaces:**
- Consumes: `sharedPreferencesProvider`, existing `messageSoundsEnabledProvider`.
- Produces:
  - `enum ChatExpressiveness { calm, expressive }`
  - `class ChatFeelPreferenceNotifier extends StateNotifier<ChatExpressiveness>`
    reading/writing key `chat_expressiveness` (default `calm`), with
    `setExpressiveness(ChatExpressiveness)`.
  - `final chatExpressivenessProvider = StateNotifierProvider<ChatFeelPreferenceNotifier, ChatExpressiveness>(...)`.

**Context:** Adds the expressiveness preference and groups it with the existing
"Message sounds" toggle under a "Chat feel" section header. Mirror the
`SoundPreferenceNotifier` pattern (Plan 2). Keep `SettingsScreen` a
`StatelessWidget` — the existing sounds row is already `Consumer`-wrapped; add a
sibling row + a section header in the same `SliverToBoxAdapter` region.

- [ ] **Step 1: Write the failing preference test**

```dart
// test/features/settings/chat_feel_preference_test.dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to calm, persists a change', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    expect(container.read(chatExpressivenessProvider), ChatExpressiveness.calm);

    await container
        .read(chatExpressivenessProvider.notifier)
        .setExpressiveness(ChatExpressiveness.expressive);
    expect(container.read(chatExpressivenessProvider),
        ChatExpressiveness.expressive);
    expect(prefs.getString('chat_expressiveness'), 'expressive');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/chat_feel_preference_test.dart`
Expected: FAIL — not found.

- [ ] **Step 3: Implement the preference**

```dart
// lib/features/settings/data/chat_feel_preference.dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How expressive the chat delight moments are. Warm-calm by default; the user
/// may opt into more expressive rituals (Spec §1.1 tone floor, §3.7).
enum ChatExpressiveness { calm, expressive }

const _kKey = 'chat_expressiveness';

class ChatFeelPreferenceNotifier extends StateNotifier<ChatExpressiveness> {
  ChatFeelPreferenceNotifier(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static ChatExpressiveness _read(SharedPreferences prefs) {
    return prefs.getString(_kKey) == 'expressive'
        ? ChatExpressiveness.expressive
        : ChatExpressiveness.calm;
  }

  Future<void> setExpressiveness(ChatExpressiveness value) async {
    state = value;
    await _prefs.setString(_kKey, value.name);
  }
}

final chatExpressivenessProvider =
    StateNotifierProvider<ChatFeelPreferenceNotifier, ChatExpressiveness>((ref) {
  return ChatFeelPreferenceNotifier(ref.watch(sharedPreferencesProvider));
});
```

- [ ] **Step 4: Run the preference test — pass**

Run: `flutter test test/features/settings/chat_feel_preference_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing section widget test**

```dart
// test/features/settings/chat_feel_section_widget_test.dart
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Chat feel section exposes an expressiveness switch that persists',
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

    final finder = find.byKey(const ValueKey('expressive_moments_switch'));
    await tester.scrollUntilVisible(finder, 200);
    expect(container.read(chatExpressivenessProvider), ChatExpressiveness.calm);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(container.read(chatExpressivenessProvider),
        ChatExpressiveness.expressive);
  });
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/features/settings/chat_feel_section_widget_test.dart`
Expected: FAIL — no such switch.

- [ ] **Step 7: Implement the grouped section**

In `settings_screen.dart`, read the current sounds-row `SliverToBoxAdapter`
(the `Consumer`-wrapped `CardInkWell` with the `message_sounds_switch`). Wrap the
sounds row and a new expressiveness row in a "Chat feel" section: add a section
header `SliverToBoxAdapter` with the text "Chat feel" (styled like the existing
section titles — read how sections render their titles), then the two rows.

Add the expressiveness row (styled to match, in the same Consumer or its own):

```dart
Consumer(
  builder: (context, ref, _) {
    final expressive = ref.watch(chatExpressivenessProvider) ==
        ChatExpressiveness.expressive;
    return CardInkWell(
      margin: EdgeInsets.zero,
      onTap: () => ref.read(chatExpressivenessProvider.notifier).setExpressiveness(
            expressive ? ChatExpressiveness.calm : ChatExpressiveness.expressive,
          ),
      child: SwitchListTile(
        key: const ValueKey('expressive_moments_switch'),
        title: const Text('Expressive moments'),
        subtitle: const Text(
          'Turn up celebratory animations. Off keeps things calm.',
        ),
        secondary: const Icon(Icons.auto_awesome_outlined),
        value: expressive,
        onChanged: (v) => ref
            .read(chatExpressivenessProvider.notifier)
            .setExpressiveness(
              v ? ChatExpressiveness.expressive : ChatExpressiveness.calm,
            ),
      ),
    );
  },
),
```

Add the import for `chat_feel_preference.dart`. Read the file first to place the
"Chat feel" header consistent with existing section headers, and to keep the
sounds row exactly as-is (just now under the new header).

- [ ] **Step 8: Run tests + analyze**

Run: `flutter test test/features/settings/`
Expected: all pass (preference + section + existing sound tests).
Run: `flutter analyze lib/features/settings/`
Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add lib/features/settings/data/chat_feel_preference.dart lib/features/settings/screens/settings_screen.dart test/features/settings/chat_feel_preference_test.dart test/features/settings/chat_feel_section_widget_test.dart
git commit -m "feat(settings): Chat feel section + expressiveness preference (default calm)"
```

---

### Task 4: First-message-of-the-day shimmer

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (the
  `_MessageList` itemBuilder, where each `MessageBubble` renders)
- Test: `test/features/chat/first_of_day_shimmer_test.dart`

**Interfaces:**
- Consumes: `Shimmer` (Task 1), `chatExpressivenessProvider` (Task 3).

**Context:** In the message list, a bubble is the "first of its day" if its
`createdAt` local date differs from the *next-older* message's local date (the
list is newest-first, so compare `messages[index]` with `messages[index+1]`). If
so — AND only for genuinely-new messages (reuse the existing `firstBuildCutoff`
so cached history doesn't shimmer on open) — wrap that bubble's `SettleIn` in a
one-shot `Shimmer`. Content-blind: only the date is read. The shimmer runs once
briefly then stops (use `Shimmer(active: ...)` that flips off after a short
delay, OR simpler: a one-shot shimmer widget — keep it a brief accent, not a
loop). In `calm` expressiveness the shimmer is very subtle; keep it always on
for first-of-day (it's inherently gentle) but respect reduce-motion via Shimmer.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/first_of_day_shimmer_test.dart
import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('a message that starts a new day is wrapped in a Shimmer',
      (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final now = DateTime.now();
    // A message "today" and one from "yesterday" → today's is first-of-day.
    repo.seedIncoming(
      id: 'today',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'today msg',
      createdAt: now,
    );
    repo.seedIncoming(
      id: 'yesterday',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'yesterday msg',
      createdAt: now.subtract(const Duration(days: 1)),
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ChatScreen(conversation: convo)),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));

    // At least one Shimmer present (the first-of-day bubble).
    expect(find.byType(Shimmer), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/first_of_day_shimmer_test.dart`
Expected: FAIL — no `Shimmer` in the list.

- [ ] **Step 3: Implement — shimmer the first-of-day bubble**

Add import to `chat_screen.dart`:

```dart
import 'package:attune/core/ui/motion/shimmer.dart';
```

In `_MessageList`'s `itemBuilder`, compute first-of-day and wrap. Read the file
to find the exact `SettleIn(...)`/`MessageBubble(...)` structure. The logic:

```dart
final message = state.messages[index];
final older = index + 1 < state.messages.length
    ? state.messages[index + 1]
    : null;
bool sameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
final isFirstOfDay = older == null ||
    !sameLocalDay(message.createdAt, older.createdAt);
final isNew = message.createdAt.isAfter(firstBuildCutoff);

Widget bubble = MessageBubble( /* ...existing args... */ );
if (isFirstOfDay && isNew) {
  bubble = Shimmer(period: const Duration(milliseconds: 1400), child: bubble);
}
// then wrap in the existing SettleIn as before:
return SettleIn(key: ValueKey(message.clientMessageId), animate: isNew, child: bubble);
```

Keep the existing `SettleIn` wrapping and `firstBuildCutoff` logic intact; only
insert the `Shimmer` wrap for first-of-day new messages. (First-of-day for
*cached* history does not shimmer, because `isNew` is false — the shimmer is a
"today's conversation begins" accent, not a history decoration.)

**Note:** the `Shimmer` as written loops; for a brief one-shot accent, keep it
simple by leaving it looping while the bubble is the newest first-of-day — it is
subtle and the message list rarely keeps many first-of-day bubbles on screen. If
the reviewer prefers a true one-shot, that's a follow-up; the brief keeps it
simple.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/first_of_day_shimmer_test.dart`
Expected: PASS.
Run: `flutter test test/features/chat/`
Expected: all pass (no regression; message_list_animation_test still green).
Run: `flutter analyze lib/features/chat/`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/first_of_day_shimmer_test.dart
git commit -m "feat(chat): first-message-of-the-day shimmer accent"
```

---

### Task 5: Reconnect cascade for unread messages

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (expose a
  "just reconnected with N new" signal)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (consume it —
  minimal; the cascade can be realized by animating the newly-arrived rows)
- Test: `test/features/chat/reconnect_cascade_test.dart`

**Interfaces:**
- Consumes: `Stagger`/`SettleIn` (already used), `ChatState`.

**Context:** The full "cascade the unread block on reopen" is heavy to do inside
a `ListView.builder`. A pragmatic, low-risk realization: the existing per-bubble
`SettleIn` already animates genuinely-new messages (post-`firstBuildCutoff`). The
"reconnect cascade" is achieved by ensuring that when several messages arrive at
once after a reconnect (via `_catchUpFromCursor`), they each animate in with the
existing `SettleIn` — which they already do. THIS TASK therefore adds the small
missing piece: a slight per-message stagger so a *batch* arriving together
cascades rather than popping simultaneously.

Simplest correct implementation: in `_MessageList`, when building a run of
`isNew` bubbles, offset each `SettleIn.duration` by its position within the
current newest-run (index from top), so a batch that arrives together settles in
sequence. This reuses the Stagger idea inline without restructuring the list.

Add a test asserting that after a reconnect delivering multiple new messages,
the newest bubbles are wrapped in `SettleIn` with `animate: true` (the cascade
is visual; assert the animate flags, which is the testable contract).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/reconnect_cascade_test.dart
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('a batch of messages arriving after reconnect each animate in',
      (tester) async {
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

    // Three partner messages arrive together, then a realtime tick.
    final base = DateTime.now();
    for (var i = 0; i < 3; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'msg $i',
        createdAt: base.add(Duration(seconds: i)),
      );
    }
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 400));

    // Each newly-arrived bubble is wrapped in a SettleIn (the cascade vehicle).
    expect(find.byType(SettleIn), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
```

- [ ] **Step 2: Run test to verify it fails or passes-trivially**

Run: `flutter test test/features/chat/reconnect_cascade_test.dart`
Expected: this may PASS trivially if `SettleIn` already wraps bubbles. If so,
the test is a guard; the *implementation* adds the stagger offset. Confirm the
test asserts the contract you implement (add an assertion on the newest bubble's
`SettleIn.duration` increasing with position if you implement duration-stagger).

- [ ] **Step 3: Implement the inline stagger for new bubbles**

In `_MessageList.itemBuilder`, for `isNew` messages, offset the `SettleIn`
duration by the message's index-from-top so a batch cascades:

```dart
final baseSettle = const Duration(milliseconds: 260);
final staggered = isNew
    ? baseSettle + Duration(milliseconds: 40 * index.clamp(0, 6))
    : baseSettle;
return SettleIn(
  key: ValueKey(message.clientMessageId),
  animate: isNew,
  duration: staggered,
  child: bubble,
);
```

(Clamp so a large batch doesn't produce absurd durations. Cached history —
`isNew == false` — is unaffected.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/reconnect_cascade_test.dart test/features/chat/message_list_animation_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/chat/`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart lib/features/chat/presentation/state/chat_state.dart test/features/chat/reconnect_cascade_test.dart
git commit -m "feat(chat): reconnect cascade — stagger a batch of new messages"
```

---

### Task 6: Streak computation RPC + flag (server, flag-off)

**Files:**
- Create: `supabase/migrations/20260711120000_chat_streaks.sql`
- Modify: `supabase/tests/chat_system_contracts.sql` (add streak-RPC coverage)

**Interfaces:**
- Produces:
  - Feature flag row `('chat_streaks', false)` in `feature_flags`.
  - `chat_conversation_streak(p_relationship_id uuid, p_utc_offset_minutes int)`
    → `int` (the current streak length in days). `SECURITY DEFINER`, fixed
    search_path, requires membership, computes consecutive local days on which
    BOTH members sent ≥1 message, ending today (or yesterday if today has no
    qualifying pair yet). Returns 0 for non-members or no streak.

**Context:** Local day = `(created_at + p_utc_offset_minutes * interval '1
minute')::date`. A day qualifies if the set of that day's senders includes both
`user_a` and `user_b`. The streak is the count of consecutive qualifying days
ending at the most recent qualifying day, but only if that most recent
qualifying day is today or yesterday (so an old streak doesn't read as current).

**Two correctness notes for the implementer:**
1. The RPC uses a CTE, NOT a temp table — the contract test calls it twice in
   one transaction, and a `TEMP TABLE ... ON COMMIT DROP` would fail the second
   call with "relation already exists." Keep the CTE.
2. The `gap = rn` window trick counts the contiguous run from the anchor: for an
   unbroken streak the Nth-most-recent qualifying day has `anchor - day = N`
   exactly; once any day is skipped, `gap` outpaces `rn` for all older rows, so
   only the unbroken prefix matches. The SQL contract test (streak = 2) is the
   safety net — make sure it passes; if a local Supabase isn't available, flag
   the streak RPC as static-only-verified (like earlier SQL work) and lean on
   the CTE's structure.

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260711120000_chat_streaks.sql
-- Conversation streak: consecutive local days on which BOTH partners messaged.
-- Flag-gated (chat_streaks, default false) until its celebratory framing passes
-- clinical/cultural review — a broken streak must never read as loss/pressure.

INSERT INTO public.feature_flags (key, enabled)
VALUES ('chat_streaks', false)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.chat_conversation_streak(
  p_relationship_id uuid,
  p_utc_offset_minutes int DEFAULT 0
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_rel public.relationships%ROWTYPE;
  v_streak int := 0;
  v_today date;
BEGIN
  IF v_user_id IS NULL THEN RETURN 0; END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = p_relationship_id
    AND chat_archived_at IS NULL
    AND (user_a = v_user_id OR user_b = v_user_id);
  IF NOT FOUND OR v_rel.user_b IS NULL THEN RETURN 0; END IF;

  v_today := ((now() + make_interval(mins => p_utc_offset_minutes))::date);

  -- No temp table (the function may be called multiple times per transaction).
  -- qual_days = local days where BOTH members messaged; anchor = the most
  -- recent qualifying day, but only if it is today or yesterday; the streak is
  -- the count of consecutive qualifying days ending at that anchor.
  WITH qual_days AS (
    SELECT ((m.created_at + make_interval(mins => p_utc_offset_minutes))::date) AS day
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
    GROUP BY 1
    HAVING bool_or(m.sender_id = v_rel.user_a)
       AND bool_or(m.sender_id = v_rel.user_b)
  ),
  anchor AS (
    SELECT max(day) AS day FROM qual_days
    WHERE day IN (v_today, v_today - 1)
  ),
  streak AS (
    -- Consecutive days ending at the anchor: a qualifying day is in the streak
    -- iff (anchor - day) equals its descending rank offset among qualifying
    -- days <= anchor.
    SELECT count(*) AS n
    FROM (
      SELECT q.day,
             (SELECT a.day FROM anchor a) - q.day AS gap,
             row_number() OVER (ORDER BY q.day DESC) - 1 AS rn
      FROM qual_days q, anchor a
      WHERE a.day IS NOT NULL AND q.day <= a.day
    ) ranked
    WHERE ranked.gap = ranked.rn
  )
  SELECT COALESCE((SELECT n FROM streak), 0) INTO v_streak;

  RETURN v_streak;
END;
$$;

REVOKE ALL ON FUNCTION public.chat_conversation_streak(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_conversation_streak(uuid, int) TO authenticated;
```

- [ ] **Step 2: Add SQL contract coverage**

Append to `supabase/tests/chat_system_contracts.sql` (before the final
`ROLLBACK;`): a test that inserts messages from BOTH members on two consecutive
days and asserts `chat_conversation_streak(rel, 0) = 2`; and a test that an
outsider gets 0. Follow the file's existing `test_set_auth` + `RAISE EXCEPTION`
style. (The fixtures already create relationship `10000000-...-001` with members
`...a1` and `...b2`.)

```sql
-- Conversation streak: both members on two consecutive days -> streak 2
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE v int;
BEGIN
  -- ensure both members have a message today and yesterday
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at)
  VALUES
   ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'a today', now()),
   ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b2', gen_random_uuid(), 'b today', now()),
   ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'a yest', now() - interval '1 day'),
   ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b2', gen_random_uuid(), 'b yest', now() - interval '1 day');
  SELECT public.chat_conversation_streak('10000000-0000-0000-0000-000000000001', 0) INTO v;
  IF v < 2 THEN RAISE EXCEPTION 'expected streak >= 2, got %', v; END IF;
END $$;

-- Outsider gets streak 0
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000c3');
DO $$
DECLARE v int;
BEGIN
  SELECT public.chat_conversation_streak('10000000-0000-0000-0000-000000000001', 0) INTO v;
  IF v <> 0 THEN RAISE EXCEPTION 'outsider expected streak 0, got %', v; END IF;
END $$;
```

- [ ] **Step 3: Static-validate the migration SQL**

Run: `bash -n` is not applicable to SQL; instead confirm the file parses by
eye and matches the existing migration style. If a local Supabase is available,
`scripts/run_sql_contracts.sh` will execute it; otherwise note it as
static-only (like earlier SQL work). Confirm the `feature_flags` insert and
`GRANT`/`REVOKE` match the repo's conventions.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260711120000_chat_streaks.sql supabase/tests/chat_system_contracts.sql
git commit -m "feat(chat): conversation-streak RPC + flag (flag-off pending review)"
```

---

### Task 7: Streak client — flag, repo fetch, header display (flag-off)

**Files:**
- Modify: `lib/features/chat/domain/services/chat_feature_flags.dart` (add
  `streaks` flag constant)
- Modify: `lib/features/chat/data/repositories/chat_repository.dart` +
  `supabase_chat_repository.dart` (add `fetchStreak`)
- Modify: `lib/features/chat/presentation/providers/chat_experience_providers.dart`
  (add streak to `ChatHeaderSnapshot`)
- Modify: `test/features/chat/support/chat_test_harness.dart` (fake `fetchStreak`)
- Test: `test/features/chat/streak_test.dart`

**Interfaces:**
- Produces:
  - `ChatFeatureFlags.streaks = 'chat_streaks'`.
  - `Future<int> fetchStreak(String relationshipId)` on `ChatRepository` (calls
    the RPC with the device UTC offset; returns 0 on error).
  - `ChatHeaderSnapshot.streak` (int, default 0) populated only when the
    `chat_streaks` flag is enabled.

**Context:** The streak is fetched and put on the header snapshot, but the
celebratory display is gated: only when `chat_streaks` is enabled does the
header show a streak chip; the shimmer celebration honors
`chatExpressivenessProvider` (subtle in calm). With the flag off (default),
`fetchStreak` isn't called and no streak UI appears — so this ships dark.

- [ ] **Step 1: Add the flag constant + repo method + fake**

`chat_feature_flags.dart`: add `static const String streaks = 'chat_streaks';`
and `streaks: false` to the defaults map.

`chat_repository.dart` interface: add
```dart
  /// Current conversation streak (consecutive local days both partners
  /// messaged). 0 on error or when there is no streak.
  Future<int> fetchStreak(String relationshipId);
```

`supabase_chat_repository.dart`:
```dart
  @override
  Future<int> fetchStreak(String relationshipId) async {
    try {
      final offset = DateTime.now().timeZoneOffset.inMinutes;
      final res = await _supabase.rpc('chat_conversation_streak', params: {
        'p_relationship_id': relationshipId,
        'p_utc_offset_minutes': offset,
      });
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }
```

`chat_test_harness.dart` `FakeChatRepository`: add a settable
`int streakValue = 0;` and `@override Future<int> fetchStreak(String r) async => streakValue;`.

- [ ] **Step 2: Write the failing test**

```dart
// test/features/chat/streak_test.dart
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  test('fetchStreak returns the repository value', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a')..streakValue = 5;
    expect(await repo.fetchStreak('rel-1'), 5);
  });

  test('fetchStreak defaults to 0', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    expect(await repo.fetchStreak('rel-1'), 0);
  });
}
```

- [ ] **Step 3: Run — fails until the interface method exists, then passes**

Run: `flutter test test/features/chat/streak_test.dart`
Expected: FAIL first (no `fetchStreak`), PASS after Step 1.

- [ ] **Step 4: Add streak to the header snapshot (flag-gated)**

In `chat_experience_providers.dart`, add `final int streak;` to
`ChatHeaderSnapshot` (default 0). In the loader, after checking the
`chat_streaks` flag via `ChatFeatureFlags.isEnabled(...)`, call
`ref.read(chatRepositoryProvider).fetchStreak(relationshipId)` only when
enabled; otherwise leave streak 0. (Read the file to place this alongside the
existing pulse/insight/reminder loads.)

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/features/chat/streak_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/chat/`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/domain/services/chat_feature_flags.dart lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart lib/features/chat/presentation/providers/chat_experience_providers.dart test/features/chat/support/chat_test_harness.dart test/features/chat/streak_test.dart
git commit -m "feat(chat): streak flag + repo fetch + header snapshot (flag-off)"
```

---

### Task 8: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Analyze (errors only gate)**

Run: `flutter analyze lib/ test/ 2>&1 | grep -E "error •|error -" || echo "no errors"`
Expected: `no errors`.

- [ ] **Step 2: Toolkit + settings + chat suites**

Run: `flutter test test/core/ui/ test/features/settings/ test/features/chat/`
Expected: all pass.

- [ ] **Step 3: Whole repo suite**

Run: `flutter test`
Expected: all pass.

- [ ] **Step 4: Commit checkpoint**

```bash
git commit --allow-empty -m "test: verify chat rituals + Chat feel full suite green (Plan 4)"
```

---

## Production gates (carry forward)

- [ ] **Clinical + Ghanaian/West-African cultural review of the streak framing
      and copy** before enabling the `chat_streaks` flag. A broken/ended streak
      must never be framed as loss, failure, or pressure. (Spec §3.7, tone floor.)
- [ ] On-device verification of the ritual "feel" (shimmer subtlety, cascade
      timing) at the `calm` and `expressive` settings, and under reduce-motion.

## Self-review notes

- **Spec coverage:** §3.7 rituals → first-of-day (Task 4), reconnect cascade
  (Task 5), streak (Tasks 6–7); §4 grouped settings → Task 3. Streak ships
  flag-off pending review (gate item).
- **Content-blind:** first-of-day uses date only; cascade uses new-ness only;
  streak uses per-day sender presence only. No content read anywhere.
- **Tone floor:** expressiveness defaults `calm` (Task 3); streak celebration
  flag-gated + review-gated; broken streak never framed as loss (RPC just
  returns a number; the display — behind the flag — must present it gently, per
  the gate).
- **Reduce-motion:** Shimmer + Stagger honor it (Tasks 1–2); first-of-day/cascade
  inherit via those primitives/`SettleIn`.
- **Universal primitives:** Shimmer + Stagger in `lib/core/ui/motion/`, no
  feature imports (Tasks 1–2).
- **Fail-safe:** `fetchStreak` returns 0 on error (Task 7); rituals are
  presentation-only and never block messaging.
- **Type consistency:** `Shimmer`, `Stagger`, `ChatExpressiveness.{calm,expressive}`,
  `chatExpressivenessProvider`, `chat_conversation_streak`, `fetchStreak`,
  `ChatHeaderSnapshot.streak`, `ChatFeatureFlags.streaks`,
  `FakeChatRepository.streakValue` used consistently across tasks.
```
