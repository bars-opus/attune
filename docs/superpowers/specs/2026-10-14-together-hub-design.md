# Together — the couple's life hub (Timeline rethink): Design

**Status:** design approved in conversation (2026-10-14); awaiting written-spec review
**Replaces:** the Timeline + Calendar screen from `2026-08-28-timeline-reminders-calendar-merge-design.md`. Its invariants that survive are restated here.
**Builds on:** Planning v2 (`2026-10-12-planning-v2-design.md`). Its date polls, countdowns, member time zones and push rules are reused, not duplicated.
**Quality bar:** each phase's own spec section must pass *Algorithm Quality Review Checklist v3.1* (`lib/architecture/algorithms/algorithm_quality_review_checklist.md`).

---

## 1. What this is

Today's Timeline is a month calendar, a moments log and an "Upcoming" reminders list. It sits as tab 2 of Planning's "Couples Journal", and the "Map" tab is a duplicate of it. It records things but does little to help a couple plan together, stay close or remember well.

**Together** replaces it as the couple's own primary destination. It is one place that does three jobs, in this order on screen:

1. **Plan together.** Today and this week, both partners' plans, proposals ("Fri or Sat?"), who is holding what, and the times both are free.
2. **Connect.** Flexible rituals (date night, a weekly check-in, the long-distance weekly call) and the "big day" care loop.
3. **Remember.** The story: moments, "On this day", and memories that grow out of the plans the couple actually lived.

### 1.1 Why this shape (research, 2026-10-14)

- **Market gap.** Logistics calendars (Cupla, TimeTree, Howbout) contain no relationship science. Bonding apps (Paired, Agapé, Evergreen) have no real calendar; Paired even recommends other people's calendar apps. Nobody joins the two.
- **What users praise:**
  - seeing both partners' existing calendars together, with free time found automatically (Cupla, Howbout);
  - reunion countdowns, and a time-zone-aware free-slot finder (Howbout, the strongest long-distance feature found);
  - a chat thread on each event;
  - a timeline that fills itself as dates are completed (Lovewick).
- **What users complain about:**
  - basics behind a paywall;
  - notification fatigue;
  - streak guilt;
  - the app becoming one partner's "system" that the other never touches;
  - nudges that feel controlling;
  - losing history after re-pairing.
- **Relationship science:**
  - Gottman: rituals of connection, turning toward bids (86% vs 33%), love maps, and the "magic 6 hours" a week, including a weekly date and a weekly State of the Union;
  - Aron: shared novelty raises satisfaction;
  - Gable: responding well to a partner's good news predicts relationship quality;
  - gratitude (Algoe; Gordon 2012);
  - long distance: fewer but longer, more open interactions;
  - Fair Play / Daminger: the invisible work of noticing and planning, which ownership from idea to done makes visible.

### 1.2 Simulated couples (design inputs)

| Couple | Situation | What it forced into the design |
|---|---|---|
| Priya & Dev | Living together, two jobs | Free-window chip → AI idea → proposal; handing an owner to the partner must be a proposal, not an assignment |
| Ana & Luca | Long distance, Toronto–London, 6 hours apart | All-day items keyed by calendar date; timed items in the viewer's zone with the partner's zone underneath; digest and care cards at each person's own local time; reunion countdown |
| Jay & Mia | Dating, separate homes, busy jobs | Overlay off for both still works; private surprise events; a 3-step empty state for new couples; quiet expiry of unanswered proposals |
| Sofia & Marco | Parents of two | Events tagged to a family member; unowned items shown to both; the busy-strip view needs the owner's own second toggle |

---

