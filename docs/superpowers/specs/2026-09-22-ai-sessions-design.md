# Attune AI Sessions — bounded multi-turn brainstorming in the composer

**Status:** draft for adversarial review. Not implementation-ready until the
review in §0 is answered and the gates in §14 are resolved.
**Date:** 2026-09-22
**Supersedes:** nothing. **Amends:** `2026-09-15-ai-assistant-design.md`
(hereafter "the base spec") at §1, §2, §3, §4.3, §7.2, §7.3.
**Scope:** a composer-level entry point to a bounded, multi-turn AI session
that either partner may run privately or share as a live three-way thread.

---

## 0. What a reviewer should attack first

This design deliberately reverses three decisions the base spec made *after*
its own adversarial review. Each reversal is a product decision already taken;
what needs review is whether the compensating controls are sufficient, not
whether the reversal should happen.

| # | Base spec said | This spec does | Compensating control | Reviewer question |
|---|---|---|---|---|
| R1 | "Pull-only… never offers itself" (§1) — entry only via long-press on a specific message | Adds a standing composer button always visible in an active chat | Button opens a sheet that makes mode/visibility/context explicit before any provider call; no generation happens on open | Does a standing affordance change the consent posture, given consent is already dual and server-verified? |
| R2 | "Never supports follow-up turns… no assistant identity persists across calls" (§1) | Bounded thread: max 10 turns per session, 15-minute idle expiry | Context is *only* that session's own turns plus an optional 6-message window; turn cap and character ceilings enforced server-side | Is 10 turns × the per-turn ceiling an acceptable cumulative disclosure to the provider? |
| R3 | Context is server-selected around **one explicitly chosen** message; §4.3 cut history precisely because a day's transcript is "far more context than one terse message needs" | Shared sessions may include the last 6 same-day messages the partners did not individually choose | Server-selected only (never client-supplied), same-day bounded, character-capped, transcript handled as quoted data, window contents shown in the UI before the first call and revocable | **This is the highest-risk item in the document.** Is a visible, revocable, 6-message, same-day, server-selected window an acceptable replacement for per-message choice? |

This spec was self-audited against
`lib/architecture/algorithms/algorithm_quality_review_checklist.md` v3.1
before review; §8.2 carries the engineering contract (timeouts, concurrency,
failure compensation, privacy/retention, latency, complexity) and §8.2.6
documents the skips. A reviewer should treat that self-audit as a claim to
check, not as evidence.

A fourth item is new rather than a reversal:

| # | New capability | Why it is risky | Control |
|---|---|---|---|
| R4 | A **shared** AI surface both partners write into | Two authors, one provider context. Partner B's prompt is influenced by, and visible to, partner A; either can steer the AI toward the other | Sessions are ephemeral, never analysed, never become chat history unless explicitly posted; either partner may end the session at any time; ending is not a rejection signal anywhere in the product |

---

## 1. Product boundary

An **AI session** is a bounded, ephemeral, multi-turn conversation with Attune
that happens *beside* the couple's chat, not inside it.

- It is entered from a new composer button, or from the existing long-press
  **Ask Attune** entry (which pre-attaches that message).
- It is **ephemeral**. The back-and-forth is never chat history. Only a turn a
  partner explicitly posts becomes a durable message, through the existing
  share path with server-owned provenance.
- It has two visibilities, chosen by the opener and changeable mid-session:
  - **Private** — only the opener sees it. This is the base spec's Assist flow
    with follow-up turns.
  - **Shared** — both partners see committed turns live and may both write.
- It is not a persona. Nothing carries across sessions: no memory, no profile,
  no prior session as context.

**Understand is not part of this feature.** The base spec's §6.3 privacy
boundary — separate types, providers, endpoints, and a static no-write
contract — is unchanged. `UnderstandResult` never enters a session, and no
session type exposes an Understand result. The prohibition on a generic
`AiAssistantResult` carrying optional actions still stands.

### 1.1 Answer scope

Unchanged from base spec §5.1. Sessions support **Ideas** (subjective
ideation) and **Nearby** (location-anchored place discovery). They do not
support general question answering, news, medical/legal/financial advice,
relationship advice, booking, checkout, browsing, or factual research.

