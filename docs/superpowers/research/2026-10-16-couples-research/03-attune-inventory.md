# 03 — Attune inventory: what the app does, what it plans, and what it doesn't cover

**Date:** 2026-10-16. **Scope:** read-only inventory for the couples-research gap synthesis. No app files were changed.

**Method**
- Read in full:
  - `lib/architecture/attune/` (SOUL, MASTER_SPEC, THESIS, CLINICAL, RISK_SOLUTIONS, PRINCIPLES_CHECKLIST).
  - Every feature spec under `lib/architecture/`.
  - The design specs under `docs/superpowers/specs/`.
  - The build-status memory notes.
- Checked status against `lib/features/*`, `supabase/migrations`, `supabase/functions`, feature-flag seeds and routes.
- Where a doc and the code disagree, **the code wins**; disagreements are flagged ⚠.

**Status legend**

| Status | Meaning |
|---|---|
| **LIVE** | Built, reachable, and the flag (if any) is on. "Live" means deployed to the project or merged on main. The app has not soft-launched to real couples. |
| **DEPLOY-PENDING** | Built and on main, but migrations or functions aren't pushed, or device checks are outstanding. |
| **FLAG-OFF** | Built behind a flag that is off. |
| **BUILT-UNREACHABLE** | Code exists, but no route or entry point reaches it. |
| **PARTIAL** | Part of the spec is built. |
| **SPEC-ONLY** | Specified, not built. |
| **PLANNED** | A roadmap line only. |

**Caveats**
- **Doc staleness.**
  - `ATTUNE_MASTER_SPEC.md` (v2.22–2.27) still says the AI provider is Claude; every AI function actually calls **Gemini** (`supabase/functions/_shared/gemini_json.ts`, default `gemini-1.5-flash`).
  - The master spec has no Planning, Together, calendar or map.
  - `lib/architecture/PLANNING.md` describes v1, which has been deleted; v2 replaced it (`docs/superpowers/specs/2026-10-12-planning-v2-design.md` §16).
  - Several game spec headers still say "not implemented" for games that have shipped.
- **AI crons are paused.** `supabase/migrations/20260931150000_pause_ai_jobs.sql` unschedules `compute-pulse-weekly`, `generate-verdict-monthly`, `analyse-session-sweep` and `analyse-message-backlog`. The resume migration is still `…_resume_ai_jobs.sql.disabled`. The safety outbox worker still runs. Remote cron state was not verified.

---

## 1. Soul and hard rules (binding on any recommendation)

### 1.1 The soul

**Precedence:** SOUL > CLINICAL > MASTER_SPEC > algorithm checklist > PRINCIPLES checklist (`ATTUNE_MASTER_SPEC.md` L84–105).

- **Identity:** "Attune is a relationship intelligence system. Not a chat app. Not a quiz app. Not a couples journal. Not a dating app." (`ATTUNE_SOUL.md` §1)
- **Core belief:** "**understanding precedes change**" (SOUL §3).
- **One-sentence soul:** "Attune is designed to be worth returning to — not designed to make leaving feel painful." (SOUL §12; THESIS §1, §10)
- **What it is not** (SOUL §2): "Not a therapist… Not a judge… Not a surveillance tool… Not a game… Not a social media platform." MASTER_SPEC §1 adds: "Not a therapy app. Not a crisis service. Not a couples counsellor."
- **The verdict is a "sourced pattern summary"** (SOUL §2a). It is "never: a judgment on the relationship's worth, a score that ranks the relationship as good or bad, a recommendation about whether to stay or leave, or a clinical assessment."
- **Psychological frameworks** (SOUL §4):
  - Self-Determination Theory
  - Fogg B=MAP ("design for the lowest-ability moment")
  - Hook model (an internal trigger of "I want to understand what is happening between us")
  - Norman's emotional design
  - Peak-End rule; the timeline as an intervention for the experiencing self
- **Relationship frameworks** cited across the docs: Gottman (bids, repair, Four Horsemen), Johnson/EFT (pursue–withdraw), Bowlby/ECR-R attachment, NVC, Aron's 36 Questions, Brené Brown, Frankl (healing = meaning-making), and Ubuntu as a cultural counter-frame (CLINICAL §9).
- **Voice** (SOUL §10): "Honest. Specific. Warm. Respectful. Grounded." It should sound like a "wise, attentive friend", never a judge.

### 1.2 "What Attune will never do" (SOUL §8, verbatim)

**Manipulation**
- NEVER: Streak mechanics designed to create obligation rather than motivation
- NEVER: Manufactured random rewards to create slot-machine compulsion
- NEVER: Exit friction designed to prevent cancellation
- NEVER: Notifications designed around DAU optimisation rather than user need
- NEVER: Gamification of relationship health that turns intimacy into a score

**Privacy**
- NEVER: Asymmetric behavioural data shown about a partner to the other partner
- NEVER: A couple report combining both users' personal insights
- NEVER: Safety event data shared with the non-at-risk partner
- NEVER: Cycle data shared without explicit opt-in
- NEVER: Forum anonymous identity linked to real profile in any public surface
- NEVER: Raw message content in AI prompt logs
- NEVER: Relationship data used for advertising targeting

**Clinical**
- NEVER: Diagnostic language — toxic, narcissist, codependent, disorder, broken
- NEVER: Telling users what to decide about their relationship
- NEVER: Attributing negative behaviour to a named or implied partner
- NEVER: Generating content that could be used as evidence against a partner
- NEVER: Positioning the AI as a substitute for professional clinical help
- NEVER: Safety features positioned as guarantees of safety

**Trust**
- NEVER: The recipient ever knowing a message was rewritten by the translator
- NEVER: Using past relationship data for dating compatibility without explicit separate consent

**Gamification** (SOUL Principle 1): "No badges. No streaks. No leaderboards." PRINCIPLES_CHECKLIST §G: "NO streaks. Ever." / "NO leaderboards. Ever."

### 1.3 Permanent constraints (MASTER_SPEC §11; memory `permanent_constraints.md`)