## 2. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | One hub doing all three jobs. Plan sits on top, Connect is woven in, Remember underneath | Owner choice; the market gap is exactly this combination |
| D2 | Name **Together**, route `/together`; `/timeline` redirects | Reads well for every couple type ("Together tonight 7–9", "12 days until together") |
| D3 | Its own primary destination. Until the 5-tab shell lands, a single "Together" card in Conversations is the entry point; Planning's Calendar tab becomes an "Open Together" row and the duplicate Map tab is removed | The shell today has only Opinions and Chat (`lib/home/home_screen.dart`); don't rebuild the shell for this |
| D4 | Supabase is the single source of truth. External calendars receive (add-to-calendar, per-user ICS feed) and can lend busy time (opt-in overlay); they never own data. The Google Calendar API is deferred | Two-way sync is fragile; avoiding Google OAuth review; works for mixed iPhone/Android couples |
| D5 | Overlay default is **free windows only**. Seeing the other partner's busy strips needs a second toggle, set by the person whose blocks they are | Hardest arrangement to misuse for monitoring |
| D6 | AI suggests; the affected person confirms. No relationship interpretation; care-loop wording is fixed templates, never AI-written | ATTUNE_SOUL; permanent constraint 8 |
| D7 | Ownership: one owner avatar per item; unowned items are visible to both; giving an item to the partner is a proposal; **no tallies, ever** | Makes invisible work visible without a scoreboard |
| D8 | Rituals are flexible (the app proposes a slot each week and both confirm). Skipping has no consequence. **No counters of any kind** | PULSE.md and SOUL forbid streaks; research on streak guilt |
| D9 | Push budget: at most one *scheduled* Together push per user per day. When a care card, digest and reminder fall on the same local day, they merge into that one push. The only other pushes are partner-initiated: a proposal sent to you, a reply to your proposal, and a new anniversary or milestone moment. Everything else appears in the app in real time | Notification-fatigue research; REMINDERS.md "never a barrage" |
| D10 | A private conflict moment still feeds its logger's own Pulse, but never reaches the partner, their feed or their verdict evidence | Pulse is self-facing; constraint 2 |
| D11 | The existing `timeline_events`, Planning v2 and Stories stay where they are. Together reads them through one read function. New concepts get a new `couple_events` table | `timeline_events` feeds compute-pulse and generate-verdict; moving it is pure regression risk |
| D12 | Old `reminders` rows keep working through the read function; a one-time backfill moves them into `couple_events` one release after the new path is live | Rollout with no regressions |
| D13 | Native extensions (home-screen widgets, Live Activity, share-sheet capture) are a later milestone (Phase 8) | Prove the in-app core first |
| D14 | Analytics: add `posthog_flutter` in Phase 1 and measure per couple only, never content | Today `_capture` is a no-op stub; privacy constraints |

---

## 3. Hard rules

These are invariants. Every phase's plan must include a test for each rule it touches.

1. **No scorecard.** No query, RPC, screen or analytics event aggregates who planned, owned, proposed or completed what. The read function returns items, never per-user counts. *Test:* a contract test asserts that `list_together_items` exposes no count or aggregate column.
2. **No progress gamification.** No streaks, badges, "weeks connected", completion rings or counters. *Test:* a schema test asserts `couple_rituals` has no counter or streak columns.
3. **Overlay safety:**
   - Opt-in for each partner, and the finder needs both partners opted in.
   - Busy-only: no titles, locations or attendees leave the device.
   - Times rounded to 30 minutes, covering a rolling 14 days, with past blocks purged daily.
   - Revoking deletes the user's rows on the server in the same call and sends the partner nothing.
4. **Proposals for anything that affects the partner.** Assigning an owner, scheduling time for them and ritual slots are all proposals. An event that names the partner as a participant arrives as a heads-up they can leave in one tap, and the creator is not told.
5. **Conflict moments never notify the partner.** This is true today at `timeline_repository.dart:36` and must stay true. A private conflict is never readable by the partner.
6. **Private events are the creator's alone** everywhere: the in-app read, the ICS feed and the partner's free-time finder. Only the creator's own finder counts them as busy.
7. **The push budget** in D9 holds. *Test:* a SQL test asserts at most one scheduled `together_*` notification per user per local day.
8. **Unlink:**
   - `end-relationship` revokes feed tokens, purges busy blocks and cancels pending proposals.
   - Moments follow existing retention.
   - Re-pairing with the same partner keeps history.