Because a session is conversational, a bare `UNSUPPORTED_REQUEST` reads as a
failure. Unsupported asks instead return a **redirect turn**: a refusal that
names what Attune can do instead.

> You asked about new restaurants in New York. I can't look places up from
> here — I can only find places near you right now, or help you think it
> through. Want me to brainstorm what kind of night you're after?

The redirect is a model output validated against a fixed schema (§5.3); it is
not free-form apology text, and it never attempts a partial factual answer.

**Rejected alternative:** adding a search-grounded provider so open factual
questions get real answers. That requires a new provider contract, a fifth
hard gate (legal/privacy review), a new eval burden, and a new exfiltration
seam — what query text reaches the search provider. Out of scope for v1.

---

## 2. Visibility and capability matrix

| Capability | Private session | Shared session | Understand (unchanged) |
|---|---:|---:|---:|
| Who sees committed turns | Opener only | Both partners | Requester only |
| Who may write turns | Opener only | Both partners | N/A |
| Sees the other's in-progress typing | N/A | **No** | N/A |
| Reads that session's own prior turns | Yes, ≤10 | Yes, ≤10 | Never |
| Reads a recent chat window | Only if a message was attached | Last 6 same-day messages, server-selected, revocable | Up to 19 + target |
| Reads profiles, insights, location history, presence, safety state, Planning, prior sessions | Never | Never | Never |
| May use device location | Nearby submode, explicit per-call | Nearby submode, explicit per-call, by the requesting partner only | Never |
| Turns persisted | Session row until expiry | Session row until expiry | Never |
| Becomes chat history | Only an explicitly posted turn | Only an explicitly posted turn | Never |
| Included in relationship analysis | Never | Never | Never |
| Who may end it | Opener | **Either partner** | N/A |

---

## 3. Entry, eligibility, and the composer

### 3.1 Eligibility

The composer AI button is present only when:

- the relationship is active and `chat_archived_at IS NULL`;
- dual AI-processing consent is currently granted (base spec §10.1) — if not,
  the button opens the consent screen instead of a session;
- the feature flag is on (§14).

The button is a `ComposerSatellite` in `chat_text_field.dart`, matching the
existing attachment/mic treatment. It is never content-triggered: it does not
appear, change, or animate in response to what the partners are typing, which
preserves the base spec's "never offers itself based on message content."

### 3.2 Composer AI mode

Tapping the button:

1. Inserts an `OverlayEntry` reusing the existing `_ChatAttachScrim` dark-scrim
   treatment, so the dimmed-background language matches the attachment menu.
2. Puts the composer into **AI mode** via a new `ChatTextField` parameter:
   attachment, microphone, game, and send-money affordances are hidden; a
   single text field and send button remain, labelled for Attune.
3. Presents the session sheet above the scrim.

AI mode is a parameter on the existing composer, not a forked widget, so the
two cannot drift. Exiting AI mode restores every dismissed control.

### 3.3 Long-press entry

Long-press → **Ask Attune** is retained. Choosing **Get ideas** now opens a
private session with that message already attached (§4.2) rather than a
single-shot sheet. Choosing **Possible ways to read this** opens Understand
exactly as today — no session, no change.

---

## 4. Context construction

### 4.1 Request contract

```typescript
{
  request_id: string;        // client UUID; idempotency + quota key, per TURN
  session_id: string;        // client UUID, created on session open
  visibility: 'private' | 'shared';
  assist_kind: 'ideas' | 'nearby';
  user_instruction: string;  // trimmed, 1..300 Unicode scalar values
  attached_message_id: string | null;
  include_recent_window: boolean;   // shared sessions only; default true
  requester_location: {             // nearby only
    latitude: number;
    longitude: number;
    accuracy_m: number;
  } | null;
}
```

As in the base spec, the request accepts **no** `relationship_id`,
`requester_id`, message content, transcript, prior turns, profile fields,
partner identity, or source records. Identity comes from `requireUser(req)`.
Only `POST` with JSON; reject unknown fields, bodies over 4 KiB, invalid
UUIDs, and non-finite numbers before any database or provider work.

**Prior turns are never client-supplied.** The server loads them from
`ai_session_turns` by `session_id` after authorising the caller. A client that
sends turn content is rejected. This is the same P0 reasoning that moved
message context server-side in the base spec: membership does not prove a
string came from that session.

