# Chat Delight & Motion — Design Spec

**Date:** 2026-07-10
**Status:** Approved for implementation planning
**Owner:** Chat feature
**Governs:** presentation-layer motion, haptics, presence liveness, sound, and
opt-in ritual moments for the couples chat surface.
**Subordinate to:** `lib/architecture/CHAT_SYSTEM_SPEC.md`, `ATTUNE_SOUL.md`,
`ATTUNE_CLINICAL.md`, `SAFETY_SYSTEM_SPEC.md`, and the permanent product
constraints. Where any conflict arises, those documents win.

---

## 1. Goal & positioning

Make Attune's chat the most *emotionally satisfying* messaging experience for a
couple — a surface they return to **for how it feels**, not only what it does.
Retention is the strategic target: delight comes from small, repeated moments of
warmth and responsiveness, not one-time spectacle.

"Fun" here is defined as **warm & alive**: buttery responsiveness, satisfying
feedback, gentle physicality, and a sense that the other person is *present* —
never childish, never a toy, never performing at the couple.

### 1.0 Build it as a universal toolkit, not chat-only code

The motion, feedback, and presence pieces are built as **app-wide reusable
primitives** (`lib/core/ui/`) that any widget in any feature can use, not code
buried inside chat. Chat is the first and richest consumer, but the same
settle/shimmer/glow/scale-pop/haptics/sound components should make buttons,
cards, and lists across the whole app feel alive. See §5 for the
primitive-vs-composition split.

### 1.1 Non-negotiable tone floor

Attune serves couples in real relationships, including hard moments, and sits in
front of a Safety System. Therefore:

- **Nothing celebratory ever fires based on message content.** Animations react
  only to *events* (sent, delivered, read, arrived, presence), never to what a
  message says. Reacting to sentiment would also leak the hidden AI analysis the
  Chat Spec forbids surfacing (§7.3).
- **Calm by default; expressiveness is opt-in.** The expressive layer (rituals,
  celebration, sound) is subtle by default and user-dimmable. A couple in a
  painful moment must never be met with confetti.
- **Accessible always.** Every animation respects the OS reduce-motion setting
  and degrades to an instant fade; meaning is never conveyed by motion or color
  alone (Chat Spec §11.4).

---

## 2. Motion language (the rules every animation obeys)

1. **Serves communication or feedback — never decoration.** If an animation does
   not tell the user something ("going", "arrived", "they're here"), it does not
   ship.
2. **Content-blind.** Driven by events only, never message content.
3. **Spring, don't slide.** The signature feel is physical: elements settle with
   a single shared spring (slight overshoot, quick damp). Defined once as a
   motion token and reused everywhere.
4. **Fast and calm.** Durations live in the 150–320ms band (existing
   `AnimationDurations` tokens). No animation blocks input.

**Guardrails baked in from the start:**

- **Reduce-motion aware.** Every animated widget checks
  `MediaQuery.disableAnimations`; when true it renders the end-state with at most
  a short fade.
- **Play-once, not on-rebuild.** Animations key off genuinely new events (a
  message that just arrived, a status that just changed), never re-firing on list
  rebuilds. Enforced with stable `ValueKey`s (the existing `AnimatedEntry`
  pattern).

### 2.1 Existing materials (reuse, don't reinvent)

- `flutter_animate` (already a dependency).
- `AnimationDurations` / `AnimationCurves` motion tokens in
  `lib/app/theme/design_tokens.dart`.
- `AnimatedEntry` widget (built, currently **unused** — wire it in).
- `chat_presence` table + `set_chat_presence` / `is_actively_viewing` RPCs
  (built for push-suppression; extend for typing/glow).

### 2.2 New materials required

- A shared **spring** curve/spec (motion token).
- A **haptics** helper for chat (thin wrapper over `HapticFeedback`).
- A **sound** service (new audio package; placeholder assets now).
- A small **typing** presence signal (extends `chat_presence`).

---

## 3. Animation set

Grouped by moment. Each item: what it does, the feel, effort (S/M/L).

### 3.1 Sending (most-felt)

1. **Send-and-settle** *(signature)* — on send, the optimistic bubble appears at
   the bottom and settles with the shared spring (rises slightly, gentle
   overshoot, damps). Send button gives a quick scale-pop. **[M]**
2. **Send haptic** — `HapticFeedback.lightImpact` the instant a send is
   initiated. **[S]**
3. **Tick morph** — status ⏱→✓→✓✓→blue✓✓ cross-fades/morphs between glyphs
   instead of hard-swapping, so the progression reads as one continuous life.
   Builds on the already-correct status model. **[S]**