9. **Safety:**
   - Together sits under the quick-exit privacy cover and the planned decoy screen.
   - The ICS endpoint returns a uniform 404 on any missing, wrong or revoked token, so it never reveals that a relationship exists.
   - Tokens are stored hashed.

---

## 4. Screen

### 4.1 Agenda (default)

| Section | Content | Notes |
|---|---|---|
| Header | "Together", both avatars, `+` (capture), date jump, Agenda/Month toggle, settings (overlay, calendar feed, digest) | — |
| **Today** | Today's items, each coloured by participants: me, partner or us (a third "ours" colour). A "Both free 19:00–22:00" chip when the overlay is on. The big-day care card | Times in the viewer's zone, with the partner's zone underneath for long-distance couples |
| **Needs you** (max 3, collapsible) | Proposals waiting on me, Planning date polls waiting on me (from Planning v2), a ritual slot to confirm, unowned items due within 7 days | Hidden when empty; never says "{partner} hasn't…" |
| **This week** | Agenda grouped by day, Mon–Sun. Free-window chips are tappable and open "Propose a date" | No week grid; the agenda already groups by day |
| **Rituals** | Horizontal cards: what's next, plus "Memories from this ritual". "Skip this week" | No counts |
| **Coming up** | Countdown cards (reunion via `isReunionEvent` in `lib/features/location/domain/reunion.dart`, anniversary, birthdays, trips), then the rest of the next 90 days | — |
| **Our story** | "On this day" card, the last 3 moments, then "All memories": the existing `MomentsList`, paginated | Conflicts excluded from "On this day" |

**Empty state for a new couple:** three steps — "Add your anniversary", "Add a birthday", "Set up one ritual". Capture (`+`) is the main action.

### 4.2 Month view and day sheet
- **Month view** is the evolved `CalendarStrip`. It keeps the existing indicator system (story avatars, moment-type glyphs), adds participant-colour dots, and shows busy hatching when the strip view is allowed.
- **Day sheet:** tapping a day opens the upgraded `CalendarDaySheet`. It lists every item for that day, with actions: edit, propose a time, add a moment, make a plan.

### 4.3 Planning's role
- Planning stays the deep document layer: checklists, budgets, polls, photos.
- Planning's dated blocks and to-dos already show on the calendar by being read at display time; that continues.
- New in the other direction: any Together event gets **"Make a plan"**, which creates a `planning_entries` row and stores its `planning_entry_id` on the event.

### 4.4 Event detail
Opened from any item:
- title, time and participants; owner avatar; visibility;
- the linked plan, if any;
- "Discuss": posts a message linking the event into the existing Chat, with no new chat system;
- "Add to my calendar";
- after the event, "Add a memory".

---

## 5. Data model

### 5.1 `couple_events` (new)
```
id uuid PK, relationship_id uuid FK, created_by uuid,
kind text CHECK (kind IN ('event','trip','big_day','ritual_occurrence')),
title text ≤120, note text ≤500, location_name text ≤120,
all_day bool NOT NULL,
start_date date, end_date date,                 -- authoritative when all_day
starts_at timestamptz, ends_at timestamptz,     -- authoritative when timed
tz text,                                        -- IANA zone at creation; validated against pg_timezone_names
rrule text, recurrence_until date,              -- RFC 5545 subset: FREQ (DAILY|WEEKLY|MONTHLY|YEARLY), INTERVAL, BYDAY, COUNT/UNTIL
participant_ids uuid[] NOT NULL,                -- subset of the two members, non-empty
owner_id uuid NULL,                             -- a member or NULL (unowned)
visibility text CHECK (IN ('shared','busy_only','private')) DEFAULT 'shared',
status text CHECK (IN ('proposed','confirmed','cancelled')) DEFAULT 'confirmed',
proposed_to uuid NULL, proposal_expires_at timestamptz NULL, decided_at timestamptz NULL,
ritual_id uuid NULL, planning_entry_id uuid NULL, memory_event_id uuid NULL REFERENCES timeline_events,
about_member_id uuid NULL REFERENCES couple_family_members,
remind_offsets_min int[] DEFAULT '{}',
legacy_reminder_id uuid NULL UNIQUE,            -- D12 backfill
created_at, updated_at, deleted_at
```
CHECKs:
- all-day rows have dates; timed rows have timestamps and a tz;
- the end is not before the start;
- a `proposed` row has `proposed_to` and an expiry.