### 4.2 What the model receives

In order, bounded and truncated server-side:

1. **Session turns** — all prior turns of this session, oldest first. Two
   independent bounds apply, and the **character bound wins**: at most 20 turn
   rows (10 exchanges), and at most 6,000 characters total. Because a single
   turn may be up to 2,000 characters, 20 rows can exceed the character
   budget; when it does, the oldest turns are dropped **whole** (never
   truncated mid-turn) until the remainder fits, and the model is told that
   earlier turns were omitted. The most recent turn is never dropped — if it
   alone exceeds the budget, the request is rejected rather than silently
   truncated.
2. **Attached message**, if any — the single message from a long-press entry,
   or one the partner explicitly attached. ≤4,000 characters after NFC
   normalisation, same eligibility rules as base spec §3.
3. **Recent window** — shared sessions only, and only when
   `include_recent_window` is true. The **last 6 messages** in the same
   server-derived day as `now()`, server-selected, ≤600 characters each and
   ≤2,400 total.

Excluded from the window in all cases: deleted messages, system notices,
`message_origin = 'attune_assist'` output, media-only/game/place cards, and
any message from an archived or inactive relationship.

Every transcript segment is delivered to the model as quoted data with an
explicit instruction that it is conversation content, never instructions to
follow. Schema validity is not treated as an injection defence (base spec §9).

### 4.3 The window is visible and revocable

Before the first call in a shared session, the sheet shows exactly which
messages are in the window, with a single control to turn it off. Turning it
off applies from that turn forward; it does not retroactively unsend earlier
turns. The state is shown persistently in the session header, not only at
open, so a partner joining mid-session sees it too.

This visibility requirement is the compensating control for R3 and is not
optional.

---

## 5. Session lifecycle

### 5.1 Creation

The client generates `session_id` and opens the sheet. **No row is written and
no provider is called on open.** The session row is created by the server on
the first successful turn, so an abandoned sheet costs nothing and leaves no
record.

### 5.2 Turns

Each turn is one `request_id`, one quota reservation, and one provider call
(two for Nearby: Gemini for category + Mapbox for places, exactly as base spec
§5.2). Turn cap is 10 per session; the 11th returns `SESSION_TURN_LIMIT` with
a message offering to start a new session.

### 5.3 Model output contract

```typescript
type SessionTurnOutput =
  | {
      kind: 'answer';
      reply_text: string;   // trimmed, 1..2000 PostgreSQL characters
      suggested_planning_item: {
        kind: 'task' | 'event';
        title: string;      // trimmed, 1..120 characters
        event_date: string | null;  // YYYY-MM-DD; non-null only for event
      } | null;
    }
  | {
      kind: 'redirect';
      reply_text: string;   // trimmed, 1..400 characters
      offered: ('ideas' | 'nearby')[];  // what Attune can do instead
    };
```

Nearby is unchanged from base spec §5.2: the model emits only an allowlisted
category (`restaurant | cafe | park | cinema | museum | recreation`), the
server calls Mapbox, and the server constructs all place prose from
allowlisted Mapbox fields. The model never supplies a place name, address,
URL, distance, or rationale. Mapbox never receives message text, prose, IDs,
or Gemini output; Gemini never receives coordinates or Mapbox results.

### 5.4 Ending and expiry

A session ends when: either partner taps End; 15 minutes pass with no new turn;
the relationship ends or archives; or consent is withdrawn by either partner.

Ending writes `ended_at`/`ended_by` and stops the realtime channel. Turn rows
are deleted on end and, regardless, purged by extending the existing
`purge_expired_ai_assist_drafts()` job rather than adding a new cron.

**Either partner may end a shared session, and ending is never surfaced as a
rejection.** It produces no notification, no chat message, no Pulse signal, and
no analysis event. The other partner sees a neutral "This session ended."

---

## 6. Shared sessions

### 6.1 Realtime

Shared sessions use one Supabase Realtime channel per session,
`ai_session:<session_id>`, following the existing `chat:<relationship_id>`
pattern in `supabase_chat_repository.dart`. Both partners subscribe on join.

Broadcast events: `turn_committed` (a new user or Attune turn),
`session_ended`, `window_changed`, and `partner_thinking`.