1. "**The pattern is shared. The role is private.**" Asymmetric data (who pursues, whose bid-toward rate is lower) is self-facing only. "'Jordan tends to withdraw' is never generated or stored" (CLINICAL §7.2).
2. "**NO COUPLE REPORT EVER**… Not now. Not in a premium tier. Not ever." `personal_insights` RLS is `auth.uid() = user_id`, with "No service role bypass."
3. Safety notification goes to "only the at-risk user… The sender never knows. Never both."
4. Translator: "No label. No indicator. No 'polished with Attune.'" It is opt-in per message, and the button reads "Help me say this".
5. Crisis hotlines, safety resources and abuse alerts are free at every tier.
6. Safety detection is hard-coded keyword matching and "never routes through Claude or any other AI model."
7. "Raw message content never enters a verdict generation call."
8. These words are banned in all AI output: toxic, narcissist, codependent, disorder, broken. PRINCIPLES adds: you should / you must / you need to / your relationship is / stay / leave / healthy / unhealthy (as verdict language).
9. The `patterns` table has no `user_id` column.
10. No E2EE, because server-side AI needs plaintext. This is disclosed at signup, and messages are discoverable in divorce or custody proceedings (MASTER_SPEC §12).
11. **Decision 28: the AI is never a companion.** "no chatty AI persona, no sustained AI-user dialogue, no anthropomorphic AI character — permanently" (MASTER_SPEC L3047; RISK_SOLUTIONS §7.5).

### 1.4 Feature-level hard rules used in recent builds

**Together hub** (`docs/superpowers/specs/2026-10-14-together-hub-design.md` §3)
- "**No scorecard.** No query, RPC, screen or analytics event aggregates who planned, owned, proposed or completed what."
- "**No progress gamification.** No streaks, badges, 'weeks connected', completion rings or counters."
- "**Proposals for anything that affects the partner.**"
- "**Conflict moments never notify the partner.**" "**Private events are the creator's alone.**"
- "at most one *scheduled* Together push per user per day" (D9).
- D6: "AI suggests; the affected person confirms. No relationship interpretation; care-loop wording is fixed templates, never AI-written."
- D7: "unowned items are visible to both… **no tallies, ever**."
- D8: "Skipping has no consequence. **No counters of any kind**."
- "Needs you" copy "never says '{partner} hasn't…'".

**Planning v2** (spec §1–2)
- "**Money without a scoreboard**: expenses are a shared pot by default. Splitting is opt-in **per entry**, and balances never aggregate across entries."
- D7: "Edits, ticks and new entries are silent… No activity feed."
- D12: "No body-measurement block, anywhere."

**Couple map** (`2026-10-16-couple-map-design.md` §2, §4)
- "About 1 km, never a dot. Updated only when that partner opens the app. Hidden after 8 hours… Both partners must opt in."
- Pause "is silent and works both ways."
- "None of the following, ever: arrive or leave events; counters; 'last seen at'; nudges; timestamps on the device; a 'closing in' tone."

**Distance widget** (`2026-10-16-couple-distance-widget-design.md` §2, §4.6)
- "Off by default… **Discreet**… No partner name… **No app name on the card**."
- "no counters (never 'days apart')… A countdown *to* being together is allowed; a count of time apart is not."

**Location presence** (`2026-09-02` §4.1): "No streaks, no counters, no 'you haven't shared today' nudge."

**Pulse** (`PULSE.md` §6): "Do not implement streak tracking for check-ins… Do not penalise missed weeks." Check-in answers are private.

**Chat–Pulse** (`2026-08-14-chat-pulse-integration-design.md`): "the UI may name chat as a data *source*. It may never explain a score *change* in terms of chat-derived signal, ever."

**Chat** (`CHAT_SYSTEM_SPEC.md`)
- "must not expose per-message AI judgments, safety matches, hidden classifications, or partner-attributed psychological claims."
- "Nothing celebratory ever fires based on message content… A couple in a painful moment must never be met with confetti."

**Stories** (`STORIES.md`): seen / not-seen only, with no exact view time ("says when your partner was awake and looking at their phone"). No push on post. "No reactions, no view counts."

**Dating** (`DATING_MODE_SPEC.md`)
- Never "swiping, infinite browsing, match/view counts, streaks, scarcity timers, confetti."
- Never "a former partner's profile, messages, private insights."
- Never "love-language similarity… as compatibility evidence."
- "Do not show 'they liked you'."

**Safety** (`SAFETY_SYSTEM_SPEC.md` §1)
- "No generative model, embedding model, hosted moderation model… may decide whether a safety event fires."
- "Sender secrecy… No accusation… No punishment… Free access."
- "Avoid blanket advice such as 'document everything' or 'leave quickly'." (§6.4)
- "No A/B testing of trigger thresholds, resources, or safety copy."

**AI** (`2026-09-15-ai-assistant-design.md` §5.1; `ai-sessions/prompts/v1/system.txt`)
- The scope is IDEAS or NEARBY. "Anything else — general question answering, news, medical/legal/financial advice, relationship verdicts, booking… — is a REDIRECT."
- "Never say you agree with one partner against the other."
- Both partners must consent, and a version bump requires both to grant again.
- A safety refusal is indistinguishable from an ordinary redirect (AI Sessions §5.3, A1).

**Notifications** (PRINCIPLES §C)
- Genuine need only, never DAU.
- "Never send between 10pm and 8am local time."
- "One notification per event."
- Safety pushes are "direct receipts". SOUL §6: "Safety is never a gift."

**Monetisation** (RISK_SOLUTIONS §5): "Safety, translator, and core chat stay free at every tier — permanent."

**Product-change covenant** (RISK_SOLUTIONS §7.3): no feature users depend on "is ever removed, paywalled, or materially changed without advance notice."

**Discreet surfaces** (Together §8.11–8.14): widget, Live Activity and calendar copy are off by default, carry no partner name or app wording, and are cleared by quick exit and sign-out.

### 1.5 What these rules imply for recommendations

- No partner-vs-partner counts. That includes chores, money totals across entries, initiations and "who planned".
- No streaks, day counters or "days apart".
- No AI that interprets the relationship, takes sides or acts as a companion.
- No AI-dependent safety.
- Anything that affects the partner is a proposal.
- At most one scheduled push per day per surface.
- Discretion by default on device surfaces.

---

## 2. Capability matrix

**Mechanism codes**

| Code | Mechanism | Code | Mechanism |
|---|---|---|---|
| LM | Love maps / knowing each other | SD | Self-disclosure / closeness |
| BID | Bids and turning toward / responsiveness | RIT | Rituals of connection |
| REP | Repair / de-escalation | GRA | Gratitude / appreciation |
| SX | Self-expansion / novelty / play | LOG | Logistics / mental load |
| LDR | Long-distance closeness | MEM | Shared memory / narrative |
| CEL | Celebration / capitalisation | GOAL | Shared dreams / goals |
| MON | Money | FAIR | Fairness / division of labour |
| SR | Self-reflection / self-knowledge | SAFE | Safety / coercive-control response |
| GRIEF | Breakup recovery / meaning-making | COMM | Community / normalisation |
| ATT | Attunement / monitoring of relationship health | | |

### 2.1 The couple's journal: Planning | Calendar | Map tabs (`PlanningHomeScreen`)

#### Planning tab (Planning v2)

