# Chat Motion Toolkit — Implementation Plan (Plan 1 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the universal `lib/core/ui/motion` primitives and wire them into
the chat so sending, receiving, ticks, scrolling, and empty/read-only states
feel warm & alive — content-blind, reduce-motion-aware, and reusable app-wide.

**Architecture:** Universal, chat-agnostic motion primitives live in
`lib/core/ui/`; the chat feature composes them. Each primitive honors OS
reduce-motion internally and animates once (keyed off events, never rebuilds).
No new dependencies, no backend changes, no data-model changes.

**Tech Stack:** Flutter, `flutter_animate` (already present), existing
`lib/app/theme/design_tokens.dart` tokens, `HapticFeedback` from `flutter/services`.

**Scope of this plan (Plan 1):** Spec §3.1 (sending visuals + haptic), §3.2
(receiving visuals + haptic), §3.3 partner-here glow (visual only — typing dots
deferred to Plan 3), §3.4 (scroll/pull/empty/read-only), §3.5 (accent), and the
universal primitives + tests in §5–6. **Deferred to later plans:** Plan 2 =
sound system (new audio package); Plan 3 = typing presence (backend touch);
Plan 4 = rituals (first-of-day, reconnect cascade, streaks).

## Global Constraints

- **Content-blind:** no primitive or animation may read message content or react
  to sentiment/analysis. Primitives take plain inputs only (child, event flag,
  color). (Spec §1.1, §2 rule 2.)
- **Reduce-motion:** every animated widget checks
  `MediaQuery.of(context).disableAnimations`; when true it renders the end-state
  with at most a short opacity fade. (Spec §2 guardrail.)
- **Play-once:** animations run on genuinely-new events, never on rebuild; use
  stable `ValueKey`s. (Spec §2 guardrail.)
- **No feature imports in `lib/core/ui/`:** primitives must not import anything
  from `lib/features/`. (Spec §5.1.)
- **Duration band:** 150–320ms; reuse `AnimationDurations` where possible.
  (Spec §2 rule 4.)
- **Never block input or the host action:** an animation error is contained to
  its widget and never blocks send/receive. (Spec §5.4.)
- **Motion curve names already in repo (`lib/app/theme/design_tokens.dart`):**
  `AnimationDurations.{instant,fastest,fast,medium,slow}`,
  `AnimationCurves.{standard,emphasized,decelerate,elastic,...}`. Extend, do not
  duplicate.

---

### Task 1: Shared spring + reduce-motion primitives (foundation)

**Files:**
- Create: `lib/core/ui/motion/motion_tokens.dart`
- Create: `lib/core/ui/motion/reduce_motion.dart`
- Test: `test/core/ui/reduce_motion_test.dart`