**In-progress prompt text is never broadcast.** `partner_thinking` is a bare
boolean that goes true only *after* a partner has submitted a turn and while
that turn's provider call is in flight — it is a spinner, not a typing
indicator. It is never set while a partner is composing, and it carries no
content, no length, and no preview. Only committed turns ever appear on the
other partner's device.

### 6.2 Concurrency

Two partners may submit at once. This is the only genuinely concurrent write
path in the feature, so the mechanism is specified rather than implied
(checklist 1.6).

**Shared mutable state:** `ai_sessions.turn_count` and the
`ai_session_turns.ordinal` sequence. Both are mutated by two devices through
one server.

**Mechanism:** the turn-reserving RPC takes a row-level lock —
`SELECT … FROM ai_sessions WHERE id = $1 FOR UPDATE` — then validates the cap,
increments `turn_count`, and returns the reserved `ordinal`, all in one
transaction. The lock is released before the provider call; provider work
never holds a database lock. Ordinal allocation is therefore serialised even
though generation is not.

**Ordering:** each provider call sees exactly the turns committed at the moment
its ordinal was reserved. Two simultaneous submissions both succeed and both
are answered; they may interleave, and the UI renders strictly by `ordinal`,
never by client arrival order.

**Cap under race:** when two partners submit at turns 9 and 10 simultaneously,
the lock guarantees exactly one receives ordinal 20 and the other receives
`SESSION_TURN_LIMIT` before any provider call — so the cap cannot be exceeded
by racing, and the loser is never charged quota.

**Consistency model (checklist 1.9):** read-your-writes for the submitting
partner (the RPC returns their reserved turn synchronously) and eventual for
the other partner (realtime broadcast, typically sub-second). A missed
broadcast is corrected by refetching turns by `session_id` on reconnect and on
sheet foreground; the `ordinal` sequence makes gap detection trivial. The
client treats realtime as an accelerator, never as the source of truth.

**Quota** is charged to each submitting partner independently — there is no
shared pool, so one partner cannot exhaust the other's allowance.

### 6.3 Switching visibility

The opener may switch private → shared. Doing so requires an explicit
confirmation naming what becomes visible:

> Your partner will see this whole session, including the 4 turns you've
> already sent.

Shared → private is **not** offered: the partner has already seen the turns,
so "making it private" would be a false promise. Ending the session and
starting a private one is the supported path.

---

## 7. Schema

```sql
CREATE TABLE public.ai_sessions (
  id uuid PRIMARY KEY,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
    ON DELETE CASCADE,
  created_by uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  visibility text NOT NULL CHECK (visibility IN ('private', 'shared')),
  include_recent_window boolean NOT NULL DEFAULT false,
  turn_count smallint NOT NULL DEFAULT 0 CHECK (turn_count BETWEEN 0 AND 10),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_turn_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  ended_at timestamptz,
  ended_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  CHECK (expires_at = last_turn_at + interval '15 minutes'),
  CHECK ((ended_at IS NULL) = (ended_by IS NULL))
);

CREATE TABLE public.ai_session_turns (
  id uuid PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES public.ai_sessions(id) ON DELETE CASCADE,
  ordinal smallint NOT NULL CHECK (ordinal BETWEEN 1 AND 20),
  role text NOT NULL CHECK (role IN ('user', 'attune')),
  author_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  content text NOT NULL CHECK (
    char_length(btrim(content)) BETWEEN 1 AND 2000
  ),
  turn_payload jsonb,          -- sources + suggested_planning_item, schema_version
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id, ordinal),
  CHECK ((role = 'user') = (author_id IS NOT NULL))
);

CREATE INDEX idx_ai_session_turns_session
  ON public.ai_session_turns (session_id, ordinal);

CREATE INDEX idx_ai_sessions_expiry
  ON public.ai_sessions (expires_at) WHERE ended_at IS NULL;
```

`ordinal` allows 20 because a 10-turn session holds 10 user turns plus 10
Attune turns.

### 7.1 Grants and RLS

Following `20260950020000_ai_assistant_rls.sql` and
`20260950030000_ai_assistant_table_grants.sql`:

```sql
ALTER TABLE public.ai_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_session_turns ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.ai_sessions, public.ai_session_turns
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ai_sessions, public.ai_session_turns TO authenticated;
```