**Status for this whole tab: LIVE** (pushed to main, 94e090a1 and later). Source: `docs/superpowers/specs/2026-10-12-planning-v2-design.md`, `lib/features/planning/`.

| Capability | What it does | Mechanism | Source |
|---|---|---|---|
| Category → Entry → Block structure | Fully shared space. One editable template per category; "Start next one" duplicates an entry. Pins, swipe actions, offline outbox, a conflict sheet ("Kofi just changed this"). No activity feed. | LOG | v2 §3, §15 |
| Starter categories | Notes, Goals ("Why this matters to us", Steps, Target date), Trips, Date nights ("What we loved"), Home & bills (Bills table with a "Paid by" column), Groceries, Wishlist, Diet, Everyday. Everyday holds AI output. | LOG, GOAL, SX, RIT, MON | v2 §4.1; migration `20261012201100` |
| Gallery templates | Next visit (countdown, date poll, dual clock, travel costs), Moving house, Wedding (guests, to-book list), Baby (due date and more). | LDR, LOG, CEL | migration `20261012200900` |
| 13 block types | See the list below this table. | LOG, MON, GOAL, CEL, LDR | `lib/features/planning/data/planning_models.dart`; v2 §6 |
| Money blocks | Shared pot by default; split per entry, opt-in; "To even out", "Mark settled", append-only audit. **No cross-entry or per-partner totals** (D6, D13). | MON (deliberately no scoreboard) | v2 D6 |
| Recent list | Five most recent plans across categories, sorted by last activity. | LOG | migration `20261015140000` |
| Ask Attune → Planning | A suggested task or event from AI becomes an Everyday plan. | LOG | v2 §16 |
| Link previews (oEmbed) | YouTube, TikTok, Spotify and similar. ⚠ The oEmbed function redeploy and the `META_OEMBED_TOKEN` secret are pending (memory). | LOG | `planning-link-preview` |

The 13 block types are:
1. Text (rich)
2. Checklist (assignee: one partner, the other, or Either; due date)
3. Table
4. Date
5. Photo
6. Link
7. Place
8. Expenses
9. Budget
10. Date poll (pushes the partner at most once an hour)
11. Countdown (push at 08:00 local on the day)
12. Progress (couple total only; the first time it hits 100% it posts a celebration in chat)
13. Dual clock (shown only when both partners share presence)

#### Calendar tab (the Together hub)

**Status: phases 0–8d are deployed** (as of 2026-10-14). The AI part (Phase 7) is FLAG-OFF. Native surfaces (8a–8d) are built but still need device checks. Source: `docs/superpowers/specs/2026-10-14-together-hub-design.md`, `lib/features/together/`, `lib/features/timeline/`, `lib/features/reminders/`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Agenda / Month views | Today / This week / Coming up / Our story, plus a month grid with a day sheet. | LOG, MEM | LIVE |
| Couple events | Timed or all-day events, marked me / partner / us. Daily, weekly, monthly or yearly repeats, with "this one only" edits. Alarms. Private and surprise events with "Reveal". Busy-only events. | LOG, SX | LIVE |
| Proposals and hand-offs | 1–3 time options. Accept, or decline with a note (one gentle push back). Quiet 7-day expiry. Giving an item to your partner is a proposal. | FAIR (consent-based), LOG | LIVE |
| "Needs you" | Up to 3 items waiting on me: proposals, unvoted polls, ritual slots, unowned to-dos due within 7 days. Never tallied. | LOG, FAIR | LIVE |
| Big-day care cards | The creator marks their own event as a big day. The partner sees an in-app card the evening before and an "Ask how it went" card after; each opens Chat with a fixed-template draft. | BID, responsiveness (stress only, not good news) | LIVE |
| Daily summary | 08:00 local; on Sundays it previews the week ahead. This is the one scheduled push per day. | LOG | LIVE |
| Rituals | Templates: Date night, State of the Union, Weekly call, After-bedtime check-in, "Something of our own". Weekly or every other week. Skip, move, pause or end, with no counts. "Memories from this ritual". | RIT | LIVE |
| Story | Memory prompt after a shared event (text only; photos deferred). On this day (earlier years, no conflicts). Private conflict moments. Paged archive. | MEM | LIVE |
| Timeline moments | Milestone, conflict, highlight, first, anniversary; mood 1–10. Partner push for non-conflict moments. | MEM, CEL | LIVE (PULSE.md §3; Together Phase 0) |
| Reminders and family | Anniversary, birthday, custom and check-in types; yearly repeats. Lead times 0/1/3/7 days. Sent from 09:00 local. Family members (name and birthday) auto-create a birthday reminder. Logging an anniversary moment offers a yearly reminder. | CEL, LOG (kin-keeping) | LIVE (`REMINDERS.md`; migrations `20261015100000`–`130000`; `2026-08-13-moment-to-reminder-offer-design.md`) |
| Family tagging on events | `couple_events.about_member_id` exists in the schema, but no client sets it. | LOG | SPEC-ONLY in the UI |
| Export | "Add to my calendar", plus a per-user hashed ICS feed (`calendar-feed`). | LOG | LIVE |
| Busy overlay / free windows | Opt-in levels: off / free windows / strips. Times only, 30-minute blocks, 14 days ahead. Server-side finder (08:00–22:00 in each zone). "Free together" list. | LOG, LDR, time together | LIVE |
| AI capture and ideas | "Describe it" turns a note into an event draft. 3 ideas per free window (home / out / costs little) that become a proposal. Needs both partners' AI consent; shared quota. | SX, LOG | FLAG-OFF (`ai_together_enabled`; migration `20261014180000`) |
| Home-screen widget | "Next" card; discreet, opt-in. | LOG | DEPLOY-PENDING (device checks) |
| Share-sheet capture | "Add to plans" from other apps. | LOG | DEPLOY-PENDING (device checks) |
| Live Activity | iOS lock screen for the current plan; title hidden once it starts. | LOG | DEPLOY-PENDING (device checks) |
| Calendar mirror | One-way copy into a phone calendar named "Plans"; never copies notes, names or private items. | LOG | DEPLOY-PENDING (device checks) |
| Analytics (PostHog) | Success metrics from Together §9. | — | SPEC-ONLY (needs a key) |

#### Map tab (couple map Phases 0–3, plus the distance widget)

**Status: committed and pushed** (f65dfaea, 13eec49e, 7caac298). `couple_map_enabled` is on in dev, which has no users. Pending: `supabase db push` of `20261016100000` and `20261017100000`, and device checks. Source: `docs/superpowers/specs/2026-10-16-couple-map-design.md`, `lib/features/couple_map/`, `lib/features/location/`.

