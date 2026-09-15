# Chat AI Assistant — Design

**Status:** proposed, not implemented
**Date:** 2026-09-15

## 1. What this is

A pull-only AI helper reachable from the chat's focused menu (tap-and-hold
a bubble). Unlike the Verdict or the weekly Pulse, it never reads the
chat on its own and never runs in the background — it only sees anything
when a partner explicitly summons it on a specific message. Unlike the
existing Conflict Translator, its output is not always private: it has
two genuinely different modes with two different visibility rules, and
getting that distinction right is most of this spec.

**Assist mode** — "help me plan/find/decide something," triggered on a
message like "where should we go for Val's" or "we need a gift for the
kids." The AI proposes ideas (places, shops, activities) and can offer
to turn the outcome into a Planning item. Its answer is a real message,
visible to both partners, permanently in the transcript — because a
restaurant idea is exactly as useful to the partner who didn't ask as to
the one who did.

**Understand mode** — "help me read this," triggered on a message that
is confusing, terse, or feels loaded ("k." after a good day; "we need to
talk"). The AI reads a short window of recent same-day chat for context
and offers a private read on what might be going on and a way to
respond. This is never shown to the partner, ever — it is a read on
*their* likely feelings, and showing them "the AI told you what I was
probably thinking" is closer to being talked about than talked to.

Both modes are opt-in per tap, cost real money per call (Claude, and for
Assist mode, a places-search API), and are rate-limited accordingly.

## 2. Decisions, and what they rule out

| Decision | Consequence |
|---|---|
| Two modes, two visibility rules — never one blended feature | Assist posts to shared chat; Understand never does. No code path can post Understand's output where a partner can see it. |
| Understand mode never advises about the relationship, only about the message | It explains a plausible reading and phrasing options; it never says "apologize," "he's probably angry," or anything framed as a verdict on someone's feelings or fault |
| Assist mode proposes, never auto-writes to Planning | An "Add to Planning" affordance in the AI's own message; nothing is created until a partner taps it |
| No new location-sharing capability | Assist mode's location need is met by `LocationService.getCurrentLocation()` (the asker's own device, on demand) — `PresenceRepository`'s partner-distance boundary is not touched, extended, or reused |
| Bounded input, always | Assist mode sees the tapped message plus a bounded surrounding window (§3); Understand mode sees the tapped message plus same-day history only — never the full thread, never other days |
| No streaming, no follow-up turns in v1 | One tap, one answer. No "ask a follow-up" chat-with-the-AI thread — that is a materially bigger feature (its own UI, its own context management) not scoped here |
| Attributed to the tapping partner, styled as AI | No new "system" sender concept — the message row's `sender_id` is the person who tapped, `is_system_notice = true` styles it distinctly, matching how Planning's own Goal-completion celebration message already works |
| Access requires an active, unarchived relationship | Both edge functions require `status = 'active' AND chat_archived_at IS NULL` for the caller's relationship — the same predicate Stories and Planning use, stated explicitly here rather than left implicit the way the Conflict Translator's own spec leaves it |
| An Assist-mode message is a real message, not exempt from anything a real message goes through | It flows through the ordinary send path, the safety-detection pipeline, and the existing 5-minute edit/delete window like any message the tapper sent — it is opted out of exactly one thing, downstream AI pattern analysis (§6), and nothing else |

## 3. Assist mode

### 3.1 Trigger and input

A new "Ask Attune" action in the focused menu
(`message_actions_sheet.dart`, alongside Reply/Copy/Star/Pin/Info/Edit/
Delete), available on any non-deleted message. Tapping it opens a small
sheet with two paths:

- **One-tap default** — "Get ideas" — the AI decides what kind of help
  fits, using only the message content.
- **Free-text field** — "What do you need?" — the tapper types a
  specific ask ("gift shops open Sunday," "somewhere with parking"),
  sent alongside the message content.

Either path sends the edge function:

```typescript
{
  message: string,              // the tapped message's content
  surrounding: string[],        // up to 6 messages immediately before/after it,
                                 // same relationship, chronological, content only
  user_instruction: string | null,  // the free-text field, if used
  relationship_id: string,
  requester_location: { lat: number, lng: number } | null,  // §3.3
}
```