`authenticated` gets **SELECT only**. All writes go through
`SECURITY DEFINER` RPCs owned by the edge function, so a client can never
fabricate a turn, forge an `attune` role, or alter `visibility`.

Read policy: a row is visible when the caller is a member of
`relationship_id` **and** (`visibility = 'shared'` **or**
`created_by = auth.uid()`). A private session is invisible to the partner at
the database level, not by client convention.

### 7.2 Quota

Reuses the base spec §7.3 ledger unchanged: `ai_assistant_usage` gains
`'session'` to its `mode` check. Each **turn** is one reservation against the
same 20-per-rolling-24-hours per-account cap. A 10-turn session therefore
consumes half a partner's daily allowance, which is intentional: it makes the
cost of multi-turn visible rather than hidden.

The turn cap and the quota cap are independent. Hitting quota mid-session
returns `RATE_LIMITED` with `retry_after_seconds`; the session stays open and
the other partner may still contribute.

---

## 8. Interaction with chat safety and analysis

Session turns are **not** messages. They are not inserted into `messages`, do
not fire the message INSERT trigger, do not create safety or notification
outbox work, and are never read by Layer 1/2 analysis, Pulse, or Verdict.

This is the reason the ephemeral decision matters: it keeps the entire
message contract — safety pipeline, `message_analysis_skipped` handling,
export, deletion, retention, edit/delete capability splits — out of scope.

When a turn is **posted to chat**, it uses the existing path with no change:
`share_ai_assist_draft`-shaped RPC, `message_origin = 'attune_assist'`,
`message_analysis_skipped = true`, validated `assistant_payload`, attributed
to the posting partner. The ordinary safety and notification outbox work runs
on that message exactly as today.

### 8.1 Safety inside a session

Session turns bypass the message safety pipeline, so the regex-based
self-harm/abuse net (`process-chat-safety-outbox`) does not see them. A
session is still a place a partner in distress may type.

Therefore the same deterministic detector used by the safety outbox runs
**synchronously** on each user turn before the provider call. On a Tier-3 or
immediate-family match the turn is not sent to the provider; the session shows
Safety Resources, exactly as the manual path does. This reuses the
already-exported `detectImmediateFamilies` and `detectTierThreeRuleIds` from
`supabase/functions/_shared/chat_safety.ts` — the same regex detector the
safety outbox uses. It is not a new classifier and it costs no model call.

---

### 8.2 Engineering contract

Audited against `lib/architecture/algorithms/algorithm_quality_review_checklist.md`
v3.1. Items the base spec already answers are inherited and cited rather than
restated; items this feature introduces are specified here.

#### 8.2.1 Timeouts (checklist 1.2)

Every external call is bounded. A session turn may make two provider calls, so
the per-turn ceiling is stated explicitly rather than left to sum:

| Call | Connect | Read | Total |
|---|---|---|---|
| Gemini (`callGeminiJson`) | 3s | 20s | 25s |
| Mapbox (Nearby only) | 3s | 8s | 10s |
| **Per-turn ceiling** | — | — | **30s** |

Exceeding the ceiling returns `PROVIDER_UNAVAILABLE`. These are configuration
values, not magic numbers in code (checklist 4.11). The 30s ceiling is the
number the client's loading state and the user-facing copy are designed
against.

#### 8.2.2 Failure compensation (checklist 1.10)

A turn is a multi-step mutation: reserve ordinal → reserve quota → call
provider → insert turn → broadcast. Each failure point has a defined outcome,
and the invariant is **never show the partner a charge with no result, and
never leave a reserved ordinal unusable**.

| Fails at | Quota | Ordinal | User sees |
|---|---|---|---|
| Ordinal reservation | Not reserved | Not allocated | `SESSION_TURN_LIMIT` or `SESSION_ENDED` |
| Quota reservation | `RATE_LIMITED` | **Released** — the reserving transaction rolls back | `retry_after_seconds`; session stays open |
| Provider call | **Charged** (cost incurred, per base spec §7.3) | Held, marked failed | `PROVIDER_UNAVAILABLE` + retry; retry uses a **new** `request_id` and a new ordinal |
| Turn insert | Charged | Held, marked failed | Same as provider failure — the compensating action is a visible error, never a silent swallow |
| Broadcast | Charged | Committed | Submitter sees their turn; partner reconciles on reconnect (§6.2) |