4. **Optimistic→sent confirm** — when the server acks, the first tick draws in
   with a quick satisfying stroke. Subtle reward for "it landed." **[S]**

### 3.2 Receiving

5. **Incoming slide-in** — a partner's new message slides up + fades with the
   shared spring (wire up the existing `AnimatedEntry`). **[S]**
6. **Receive haptic** — a soft haptic when a message arrives *while the chat is
   foregrounded and visible* (reuses the presence/foreground state already
   tracked for read receipts). Never when backgrounded — that is the push's job.
   **[S]**

### 3.3 Presence & liveness (where "warm" lives)

7. **Typing indicator** — three breathing dots while the partner is composing.
   Requires a lightweight "is composing" presence signal — a small extension of
   `chat_presence`. Coalesced/debounced; auto-expires. **[M, backend touch]**
8. **Partner-here glow** — a subtle, slow pulse on the partner's avatar while
   they are actively in the conversation (reuses the presence signal). Calm, not
   blinky. **[S]**

### 3.4 Navigation & states

9. **Scroll-to-latest** — the "new messages ↓" pill and jump-to-bottom animate
   with the spring instead of snapping. **[S]**
10. **Pull-to-refresh** — a calm elastic pull for loading older history, not a
    spinner yank. **[S]**
11. **Empty / read-only warmth** — empty-conversation and read-only states get a
    gentle fade-in and softer presentation, so those moments feel intentional,
    not broken. **[S]**

### 3.5 Signature identity

12. **Couple accent** — the spring, tick color, and glow pull from one coherent
    warm palette so the chat is instantly recognizable as "the Attune place we
    talk," distinct from WhatsApp green / iMessage blue. Sourced from the design
    system; no per-couple theming in this pass. **[S]**

### 3.6 Sound (system now, pro assets pre-launch)

13. **Send / receive sounds** — soft, warm, short. Default **on**, a single
    settings toggle, muted in silent mode / DND, paired with the reduce-motion
    posture. Placeholder tones now; professionally-designed assets swapped in
    before launch. Playback guards: never on backgrounded receive, never
    double-fire on optimistic→canonical reconciliation. **[M, new package]**

### 3.7 Rituals (warm-calm default, opt-in for more)

14. **First-message-of-the-day** — a subtle one-time shimmer on the first bubble
    each day (date-based, content-blind). **[S]**
15. **Reconnect warmth** — on reopening after time away with unread partner
    messages, the unread set cascades in with a gentle stagger rather than
    appearing at once. Makes the *return* rewarding. **[S]**
16. **Streak / milestone celebration** — tasteful, opt-in-to-bigger shimmer on
    cadence events the system already knows (e.g., a run of daily conversation).
    **DEPENDENCY:** no streak/cadence signal exists yet; this item is gated on a
    cadence source and remains **opt-in and subtle by default**. If the source is
    not ready, ship 14–15 and defer 16. **[M + dependency]**

---

## 4. Settings & user control

A small **Chat feel** settings group (local device preferences, no server
needed except where noted):

- Message sounds — on/off (default on).
- Haptics — on/off (default on; also respects OS settings).
- Expressive moments — calm (default) / more expressive (opt-in).
- All of the above are independent; reduce-motion at the OS level overrides
  toward calm regardless.

Typing/presence visibility follows the existing presence model and its privacy
rules (a partner never sees more than "active / composing", never content).

---

## 5. Architecture & boundaries

**Core principle: universal primitives, feature compositions.** The motion,
feedback, and presence *primitives* are app-wide, reusable, and content-blind by
construction — they live in a shared `lib/core/ui/` toolkit and know nothing
about chat, so any widget anywhere in the app (buttons, cards, lists, other
features) can drop them in. Chat is simply the **first consumer**. Chat-specific
*compositions* (typing indicator, optimistic→sent confirm, rituals) stay in the
chat feature but are **built from** the universal primitives.

This split is not just tidiness: because a universal primitive literally does
not know what a message is, it *cannot* react to message content — so the
content-blind tone floor (§1.1) is enforced at the architecture level, not just
by discipline.

### 5.1 Universal toolkit — `lib/core/ui/` (knows nothing about chat)