`surrounding` exists so "yeah let's do that" three messages later is not
meaningless — it is not a general chat-reading capability. Six is a
deliberately small, stated number: enough for the immediate exchange
around one topic, not enough to reconstruct a day's conversation. The
edge function must reject a request whose `surrounding` array exceeds
six entries rather than silently truncating it, so a client bug that
sends more cannot quietly expand what this mode is allowed to see.

### 3.2 Response shape and the chat message

```typescript
// Success
{
  reply_text: string,          // the message body, ready to post as-is
  suggested_planning_item: {
    kind: 'task' | 'event',
    title: string,
    event_date: string | null, // ISO date, only when kind = 'event'
  } | null,
  sources: Array<{ name: string; distance_label: string | null }>,  // §3.3
}

// Error
{
  error: true,
  code: 'TIMEOUT' | 'INVALID_INPUT' | 'RATE_LIMITED' | 'LOCATION_UNAVAILABLE' | 'INTERNAL_ERROR',
  message: string,
}
```

On success, the client inserts one `messages` row: `sender_id` = the
tapping partner, `content` = `reply_text`, `is_system_notice = true`,
`message_analysis_skipped = true`, `source = 'native'` — the same shape
Planning's own Goal-completion notice already uses, so no new message
type needs inventing and the existing system-notice rendering in
`message_bubble.dart` covers it. `message_bubble.dart` gains one new
visual treatment: an "Attune" label and icon on a system-notice message
whose content did not come from `reconcile_planning_goal`'s own
celebration text, distinguishing "your partner completed a goal" from
"the AI suggested something," which currently look identical.

If `suggested_planning_item` is present, the message renders an inline
"Add to Planning" affordance (title + date shown, tap to confirm) below
the reply text — this is the ONLY way a Planning row can be created from
this feature. Tapping it calls Planning's own `create_planning_task` or
`upsert_planning_event` RPC directly with the suggested values,
pre-filled and editable before the actual create call, using Planning's
existing create-flow screens (`create_planning_task_screen.dart` /
`create_planning_event_screen.dart`) rather than a bespoke inline
form — this feature is a caller of Planning, not a second way to write
to it.

### 3.3 Location and real-world results

The AI does not invent restaurant or shop names from training knowledge
alone — general "a rooftop restaurant" ideas with no way to verify they
exist are worse than useless in a shared chat message, and this is the
one place in the app where an AI answer could be confidently wrong about
something checkable. `requester_location` is obtained via
`LocationService.getCurrentLocation()` — the ALREADY-EXISTING,
general-purpose location service, unconnected to `PresenceRepository`'s
partner-distance feature — at the moment "Get ideas" or the free-text
ask is submitted. Standard one-time permission prompt if not already
granted; never stored, never associated with the message row, discarded
after the request completes.