There is no partial turn. A turn row is inserted only with complete, validated
content; a failed generation never writes a half-formed row that a later
provider call could read back as context.

Failed ordinals leave gaps in the sequence. This is intentional: gaps are
cheap, and reusing an ordinal would let a retry silently overwrite a committed
turn. `turn_count` counts *reserved* exchanges, so a session with failures
reaches its cap sooner — the cap bounds provider work, not successful replies.

#### 8.2.3 Privacy and retention (checklist 1.11)

PII reaching the provider is bounded by §4.2 and consists only of
conversational content the partners wrote. Never sent to any provider:
profiles, names, user/relationship IDs, presence, location history, safety
state, Planning, prior sessions, or coordinates (Nearby sends coordinates to
Mapbox only, never to Gemini — base spec §5.2).

| Data | Where | Retention |
|---|---|---|
| `ai_sessions` row | Attune DB | Until end, or 15 min idle; purged by the existing job |
| `ai_session_turns` rows | Attune DB | Deleted on session end; purged with the session |
| Prompt + turn content | Gemini | Per provider contract — **gate 2, §14** |
| Coordinates + category | Mapbox | One request, then discarded; never stored by Attune |
| Posted turn | `messages` | Ordinary chat retention |

Telemetry follows the base spec §10.3 allowed/forbidden field list unchanged
(checklist 4.4, P0-U). Sessions add exactly two allowed operational fields:
`session_id` (pseudonymous UUID) and `turn_ordinal`. Session content, prompts,
and the recent-window contents are forbidden in logs, analytics, and Sentry,
and are covered by the same canary-content scrubbing test the base spec
already requires.

#### 8.2.4 Latency and first feedback (checklist 5.2)

A session turn is provider-bound and will exceed 1 second, so the interactive
target is **first feedback within 200ms**, not completion:

- Composer button tap → sheet + scrim rendered: ≤200ms (no network on open,
  §5.1).
- Turn submitted → the partner's own turn rendered and a thinking indicator
  visible: ≤200ms (optimistic local render; the turn is already theirs).
- Turn submitted → `partner_thinking` visible on the other device: best-effort,
  realtime-bound.
- Turn completion: p95 target ≤8s for Ideas, ≤12s for Nearby (two provider
  calls), hard ceiling 30s per §8.2.1.

Progressive rendering of a partial model response is explicitly **not** in v1:
output is validated against the §5.3 schema before display, and streaming
unvalidated text would defeat that validation.

#### 8.2.5 Complexity and cost (checklist 1.8, 1.12)

Context assembly is O(t + w) time and space in turns `t` (≤20) and window
messages `w` (≤6) — both hard-capped, so per-turn work is O(1) with respect to
relationship size and chat history length. No query scans unbounded history:
the window query is `ORDER BY created_at DESC LIMIT 6` against the existing
chat index, and turn loading is a bounded index scan on
`idx_ai_session_turns_session` (checklist 3.3).

Cost per session is at most 10 Gemini calls, plus up to 10 Mapbox calls if
every turn is Nearby. The existing 20-per-24h per-account quota is the binding
cost control; a full 10-turn session consumes half a partner's daily
allowance, which is deliberate — it makes multi-turn cost visible rather than
hidden (§7.2).

#### 8.2.6 Applicability notes

Skips, documented per the checklist's "Skip checks that don't apply" rule:

- **`[FIN]` (2.19–2.23)** — no monetary value. N/A.
- **`[UI-WEB]` (7.6 CSRF/CORS)** — native mobile only; Edge Functions are
  token-authenticated, not cookie-authenticated. N/A.
- **3.12 graceful shutdown, 4.12/4.13 health/readiness** — Supabase Edge
  Functions are platform-managed; not this feature's surface.
- **3.11 circuit breaker (P3)** — deferred. The 20/24h quota already bounds
  blast radius from a degraded provider.
- **6.10 soak / 6.11 load / 6.12 chaos** — deployment-gate items, not design
  items; they belong to the implementation plan's verification phase, and are
  listed in §11 as such.

---

## 9. Client architecture

