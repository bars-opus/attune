# Simulated Chat Conversation — For Testing Message Analysis & Pulse

Date: 2026-08-14
**Updated 2026-08-13: chat → Pulse is now connected.** See the update note
below before relying on anything in the original "disconnected pipelines"
section, which is kept for its still-accurate Track A mechanics.

## Update (2026-08-13): chat now feeds Pulse — with conditions

The `chat-pulse-integration` feature (commits `a54e6621`..`2255acaa`) shipped
and merged to `main`. The framing below this note — "chat messages do NOT
currently feed the Pulse score" — **is no longer true as written**. What
changed and what still gates it:

- `compute-pulse` now reads a 30-day chat signal aggregate (tone, NVC
  violations, bids, escalation, repair attempts/landed, stonewalling,
  pursue-withdraw) via a new RPC and blends it into Communication,
  Connection, Conflict Health, and Emotional Safety. **Alignment is
  deliberately untouched by chat** — it only moves via check-ins and the
  attachment quiz, same as before.
- Chat's influence ramps in gradually, not on/off: `chatWeight` is 0 below
  ~7.5 days of coverage since the first analysed message, ramping linearly
  to full weight at ~22.5 days. **A single day of test messages will not
  move the score by chat alone** — the same real-time delay applies as
  before, just via a different mechanism (coverage ramp instead of "not
  built").
- Even at full weight, chat is a *secondary* signal on Conflict Health
  specifically — it's blended at 0.8 weight, subordinate to mood/check-in
  data at weight 1.0, not a replacement for it.
- **This requires the migration to be applied to the live Supabase project
  first** (`supabase/migrations/20260830120000_chat_pulse_signals.sql`,
  applied via `supabase db push --linked`) and the `analyse-session-sweep`
  cron actually registered and firing — both still unverified against the
  live project as of this writing (sandboxed dev environment has no live
  DB access). If you haven't confirmed that migration is live, treat this
  doc's original framing as still operationally true for now: assume chat
  won't move Pulse until someone confirms the migration is applied.

Given the ramp, **Track A below is still the right tool for "does message
analysis work correctly right now"** (tone/NVC/bid/escalation detection,
visible within seconds to 30+ minutes). It is no longer the right tool for
"does chat move Pulse today" — that requires ~1-3 weeks of real message
history post-migration, not a single simulated conversation. Track B
remains the fastest way to move Pulse in one sitting.

## Original framing (2026-08-14, kept for Track A mechanics — see update above)

Before sending anything, the important finding from checking the actual
code (`analyse-message`, `analyse-session`, `compute-pulse` edge
functions), **as of before the update above**:

- If your goal is **"see the Pulse score move today, in one sitting,"**
  chat messages alone — however realistic — still will not do it (the
  coverage ramp requires real elapsed time). You need Timeline events (a
  logged `conflict`/`milestone`/`highlight`) and/or a submitted weekly
  check-in. See Track B below.
- If your goal is **"exercise the AI message/session analysis pipeline
  and see it correctly detect tone, NVC violations, bids, escalation,
  repair attempts,"** chat messages are exactly the right lever — that
  pipeline is real, runs automatically on every message you send, and
  writes detectable results to the database. See Track A below.

Do both if you want the full picture. Track A's detection results feed
Pulse eventually (over the coverage ramp, once the migration is live);
Track B's check-in/timeline entries move Pulse immediately and don't
touch chat analysis at all.

---

## Track A: Chat messages — exercises `analyse-message` + `analyse-session`

### How this actually triggers (no flags needed, one manual step required)

Sending a message through the normal chat send flow automatically:
1. Queues a safety scan (`process-chat-safety-outbox`) — runs in seconds.
2. Once the safety scan completes, automatically fires `analyse-message`
   (Layer 1) on that message — writes `tone_score`, `nvc_violations`,
   `bid_type` onto the `messages` row. This happens per-message,
   automatically, no waiting required beyond a few seconds.

**Session-level analysis (`analyse-session`) is NOT automatically
triggered by anything** — there's no cron wired up for it in this
codebase. It only runs when something explicitly calls it, and even then
it only picks up a burst of messages once **30+ minutes of silence**
have passed since the last message in that burst (`SESSION_GAP_MS`). So
after sending the conversation below:
- Either wait 30+ real minutes after your last message before expecting
  session-level results (escalation score, repair-attempt detection,
  pursue/withdraw pattern) to appear, **or**