### 5.2 `couple_event_options` (new)
`(id, event_id FK, all_day, start_date, end_date, starts_at, ends_at, chosen bool)` holds 2–3 options per proposal. Accepting one option, in a single transaction:
- copies it onto the event;
- sets `status = confirmed`;
- marks the option chosen.

### 5.3 Later-phase tables
- `couple_rituals` (Phase 3): template, cadence, preferred windows, duration, participants, `active`. **No counters.**
- `together_member_prefs` (Phase 2): owner-only rows holding digest time, care nudges on/off, overlay level (`off | free_windows | strips`).
- `calendar_feed_tokens` (Phase 5): `user_id`, `token_hash`, `created_at`, `revoked_at`.
- `couple_busy_blocks` (Phase 6): `user_id`, `starts_at`, `ends_at`, rounded to 30 minutes, ≤14 days ahead.

The time zone comes from Planning v2's `planning_member_settings(relationship_id, user_id, timezone)`; it is reused, not duplicated.

### 5.4 Row-level security
- **`couple_events` SELECT:** member AND (`visibility <> 'private'` OR `created_by = auth.uid()`).
- **`couple_events` writes:** go through SECURITY DEFINER RPCs (create, update, propose, decide, leave, delete), which enforce the proposal rules in §3.4. Column grants follow the reminders pattern.

### 5.5 Unified read: `list_together_items(rel uuid, start date, end date)`
SECURITY DEFINER, member-checked, with a window of at most 93 days. It returns one row shape:
```
(item_kind, id, date, starts_at, ends_at, all_day, tz, title, participant_ids,
 owner_id, status, visibility, source_ref jsonb)
```
It combines:
- `couple_events`:
  - `busy_only` rows are masked to the title "Busy" for the non-creator;
  - `private` rows are dropped for the non-creator;
  - `rrule` is expanded on the server within the window.
- `timeline_events` with `deleted_at IS NULL`; private conflicts appear only for their logger.
- `reminders` and `couple_family_members` birthdays, as yearly all-day items (until the D12 backfill).
- `list_planning_calendar_entries` (dates and to-dos).
- Planning date polls waiting on the caller.
- `couple_busy_blocks`, only within the rules of §3.3.

Expanding recurrence on the server means the app, the push generator and the ICS feed all agree.

### 5.6 Client
- `lib/features/together/domain/together_item.dart` holds a sealed `TogetherItem`, with kind one of: moment, reminder, birthday, planningDate, planningItem, pollAwaiting, story, event, proposal, ritualOccurrence, busy, freeWindow.
- `togetherRangeProvider(range)` fetches the range. A realtime subscription to `couple_events`, `timeline_events` and `reminders`, plus Planning's change signal, invalidates it.
- The existing widgets (`CalendarStrip`, `CalendarDaySheet`, `MomentCard`, `UpcomingRemindersSection`) are adapted to `TogetherItem` rather than rewritten.

---

## 6. Features

### 6.1 Plan together
- **Events:** timed or all-day, with participants and the "ours" colour.
- **Proposals:** up to three time options; accept, decline with an optional note, or let it expire quietly after 7 days. One push when sent; it then appears in the recipient's digest. The sender's view says "No reply yet".
- **Ownership:**
  - one avatar per item; setting yourself as owner is direct;
  - setting the partner as owner is a hand-off proposal;
  - an "Unowned" filter;
  - unowned items due within 7 days appear in Needs you for both partners.
- **Private / surprise events:** only the creator sees them. "Reveal" turns one shared and offers a memory prompt.
- **Reminders on any event** (`remind_offsets_min`), yearly recurrence, and family birthdays (`upsert_family_member` keeps working).
- **Digest:** a Sunday-evening "week ahead", plus a morning "today" only when something involves you. Each is sent at the recipient's local time. Planning v2's own pushes (polls waiting on you, countdown day-of) stay as they are; the digest never repeats them.