```
lib/features/ai_assistant/
  data/models/ai_session.dart          # AiSession, AiSessionTurn (sealed)
  data/repositories/…                  # extends AiAssistantRepository
  presentation/providers/
    ai_session_provider.dart           # autoDispose, per-session
  presentation/screens/
    ai_session_sheet.dart              # the sheet over the scrim
  presentation/widgets/
    ai_session_turn_bubble.dart
    ai_session_context_banner.dart     # the visible, revocable window (§4.3)
```

`AiSessionTurn` is its own sealed type. It can produce an `AssistDraft` for
posting; it can never produce or hold an `UnderstandResult`. The provider is
`.autoDispose` and session-scoped, preserving the base spec's guarantee that
no long-lived singleton lets one invocation observe another's result.

`chat_text_field.dart` gains one parameter (`aiMode`) and one satellite
button. No other chat file changes.

---

## 10. Errors

| Code | Meaning | UI |
|---|---|---|
| `SESSION_TURN_LIMIT` | 11th turn | Offer to start a new session |
| `SESSION_ENDED` | Turn submitted after end | Neutral "This session ended." |
| `RATE_LIMITED` | Quota exhausted | `retry_after_seconds`; session stays open |
| `CONSENT_REQUIRED` | Consent withdrawn mid-session | End session, open consent screen |
| `UNSUPPORTED_REQUEST` | Out of scope, unrecoverable | Redirect turn (§1.1) |
| `PROVIDER_UNAVAILABLE` | Gemini/Mapbox timeout or failure | Retry offered; quota already spent |
| `NO_RESULTS` | Nearby returned nothing valid | Offer ideation instead |
| `SAFETY_INTERCEPT` | Deterministic detector matched (§8.1) | Safety Resources; no provider call |

---

## 11. Testing

Checklist references in brackets.

- **SQL:** RLS proves a partner cannot read a private session; `authenticated`
  cannot INSERT/UPDATE either table; purge removes expired sessions and their
  turns.
- **Concurrency [6.3, 1.6]:** two simultaneous turn reservations against the
  same session — assert exactly one ordinal per submitter, no duplicate
  ordinal, cap never exceeded, and the capped-out submitter charged no quota.
  Run repeatedly; flaky is a failure.
- **Edge function:** client-supplied turns rejected; window never exceeds 6
  messages/2,400 characters; window excludes deleted/system/assist messages;
  quota charged per turn; `SAFETY_INTERCEPT` short-circuits before the provider.
- **Failure paths [6.2, 6.4]:** inject provider timeout, provider 5xx, and a
  turn-insert failure. Assert the §8.2.2 table holds — specifically that a
  failed turn writes no partial row and that a retry uses a new ordinal rather
  than overwriting a committed turn. Negative assertion: after a failed
  generation, `ai_session_turns` contains no row for that `request_id`.
- **Boundary [6.1]:** empty instruction, 300-character instruction, 301
  (reject), a single turn exceeding the 6,000-character budget (reject, per
  §4.2), a 2,000-character turn, turn 10 and turn 11, Unicode and
  NFC-normalisation cases, and the same-day boundary at the partners' UTC
  offset.
- **Privacy [4.4]:** a static test asserting no session type exposes an
  Understand result, mirroring the base spec's existing no-write contract test;
  plus canary content in a turn and in the recent window, asserted absent from
  logs, analytics, and Sentry payloads.
- **Widget:** AI mode hides exactly the expected composer controls and restores
  them on exit; the context banner renders the real window and its off state.
- **Adversarial evals:** prompt injection from the recent window; a partner
  attempting to steer the AI to speak *about* the other partner; redirect turns
  never emit partial factual answers.
- **Two-account manual:** shared session visibility, concurrent turns, either
  partner ending, consent withdrawal mid-session.

### 11.1 Deployment-gate verification

Not design-time items; they belong to the implementation plan's final phase
and must be evidenced before the flag is enabled:

- Load behaviour at 2x expected peak session starts [6.11].
- Provider-failure chaos: kill Gemini mid-turn, assert §8.2.2 holds and no
  session is left in an unrecoverable state [6.12].
- Branch coverage thresholds: edge-function logic ≥90%, repository ≥70%,
  widgets ≥50% [6.7].
- Rollback runbook (Tier 2 acceptable): the flag kill-switch plus
  `supabase functions deploy ai-assist@<prev>` , time-to-recovery ≤30 min [8.1].