| Capability | What it does | Mechanism |
|---|---|---|
| Approximate presence | An area of about 1 km, never a dot. Both partners opt in. Updates only when the app is opened; hidden after 8 hours. Symmetric pause (1 h, 8 h, or until resumed). | LDR |
| Distance card | Rounded distance (5/10 km steps, never below "about 2 km"), the partner's local time, and a **reunion countdown** taken from calendar reunion events. | LDR, anticipation |
| Dual clock | Shown on the distance card and as a Planning block. | LDR |
| Story pins | Opt-in per story ("Pin to our map"). Clustered thumbnails; filter by Both / Mine / Partner's. "Remove all my places". Home-area warning. | MEM (place-based) |
| Distance widget | Small and medium sizes with a region map. Never samples location or touches the network. No name, no app name. | LDR |
| Place update in chat | A deliberate "I'm at…" card (`share_place_sheet.dart`). | LDR, BID |

### 2.2 App-wide areas

**Chat**

Source: `CHAT_SYSTEM_SPEC.md`, `lib/features/chat/`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Couple chat core | Idempotent sends, offline queue, realtime, delivered/read ticks, search, starred messages, pinned messages (up to 3), edit/delete with a tombstone, reactions. | BID | LIVE |
| Media | Images, voice (up to 5 min), video (up to 3 min), view-once video, "streak" clips (1 or 3 views). EXIF/GPS stripped. | BID, LDR, SX | LIVE (`20260905120000_enable_completed_chat_features.sql`) |
| Couple identity | Chosen chat name and shared avatar. | MEM, identity | LIVE |
| Delight layer | First-message-of-the-day shimmer, "reconnect warmth". Milestone celebration deferred. | BID | LIVE |
| Conversation streak counter | Server computes consecutive days on which both partners messaged; the client fetches it into the header snapshot. | ⚠ Conflicts with SOUL "No streaks" | **Computed but not rendered**: no widget reads `.streak` (`chat_experience_providers.dart`; migration `20260711120000_chat_streaks.sql`; flag `chat_streaks` on) |
| Insights screen | Your own unread personal insights. | SR | LIVE (built), but the source jobs are paused |
| WhatsApp import | Dual consent; parsed on the device; ranked one confidence tier lower. | MEM | FLAG-OFF (`chat_historical_import`) |
| Expanded header drawer | Pulse, latest insight, next reminder. | ATT | FLAG-OFF |
| Read-receipt opt-out | — | — | **Absent** |

**Stories**

Source: `STORIES.md`, `lib/features/stories/`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Stories | Audience of exactly one: your partner. 24-hour reel, then kept permanently on the calendar. Seen / not-seen only. No push, no reactions. | BID (low-pressure), MEM, LDR | LIVE (`20260939030000_stories_enable.sql`). ⚠ Realtime refetch never wired. |

**Streak camera**

Source: `2026-08-28-streak-camera-design.md`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Streak camera | One clip of up to 60 s through the outbox. Replays off by default, opt-in up to 3. No day counter ("out of scope"). | LDR, SX | LIVE |

**Pulse and weekly check-in**

Source: `PULSE.md`, `2026-08-14-chat-pulse-integration-design.md`, `lib/features/pulse/`, `supabase/functions/compute-pulse`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Pulse score | Weekly score from 0 to 100. Communication 22, Connection 22, Conflict health 20, Alignment 18, Emotional safety 18. Inputs: chat aggregates over 30 days (tone, NVC rate, bids answered toward, repair, escalation, stonewalling), games and check-ins. A confidence dot per dimension. | ATT, BID, REP | PARTIAL: the screen and function are built; ⚠ the weekly cron is paused; recompute happens only via Refresh or when both partners have checked in |
| Weekly check-in | Five 1–10 questions, under 90 s. Answers are private. | ATT, SR | PARTIAL: built; ⚠ the reminder push is a `debugPrint` stub and `send-checkin-reminders` is not scheduled |

**Verdict (monthly readout)**

Source: `VERDICT_SYSTEM_SPEC.md`, `generate-verdict`, `lib/features/verdict/verdict_screen.dart`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Monthly verdict | Headline, 1–3 strengths, 1–3 watch areas (each sourced), exactly one "Ask each other: …" conversation starter. Fixed disclaimer. Derived data only. | ATT, REP (a conversation prompt), RIT (monthly) | **BUILT-UNREACHABLE**: `VerdictScreen` has no route; the cron is paused; all seven gates in §14.2 are unchecked |

**Conflict translator**

Source: `CONFLICT_TRANSLATOR.md`, `translate-conflict`, `chat_screen.dart:1080`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| "Help me say this" | Opt-in per message. NVC rewrite (one alternative) plus a private "Underlying need: …" note. Send mine / send this / edit. The recipient never knows. After 5 or more uses it feeds a personal insight. | REP (gentle start-up), self-regulation | LIVE (flag `chat_translator_entry` on) |

**AI understanding layer**

Source: MASTER_SPEC §6–7, `analyse-message`, `analyse-session`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Layer 1 per message | Tone, NVC violations, bid type (toward / away / against). Bid type is never shown. | BID (measurement only) | Built; ⚠ cron paused |
| Layer 2 session analysis | Escalation, pursue–withdraw, stonewalling, repair attempted/landed, topic, root need (respect / fairness / affection / security / autonomy / rest). | REP, ATT | Built; ⚠ cron paused |
| Personal insights | Second person, self-facing only. | SR | Built; source jobs paused |

**Healing mode**

Source: `HEALING_MODE_SPEC.md` v1.3, `2026-08-03-healing-self-report-entry-design.md`, `lib/features/healing/`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Five-stage journey | 1. Prompts. 2. AI post-mortem observation (or "insufficient evidence"). 3. Pattern awareness from quizzes. 4. AI portrait ending in a reflection question. 5. Readiness check-in (0–100; retake after 7 days). Private; the ex is never notified. | GRIEF, SR | LIVE (v1.1/1.2) |
| Self-reported breakup entry | "Healing from a breakup?" card on the locked chat screen. | GRIEF | LIVE |
| "No prior relationship" readiness variant | — | — | SPEC-ONLY (v1.3) |
| Safety on Healing screens | Spec rule 7 requires Safety Resources and quick exit on every screen. | SAFE | ⚠ Missing: no safety link; triple-tap only wraps the home shell |

**Quizzes**