### 6.2 Connect
- **Rituals:** templates with defaults per couple type:
  - date night, every week or two;
  - State of the Union, weekly, 1 hour;
  - weekly call, for long-distance couples;
  - a 20-minute after-bedtime check-in, for parents;
  - a reunion talk.
  Each week a cron job creates the next `ritual_occurrence` as a proposal: in the first mutual free window when the overlay is on, otherwise in the preferred window. Both partners confirm. "Skip this week" has no consequence. The ritual card shows only "Next" and "Memories from this ritual".
- **Big-day care loop:**
  - The creator marks *their own* event as a big day, e.g. an interview, exam or appointment.
  - The partner gets a card the evening before ("{name}'s interview is tomorrow at 15:00 your time") and 2 hours after ("Ask how it went").
  - Tapping opens Chat with a draft, which the partner can edit or discard.
  - The wording is fixed templates. The cards are scheduled pushes, so on a day with a digest they merge into the same single push (D9).
- **Date ideas from a free window:** tapping a free-window chip offers three ideas through the existing `ai-sessions` Ideas/Nearby; picking one creates a proposal.
- **Reunion countdown:** a countdown card driven by `isReunionEvent`; a widget comes in Phase 8.
- **Discuss:** posts a message linking the event into Chat.

### 6.3 Remember
- **Event → memory:** after a confirmed shared event ends, each partner gets one in-app prompt (not a push): "Add a line or photo about Saturday?". The answer becomes a `timeline_events` moment linked through `memory_event_id`; photos use the existing Planning photo pipeline.
- **On this day:** moments and past confirmed shared events from earlier years on today's date. Conflicts are excluded.
- **Conflict visibility** `private | shared`, closing the master-spec gap. The default stays shared, which is today's behaviour.
- **Ritual memories:** past occurrences, each with its moments.
- **Moments archive:** the existing `MomentsList`, paginated across months, with the partner's name instead of "Partner".

### 6.4 External calendars
- **Add to my calendar** on any item, via `add_2_calendar`, which opens the system editor and needs no read permission.
- **ICS feed, one per user:**
  - an edge function `calendar-feed` with JWT verification off, which looks up a hashed token;
  - applies the same visibility filter as §5.5 for that user;
  - passes RRULEs through and includes VTIMEZONE.
  - In-app copy states that Google refreshes subscribed calendars every 12–24 hours and Apple lets you choose.
  - Settings: copy webcal link, revoke and regenerate.
- **Busy overlay** via `device_calendar_plus`:
  - reads busy-only time, rounds it, uploads 14 days;
  - the purge cron runs daily, and the overlay level comes from §5.3;
  - OS keys: iOS 17+ `NSCalendarsFullAccessUsageDescription` (keep `NSCalendarsUsageDescription` for older iOS) and Android `READ_CALENDAR`.
- **Mutual-free finder:** a pure Dart function. It takes the intersection of both partners' free time, keeps it within each partner's waking hours in their own zone, removes Together events, respects the private-event rule, and returns windows of at least 60 minutes.

### 6.5 AI (suggest, confirm)
- **Capture:** typed text, e.g. "dinner with Ama's parents Sat 7pm", becomes an event draft. It goes through a new `ai-together-capture` edge function using `_shared/gemini_json.ts` with a schema-validated output. Nothing is saved until the user confirms in the app (a confirm RPC).
- **Free window → ideas:** via `ai-sessions` Ideas/Nearby, as in §6.2.
- **Not in scope:** behaviour summaries, "you've had fewer evenings together" insights, and any AI wording about the partner.

---

## 7. Scenario walkthroughs (simulations)

### 7.1 Living together: Priya & Dev
**The week:**
- **Mon:** Priya adds "Plumber 14:00–16:00" for both of them, owner Priya. It shows in Dev's Today with Priya's avatar; no push.
- **Wed:** a "Both free 19:30–22:00" chip appears. Dev taps it, gets three ideas, and proposes "Thai + walk, Thu or Fri".
- **Same evening:** Priya accepts Friday. Each of them gets one push about it.
- **Sat:** a memory prompt. Priya adds a photo, which becomes a moment.