The edge function performs a **places search** (not a raw Claude
web-knowledge answer) via Mapbox's Search Box API — Mapbox is already a
paid project dependency (`mapbox_maps_flutter`), currently used only for
map rendering and `LocationService`'s address geocoding, not POI/category
search, so this is genuinely new integration work, called out here so
it is planned rather than discovered. Claude's role is to turn the
tapped message + instruction into a search category/query ("date-night
restaurant," "toy shop," "cooking class"), and to turn the places
results into a short, specific reply — never to generate place names
itself. `sources` in the response is the places-search result set the
reply text was built from, kept so the reply can cite exactly what it
found rather than a caller having to trust an unsourced list — the same
"every claim is sourced" discipline `ATTUNE_SOUL.md` holds Verdict to.

If location is unavailable or refused, the edge function returns
`LOCATION_UNAVAILABLE` for any request Claude classifies as needing a
real-world place; the client shows "Attune needs your location to find
places nearby" rather than falling back to an unsourced, possibly-wrong
answer. A request that is not place-shaped (e.g. "what should we name
the dog") does not require location and proceeds without it — the
classification of "does this need a place" happens server-side, in the
same Claude call that decides the reply, not as a separate client-side
heuristic guessing from keywords.

## 4. Understand mode

### 4.1 Trigger, input, and the hard rule

The same "Ask Attune" action offers a second path when the tapped
message reads as ambiguous, terse, or emotionally loaded rather than
informational — the sheet shows "Help me understand this" alongside "Get
ideas" and lets the tapper pick, rather than the AI silently choosing a
mode on the tapper's behalf. (An automatic mode-guess is tempting but
wrong here: the tapper knows whether they want ideas or clarity far
better than a keyword heuristic does, and misrouting a place-idea
request into an emotional read — or the reverse — is the kind of
mistake this feature cannot afford in either direction.)

Request:

```typescript
{
  message: string,               // the tapped message
  same_day_history: string[],    // every message from the SAME sender_id-blind
                                  // day, chronological, content only — never
                                  // other days, never a fixed count
  relationship_id: string,
  requester_id: string,          // derived from auth.uid() server-side, not
                                  // trusted from the client
}
```

`same_day_history` is bounded by calendar day, not by count — a quiet
day with three messages sends three; a busy day sends more, up to a hard
server-side cap of 200 messages (a defensive ceiling against an
unusually long day, not a design target). This is wider than Assist
mode's six-message window because understanding a terse reply genuinely
needs the day's arc ("good morning," "rough meeting," "k." reads
differently after those two messages than cold) — but it is still
bounded to one day, never a rolling window, never prior days, and never
persisted or logged with content.

**The hard rule, stated once and binding everywhere in this mode:** the
response is never inserted as a `messages` row, is never associated with
the conversation's permanent history in any form, and is discarded from
the client the moment the sheet is dismissed. It exists only in the
requesting partner's own screen, for as long as they are looking at it —
this means in-memory state, never written to disk, never cached by the
repository layer the way a normal read result would be.

Whatever Riverpod provider holds the in-flight/completed response must
be `.autoDispose` (this codebase's established convention — see
Stories' and Planning's own reel/pager providers — for "this state must
not outlive the screen that owns it"), scoped no wider than the sheet's
own widget subtree, and never promoted to a `keepAlive` or
relationship-scoped provider the way Planning's list providers
deliberately are. A backgrounded app that later resumes to a
`.autoDispose` provider whose widget was already disposed gets a fresh,
empty state — not a stale private result reappearing.

**What this does not defend against, stated plainly rather than left
implicit: a screenshot of the sheet itself.** This app has one existing
screenshot-detection mechanism (`20260816140000_chat_screenshot_notice.sql`),
and it is scoped narrowly to ephemeral video playback — it has no general
capability to detect a screenshot of an arbitrary screen, and building
one is not this feature's scope. A partner who reads their private
Understand-mode result and screenshots it has a record their partner
will never see through the app, the same residual risk every "private to
one device" feature in this codebase already accepts (a screenshot of
the Conflict Translator's own private rewrite sheet is equally
undetected today). Naming this here is deliberate: an implementer should
not assume screenshot protection exists just because the content is
sensitive, and should not scope-creep this feature into building
general screenshot detection to compensate.

### 4.2 Response shape and what it may say

```typescript
// Success
{
  likely_context: string,     // one or two sentences, describing a PLAUSIBLE
                               // reading, never asserted as fact
  response_options: string[], // 2-3 short, concrete things the tapper could
                               // say or do next — never a single prescribed answer
  confidence: 'high' | 'medium' | 'low',
}

// Error: same shape as §3.2, minus LOCATION_UNAVAILABLE
```

Two things are enforced in the prompt design and must be treated as
acceptance criteria, not style guidance:

- **`likely_context` never assigns blame, never states a partner's
  feelings as fact, and never tells the tapper what they did wrong.**
  "This may read as frustration about feeling unheard" is in scope.
  "He's upset because you didn't call" is not — it asserts a specific
  cause as true, about a real person who has no visibility into this
  conversation happening at all. The distinction is the same one the
  Verdict already holds itself to (cites evidence, never verdicts on the
  relationship) applied to a single message instead of months of data.
- **`response_options` are never a single instruction.** At least two
  genuinely different options, phrased as things the tapper could choose
  among — never "you should apologize," always something closer to "you
  could name what's going on for you," "you could ask what's on their
  mind," "you could give it some space and check in later." The model is
  offered a way forward, not told the way forward.