All four are solo self-report and private by default, with optional sharing. Source: the four quiz specs, `lib/features/quiz/`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Attachment (25 items, ECR-R-adapted) | Anxiety × avoidance spectrum; 9 types. | SR | LIVE, reachable **only** from Pulse's "Attachment styles" row. ⚠ Compatibility "pairing" card (`attachment_compatibility_service.dart`) conflicts with the other specs' ban on compatibility. ⚠ Clinical/Ghana review open. |
| Love languages (15) | Self-awareness only; "never used for compatibility". | SR | **BUILT-UNREACHABLE** (`KnowYourselfSection` / `CompatibilitySection` are never mounted) |
| Communication style (20) | Assertive / passive / aggressive / passive-aggressive. | SR | **BUILT-UNREACHABLE**; release gate is clinical review |
| Conflict style (18) | Collaborating, competing, avoiding, accommodating, compromising. | SR | **BUILT-UNREACHABLE**; same clinical gate |
| Compatibility preview | Day-one "pairing type" plus "something for tonight". | LM | Specified as the Ask-2 reward (MASTER_SPEC decision 29); built as the attachment lookup |

**Love map**

Source: `2026-08-28-love-map-design.md`, migration `20260913150000_love_map_content.sql`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Love map | 3 guess-then-truth prompts a week. 60 prompts in four domains: fears, dreams, stressors, history. Coverage shown ("34 of 60"), never accuracy. A weekly refresh biases the domain by the chat topic. | LM, GOAL (dreams) | LIVE. ⚠ SQL contract test not proven run. |

**36 Questions**

Source: `36_QUESTIONS.md`, `lib/features/games/…/thirty_six_*`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| 36 Questions | Three chapters of 12, with fresh mutual opt-in each time. Asynchronous free-text answers, then a side-by-side reveal. 2 private skips per chapter. AI reflection per chapter and at the end. Bank of 120 questions (English). | SD, LM | LIVE. ⚠ Chapter-3 translations self-certified `is_reviewed=true`. |

**Games**

Source: `GAMES.md`, `docs/reviews/GAMES_LAUNCH_REVIEW.md`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Mirror | 8 rounds guessing your partner's current state. The /8 score and the attentiveness flag are private. | LM, ATT | LIVE. ⚠ The flag fires at 3/4. |
| Sliding Scale | Both rate a statement 1–10. Only **6 statements**: money, children, independence, location, ambition, religion. Feeds Pulse Alignment. | GOAL / values alignment | LIVE (thin) |
| Scenario | 10 situations; "no correct answer". | REP awareness | LIVE (content review not recorded) |
| This-or-That | 10 binary rounds. Tones: Connecting, Romantic, Playful, Spicy (flirting), Intimate (emotional). Custom and community questions. | SX, LM | LIVE. Bank 50 of 230; Intimate needs clinical sign-off. |
| Truth-or-Dare | 10 rounds; truths run through safety detection; private skip; both must consent to Intimate. | SX, SD | LIVE. Bank 50 of 250. |
| Paint Ball | Arcade; the loser gets a declinable Truth-or-Dare prompt; "You got each other" on a draw. | SX (play) | LIVE (neon redesign in progress) |
| Snakes & Ladders | Arcade with "no insight layer". | SX | Code-complete, device QA pending |
| Word Hunt | Arcade with "no insight layer". | SX | Code-complete, device QA pending |
| Dots & Boxes | — | SX | Prototype ("not recommended") |
| Constellation | Co-operative. | SX | Prototype |
| Never Have I Ever | — | — | Listed as "coming soon"; no spec |

**AI assistant (Ask Attune) and AI Sessions**

Source: `2026-09-15-ai-assistant-design.md`, `2026-09-22-ai-sessions-design.md`, `ai-assist`, `ai-understand`, `ai-sessions`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Ask Attune: Get ideas | Long-press a message, then Ideas (date themes, gifts, activities) or Nearby (3 Mapbox place cards). A private 15-minute draft you can Share or Edit; "Add to Planning". | SX, LOG | LIVE (all 6 flags on since 2026-10-11) |
| Ask Attune: Understand | Private "possible ways to read this" for a partner's message: 2–3 readings plus 2–3 reply options; confidence low or medium only. Never saved. | REP / charitable reading | LIVE |
| AI Sessions | Multi-turn, Ideas or Nearby only. Private, or shared (both approve). Optional frozen recent-chat context. 10 turns, 15-minute idle limit. Self-harm/coercion phrases trigger a generic redirect plus a resources link. | SX, LOG | LIVE |

The six flags are `ai_assist`, `ai_understand`, `ai_sessions_private`, `ai_sessions_shared`, `ai_sessions_recent_window` and `ai_sessions_nearby`.

What AI Sessions explicitly will not do: "relationship interpretation, adjudication… crisis counselling".

⚠ External gates G2–G7 are not recorded as signed off. These cover provider legal terms, clinical/cultural evals and a coercive-control review.

**Reflection journal**

Source: `2026-08-02-reflection-journal-design.md`, `2026-10-14-journal-notes-design.md`, `analyse-journal-entry`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Private notes-style journal | Title plus text and photo blocks; available in any mode. On close, an AI reflection gives a tone and an NVC observation/feeling/need from the writer's own words. Patterns summary after 3 entries. Never shared; no streaks. | SR | DEPLOY-PENDING (pushed 284e18b3; 2 migrations and device checks outstanding). ⚠ No safety or crisis check on journal text. |

**Safety**

Source: `SAFETY_SYSTEM_SPEC.md`, `process-chat-safety-outbox`, `lib/features/safety/`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Keyword detector | Tier 1 (threats), Tier 2 (isolation/coercion), Tier 3 (fires on the 3rd hit in 30 days). Server-side, incoming messages only. Notifies only the recipient ("Some resources are available"), at most once per 24 h. | SAFE | LIVE, but the phrase list is a **9-phrase placeholder** (`_shared/chat_safety.ts`); English only; known evasions |
| Resources screen | Settings and deep links. | SAFE | PARTIAL: ⚠ hard-coded Ghana DOVVSU / US / UK only; no country routing, emergency numbers or international fallback; the tip "plan for leaving quickly" contradicts §6.4 |
| Quick exit | Triple-tap goes to a neutral "Daily overview" decoy; clears Together and map device data. | SAFE | PARTIAL: ⚠ **no safety PIN** (the unlock marker is written but never read); triple-tap covers only the home shell; Android doesn't call `finishAndRemoveTask` |
| App-switcher privacy cover | Hides app content in the app switcher. | SAFE | LIVE (`lib/core/services/app_privacy_cover.dart`) |
| Truth-answer safety | Truth-or-Dare answers go through safety detection. | SAFE | LIVE (`process-truth-answer-safety`) |

**Dating mode**

Source: `DATING_MODE_SPEC.md` v1.3, `lib/features/dating/`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Curated introductions | Gated by healing readiness (score above 70, plus time gates). Alignment bands, not scores. Double-blind interest. Guided first date. Photo moderation and identity check. Former partners excluded via phone HMAC. | Re-partnering, SAFE | FLAG-OFF (all `dating_*` flags false; 20 migrations, 7 screens) |
| Dating chat | — | — | SPEC-ONLY (draft safety spec "nothing approved") |