```
lib/core/ui/
  motion/
    motion_tokens.dart     # shared spring spec + durations/curves (with app/theme)
    reduce_motion.dart     # MediaQuery.disableAnimations helper / wrapper
    settle_in.dart         # spring settle + fade entry (generalizes AnimatedEntry)
    shimmer.dart           # one-shot / looping shimmer sweep
    glow_pulse.dart        # slow breathing glow (any widget/avatar)
    scale_pop.dart         # quick press/confirm scale-pop (any button/icon)
    icon_crossfade.dart    # morph between two icons (generic; chat ticks use it)
    stagger.dart           # staggered entry for a list of children
    elastic_refresh.dart   # calm elastic pull-to-refresh
  feedback/
    haptics.dart           # thin injectable wrapper over HapticFeedback
    sound_service.dart     # interface + audio-package impl + no-op (tests)
  presence/
    breathing_dots.dart    # generic "someone is doing something" 3-dot indicator
```

Every primitive: (1) takes plain inputs (a child, an event/flag, a color), (2)
honors reduce-motion internally, (3) is play-once safe via keys/flags, (4) has
no feature imports. Each is independently testable and usable outside chat.

**Reuse note:** `settle_in.dart` supersedes the existing unused
`lib/features/chat/presentation/widgets/animated_entry.dart` — generalize and
move it to core, then delete the chat copy. `motion_tokens.dart` extends, and
does not duplicate, the existing `AnimationDurations`/`AnimationCurves` in
`lib/app/theme/design_tokens.dart`.

### 5.2 Chat compositions — `lib/features/chat/presentation/` (uses the toolkit)

- **Typing indicator** = `breathing_dots` + chat presence data.
- **Optimistic→sent confirm** = `icon_crossfade`/`scale_pop` + message status.
- **Send-and-settle** = `settle_in` + `scale_pop` + `haptics`, wired to the send
  action.
- **First-message-of-the-day / reconnect cascade** = `shimmer` / `stagger` +
  chat date/unread logic.
- Controllers and repositories are untouched except the typing presence
  extension in the chat data layer.

### 5.3 Testability

- Haptics and sound are injectable interfaces (with no-op/fake impls) so widget
  tests assert "one send → exactly one haptic + at most one sound" with no real
  device.
- Motion primitives are driven by explicit `animate:`/event flags so play-once
  behavior is unit-testable (mirrors the existing `AnimatedEntry` test pattern).
- Universal primitives get their **own** tests in `test/core/ui/`, independent of
  chat, proving they work as standalone components.

### 5.4 Failure / degradation behavior

- Reduce-motion on → instant end-states, no springs (enforced inside each
  primitive, so every consumer inherits it for free).
- Silent mode / DND → no sound; visuals + haptics unaffected.
- Audio init failure → silent no-op, never blocks the host widget.
- Typing signal unavailable/stale → indicator simply doesn't show; chat
  unaffected.
- Any animation error is contained to its widget and never blocks the host
  feature's core action (send/receive, tap, navigation).

---

## 6. Testing

- **Universal primitive tests (`test/core/ui/`):** each primitive works
  standalone — settle/shimmer/glow/scale-pop/icon-crossfade/stagger animate once
  and honor reduce-motion; breathing-dots renders/loops; elastic-refresh fires
  its callback. No chat dependency.
- **Feedback interface tests:** sound/haptic services honor their toggles and the
  silent/DND guard; fakes assert call counts.
- **Chat composition widget tests (`test/features/chat/`):** send fires exactly
  one haptic and at most one sound; optimistic→canonical reconciliation does
  **not** double-fire sound/haptic; incoming message animates once and not on
  rebuild; reduce-motion renders end-state instantly; read-only/empty states fade
  in. Extends the existing chat harness (FakeChatRepository + injectable feedback
  fakes).
- **Presence/typing tests:** typing signal debounces, expires, and never leaks
  content; glow follows presence.

## 7. Rollout & gates

- Presentation polish (3.1–3.5, 3.6 system, 3.7 #14–15) ships with the launch
  chat behind the normal feature-flag posture.
- **Sound assets** require final audio before the audio is enabled by default
  (placeholder until then).
- **#16 streak celebration** is gated on a cadence source AND stays opt-in;
  defer if not ready.
- The expressive layer (sound defaults, rituals, celebration copy) is included
  in the same **Ghanaian/West-African cultural review** and clinical tone review
  the Chat Spec already requires — expressive motion/sound is exactly the kind of
  thing that review exists to catch.

## 8. Explicit non-goals (this pass)

- No reactions, stickers, GIFs, voice/video (later phases with their own
  contracts).
- No content-reactive effects of any kind.
- No per-couple custom theming (one coherent accent only).
- No full-screen "screen effects" (iMessage-style) — against the tone floor.