**Findings:**
- If Dev hasn't turned the overlay on, there are no free-window chips. Rituals fall back to preferred windows, and the app never nags Dev to turn it on.
- Priya setting Dev as owner of an errand becomes a hand-off proposal, so it is never an assignment.

### 7.2 Long distance, 6 hours apart: Ana (Toronto) & Luca (London)
**The week:**
- **Rituals:** "Weekly call, 60 min, Sun". The finder intersects both waking-hour windows and proposes 19:00 London / 13:00 Toronto. Both confirm.
- **Big day:** Ana marks "Thesis defence Thu 10:00" as a big day. Luca sees a card on Wednesday evening in London ("…tomorrow at 15:00 your time"), and "Ask how it went" at 17:00 London.
- **Reunion:** the flight becomes a countdown card.

**Findings:**
- All-day items are keyed by calendar date, so they never jump a day.
- The digest goes out at each person's own local time.

### 7.3 Dating, separate homes: Jay & Mia
**The week:**
- Both keep the overlay off, and This week works from Together events alone.
- Jay creates a private "Pick up ring". Mia sees nothing, while Jay's own finder counts it as busy.

**Findings:**
- New couples see the 3-step empty state.
- If Mia doesn't answer a proposal, it expires after 7 days. She gets one push and it appears in her digest; there is no barrage, and Jay never sees blaming copy.

### 7.4 Parents: Sofia & Marco
**The week:**
- Kids' events are tagged with `about_member_id`.
- "Leo's dentist Tue 15:30" has participant Sofia and owner Sofia. Marco sees it but gets no push.
- An unowned Planning to-do, "Book summer camp", due within 7 days, appears in Needs you for both.

**Abuse case:** Marco tries to watch Sofia's day. He sees free windows only, and only if Sofia opted in. Sofia's busy strips need her own second toggle. She can revoke at any time; her rows are purged at once and Marco is told nothing.

### 7.5 Cross-cutting cases
- **A controlling partner piling events onto the other:** the other person can leave any event silently, and creating events for someone else is a heads-up only.
- **Unlink:** handled per §3.8.
- **One partner never opens the app:** proposals and ritual confirmations need two people, so it can't silently become one partner's system. The metrics in §9 watch for this; the app never mentions it.
- **Notification overload:** the D9 budget. `moment_logged` pushes are batched into the digest, except anniversaries and milestones, which are sent immediately.

---

## 8. Phases

Each phase is shipped on its own and gets its own plan, executed test-first on main.

| # | Phase | Scope | Schema | Risk |
|---|---|---|---|---|
| **0** | **Make what exists solid** | See §8.1 | `reminders.remind_on`, `custom` type, `moment_logged` trigger | Low |
| 1 | Together hub + unified read | `lib/features/together/`; Today / This week / Coming up / Our story; `/together` route with `/timeline` redirect; Conversations card; Planning tabs simplified; timed events; minimal accept/decline; PostHog | `couple_events`, `couple_event_options`, `list_together_items`, `generate_event_notifications` | Medium |
| 2 | Proposals, ownership, care loop, digest | Needs you, hand-off proposals, big days, per-user digest cron in local time, notification deep links | `together_member_prefs` | Medium |
| 3 | Rituals | Ritual cards and setup with templates per couple type; weekly proposal cron; skip | `couple_rituals` | Low |
| 4 | Story | Event → memory, On this day, conflict visibility in compute-pulse and generate-verdict, paginated archive, ritual memories | `timeline_events.visibility`, `memory_event_id` | Medium |
| 5 | External export | add-to-calendar, `calendar-feed` function, settings, revoke on unlink | `calendar_feed_tokens` | Low |
| 6 | Busy overlay + finder | `device_calendar_plus`, upload and purge, two-level toggle, pure finder | `couple_busy_blocks` | Medium |
| 7 | AI capture + ideas | `ai-together-capture`, free window → ideas → proposal | — | Medium |
| 8 | Native (later milestone) | `home_widget`, `live_activities`, share-sheet capture, optional mirror into an on-device calendar | — | High |