- Alerts with runbooks for: turn error-rate spike, provider-failure rate,
  quota-rejection rate, and purge-job failure (an unpurged session is a
  retention violation, not just a leak) [4.9, 6.14].

---

## 12. Rejected alternatives

**AI turns as `messages` rows with `thread_kind = 'ai'`.** Free realtime and
persistence, most natural UX. Rejected: every turn inherits the full message
contract (safety, analysis-exclusion, export, retention, deletion, edit
splits). The base spec spent a P0 finding making `message_analysis_skipped`
real everywhere; this multiplies that surface, and it contradicts the
ephemeral decision.

**Two separate stacks — a private client-only scratchpad now, a shared room
later.** Rejected: guarantees two divergent AI stacks, two consent paths, and
two quota accountings.

**Search-grounded factual answering.** Rejected for v1 — see §1.1.

**Unbounded turns.** Rejected: re-opens the cost, injection, and cumulative
disclosure concerns the base spec bounded.

---

## 13. Amendments to the base spec

On adoption, `2026-09-15-ai-assistant-design.md` must be amended, not silently
contradicted:

- §1 — "pull-only" and "never supports follow-up turns" become
  "pull-only **outside sessions**"; sessions are the bounded exception.
- §2 — capability matrix gains the two session columns from §2 here.
- §3 — entry eligibility gains the composer entry.
- §4.3 — context bounds gain the shared-session window.
- §7.2 — schema gains `ai_sessions`/`ai_session_turns`.
- §7.3 — `mode` gains `'session'`.

---

## 14. Gates

The base spec's four hard gates still bind this feature. Verified status as of
2026-09-22 by repository inspection:

| # | Gate | Status | Evidence |
|---|---|---|---|
| 1 | Server-authoritative versioned dual consent + withdrawal | **Built** | `ai_processing_consent_events` + RPCs (`20260950040000`), `ai_consent_screen.dart` |
| 2 | Gemini/Mapbox privacy, retention, no-training, credential, quota, billing, attribution, legal review | **No evidence in repo** | External sign-off; cannot be verified from code |
| 3 | Understand clinical/safety/cultural framing + eval approval | **No evidence in repo** | Code enforces the framing; the approval is external |
| 4 | Global app-switcher privacy cover, real-device verified | **Not implemented** | Referenced only in `SAFETY_SYSTEM_SPEC.md` and other docs; no `FLAG_SECURE`/lifecycle cover in `lib/` |

This feature adds a fifth:

| 5 | Shared-session disclosure review: the §4.3 visible/revocable window and the §6.3 one-way visibility switch reviewed against the product's privacy commitments | **Open** |

**Two findings a reviewer should note about the current repository state,
independent of this design:**

1. **`Ask Attune` is already wired live** in `message_bubble.dart`'s long-press
   menu with no feature flag guarding it, despite the base spec §14.1 requiring
   the flag stay off until all four gates have written evidence. Either the
   gates cleared without being recorded in the repo, or a shipped entry point
   is ahead of its gate. This should be resolved before adding a second,
   more prominent entry point.
2. **The LLM cron jobs are currently paused** (`20260931150000_pause_ai_jobs.sql`;
   the resume migration is `.disabled`). That does not affect these
   user-invoked edge functions, but it means the surrounding analysis pipeline
   is not currently running.

---

## 15. Acceptance criteria

1. A partner can open a session from the composer, send up to 10 turns, and
   post any Attune turn to chat with correct `attune_assist` provenance.
2. A private session is unreadable by the partner at the database level.
3. A shared session shows both partners' committed turns live, shows neither
   partner's in-progress text, and can be ended by either.
4. The recent-chat window never exceeds 6 same-day messages / 2,400 characters,
   is server-selected, is shown in the UI before the first call, and can be
   turned off.
5. Client-supplied prior turns are rejected by the edge function.
6. A Tier-3/immediate-family match intercepts the turn before any provider call
   and surfaces Safety Resources.
7. Session turns never appear in `messages`, analysis, Pulse, or export.
8. Quota is charged per turn against the existing shared 20/24h ledger.
9. An out-of-scope ask returns a redirect turn naming what Attune can do, never
   a partial factual answer.
10. Exiting AI mode restores every dismissed composer control.