- Ask me to manually invoke `analyse-session` afterward (I can do this
  once you've sent everything — just say so).

### The conversation (send in order, alternating both partner accounts)

This is written as one continuous "session" — a realistic arc from
warm/light, through a real friction point with genuine NVC-flavored
language, into stonewalling/one-sided replies, then an explicit repair
that lands. Each line is tagged with what it's aiming to trigger, so you
know what to look for afterward — don't paste the tags into the chat
itself, obviously.

```
[Partner A] Hey, how'd the thing with your sister go today?
    → aims for: bid_type: toward (question, genuine interest)

[Partner B] It went okay actually! She apologized for last week.
    → aims for: sentiment: positive, tone_score positive

[Partner A] That's really good. I know that's been weighing on you.
    → aims for: bid_type: toward (acknowledgment, warmth)

[Partner B] Yeah. Anyway did you remember to pay the electricity bill?
    → neutral pivot, sets up the friction below

[Partner A] No, I forgot, I've been slammed today
    → sentiment: neutral-to-negative (mild defensiveness begins)

[Partner B] You always forget stuff like this. I always end up having to
handle it.
    → aims for: nvc_violations: you_always_never
    → aims for: sentiment: negative/charged
    → aims for: bid_type: against (on A's prior warmth)

[Partner A] Wow, okay. I said I was busy, I didn't say I'd never do it.
    → sentiment: negative, defensive tone_score

[Partner B] Whatever. It's fine. I'll just do it myself like always.
    → aims for: nvc_violations: contempt ("whatever," dismissive)
    → aims for: escalation_score contribution at session level

[Partner A] Can we not do this right now
    → short, closed reply — sets up stonewalling signal

[Partner B] Sure. Fine.
    → one more short/closed reply

[Partner A] ...
    → very short/minimal — aims for: stonewalling_signals: true,
      pursue_withdraw_detected: true (A withdrawing here)

[15-30+ min gap — real or backdated — before the next message, so the
 burst above can close as its own session and the repair below can
 optionally be its own follow-up session, or keep it in the same burst
 if you don't want a gap]

[Partner B] Hey. I'm sorry, that came out harsher than I meant it. I know
you had a lot going on today.
    → aims for: repair_attempted: true, sentiment shifts positive

[Partner A] Thank you for saying that. I'm sorry too, I got defensive
instead of just saying I'd get to it tonight.
    → aims for: repair_landed: true, session_resolved: true

[Partner B] I'll pay it tonight together with you if you want, so it's
not just on either of us.
    → aims for: bid_type: toward, root_need_detected: fairness

[Partner A] I'd like that. Love you.
    → clean positive close, sentiment: positive
```

### What to check afterward

- Individual message rows: each should have `message_analysis_done =
  true`, `tone_score`, `nvc_violations` (array), `bid_type` populated
  within a few seconds of sending.
- Once a session is finalized (30+ min gap elapsed + `analyse-session`
  invoked): the `analysis_sessions` row for this burst should show
  `escalation_trajectory` rising-then-falling, `stonewalling_signals:
  true`, `pursue_withdraw_detected: true`, `repair_attempted: true`,
  `repair_landed: true`, `session_resolved: true`,
  `root_need_detected: "fairness"` (or similar).
- Do **not** expect anything on the Pulse screen to change from this —
  per the finding above, that's Track B's job.

### Optional: also test the safety pipeline (separate from Pulse entirely)

Not requested, flagging only so you don't accidentally trigger it while
improvising additional lines: the DV/coercive-control safety scanner
(`chat_safety.ts`) does literal phrase matching, e.g. "you don't need
them," "if you leave" (3x within 30 days), "kill you." These are
unrelated to Pulse or the NVC/tone pipeline — a completely separate
system (`safety_events` table). Avoid these phrases unless you
specifically want to test that system too, which is out of scope here.

---

## Track B: Timeline events + check-in — actually moves the Pulse score

`compute-pulse`'s algorithm (from `PULSE.md` §4.3, confirmed still
matching the live edge function):

- **Communication**: baseline 50, check-in-driven, minus 3 per conflict
  event (30d), plus 5 per conflict with mood_score ≥7 after.
- **Connection**: baseline 50, +8 per milestone/highlight (30d), +15 for
  an anniversary this week, blended with check-in.
- **Conflict Health**: baseline 70 (optimistic — no conflict logged means
  neutral), becomes `avg_conflict_mood × 10` once a conflict exists.
- **Alignment**: baseline 50, +20 if both partners completed the
  attachment quiz, blended with check-in.
- **Emotional Safety**: baseline 50, becomes `avg_mood_all_events × 10`.

To see the score move within one recompute cycle, log real Timeline
events with real `mood_score` values — through the app's own "Log a
moment" flow (Timeline tab), not raw inserts, so the moment also shows up
correctly in Upcoming/dedup/etc. Suggested minimal set to touch every
dimension at least once:

1. **A `milestone`**, mood_score 8 — e.g. "Talked through the electricity
   bill thing and actually resolved it," dated today. Moves Connection
   up, Emotional Safety up slightly.
2. **A `conflict`**, mood_score 7 (resolved-well signal, not a raw
   unresolved conflict) — e.g. "Disagreement about forgetting a bill,
   talked it out same day." Moves Conflict Health up (mood≥7 branch),
   Communication down slightly then partially offset by the
   resolution bonus.
3. **A `highlight`**, mood_score 9 — e.g. "She said something that made
   me laugh so hard I cried." Moves Connection up again.

Then, if both partners submit the **weekly check-in** (Pulse tab → the
check-in banner/entry point), every dimension gets a direct 1-10
self-report blended in — this is the fastest way to move all five
dimensions in one shot without waiting on the 30-day rolling windows the
event-based math uses.

**Recompute timing**: Pulse recomputes automatically every Sunday, or
immediately once BOTH partners have submitted that week's check-in
(`PULSE.md` §6, "After submission"), or on-demand via the `[Refresh]`
button on the Pulse screen (rate-limited to once per 24h,
`recomputePulseProvider`). Logging Timeline events alone does not trigger
an immediate recompute — you'd need the refresh button, both check-ins,
or to wait for Sunday.