Dating blockers are human/ops: CI contract test, HMAC secret, KYC backend, clinical/cultural review, and 2,000+ active couples.

**Community**

Source: `FORUM.md`, `COMMUNITY_QUESTIONS.md`, `lib/features/forums/`, `lib/features/opinions/`, `lib/features/community/`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Forums / debates | Anonymous topics voted into FOR/AGAINST debate rooms. No winning side; `user_id` is never exposed. | COMM, perspective-taking | LIVE (no flag) |
| Opinions feed | Anonymous posts, polls, quotes; 21 fixed tags (e.g. "long distance", "breakup", "sex", "anniversary"). Browsable without an account. | COMM | LIVE |
| Community questions | Users share Truth-or-Dare / This-or-That prompts. | SX, COMM | LIVE (the "not before Month 3" rule overridden) |

**Onboarding and lifecycle**

Source: `AUTH_ONBOARDING_ENGINE.md`, MASTER_SPEC §8.8, `2026-07-21-ask2-trigger-design.md`, `2026-08-02-relationship-lifecycle-sync-design.md`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Auth and fork | Phone OTP. Fork into Single (Personal mode) or Couples. Invite with QR code. | — | LIVE |
| Ask 1 / Ask 2 | Ask 1 avoids AI vocabulary entirely. Ask 2 fires after 30+ messages each and 3 shared days, then a single push, intro, quiz, anchors ("what you admire about your partner") and compatibility preview; skippable. | Trust before AI; GRA (anchor question, once) | LIVE |
| 48-hour solo fallback | Reflection while waiting for the partner. | SR | PARTIAL: ⚠ offered immediately with no 48 h gate; no "keep private / share" prompt when the partner joins |
| Day-7 pivot | Keep waiting / Personal / invite someone else. | — | SPEC-ONLY (missing) |
| Couple types | married, engaged, cohabiting, LDR, parents | — | **Absent** (modes are only `personal | couplesPending | couples`). Owner decision "all four couple types at launch" (Together memory) is not reflected in the schema. |
| End relationship | Either partner, alone, instantly and irreversibly. The chat is archived (⚠ immediately, skipping the spec's read-only stage). Pushes the other partner. Offers Healing to the one who ended it. Dating exclusion. | GRIEF, SAFE | LIVE |
| Pause relationship | `paused` exists in the enum, but no RPC or UI sets it. | — | SPEC-ONLY |

**Notifications**

Source: `NOTIFICATION_ENGINE.md`, `2026-08-02-push-notification-wiring-design.md`.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Push engine | OneSignal, scheduled-notification cron, routing for all types, chat push suppressed while the recipient is viewing, preview off by default. | LOG | LIVE |
| Per-feature budgets | Together: 1 scheduled push a day. Reminders: once per person per day from 09:00. Polls: at most hourly. Forum: at most every 2 hours. | — | LIVE |
| Global budget and quiet hours | PRINCIPLES §C: "Never send between 10pm and 8am". | — | **Absent** (no implementation found) |

**Cycle tracking**

Source: MASTER_SPEC §8.3, §14.

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Cycle tracking | Private; the partner sees the phase only if the user opts in; a short supportive note for the partner. | Health, attunement | PLANNED (Month 4); `cycle_logs` table specified |

**Widgets and live activity**

| Capability | What it does | Mechanism | Status |
|---|---|---|---|
| Widgets and Live Activity | Together "Next" widget, couple distance widget, Live Activity. | LOG, LDR | DEPLOY-PENDING (device checks); lock-screen families deferred to W3 |

**Post-launch roadmap (MASTER_SPEC §14)**

| Item | Mechanism | Status |
|---|---|---|
| Time capsule messages | MEM, CEL | PLANNED, Month 4 |
| Anniversary report ("Spotify Wrapped") | CEL, MEM | PLANNED, Month 4 |
| Weekly intimacy challenges (love-language based) | SX, intimacy | PLANNED, Month 4 (one line) |
| Live conflict cooldown ("real-time escalation banner") | REP, flooding | PLANNED, Month 5 (one line). ⚠ Tension with the never-automatic rule. |
| Ritual builder | RIT | Largely realised by Together rituals |
| Therapist integration and export (B2B) | Therapist handoff | PLANNED, Month 5–6 (one line) |

---

## 3. What is not covered, or covered only thinly

Each verdict is based on the docs plus a code and content check. "By design" means a hard rule forbids the obvious version.

| Topic | Verdict | What exists | What's missing |
|---|---|---|---|
| **Sex / sexual intimacy** | **Absent** | "Spicy" = flirting and touch prompts; "Intimate" tone = *emotional* safety (seed `20260712125000`). THIS_OR_THAT §5.3 had explicit sexual examples that were **never seeded**. "sex" is a forum tag. AI blocks "adult venues". Weekly intimacy challenges are a one-line Month-4 plan. | No sexual-communication content, desire-discrepancy support, consent or preference sharing, or satisfaction check-in. Any of these needs an opt-in or consent design and clinical authorship (per the specs). |
| Cycle / reproductive health | Planned | Spec'd with opt-in phase sharing (MASTER_SPEC §8.3). | Not built. |
| **Faith / spiritual practice** | **Absent** (one item) | Sliding Scale has 1 religion statement; 36Q has 1 "belief" item. Churches appear only as a distribution channel (THESIS §7.2). AI Nearby blocks "religion". | No shared-faith practices, prayer or devotional rituals, or values layer. Notable given the Ghana-first market. |
| **Money** | **Thin, logistics only** | Expenses, budget, split/settle (per entry, never aggregated, by design), Home & bills, Wishlist, savings Progress. One item each in Sliding Scale, Love Map and Scenario. AI refuses "financial advice". | Money values, money history and money-date conversations. Recurring bills (no recurrence engine in Planning). A "money date" ritual template. |
| **Chores / division of labour** | **Thin; tallies forbidden** | Checklist assignee, hand-off proposals, unowned items in "Needs you". Together cites Fair Play / Daminger. "Fairness" is a detected root need. | No chores template, recurring chores, or "who notices and plans" (cognitive load) flow. No fairness conversation prompt. A **non-numeric** fairness check-in is the only rule-compatible shape. |
| **Family / in-laws** | **Thin** | Family members (name and birthday) give birthday reminders. CLINICAL §9 discusses extended family, bride price and Ubuntu; "communal obligation" is proposed as a 7th need but still open. | No relation types; `about_member_id` has no UI. No in-law boundaries, holiday rotation, visit planning, or family-pressure discussion tools. A high-relevance gap for West African couples. |
| **Parenting** | **Absent** | Baby template, the "after-bedtime check-in" ritual, 1 Sliding Scale item. | No parenting-style alignment, co-parenting load, family planning, or co-parenting after separation. |
| **Health (physical / mental)** | **Absent** | Mirror asks "How rested?"; cycle tracking planned. Body metrics banned (Planning D12). AI refuses medical topics. | No illness, caregiving or stress-and-coping (dyadic coping) support beyond awareness prompts. |
| **Gratitude rituals** | **Absent** | Together §1.1 cites Algoe & Gordon, but nothing is built. The journal prompt bank deliberately avoids "What are you grateful for?". | No gratitude prompt, ritual template or memory type. The clearest research-backed gap that fits all the hard rules. |
| **Appreciation / fondness & admiration** | **Thin** | Ask-2 anchor "what you admire about your partner" (once). "Strength" insight cards and verdict strengths (verdict unreachable). | No ongoing partner-to-partner appreciation mechanic. |
| **Dreams / goals** | **Partial** | Goals template ("Why this matters to us"), Progress plus celebration, Love Map "dreams" domain (15 prompts), 36Q Ch3 future. | No life-vision or bucket-list layer, no Gottman "dreams within conflict", no goal check-ins. |
| **Celebrations / capitalisation** | **Partial** | Anniversaries and birthdays, moment → yearly reminder, countdowns, Progress celebration in chat, Wedding template, partner push for milestones. | No active-constructive response to *good news*: care cards cover stressful big days only. No "share a win" flow. Anniversary report and time capsule are only planned. |
| **Apology / repair flows** | **Thin** | Repair is *measured* (Layer 2 → Pulse; cron paused). The translator rewrites blame into needs and must "never… make sender apologise for something undecided". Understand gives reply options. The verdict's one conversation starter is unreachable. | No guided apology, repair-attempt prompts, post-fight debrief, or make-up ritual. The post-fight "bridge" is deferred (RISK_SOLUTIONS §1). |
| **Conflict time-outs / flooding** | **Absent** | Flooding is explained in CLINICAL §4.1 (stonewalling reframed as physiological). "Live conflict cooldown" is a one-line Month-5 plan. | No self-initiated pause, time-out-and-return agreement, or self-soothing. A user-initiated version fits the pull-not-push rule. |
| **Therapist handoff / referral** | **Absent** | Copy guidance only: "a trained outside perspective" rather than "therapist", because of Ghana stigma (CLINICAL §9.3). Referral language is [OPEN] (CLINICAL §12, L1214). "Therapist integration (B2B)" is a Month 5–6 line. | No referral criteria, directory or handoff flow; no B2B2C counsellor or church link. |
| **Crisis routing** | **DV: partial. Self-harm: gap.** | DV tiers notify the recipient only (placeholder phrases); resources for 3 countries. | No country routing, emergency numbers or international fallback (spec'd, not built). **Self-harm by the sender is excluded** from chat safety ("no protocol yet", THESIS §6.8). Only AI Sessions refuses self-harm phrases (English only), and the journal and Healing have no check. No 988, Samaritans or findahelpline anywhere in the code. |
| **Breakups / separation** | **Covered for the individual; thin for the pair** | Healing mode v1.2, self-reported entry, dating gates, former-partner exclusion, end-relationship flow. | Ending is one-sided, instant and irreversible, with no cooling-off, mutual or soft end. No pause state (enum only). Nothing for co-parenting after separation. No export choice before archive. |
| **Long-distance (LDR)** | **Strong (recent)** | Couple map, distance and reunion countdown, dual clock, distance widget, Next-visit template, free-window finder across time zones, voice/video/streak clips, stories. | Not in MASTER_SPEC or THESIS (docs lag the code). No LDR couple type. |
| Bids / turning toward | **Measured, not supported** | `bid_type` is computed per message and never shown (by design). Big-day care cards are the only active responsiveness prompt. | No user-facing bid-awareness or turning-toward practice. |
| Rituals of connection | **Covered** | Together rituals (5 templates), Love Map weekly, daily summary. | No rituals for gratitude, money, faith or reunion/departure. |
| Self-expansion / novelty | **Partial** | AI date ideas (live), Together free-window ideas (flag off), Trips and Date nights, games, community prompts. | No "new shared experience" challenge mechanism; intimacy challenges only planned. |
| Infidelity / trust repair | **Absent** | Appears only as a hallucination risk (RISK_SOLUTIONS §2). | — |
| Coercive control beyond keywords | **Thin by design** | Tier 2/3 phrases only; no behavioural detection (monitoring, financial or location control). RISK_SOLUTIONS §2.3 abuse-context suppression is "should", not built. | — |
| Couple-level assessment | **Absent** | All quizzes are individual trait instruments. | No relationship-satisfaction, values, sexual-satisfaction, fairness or dyadic-coping measures. |
| Positive-psychology frameworks | **Absent in the docs** | Gottman is used only for horsemen, bids and repair. | No capitalisation (Gable), savouring, shared meaning, or Sound Relationship House upper floors. |

---

## 4. Open TODOs, roadmap items and owner decisions

### 4.1 Owner and product decisions

- **Compatibility policy conflict.** Three things pull against each other:
  - The attachment "pairing" card (built) and This-or-That's shared match percentage.
  - The love-language, communication and conflict specs' "no compatibility verdict" rule.
  - The CLINICAL position on love-language matching (Impett 2024).
- **Three quizzes are built but unreachable.** Wire `KnowYourselfSection` / `CompatibilitySection` into the app or remove them.
- **Verdict.** Route the screen and resume the cron, or hold it until the §14.2 gates pass. The in-app name is still open ("monthly readout" / "pattern report"; MASTER_SPEC §16).
- **Resume AI jobs** (`…_resume_ai_jobs.sql.disabled`). Pulse, verdict, insights and love-map refresh depend on them.
- **Flip `ai_together_enabled`**, then smoke-test the `claimProviderStart` RPC shape in prod.
- **Mirror.** /4 vs /8 rounds, and the flag that fires at 3/4.
- **Sexual-intimacy content.** In scope or not? If yes, it needs an opt-in or consent design and clinical authorship.
- **Couple types.** The owner said "all four couple types at launch" (Together memory), but there is no schema for them.
- **Pulse §10 open items:**
  - no push when a conflict is logged;
  - shared score vs personal score;
  - showing each partner's check-in status;
  - refresh limit (24 h vs 4 h).
- **Couple map.** Shared `BottomSheetHeader` "Done" target is 24 dp. `InfoRowWidget` subtitle contrast is 4.42. Status-bar contrast over the dark globe (top scrim offered).
- **Monetisation tiers** are not specified (THESIS §7.3; MASTER_SPEC §16). "Attune" is still a working title.
- **Doc inconsistency: chat after unlinking.** THESIS §3.1 says "both people can revisit the history". PRINCIPLES §J says each user reads only their own messages. The code archives instantly.
- **Chat streak counter.** It is computed and fetched but not displayed. Remove it or keep it dormant. Displaying it would breach SOUL §8 and PRINCIPLES §G.

### 4.2 Clinical, legal and cultural gates (human)

**CLINICAL §12 open items**
- ECR-R avoidance calibration for Ghana; instrument length.
- Whether text-based horsemen detection is responsible.
- NVC cultural fit.
- A 7th "communal obligation" need.
- Safety trigger list cultural review.
- **Professional referral language.**
- Love-language cultural categories.

**Clinical advisor sign-off** is pending for:
- all prompts and quizzes;
- the Intimate tone banks;
- 36Q Chapter 3 (currently self-certified);
- healing readiness weights and the >70 threshold;
- verdict, the Scenario and Sliding Scale content.

**Safety**
- DV professional review of resources and push copy.
- DV lawyer review of the ToS.
- The production phrase list (the current 9 phrases are placeholders).
- Safety PIN recovery design.
- **Self-harm protocol (not designed).**
- Fix the zero-width-character and non-English evasions.

**AI Sessions G2–G7**
- Gemini no-training and retention terms; Mapbox storage licence.
- Clinical and cultural evals.
- Coercive-control review of the shared surface.
- Operations runbooks.

**Regulatory** (RISK_SOLUTIONS App B)
- Ghana Data Protection Commission (DPC) registration.
- Apple 5.1.2(i) AI consent.
- GDPR Art. 9 / DPIA and AI Act Art. 50 before EU/UK.
- SDK audit.

**Dating flag flip**
- CI contract test.
- HMAC secret.
- KYC age backend.
- Wire candidate generation to the exclusion list.
- §16 checklist.
- 2,000+ active couples.

### 4.3 Engineering, deploy and device

**Deploys**
- Couple map: `db push` of `20261016100000` and `20261017100000` (drops existing presence rows).
- Journal: 2 migrations.
- Planning: `201100`/`201200` if not yet applied, the `planning-link-preview` redeploy, and `META_OEMBED_TOKEN`.

**Device checks**
- Together widget, share sheet, Live Activity, calendar mirror.
- The §10 two-device scenarios.
- Couple map (layer order, telemetry, tile-cache clear).
- Distance widget (Doze, StandBy, VoiceOver/TalkBack).
- Snakes and Word Hunt QA.

**Spec items that aren't built**
- Safety: PIN gate, country routing, emergency numbers, `finishAndRemoveTask`, triple-tap on every screen, and safety access on Healing screens.
- Pulse check-in reminder scheduling.
- Day-7 pivot and the 48 h gate.
- Relationship pause.
- Stories realtime publication.
- Family tagging UI.
- PostHog.
- Global quiet hours and push budget.
- Read-receipt opt-out (not specified anywhere).

**Content**
- This-or-That bank: 50 of 230 required. Truth-or-Dare bank: 50 of 250.
- Sliding Scale has 6 statements.
- `game_questions` localisation.

**Tests and verification**
- SQL contract suites "static-verified, never executed" in CI: chat, dating, games, love map.
- Chat localisation extraction.
- Insight-retraction mechanism, adversarial verdict suite, abuse-context suppression, and "used against me" signal (RISK_SOLUTIONS, specified only).

### 4.4 Roadmap lines (MASTER_SPEC §14 and the specs' deferrals)

**MASTER_SPEC §14**
- Month 4: cycle tracking, time capsule, anniversary report, weekly intimacy challenges, Healing (done).
- Month 5: live conflict cooldown, ritual builder (largely done via Together), WhatsApp import (built, flag off), voice notes (done), video (done).
- Month 5–6: therapist integration and export.
- Month 6+: dating.

**Together deferrals**
- Photo memories.
- Fitting rituals into free time.
- Google two-way sync.
- Reminders backfilled into `couple_events`.
- The 5-tab shell.

**Planning v2 non-goals**
- Recurrence engine.
- Event times.
- Currency conversion.
- AI-written plans.

**Journal deferrals**
- Search, export, AI prompts.

---

### Key sources

**Soul and principles**
- `lib/architecture/attune/ATTUNE_SOUL.md`
- `lib/architecture/attune/ATTUNE_MASTER_SPEC.md`
- `lib/architecture/attune/ATTUNE_THESIS.md`
- `lib/architecture/attune/ATTUNE_CLINICAL.md`
- `lib/architecture/attune/ATTUNE_RISK_SOLUTIONS.md`
- `lib/architecture/attune/ATTUNE_PRINCIPLES_CHECKLIST.md`

**Feature specs**
- `lib/architecture/`: `PULSE.md`, `VERDICT_SYSTEM_SPEC.md`, `CONFLICT_TRANSLATOR.md`, `HEALING_MODE_SPEC.md`, `SAFETY_SYSTEM_SPEC.md`, the four quiz specs, `36_QUESTIONS.md`, `GAMES.md`, `CHAT_SYSTEM_SPEC.md`, `STORIES.md`, `REMINDERS.md`, `NOTIFICATION_ENGINE.md`, `AUTH_ONBOARDING_ENGINE.md`, `DATING_MODE_SPEC.md`, `FORUM.md`, `COMMUNITY_QUESTIONS.md`

**Design specs** (`docs/superpowers/specs/`)
- `2026-10-12-planning-v2-design.md`
- `2026-10-14-together-hub-design.md`
- `2026-10-16-couple-map-design.md`
- `2026-10-16-couple-distance-widget-design.md`
- `2026-09-15-ai-assistant-design.md`
- `2026-09-22-ai-sessions-design.md`
- `2026-08-28-love-map-design.md`
- `2026-08-27-session-games-design.md`
- `2026-10-14-journal-notes-design.md`
- `2026-08-14-chat-pulse-integration-design.md`
- `2026-09-02-location-presence-design.md`
- `2026-08-28-streak-camera-design.md`
- `2026-08-13-moment-to-reminder-offer-design.md`

**Code evidence**
- `supabase/migrations/20260931150000_pause_ai_jobs.sql`
- `supabase/functions/_shared/{gemini_json,chat_safety,ai_session_safety}.ts`
- `lib/features/safety/domain/services/quick_exit_service.dart`
- `lib/features/profile/widgets/{know_yourself_section,compatibility_section}.dart` (orphaned)
- `lib/features/verdict/presentation/screens/verdict_screen.dart` (no route)
- `lib/features/chat/presentation/providers/chat_experience_providers.dart` (dormant streak)
- `supabase/migrations/20261014110000_couple_events.sql` (`about_member_id`)