**Interfaces:**
- Produces:
  - `class AppSpring { static const SpringDescription settle; }` — the shared
    settle spring.
  - `const Duration kSettleDuration` (280ms), `const Curve kSettleCurve`
    (`Curves.easeOutBack`) for tween-based fallbacks.
  - `bool reduceMotionOf(BuildContext context)` → returns
    `MediaQuery.of(context).disableAnimations`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/reduce_motion_test.dart
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reduceMotionOf reflects MediaQuery.disableAnimations',
      (tester) async {
    late bool reduced;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            reduced = reduceMotionOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(reduced, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/reduce_motion_test.dart`
Expected: FAIL — `reduce_motion.dart` / `reduceMotionOf` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/motion/reduce_motion.dart
import 'package:flutter/widgets.dart';

/// True when the OS "reduce motion" accessibility setting is on. Every animated
/// primitive checks this and degrades to an instant end-state (Spec §2).
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.of(context).disableAnimations;
```

```dart
// lib/core/ui/motion/motion_tokens.dart
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Shared spring for the "settle" feel — a gentle overshoot that damps quickly.
/// One spring, reused everywhere, so the whole app moves with one personality.
class AppSpring {
  const AppSpring._();
  static const SpringDescription settle = SpringDescription(
    mass: 1,
    stiffness: 480,
    damping: 26,
  );
}

/// Tween fallbacks for widgets that use an implicit/explicit tween rather than a
/// physics simulation. Kept in the 150–320ms band (Spec §2 rule 4).
const Duration kSettleDuration = Duration(milliseconds: 280);
const Curve kSettleCurve = Curves.easeOutBack;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/reduce_motion_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/motion_tokens.dart lib/core/ui/motion/reduce_motion.dart test/core/ui/reduce_motion_test.dart
git commit -m "feat(core/ui): shared settle spring + reduce-motion helper"
```

---

### Task 2: SettleIn primitive (generalizes AnimatedEntry)

**Files:**
- Create: `lib/core/ui/motion/settle_in.dart`
- Test: `test/core/ui/settle_in_test.dart`
- Delete (after wiring, Task 7): `lib/features/chat/presentation/widgets/animated_entry.dart`

**Interfaces:**
- Consumes: `kSettleDuration`, `kSettleCurve`, `reduceMotionOf` (Task 1).
- Produces:
  - `class SettleIn extends StatefulWidget` with
    `SettleIn({Key? key, required Widget child, bool animate = true, Offset beginOffset = const Offset(0, 0.10), Duration duration = kSettleDuration, Curve curve = kSettleCurve})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/settle_in_test.dart
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('animate:false renders child immediately at full opacity',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SettleIn(animate: false, child: Text('hi')),
    ));
    expect(find.text('hi'), findsOneWidget);
    final opacity = tester.widget<FadeTransition>(
      find.byType(FadeTransition),
    );
    expect(opacity.opacity.value, 1.0);
  });

  testWidgets('reduce-motion renders end-state without a running animation',
      (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: SettleIn(child: Text('hi'))),
    ));
    await tester.pump(); // no need to settle; should already be at end-state
    final opacity = tester.widget<FadeTransition>(
      find.byType(FadeTransition),
    );
    expect(opacity.opacity.value, 1.0);
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('animate:true starts hidden and ends visible', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SettleIn(child: Text('hi')),
    ));
    final startOpacity =
        tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;
    expect(startOpacity, lessThan(1.0));
    await tester.pumpAndSettle();
    final endOpacity =
        tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;
    expect(endOpacity, 1.0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/settle_in_test.dart`
Expected: FAIL — `SettleIn` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/motion/settle_in.dart
import 'package:flutter/widgets.dart';

import 'motion_tokens.dart';
import 'reduce_motion.dart';

/// One-shot spring settle + fade entry. Universal: knows nothing about chat.
/// Pair with a stable ValueKey on the parent list item so it runs only when the
/// item is genuinely new (Spec §2 play-once).
class SettleIn extends StatefulWidget {
  const SettleIn({
    super.key,
    required this.child,
    this.animate = true,
    this.beginOffset = const Offset(0, 0.10),
    this.duration = kSettleDuration,
    this.curve = kSettleCurve,
  });

  final Widget child;
  final bool animate;
  final Offset beginOffset;
  final Duration duration;
  final Curve curve;

  @override
  State<SettleIn> createState() => _SettleInState();
}

class _SettleInState extends State<SettleIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: widget.beginOffset,
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: widget.curve));

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decide once, after context (and thus MediaQuery) is available.
    if (_started) return;
    _started = true;
    if (!widget.animate || reduceMotionOf(context)) {
      _ctrl.value = 1.0; // jump to end-state
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/settle_in_test.dart`
Expected: PASS (all three).

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/settle_in.dart test/core/ui/settle_in_test.dart
git commit -m "feat(core/ui): SettleIn spring entry primitive"
```

---

### Task 3: ScalePop primitive (press/confirm feedback)

**Files:**
- Create: `lib/core/ui/motion/scale_pop.dart`
- Test: `test/core/ui/scale_pop_test.dart`

**Interfaces:**
- Consumes: `reduceMotionOf` (Task 1).
- Produces:
  - `class ScalePop extends StatefulWidget` with
    `ScalePop({Key? key, required Widget child, required Object trigger, double magnitude = 0.12, Duration duration = const Duration(milliseconds: 180)})`.
    When `trigger` changes (via `didUpdateWidget`), it plays a quick scale
    down-and-back. `trigger` is any value whose change signals "pop now".

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/scale_pop_test.dart
import 'package:attune/core/ui/motion/scale_pop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pops (scale != 1.0 mid-animation) when trigger changes',
      (tester) async {
    var trigger = 0;
    late StateSetter setState;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, s) {
        setState = s;
        return ScalePop(trigger: trigger, child: const Icon(Icons.send));
      }),
    ));
    setState(() => trigger = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final t = tester.widget<ScaleTransition>(find.byType(ScaleTransition));
    expect(t.scale.value, isNot(1.0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value,
      1.0,
    );
  });

  testWidgets('reduce-motion never leaves scale off 1.0', (tester) async {
    var trigger = 0;
    late StateSetter setState;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: StatefulBuilder(builder: (context, s) {
          setState = s;
          return ScalePop(trigger: trigger, child: const Icon(Icons.send));
        }),
      ),
    ));
    setState(() => trigger = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value,
      1.0,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/scale_pop_test.dart`
Expected: FAIL — `ScalePop` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/motion/scale_pop.dart
import 'package:flutter/widgets.dart';

import 'reduce_motion.dart';

/// Quick scale down-and-back "pop" when [trigger] changes. Universal press/
/// confirm feedback for any button or icon.
class ScalePop extends StatefulWidget {
  const ScalePop({
    super.key,
    required this.child,
    required this.trigger,
    this.magnitude = 0.12,
    this.duration = const Duration(milliseconds: 180),
  });

  final Widget child;
  final Object trigger;
  final double magnitude;
  final Duration duration;

  @override
  State<ScalePop> createState() => _ScalePopState();
}

class _ScalePopState extends State<ScalePop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.duration, value: 1.0);
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.0 - widget.magnitude),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.0 - widget.magnitude, end: 1.0),
      weight: 1,
    ),
  ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant ScalePop old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !reduceMotionOf(context)) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/scale_pop_test.dart`
Expected: PASS (both).

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/scale_pop.dart test/core/ui/scale_pop_test.dart
git commit -m "feat(core/ui): ScalePop press/confirm primitive"
```

---

### Task 4: IconCrossfade primitive (tick morph)

**Files:**
- Create: `lib/core/ui/motion/icon_crossfade.dart`
- Test: `test/core/ui/icon_crossfade_test.dart`

**Interfaces:**
- Consumes: `reduceMotionOf` (Task 1).
- Produces:
  - `class IconCrossfade extends StatelessWidget` with
    `IconCrossfade({Key? key, required Widget child, Duration duration = const Duration(milliseconds: 200)})`.
    Wraps `AnimatedSwitcher` with a fade+scale transition; the caller gives the
    child a `ValueKey` per state so switching morphs between glyphs.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/icon_crossfade_test.dart
import 'package:attune/core/ui/motion/icon_crossfade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('crossfades to the new child when the keyed child changes',
      (tester) async {
    IconData icon = Icons.check;
    late StateSetter setState;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, s) {
        setState = s;
        return IconCrossfade(child: Icon(icon, key: ValueKey(icon)));
      }),
    ));
    expect(find.byIcon(Icons.check), findsOneWidget);
    setState(() => icon = Icons.done_all);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/icon_crossfade_test.dart`
Expected: FAIL — `IconCrossfade` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/motion/icon_crossfade.dart
import 'package:flutter/widgets.dart';

import 'reduce_motion.dart';

/// Morphs between two glyphs with a fade+scale. Generic: chat status ticks are
/// one consumer, but any state-icon can use it. Caller keys the child per state.
class IconCrossfade extends StatelessWidget {
  const IconCrossfade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 200),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final d = reduceMotionOf(context) ? Duration.zero : duration;
    return AnimatedSwitcher(
      duration: d,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/icon_crossfade_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/icon_crossfade.dart test/core/ui/icon_crossfade_test.dart
git commit -m "feat(core/ui): IconCrossfade morph primitive"
```

---

### Task 5: GlowPulse primitive (presence liveness)

**Files:**
- Create: `lib/core/ui/motion/glow_pulse.dart`
- Test: `test/core/ui/glow_pulse_test.dart`

**Interfaces:**
- Consumes: `reduceMotionOf` (Task 1).
- Produces:
  - `class GlowPulse extends StatefulWidget` with
    `GlowPulse({Key? key, required Widget child, required bool active, Color? color, double maxSpread = 8.0})`.
    When `active`, a slow breathing box-shadow pulses around the child; when
    inactive or reduce-motion, no shadow.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/glow_pulse_test.dart
import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inactive shows no glow decoration', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GlowPulse(active: false, child: SizedBox(width: 40, height: 40)),
    ));
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.boxShadow == null || deco.boxShadow!.isEmpty, isTrue);
  });

  testWidgets('active renders a glow that animates', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GlowPulse(
        active: true,
        color: Color(0xFFEEAA55),
        child: SizedBox(width: 40, height: 40),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.boxShadow, isNotNull);
    expect(deco.boxShadow!.isNotEmpty, isTrue);
    // Stop the infinite animation so the test can settle.
    await tester.pumpWidget(const MaterialApp(
      home: GlowPulse(active: false, child: SizedBox(width: 40, height: 40)),
    ));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/glow_pulse_test.dart`
Expected: FAIL — `GlowPulse` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/motion/glow_pulse.dart
import 'package:flutter/material.dart';

import 'reduce_motion.dart';

/// Slow breathing glow around a child while [active]. Universal "someone/
/// something is live" indicator — used for a partner-present avatar, but usable
/// anywhere. Calm by design (Spec §3.3): long period, small spread.
class GlowPulse extends StatefulWidget {
  const GlowPulse({
    super.key,
    required this.child,
    required this.active,
    this.color,
    this.maxSpread = 8.0,
  });

  final Widget child;
  final bool active;
  final Color? color;
  final double maxSpread;

  @override
  State<GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<GlowPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant GlowPulse old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active && !reduceMotionOf(context)) {
      _ctrl.repeat(reverse: true);
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
    final color =
        widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final spread =
            widget.active ? widget.maxSpread * _ctrl.value : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45 * _ctrl.value),
                      blurRadius: spread * 1.5,
                      spreadRadius: spread,
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/glow_pulse_test.dart`
Expected: PASS (both).

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/motion/glow_pulse.dart test/core/ui/glow_pulse_test.dart
git commit -m "feat(core/ui): GlowPulse presence primitive"
```

---

### Task 6: Haptics feedback service (injectable)

**Files:**
- Create: `lib/core/ui/feedback/haptics.dart`
- Test: `test/core/ui/haptics_test.dart`

**Interfaces:**
- Produces:
  - `abstract class Haptics { void light(); void selection(); }`
  - `class SystemHaptics implements Haptics` — wraps `HapticFeedback`.
  - `class FakeHaptics implements Haptics { int lightCount = 0; int selectionCount = 0; }`
  - `final hapticsProvider = Provider<Haptics>((ref) => SystemHaptics());`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/ui/haptics_test.dart
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FakeHaptics counts calls for assertions', () {
    final h = FakeHaptics();
    h.light();
    h.light();
    h.selection();
    expect(h.lightCount, 2);
    expect(h.selectionCount, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/ui/haptics_test.dart`
Expected: FAIL — `haptics.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ui/feedback/haptics.dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable haptic feedback so widgets can trigger taps and tests can assert
/// call counts without a device. Universal — any feature can depend on it.
abstract class Haptics {
  void light();
  void selection();
}

class SystemHaptics implements Haptics {
  const SystemHaptics();
  @override
  void light() => HapticFeedback.lightImpact();
  @override
  void selection() => HapticFeedback.selectionClick();
}

class FakeHaptics implements Haptics {
  int lightCount = 0;
  int selectionCount = 0;
  @override
  void light() => lightCount++;
  @override
  void selection() => selectionCount++;
}

final hapticsProvider = Provider<Haptics>((ref) => const SystemHaptics());
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/ui/haptics_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/ui/feedback/haptics.dart test/core/ui/haptics_test.dart
git commit -m "feat(core/ui): injectable Haptics service"
```

---

### Task 7: Wire SettleIn into the message list; delete AnimatedEntry

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (the
  `_MessageList` `itemBuilder`, ~line 860)
- Delete: `lib/features/chat/presentation/widgets/animated_entry.dart`
- Test: `test/features/chat/message_list_animation_test.dart`

**Interfaces:**
- Consumes: `SettleIn` (Task 2).

**Context:** `_MessageList` builds bubbles in a `ListView.builder` with
`reverse: true`. Wrap each `MessageBubble` in `SettleIn` keyed by
`message.clientMessageId`, and only animate when the message is newer than the
list's initial load so cached history does not replay. Track the newest
`createdAt` seen at first build.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/message_list_animation_test.dart
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('each message bubble is wrapped in a SettleIn', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello',
      createdAt: DateTime.now(),
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ChatScreen(conversation: convo)),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SettleIn), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/message_list_animation_test.dart`
Expected: FAIL — no `SettleIn` in the tree yet.

- [ ] **Step 3: Implement — wrap bubbles in SettleIn**

In `chat_screen.dart`, add the import:

```dart
import 'package:attune/core/ui/motion/settle_in.dart';
```

In `_MessageList`, capture the newest timestamp at first build and wrap the
bubble. Replace the `itemBuilder`'s bubble return with:

```dart
final message = state.messages[index];
return SettleIn(
  key: ValueKey(message.clientMessageId),
  // Only animate messages that arrived after this list first rendered, so
  // cached history does not replay on open (Spec §2 play-once).
  animate: message.createdAt.isAfter(_firstBuildCutoff),
  beginOffset:
      message.isMine ? const Offset(0, 0.12) : const Offset(0, 0.10),
  child: MessageBubble(
    message: message,
    onRetry: message.isFailed
        ? () => ref
            .read(chatControllerProvider(state.conversation).notifier)
            .retryMessage(message)
        : null,
    onRemove: message.isFailed
        ? () => ref
            .read(chatControllerProvider(state.conversation).notifier)
            .removeFailedMessage(message)
        : null,
  ),
);
```

Add the cutoff field to `_MessageList` (convert it to capture a stable cutoff).
Since `_MessageList` is a `ConsumerWidget`, add a `final DateTime _firstBuildCutoff = DateTime.now();`
as an instance field is not possible on a StatelessWidget's build; instead
compute it once by storing it on the widget when constructed in
`ChatScreen.build`:

```dart
// In ChatScreen.build, where _MessageList is created:
Expanded(
  child: _MessageList(
    state: state,
    scrollController: _scrollController,
    firstBuildCutoff: _messageListCutoff,
  ),
),
```

Add to `_ChatScreenState`:

```dart
final DateTime _messageListCutoff = DateTime.now();
```

And update `_MessageList` to accept and use it:

```dart
class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.state,
    required this.scrollController,
    required this.firstBuildCutoff,
  });

  final ChatState state;
  final ScrollController scrollController;
  final DateTime firstBuildCutoff;
```

(replace `_firstBuildCutoff` in the bubble code above with `firstBuildCutoff`.)

Delete the old widget:

```bash
git rm lib/features/chat/presentation/widgets/animated_entry.dart
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/message_list_animation_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/chat/ lib/core/ui/`
Expected: No errors (AnimatedEntry references gone).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/message_list_animation_test.dart
git rm lib/features/chat/presentation/widgets/animated_entry.dart
git commit -m "feat(chat): settle-in message entry; remove dead AnimatedEntry"
```

---

### Task 8: Tick morph + optimistic→sent confirm in the bubble

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (the
  `_StatusChip` icon, ~line 170)
- Test: `test/features/chat/message_bubble_test.dart` (extend existing)

**Interfaces:**
- Consumes: `IconCrossfade` (Task 4).

**Context:** `_StatusChip` already picks an `icon` per `message.status`. Wrap the
icon in `IconCrossfade` with a `ValueKey(message.status)` so status changes morph
instead of hard-swapping.

- [ ] **Step 1: Write the failing test (add to message_bubble_test.dart)**

```dart
  testWidgets('status icon is wrapped in an IconCrossfade for morphing',
      (tester) async {
    await _pump(
      tester,
      MessageBubble(message: _mine(status: MessageStatus.delivered)),
    );
    expect(find.byType(IconCrossfade), findsOneWidget);
  });
```

Add the import at the top of the test file:

```dart
import 'package:attune/core/ui/motion/icon_crossfade.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/message_bubble_test.dart -n "IconCrossfade"`
Expected: FAIL — no `IconCrossfade` in the bubble.

- [ ] **Step 3: Implement — wrap the status icon**

In `message_bubble.dart` add:

```dart
import 'package:attune/core/ui/motion/icon_crossfade.dart';
```

Replace the `Icon(icon, size: 14, color: color)` inside `_StatusChip.build`'s
`Row` with:

```dart
IconCrossfade(
  child: Icon(icon, key: ValueKey(message.status), size: 14, color: color),
),
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/message_bubble_test.dart`
Expected: PASS (existing + new).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/widgets/message_bubble.dart test/features/chat/message_bubble_test.dart
git commit -m "feat(chat): morph status ticks with IconCrossfade"
```

---

### Task 9: Send feedback — ScalePop on the send button + haptic on send

**Files:**
- Modify: `lib/features/chat/presentation/widgets/chat_text_field.dart` (the
  send `IconButton.filled`, ~line 92)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_send`,
  ~line 114)
- Test: `test/features/chat/send_feedback_test.dart`

**Interfaces:**
- Consumes: `ScalePop` (Task 3), `hapticsProvider` + `FakeHaptics` (Task 6).

**Context:** Fire `ref.read(hapticsProvider).light()` at the top of `_send`
(before the async send) so it's instant. Wrap the send icon in `ScalePop`
triggered by a counter that increments each send.

**First, extend the harness** so tests can inject extra provider overrides
(riverpod 2.4 `ProviderContainer(parent:)` overrides are fragile — pass them at
construction instead). In `test/features/chat/support/chat_test_harness.dart`,
change `buildChatContainer` to accept optional extra overrides:

```dart
ProviderContainer buildChatContainer({
  required FakeChatRepository repository,
  required String userId,
  List<Override> extraOverrides = const [],
}) {
  final cache = ChatCacheService.forTesting(backend: stub.createBackend());
  final container = ProviderContainer(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repository),
      chatCacheServiceProvider.overrideWithValue(cache),
      currentUserProvider.overrideWithValue(testUser(userId)),
      ...extraOverrides,
    ],
  );
  return container;
}
```

(`Override` comes from the existing `flutter_riverpod` import.)

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/send_feedback_test.dart
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('sending a message fires exactly one light haptic',
      (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fakeHaptics = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [hapticsProvider.overrideWithValue(fakeHaptics)],
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

    expect(fakeHaptics.lightCount, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/send_feedback_test.dart`
Expected: FAIL — no haptic call yet.

- [ ] **Step 3: Implement — haptic + ScalePop**

In `chat_screen.dart`, import and fire the haptic in `_send`:

```dart
import 'package:attune/core/ui/feedback/haptics.dart';
```

```dart
Future<void> _send() async {
  final text = _controller.text.trim();
  if (text.isEmpty) return;
  ref.read(hapticsProvider).light(); // instant tactile confirm (Spec §3.1)
  await _sendDraftText(_controller.text);
}
```

Wrap the send icon in `chat_text_field.dart` with `ScalePop`. Add:

```dart
import 'package:attune/core/ui/motion/scale_pop.dart';
```

Add a send counter to `_ChatTextFieldState`:

```dart
int _sendPulse = 0;
```

In `_ChatTextFieldState`, wrap the send button's icon; change the send
`IconButton.filled` to fire the pulse and call `onSend`:

```dart
IconButton.filled(
  onPressed: widget.enabled && _hasText
      ? () {
          setState(() => _sendPulse++);
          widget.onSend();
        }
      : null,
  tooltip: 'Send message',
  icon: ScalePop(
    trigger: _sendPulse,
    child: const Icon(Icons.send_rounded),
  ),
),
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/send_feedback_test.dart test/features/chat/chat_text_field_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart lib/features/chat/presentation/widgets/chat_text_field.dart test/features/chat/send_feedback_test.dart
git commit -m "feat(chat): send haptic + send-button ScalePop"
```

---

### Task 10: Receive haptic (foreground-only) in the controller

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (the realtime
  refresh callback, ~line 170, and add a helper)
- Test: `test/features/chat/receive_haptic_test.dart`

**Interfaces:**
- Consumes: `hapticsProvider` + `FakeHaptics` (Task 6).

**Context:** When a realtime refresh brings in a NEW partner message and the view
is active (`_isViewActive`), fire one soft haptic. Must not fire for the user's
own messages, for cached history, or when backgrounded. Detect "new partner
message" by comparing the newest partner message id before/after the refresh.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/receive_haptic_test.dart
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  test('a new partner message while viewing fires one receive haptic',
      () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fake = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [hapticsProvider.overrideWithValue(fake)],
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

    expect(fake.selectionCount + fake.lightCount, greaterThanOrEqualTo(1));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/receive_haptic_test.dart`
Expected: FAIL — no receive haptic yet.

- [ ] **Step 3: Implement — receive haptic on new partner message**

In `chat_state.dart`, add import:

```dart
import 'package:attune/core/ui/feedback/haptics.dart';
```

Add a field to track the newest partner message id:

```dart
String? _lastPartnerMessageId;
```

In `loadMessages` success (after state is updated with merged messages), compute
the newest partner message and, if it changed and the view is active, buzz.
Add this helper and call it at the end of the `loadMessages` try block and the
`_catchUpFromCursor` success block:

```dart
void _maybeReceiveHaptic() {
  final newestPartner = state.messages
      .where((m) => !m.isMine && !m.id.startsWith('_local_'))
      .fold<Message?>(null, (best, m) =>
          best == null || m.createdAt.isAfter(best.createdAt) ? m : best);
  final id = newestPartner?.id;
  if (id == null) return;
  final isNew = _lastPartnerMessageId != null && id != _lastPartnerMessageId;
  _lastPartnerMessageId = id;
  if (isNew && _isViewActive) {
    ref.read(hapticsProvider).selection();
  }
}
```

Call `_maybeReceiveHaptic();` right after the `state = state.copyWith(...)` in
`loadMessages` (success path) and after the merge in `_catchUpFromCursor`.

Note: seed `_lastPartnerMessageId` on first load so the initial history does not
buzz — set it once inside `_init` after the first `loadMessages()`:

```dart
// after await loadMessages(silent: hasWarmCache); in _init:
_lastPartnerMessageId = state.messages
    .where((m) => !m.isMine && !m.id.startsWith('_local_'))
    .fold<Message?>(null, (best, m) =>
        best == null || m.createdAt.isAfter(best.createdAt) ? m : best)
    ?.id;
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/receive_haptic_test.dart test/features/chat/chat_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/state/chat_state.dart test/features/chat/receive_haptic_test.dart
git commit -m "feat(chat): soft receive haptic for new partner message while viewing"
```

---

### Task 11: Partner-here glow on the header avatar

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart`
  (`_ConversationHeaderCard` avatar `CircleAvatar`, ~line 523)
- Test: `test/features/chat/header_glow_test.dart`

**Interfaces:**
- Consumes: `GlowPulse` (Task 5).

**Context:** For this plan, drive `active` from the conversation's online-ish
state we already have: `conversation.availability == active` AND the last-synced
recency. (True partner-presence comes in Plan 3.) Wrap the avatar in `GlowPulse`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/chat/header_glow_test.dart
import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('header avatar is wrapped in a GlowPulse', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ChatScreen(conversation: convo)),
    ));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(GlowPulse), findsWidgets);
    // Stop timers.
    await tester.pumpWidget(const SizedBox());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/header_glow_test.dart`
Expected: FAIL — no `GlowPulse` in header.

- [ ] **Step 3: Implement — wrap avatar in GlowPulse**

In `chat_screen.dart` import:

```dart
import 'package:attune/core/ui/motion/glow_pulse.dart';
```

Wrap the header `CircleAvatar` (in `_ConversationHeaderCard`):

```dart
GlowPulse(
  active: conversation.availability == ConversationAvailability.active &&
      isOnline,
  child: CircleAvatar(
    backgroundImage: conversation.avatarUrl == null
        ? null
        : NetworkImage(conversation.avatarUrl!),
    child: conversation.avatarUrl == null
        ? Text(_initialForName(conversation.name))
        : null,
  ),
),
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/chat/header_glow_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/header_glow_test.dart
git commit -m "feat(chat): partner-here glow on header avatar"
```

---

### Task 12: Full-suite verification + analyze

**Files:** none (verification only).

- [ ] **Step 1: Analyze the whole app (errors only gate)**

Run: `flutter analyze lib/ test/ 2>&1 | grep -E "error •|error -" || echo "no errors"`
Expected: `no errors`.

- [ ] **Step 2: Run the core/ui primitive suite**

Run: `flutter test test/core/ui/`
Expected: All pass.

- [ ] **Step 3: Run the full chat suite**

Run: `flutter test test/features/chat/`
Expected: All pass (existing 42 + new animation tests).

- [ ] **Step 4: Run the entire repo suite**

Run: `flutter test`
Expected: All pass, no regressions.

- [ ] **Step 5: Commit any final cleanups**

```bash
git commit --allow-empty -m "test: verify chat motion toolkit full suite green"
```

---

## Deferred to follow-on plans

- **Plan 2 — Sound system (Spec §3.6):** add an audio package (`audioplayers` or
  `just_audio`), `lib/core/ui/feedback/sound_service.dart` (interface + impl +
  no-op), silent/DND guard, settings toggle, send/receive playback with the
  no-double-fire guard on optimistic→canonical reconciliation. Placeholder assets
  now; pro assets pre-launch.
- **Plan 3 — Typing presence (Spec §3.3 typing, §5.2):** extend `chat_presence`
  with an is-composing signal + debounce/expiry, `breathing_dots.dart` primitive,
  and the typing indicator composition. (Backend touch.)
- **Plan 4 — Rituals (Spec §3.7):** first-message-of-the-day shimmer, reconnect
  cascade (`stagger.dart`), and streak/milestone celebration (gated on a cadence
  source; opt-in, subtle by default). Includes `shimmer.dart` + `stagger.dart`
  primitives, `elastic_refresh.dart` for §3.4 pull-to-refresh, and the "Chat
  feel" settings group (§4).

## Self-review notes

- **Spec coverage (Plan 1):** §3.1 sending → Tasks 8,9; §3.2 receiving → Tasks
  7,10; §3.3 glow → Task 11 (typing deferred to Plan 3); §3.4 empty/read-only
  already present, pull-to-refresh deferred to Plan 4; §3.5 accent → uses theme
  colorScheme.primary throughout; §5.1 primitives → Tasks 1–6; §6 primitive
  tests → each task. Sounds (§3.6), typing (§3.3), rituals (§3.7) explicitly
  deferred with owning plans.
- **Reduce-motion:** every primitive checks it (Tasks 1–5); verified in tests.
- **Content-blind:** no task reads message content; primitives take plain inputs.
- **Type consistency:** `SettleIn`, `ScalePop(trigger:)`, `IconCrossfade`,
  `GlowPulse(active:)`, `Haptics.{light,selection}`, `hapticsProvider`,
  `FakeHaptics` used consistently across producing and consuming tasks.