### 8.1 Phase 0 scope (no new product surface)
1. **Moments appear without a manual refresh:**
   - the month provider is keyed to the first of the month in both `timeline_providers.dart` and `timeline_screen.dart`;
   - the log-moment flow returns its result to the Timeline;
   - the reminder → moment flow also refreshes.
2. **Realtime:** subscribe to `timeline_events` and `reminders`, replacing the empty `subscribeToEvents`.
3. **Partner push for non-conflict moments:**
   - a DB trigger inserts into `scheduled_notifications`, with a `source_key` for idempotency;
   - remove the client stub that only logs (`notifyPartnerMomentLogged`).
4. **`reminders.remind_on date`:**
   - backfilled from `remind_at`;
   - the client writes the calendar date;
   - `generate_reminder_notifications` switches to it.
   This fixes the day shift caused by `reminders_repository.dart:39`.
5. **Reminder editing:**
   - an edit/delete sheet, opened by `onReminderTap` in `timeline_screen.dart` and by the day-sheet reminder rows;
   - a type picker, with `custom` added to the CHECK constraint;
   - only anniversary and milestone types prompt "Add to Timeline?".
6. **Calendar dots:** reminder dots for the whole focused month, not just the 3-month window.
7. **Moment cards** show the partner's real name.
8. **Day sheet:** the "Nothing on this day yet." gating is fixed.
9. **`_scrollToDate`** actually scrolls.
10. **Deleted moments:** the verdict eligibility SQL (`20260703183000_verdict_system_v1_1.sql`) and `generate-verdict` exclude `deleted_at` rows.
11. **Soft delete under RLS:** verify that a soft delete passes the read policy, and fix it if not.

---

## 9. Success metrics

Measured with PostHog from Phase 1, per couple. Events carry `relationship_id`, item `kind`, `participants` (us, me or partner) and `via` (manual, ai, share or free_window). Events never carry titles, notes or who owns what. Nothing below is ever shown in the app.

| Metric | Definition | Target |
|---|---|---|
| Both-touched planning | % of active couples per week with ≥1 shared event confirmed by the person who didn't create it | ≥ 40% |
| Two-sided use | Both partners opened Together within 7 days | Rising |
| Ritual follow-through | Confirmed occurrences ÷ proposed occurrences; skip rate versus disable rate | Skips without disables are healthy |
| Care loop | Care card shown → acted on | ≥ 30% |
| Event → memory | Memory prompt shown → moment created | ≥ 20% |
| Finder value | Proposals created from a free window ÷ all proposals | Rising |
| Quiet | Together push opt-out rate; digest open rate | Opt-out < 5% |
| Safety signal | Overlay turned off after being turned on | Investigate if > 15% |
| Retention | D30 retention of couples with ≥1 ritual vs none | Cohort comparison |

---

## 10. Testing strategy

- **Dart:**
  - widget tests for each section;
  - grouping across time zones (6 hours apart, DST changes);
  - pure finder tests;
  - `TogetherItem` mapping tests;
  - existing `test/features/timeline/*` keeps passing until each surface is replaced.
- **SQL contract tests:**
  - RLS masking (busy-only, private, private conflicts);
  - rrule expansion across DST and year boundaries, and Feb 29;
  - proposal accept is atomic;
  - notification idempotency and the one-scheduled-push-per-day invariant;
  - no per-user aggregate columns, and no counter columns.
- **Edge functions:**
  - ICS output checked against validator fixtures; invalid or revoked tokens return a uniform 404;
  - the capture schema is validated, and a test checks that nothing is saved without the confirm RPC.
- **Manual, two devices / two accounts:** run each §7 scenario, including:
  - a proposal round trip;
  - care-card timing in each time zone;
  - turning the overlay on and off with immediate purge;
  - unlink cleanup.

---

## 11. Out of scope

- Google Calendar API two-way sync.
- Shared calendars with more than two people (family members are tags, not users).
- AI insights about the relationship.
- Paywalls on the shared basics; monetisation is a separate decision.
- Week grid view.