This is closer to a *reading comprehension and phrasing* tool than an
emotional-advice tool, and the prompt must be built and reviewed with
that framing — the same posture the Conflict Translator already holds
for the sender's own words, applied here to reading the partner's.

## 5. Edge function architecture

Two functions, following the Conflict Translator's own pattern
(`CONFLICT_TRANSLATOR.md` §5) exactly — server-side only, versioned
prompts, no client-side API key:

- `supabase/functions/ai-assist/index.ts` — §3, calls Claude then Mapbox
  Search Box (or Mapbox then Claude, whichever the implementation plan
  finds cheaper/faster in practice — not a product decision, an
  engineering one to make when building it).
- `supabase/functions/ai-understand/index.ts` — §4, calls Claude only.

Both load their prompt templates from `/prompts/v1/`, matching the
Conflict Translator's own versioning discipline (`CONFLICT_TRANSLATOR.md`
§5.1) rather than embedding an unversioned one-off prompt either
function could drift from silently.

Rate limits, stated explicitly rather than left to whatever a shared
default happens to be: **20 calls per user per rolling 24 hours across
both modes combined.** A single shared limit rather than two separate
ones, because a user who exhausts either mode by spamming the other
still needs the same underlying protection (Claude cost, Mapbox cost, and
this feature's own abuse surface). A `RATE_LIMITED` response is a normal,
expected outcome the client shows plainly ("You've used Ask Attune a lot
today — try again tomorrow"), not an error state to hide.

## 6. Security and privacy

- **No new grant on `messages` beyond what Planning's celebration
  message already required.** The Assist-mode message insert goes
  through the ordinary client insert path (`sender_id = auth.uid()`),
  not a `SECURITY DEFINER` RPC — there is no server-owned field here an
  RPC needs to protect, the same reasoning that keeps Planning's own
  tables client-writable-via-RPC-only but does NOT extend to `messages`
  itself, which already has its own established grant/trigger shape
  (`CHAT_SYSTEM_SPEC.md`).
- **Understand mode's request never touches the database at all** beyond
  the edge function's own membership check (the caller must be an active
  member of the relationship, same predicate every other feature in this
  codebase uses) and reading the day's messages to build the prompt. No
  table stores an Understand-mode request or response, ever — logging
  for the rate limiter counts calls, never content.
- **`requester_location` is transport-only.** It reaches the edge
  function in the request body, is used for one Mapbox call, and is
  never written to any table, log, or the `messages` row it eventually
  produces.
- **Assist mode's edge function must verify `relationship_id` membership
  server-side** the same way Understand mode does — the client cannot be
  trusted to only ever send its own relationship's id, matching every
  other RPC/edge-function boundary in this codebase.
- **Both functions require the caller's relationship to be `status =
  'active' AND chat_archived_at IS NULL`**, checked server-side on every
  call, not only at the point the focused menu happens to render the
  action. A relationship that ends mid-request must fail the call, not
  succeed on a stale client-side check.
- **An Assist-mode message insert does NOT bypass the safety-detection
  pipeline.** `SAFETY_SYSTEM_SPEC.md` §2.1 creates a durable safety job
  for "authenticated sender submits message," transactionally, with no
  carve-out by message source — an Assist-mode insert has a real
  `sender_id` and goes through the exact same insert path any other
  message does, so it is evaluated the same way. This is deliberate, not
  an oversight to patch: there is no principled reason an AI-authored
  reply should be exempt from the same deterministic safety scan a
  human-authored one gets, and building a bypass would be strictly worse
  than doing nothing here.
- **It IS exempt from one specific downstream step: Layer 1/2 AI pattern
  analysis** (`message_analysis_skipped = true`), the same flag
  Planning's celebration message already sets. This matters here more
  than it did for Planning: if Verdict or Pulse's pattern analysis
  ingested an Assist-mode message as if a partner wrote it from scratch,
  it would misread the couple's own communication patterns — a
  restaurant suggestion is not a data point about how this couple
  communicates. `message_analysis_skipped` is what keeps this feature's
  output from contaminating the very system the app's core insight
  engine is built on. The safety detector operates independently of this
  flag (`SAFETY_SYSTEM_SPEC.md` §2.3, "safety processing does not call
  or wait for Claude" and is never gated on the analysis-skip flag), so
  turning off pattern analysis does not turn off safety scanning.
- **Both edge functions enforce a strict JSON response contract** (§3.2,
  §4.2) as the primary mitigation against prompt injection via the
  free-text instruction field or a message crafted to manipulate the
  model — the same mitigation `ATTUNE_MASTER_SPEC.md` names for its own
  chat-analysis pipeline ("Output is valid analysis JSON, not injected
  instructions"). A response that does not parse as the declared shape
  is treated as `INTERNAL_ERROR`, never partially trusted or passed
  through to the chat message unvalidated.
- **Editing an Assist-mode message after it posts is a real, accepted
  edge case, not a gap to close.** `canEditOrDelete` (unmodified) already
  makes this the tapper's own message for 5 minutes, same as anything
  they typed — so they can edit the AI's generated text into something
  else entirely, and the edited version carries no marker that it
  diverged from what was actually generated. This is accepted rather
  than special-cased: building a "locked, AI-authored, uneditable"
  message type would be new message-model surface for one feature, and
  the existing edit affordance already assumes whoever edits a message
  is accountable for what it now says — true here too.

## 7. What this does not do, and why

**No AI-initiated messages, ever.** Every response in this spec exists
because a partner tapped something. There is no scheduled job, no
"noticed you two haven't talked about the trip in a while," nothing that
looks like the AI deciding to speak. That is what "reads quietly, never
interrupting" (`ATTUNE_THESIS.md`) means, and this feature's pull-only
design is what keeps it inside that rule despite being a much more
active tool than the Verdict.

**No conversation with the AI.** One tap, one answer, no follow-up turns,
no "tell me more." A multi-turn assistant is a real, separable feature
with its own context-window and cost implications — naming it here would
smuggle in a decision this spec was never asked to make.

**No auto-detection of "this message needs help."** The AI never
suggests itself. There is no badge, no highlight, no "this looks like a
hard message, want help?" prompt on any bubble — matching the Conflict
Translator's own "never a push, never a suggestion" rule exactly
(`CONFLICT_TRANSLATOR.md` §2.2), extended here to a feature that touches
both the sender's and the recipient's messages.

**No general web search or open-ended question-answering.** Assist mode
is scoped to place-shaped requests (somewhere to go, something to buy);
it is not a general knowledge assistant embedded in chat. A message like
"what's the capital of France" tapped for "Get ideas" should get a
graceful "I'm best at finding places and ideas nearby" rather than an
attempt to answer everything.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Understand mode's read is shown to the wrong partner or leaks into shared chat | Never inserted as a `messages` row, never persisted anywhere, discarded on sheet dismissal (§4.1) |
| Understand mode states a partner's feelings as fact, or assigns blame | Prompt-level rule, treated as an acceptance criterion: never assert cause, always "may read as," never a single prescribed response (§4.2) |
| Assist mode invents a restaurant/shop that doesn't exist or is closed | Claude never generates place names; a real Mapbox places search is the only source, and results are cited (§3.3) |
| A partner's location leaks via this feature | `requester_location` is transport-only, never persisted (§6); reuses no part of the partner-distance-sharing boundary |
| Planning gets silently populated with something a couple didn't actually want | Propose-only — nothing is created until a partner taps "Add to Planning" and confirms through Planning's own existing create screens (§3.2) |
| A misrouted mode (Understand request answered as Assist, or vice versa) produces a harmful mismatch | Mode is an explicit tapper choice, never an automatic classification (§4.1) |
| Cost/abuse from repeated taps | A single 20-calls/24h limit across both modes, server-enforced (§5) |
| An "Attune" message is mistaken for something either partner actually said | Distinct visual treatment beyond the existing system-notice style — an explicit "Attune" label/icon, not reused from Planning's celebration message styling (§3.2) |
| An Assist-mode message silently contaminates Verdict/Pulse's read of the couple's own communication patterns | `message_analysis_skipped = true` opts it out of Layer 1/2 AI pattern analysis specifically — it is not exempt from anything else, including safety scanning (§6) |
| The free-text instruction field is used to manipulate the model (prompt injection) into an off-scope or unsafe response | Both edge functions enforce a strict JSON response contract; a non-conforming response is `INTERNAL_ERROR`, never passed through (§6) |
| A partner keeps using this feature after the relationship ends or the chat is archived | Both edge functions require `status = 'active' AND chat_archived_at IS NULL`, checked server-side on every call (§2) |

## 9. Testing

| Area | What must be covered |
|---|---|
| Mode selection | Tapping "Get ideas" vs "Help me understand this" always routes to the matching edge function; no keyword-based auto-routing exists anywhere in the client |
| Assist message insert | The posted message has `is_system_notice = true`, the correct `sender_id` (the tapper, not a synthetic system user), and renders with the distinct "Attune" treatment, not the Planning-celebration treatment |
| Planning proposal | "Add to Planning" pre-fills but does not create until confirmed through the real create screen; declining leaves no trace in Planning |
| Understand mode persistence | No database row, log line, or client-side cache retains Understand-mode content after the sheet is dismissed — verified by inspecting what a session actually wrote, not by reading the intent from the code |
| Location | `requester_location` is never present in the `messages` row, any log, or persisted client state; a refused/unavailable location produces `LOCATION_UNAVAILABLE` for a place-shaped request and does not silently answer without it |
| Bounds | `surrounding` (Assist) rejects more than 6 entries; `same_day_history` (Understand) rejects messages outside the calendar day and enforces the 200-message ceiling |
| Rate limiting | The 20/24h limit is shared across both modes and enforced server-side; a client that races two calls cannot exceed it |
| Prompt acceptance criteria | A held-out set of test messages for Understand mode is graded against "never asserts cause as fact" and "never a single prescribed response" — this is a content-quality gate, not just a schema-shape test, and needs human review before ship, not just automated assertions |
| Safety and analysis interaction | An Assist-mode message inserted through the real send path creates a safety job exactly as any other message would (verified against a live safety-detector fixture, not assumed from the insert path's shape); the same message is excluded from Layer 1/2 analysis session consumption |
| Post-end/archive access | A call to either edge function against a relationship that is `status != 'active'` or `chat_archived_at IS NOT NULL` fails, verified directly against both functions, not only against the client's own gating |
| Malformed model output | A response that does not conform to the declared JSON contract is treated as `INTERNAL_ERROR` client-side, never partially rendered or passed through as message content |

## 10. Implementation order

1. **Edge functions and prompts** — `ai-assist` and `ai-understand`,
   versioned prompts, rate limiting, membership checks. Testable against
   the edge function directly before any client work exists.
2. **Assist mode client** — the focused-menu action, the two-path sheet,
   the message insert and its new "Attune" visual treatment.
3. **Mapbox Search Box integration** — new work, not an extension of
   existing geocoding; its own error handling for "no results nearby."
4. **Planning proposal wiring** — the inline "Add to Planning"
   affordance, calling Planning's existing create screens/RPCs (depends
   on Planning being built — see `PLANNING.md`).
5. **Understand mode client** — the second sheet path, its ephemeral
   private display, explicit non-persistence.
6. **Prompt review and acceptance testing** — the held-out message set
   from §9, human-reviewed against the never-blame/never-prescribe rules
   before this ships to anyone.

## 11. Open questions

- **Exact wording for the "Add to Planning" confirmation and the
  Understand-mode response-options phrasing.** Copywriting detail for
  the implementation plan, not locked here — but whatever ships must
  pass the same review this spec's own §4.2 rules describe.
- **Whether Assist mode should also handle "no results found nearby"
  gracefully with a wider-radius retry**, or simply say so and stop.
  Left as an implementation-plan decision; either is safe, this spec
  does not need to pick.
- **Whether the 20-calls/24h limit is the right number.** Stated
  explicitly so it is a real, changeable constant rather than an
  implicit default, not because 20 is empirically justified yet — revisit
  once real usage exists.
