# ATTUNE — MASTER SPECIFICATION
### The complete product, technical, and architectural bible
**Version:** 2.22 (Two-ask couples onboarding; SMS delivery requirements)
**Last updated:** July 2026
**Status:** Locked and buildable
**Build tool:** OpenAI Codex (implementation) + Claude (this session, review)
**Review process:** All code reviewed against this document before merge

---

> ## STOP — READ THIS BEFORE ANYTHING ELSE
>
> This master spec is the **entrance**, not the whole building. Before reading
> any section below, or before this document is used to onboard a new
> collaborator, reviewer, or advisor, read these two documents in full —
> **they are not optional background, they are required prerequisite reading**:
>
> 1. **`../ATTUNE_THESIS.md`** — what Attune is, in plain language; the problem
>    it solves; why the approach can win; how it scales; the dating-mode gaps
>    already closed and still open. Read this first. If you cannot explain
>    Attune's thesis in one paragraph after reading it, you are not ready to
>    read the spec below.
> 2. **`../ATTUNE_RISK_SOLUTIONS.md`** — the mechanism-level treatment of the
>    six risks that could kill this product, with falsifiable tests and
>    pre-committed fallbacks for each. Read this second. It tells you *why*
>    certain sections of this spec exist (the conflict-capture gate, the
>    dismissal-queue calibration loop, the RLS canary requirement, and more
>    all trace directly back to a named risk in that document).
>
> **The reading order is not interchangeable.** The thesis is the *why*; the
> risk-solutions document is the *what could go wrong and how we're handling
> it*; this master spec is the *how to build it correctly*. Implementing
> against this spec without having read the other two produces code that is
> technically correct and strategically blind — it will pass every gate below
> while missing the point of why the gate exists.

---

> **HOW TO USE THIS DOCUMENT**
> This file is the implementation source of truth for the Attune project.
> Every line of code Codex writes must be reviewable against a section here.
> Every architectural decision made in this session is recorded here with its reasoning.
> When in doubt about any implementation detail, this document has the answer.
> When this document does not have the answer, do not guess — open the Claude review session.
> For what Attune is and why it exists, see `../ATTUNE_THESIS.md` (read first).
> For the risks this spec is defending against, see `../ATTUNE_RISK_SOLUTIONS.md` (read second).
> For the psychological and design principles that govern every product decision, see ATTUNE_SOUL.md.
> For evidence limits on psychologically interpretive features, see ATTUNE_CLINICAL.md.
> For algorithmic correctness, safety, reliability, observability, and rollout quality, see ../algorithms/algorithm_quality_review_checklist.md.
> For daily implementation review, use ATTUNE_PRINCIPLES_CHECKLIST.md.

---

## DOCUMENT HIERARCHY AND REVIEW WORKFLOW

This master spec is the implementation blueprint, but it is not the only
governing document, and it is not where the reading starts. Attune's
documentation has two layers:

**Layer 0 — Context (read before anything else, once, and revisit after any
major strategic decision):**

| Document | Role | Use when |
|---|---|---|
| `../ATTUNE_THESIS.md` | Why Attune exists | Onboarding to the project at all; explaining Attune to anyone; before any decision that touches positioning, market, or strategy |
| `../ATTUNE_RISK_SOLUTIONS.md` | What could go wrong, and the mechanisms fixing it | Before implementing any feature tied to a named risk (conflict capture, dyadic onboarding, AI cost architecture, cultural calibration, trust/security posture, or process discipline); before any roadmap or prioritization decision |

**Layer 1 — Governance (five documents used together during implementation):**

| Document | Role | Use when |
|---|---|---|
| `ATTUNE_SOUL.md` | Constitution | Deciding whether a feature should exist, how it should feel, and what Attune must never become |
| `ATTUNE_CLINICAL.md` | Evidence boundary | Building any psychologically interpretive feature: quizzes, AI analysis, verdicts, pulse, translator, safety, dating compatibility |
| `ATTUNE_MASTER_SPEC.md` | Build blueprint | Implementing architecture, data models, routes, flows, schemas, edge functions, and feature behavior |
| `../algorithms/algorithm_quality_review_checklist.md` | Algorithm quality gate | Building any algorithm, scoring system, classifier, ranking system, scheduler, detector, recommender, matching system, or automated decision path |
| `ATTUNE_PRINCIPLES_CHECKLIST.md` | Shipping checklist | Reviewing every feature, prompt, notification, copy change, privacy change, and monetisation decision before merge |

Layer 0 never overrides Layer 1 on implementation specifics — the thesis and
risk-solutions documents explain *why*, they do not relitigate what the
governing documents have already locked. But no one should be implementing
against Layer 1 without having read Layer 0 first; the conflict order below
governs disagreements strictly within Layer 1.

### Conflict order
If documents conflict, resolve in this order:

```text
ATTUNE_SOUL.md
  ↓
ATTUNE_CLINICAL.md
  ↓
ATTUNE_MASTER_SPEC.md
  ↓
algorithm_quality_review_checklist.md
  ↓
ATTUNE_PRINCIPLES_CHECKLIST.md
```

The soul document wins on product ethics and permanent philosophical
constraints. The clinical document wins on what psychological claims can be
made and how strongly they can be stated. This master spec wins on concrete
implementation once the feature is ethically and clinically allowed. The
algorithm quality checklist wins on implementation quality for algorithms:
security, robustness, scalability, maintainability, observability, and
user-aware behavior. The principles checklist is the final pre-merge scan.

### Required workflow before implementation

```text
1. Soul check:
   Should this feature exist in Attune at all?

2. Clinical check:
   Does this feature interpret psychology, behavior, safety, compatibility,
   relationship health, or user intent?
   If yes, its claims and confidence level must be supported by
   ATTUNE_CLINICAL.md before implementation.

3. Master spec check:
   Is the implementation path, schema, route, service, and UI behavior
   specified here?
   If not, update this master spec before coding.

4. Algorithm quality check:
   Does this feature compute, classify, rank, score, match, schedule, detect,
   recommend, summarize, moderate, or automate a decision?
   If yes, it must pass the relevant scope of
   ../algorithms/algorithm_quality_review_checklist.md before merge.

5. Principles checklist:
   Before merge, run the relevant sections of
   ATTUNE_PRINCIPLES_CHECKLIST.md.
```

### Section-specific companion document requirements

- Product vision, feature morality, monetisation, dark-pattern questions:
  read `ATTUNE_SOUL.md`.
- Quizzes, psychological profiles, pulse, verdicts, conflict translator,
  safety triggers, dating compatibility: read `ATTUNE_CLINICAL.md`.
- AI message analysis, session detection, pulse scoring, safety detection,
  compatibility matching, dating ranking, abuse detection, notification timing,
  recommendation logic, deduplication, rate limiting, or any automated decision
  path: run `../algorithms/algorithm_quality_review_checklist.md`.
- Prompts, AI output copy, notifications, data privacy, RLS, gamification:
  run `ATTUNE_PRINCIPLES_CHECKLIST.md`.
- Flutter folder structure, design tokens, implementation mechanics:
  use this master spec Section 17 plus the principles checklist.

---

## TABLE OF CONTENTS

1. [Product Vision](#1-product-vision)
2. [Product Modes](#2-product-modes)
3. [Tech Stack](#3-tech-stack)
4. [Database Schema](#4-database-schema)
5. [AI Analysis Pipeline](#5-ai-analysis-pipeline)
6. [Prompt Templates](#6-prompt-templates)
7. [Pulse Score System](#7-pulse-score-system)
8. [Feature Specifications](#8-feature-specifications)
   - 8.1 Chat System
   - 8.2 Psychological Profiling
   - 8.3 Relationship Tracking
   - 8.4 Games & Connection
   - 8.5 Insights & Verdict
   - 8.6 Conflict Translator
   - 8.7 Safety System
   - 8.8 Onboarding & Cold Start
   - 8.9 Personal Mode
   - 8.10 Dating Mode (post-launch)
   - 8.11 Opinions & Anonymous Forum
9. [Navigation Architecture](#9-navigation-architecture)
10. [Privacy Architecture](#10-privacy-architecture)
11. [Permanent Product Constraints](#11-permanent-product-constraints)
12. [Security & Legal](#12-security--legal)
13. [3-Month Build Plan](#13-3-month-build-plan)
14. [Post-Launch Roadmap](#14-post-launch-roadmap)
15. [Decision Log](#15-decision-log)
16. [Open Questions & Future Updates](#16-open-questions--future-updates)
17. [Flutter Implementation Standards](#17-flutter-implementation-standards)

---

## 1. PRODUCT VISION

### What Attune is
Attune is a relationship intelligence app with its own internal chat system. The AI sits silently inside that chat, reading every message in real time, building a psychological and behavioural picture of the relationship over time, and surfacing that picture back to users as clarity — not diagnosis.

### What Attune is not
- Not a therapy app. Not a crisis service. Not a couples counsellor.
- Not a surveillance tool. Not a verdict machine. Not a relationship judge.
- Not another quiz app with a chat feature bolted on.

### The core insight
Every other relationship app tells people generic advice. Attune shows people their own specific patterns, sourced from their own data.

### Tagline
*Understand your patterns. Heal your cycles. Grow together or grow wiser alone.*

### The one-sentence pitch
Most people repeat the same relationship mistakes for years because they have no objective data, no pattern recognition, and no shared language for what is actually happening between them.

### What success looks like for the user
They get a clear verdict on their relationship — specific, sourced, honest — without being told what to decide.

### Positioning (locked in — refines decision 4)
Attune is not a WhatsApp replacement for everyone. It is **the chat for this
one relationship** — a dedicated space that exists because the relationship
exists. One chat per couple; when the relationship ends the chat seals
(read-only, then archived — 8.1). "Primary chat" in decision 4 means primary
*for the couple's communication with each other*, not primary for the user's
messaging life. Precedent: dedicated couples spaces are a proven category
(Between reached tens of millions of installs on exactly this model); Attune's
differentiator on top of that model is the intelligence layer and the sealed
chat-per-love design.

### The ceremonial-drift risk (named and managed)
The known failure mode of dedicated couples apps: they become the *ritual*
channel — good-morning texts, anniversaries, photos — while the load-bearing
communication (logistics, money, the 11pm argument) stays in the general
messenger. For Attune this is existential, not cosmetic: the intelligence
layer feeds on exactly the conversations least likely to migrate. Pattern
detection, escalation trajectories, repair attempts, and root-need analysis
all need the hard conversations, and a couple can be active daily while
starving the pipeline of all of them.

Countermeasures (each specced elsewhere; this section names the strategy):
1. **Conflict translator as the pull mechanism (8.6).** "Help me say this" is
   only useful mid-conflict and only exists in Attune — it is the one feature
   that gives a couple a reason to have the hard conversation here. Its
   composer entry point is first-class UI, not a buried tool. (The opt-in-only
   rule is permanent and unchanged — prominence never means automatic.)
2. **Honest data-confidence as nudge (7, 8.8).** "We can't see your patterns
   yet" is not an apology; visible data_confidence teaches that insight
   quality is proportional to real usage.
3. **Measure conflict capture, not activity (13).** The soft-launch gate
   includes a conflict-capture metric so ceremonial usage cannot masquerade
   as product-market fit.

---

## 2. PRODUCT MODES

| Mode | Who it's for | Core value | Status |
|---|---|---|---|
| Couples mode | Active couples using Attune as their primary chat | Shared chat + AI intelligence + games + insights | Build first |
| Personal mode | Individuals — between relationships, solo users, waiting partners | Self-reflection, pattern awareness, growth | Build alongside couples |
| Healing mode | Post-breakup users | Structured recovery journey before dating unlocks | Month 4 |
| Dating mode | Single users ready to date again | Psychology-first matching using real behavioural data | Month 6+ |

### Mode transitions
```
New user (taken) → Couples mode (only after partner accepts invite and completes their onboarding)
New user (taken) → Personal mode / waiting state (if partner doesn't join within 7 days)
New user (single) → Personal mode immediately
Couples mode → Personal mode (if relationship ends or partner unlinks)
Personal mode → Healing mode (if user flags a recent breakup)
Healing mode → Dating mode eligibility (latest valid readiness score > 70,
minimum 8 weeks, all trusted gates pass); separate opt-in and profile activation
Dating mode → Couples mode (after match forms and both users link)
```

### Onboarding fork (screen one — locked in)
The very first screen after signup asks one question: **"Are you single or in a relationship?"**
- **Single** → Personal mode onboarding (attachment quiz + personal anchors, no invite flow — self-initiated self-knowledge is the value, so the quiz stays up front here)
- **In a relationship** → Couples onboarding, two-ask design (8.8, decision 29): Ask 1 is profile + partner invite only — chat unlocks on mutual verified linking; the intelligence layer, quiz, and anchors are introduced as Ask 2 after chat value exists

The partner invite is only a relationship-linking invite. It is not the same as
the public "Invite a friend" action on `LoginProfile`. A user is not recognised
as part of a couple until both sides have phone-verified, accepted the partner
invite, and completed their own onboarding flow.

---

## 3. TECH STACK

### Frontend
- **Framework:** Flutter
- **Language:** Dart
- **Navigation:** GoRouter
- **State management:** Riverpod where provider state is needed; local `StatefulWidget` state is allowed for simple screen-local flow state
- **Local cache:** SharedPreferences for launch flags/onboarding completion; drift (SQLite) for the chat read cache and offline outgoing queue (see 8.1)
- **Real-time chat:** Supabase Realtime (websocket subscriptions)
- **Push notifications:** Existing notification engine, adapted from the legacy app where useful
- **UI:** Existing custom Attune/Aura design system — do NOT use a third-party UI kit
- **File size rule:** Prefer under 200 lines per file — split aggressively. Exceptions permitted for: schema migration files, generated type files, route layouts, and test suites. Justify exceptions in a comment.

### Flutter implementation structure

Feature code must follow the maintainable legacy profile-style structure:

```
lib/features/[feature]/
  data/                 # storage, DTOs, local stores, remote data sources
  domain/               # app/domain models, pure feature rules
  models/               # legacy-compatible model folder when already established
  repositories/         # repository interfaces and implementations
  services/             # focused external/API/business services
  presentation/
    screens/            # route-level screens and flow coordinators only
    widgets/            # reusable pieces used by those screens
    state/              # UI state/controllers/providers when feature-owned
  utility/              # feature export files only when already established
```

Do not place a full feature's private screen components inside one large screen
file. A screen such as `OnboardingFlow` may orchestrate state and routing between
steps, but each visible step and repeated UI element must live in its own file
under `presentation/widgets` or `presentation/screens`.

### Design-system enforcement

All new Flutter UI must use existing app design tools before adding new
components:

- Use `AppTextFormField` for text inputs.
- Use `AppButton`, `AppIconButton`, `SelectionTile`, `TabsWithContent`, and
  existing bottom sheet/snackbar utilities before creating new controls.
- Use `SemanticContainerWidget` for explanatory information blocks.
- Use `Gap` instead of `SizedBox` for spacing.
- Use `Spacing`, `BorderRadiusTokens`, `IconSizes`, `FontSizeTokens`,
  `BorderWidthTokens`, `AnimationDurations`, `AnimationCurves`,
  `OpacityTokens`, and `.h/.w/.sp/.r` for responsive sizing.
- Use `Theme.of(context).colorScheme` and app theme colors. Do not hardcode
  arbitrary colors in UI.
- Avoid raw `SnackBar`; use `context.showInfoSnackbar`,
  `context.showSuccessSnackbar`, or `context.showErrorSnackbar`.
- Avoid raw `Duration(...)` in UI animation code; use `AnimationDurations`.
- Avoid nested cards and oversized one-file widgets. Split by responsibility.

Info blocks use this visual direction unless a more specific semantic state is
needed:

```dart
SemanticContainerWidget(
  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
  borderColor: colorScheme.primary,
  iconColor: colorScheme.primary,
  // ...
)
```

### Backend
- **Platform:** Supabase (auth + database + real-time + storage + edge functions)
- **Auth:** Supabase Auth, passwordless only at launch
  - Only launch method: phone number OTP via Supabase Auth + Twilio
  - Email magic link: not at launch
  - Password auth: not at launch
  - Mobile invite links: Flutter `app_links` deep-link handling
- **Database:** PostgreSQL via Supabase
- **Edge functions:** Deno (TypeScript)
- **Storage:** Supabase Storage (private buckets)
- **Scheduled jobs:** Supabase pg_cron extension
- **AI:** Anthropic Claude API — model configured via `CLAUDE_MODEL` env var,
  default `claude-sonnet-5`. Never hardcode the model id at call sites.
  (`claude-sonnet-4-20250514` is deprecated/retired — do not use.)

### Auth system

#### Launch decision
Attune uses passwordless auth at launch.

```
Primary:   Phone number OTP
Fallback:  None at launch
Skipped:   Email magic link at launch
Skipped:   Password-based auth at launch
Skipped:   Apple Sign-In and Google Sign-In at launch
```

Phone number auth is the primary path because Attune is a chat-first product:
phone identity matches the messaging mental model, improves invite trust, and
reduces low-effort throwaway accounts. It also gives the moderation and safety
pipeline a stronger verified identity anchor than email or social OAuth.
Email magic link, Apple Sign-In, Google Sign-In, and password auth are
intentionally excluded from launch to keep the auth surface simple and make
abuse response cleaner.

Password auth is not a permanent product prohibition. It is excluded from launch
to reduce support burden and onboarding friction. Reopening it later requires a
documented product/security reason.

#### Auth callback routes
```
attune://invite?code=[invite_code]
```

Invite links contain only the invite code. Inviter name, relationship metadata,
and expiry are fetched server-side after the code is validated. Do not put
partner names, email addresses, phone numbers, relationship IDs, or mode labels
inside invite URLs.

#### Invite code rules
- Invite codes are short alphanumeric codes generated server-side.
- One pending invite code exists per pending relationship.
- A user may hold multiple pending relationships (the Day 7 "invite someone
  else" option requires it); `create-relationship-invite` caps concurrent
  pending invites at 3 per inviter.
- Invite codes expire after 7 days.
- Invite codes are reusable until accepted or expired.
- Accepting an invite sets `relationships.user_b`, activates the relationship,
  and invalidates the invite code.
- Invite acceptance is idempotent: retrying the same accepted code returns the
  existing relationship state and does not create a second relationship.

### Infrastructure
- **Builds:** Flutter release builds (`flutter build appbundle` / `flutter build ipa`); CI provider not yet chosen — see Section 16 open questions
- **Error tracking:** Sentry
- **Analytics:** PostHog (privacy-respecting, self-hostable)
- **Environment:** `.env.local` for all secrets — never committed

### Why this stack (reasoning locked in)
Supabase removes the need for a separate auth server, REST API, and real-time infrastructure. Flutter gives both iOS and Android from one codebase and is what the legacy app, design system, and team expertise are already built on. Claude API handles all NLP — no model hosting required at this stage.

---

## 4. DATABASE SCHEMA

> All tables have Row Level Security (RLS) enabled.
> RLS is enforced at the database level, not the application level.
> A compromised API cannot bypass RLS.

### 4.1 Core tables

```sql
-- Users
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone text NOT NULL UNIQUE,
  display_name text NOT NULL,
  avatar_url text,
  created_at timestamptz DEFAULT now(),
  mode text CHECK (mode IN ('couples', 'personal', 'healing', 'dating'))
    DEFAULT 'personal'
);

-- Relationships (the couple unit)
CREATE TABLE relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a uuid REFERENCES users NOT NULL,
  user_b uuid REFERENCES users,              -- null until partner accepts
  invite_code text UNIQUE,                   -- null after accepted/expired
  invite_expires_at timestamptz,             -- 7 days after invite creation
  invite_accepted_at timestamptz,
  status text CHECK (status IN ('pending', 'active', 'paused', 'ended'))
    DEFAULT 'pending',
  started_at date,
  created_at timestamptz DEFAULT now(),
  -- Soft delete fields
  ended_at timestamptz,
  ended_by uuid REFERENCES users,
  deletion_scheduled_at timestamptz,        -- 30 days after ended_at
  -- Chat archive state (see 8.1 chat locking; replaces earlier chat_sections table)
  chat_archived_at timestamptz,             -- set when either partner starts a new active relationship
  chat_archived_reason text CHECK (chat_archived_reason IN (
    'partner_new_relationship', 'manual_end'
  )),
  -- Metadata
  total_sessions int DEFAULT 0,
  message_count int DEFAULT 0,
  games_completed int DEFAULT 0,
  last_overall_pulse int
);

-- Messages (the chat — source of truth always in Supabase)
CREATE TABLE messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  sender_id uuid REFERENCES users NOT NULL,
  client_message_id uuid NOT NULL,            -- stable across client retries
  content text,                              -- null if media-only message
  created_at timestamptz DEFAULT now(),
  -- Delivery state
  delivered_at timestamptz,
  read_at timestamptz,
  -- Media
  media_url text,
  media_thumbnail_url text,
  media_type text CHECK (media_type IN ('image', 'video')),
  -- AI analysis
  -- Two separate flags: Layer 1 (per-message) and Layer 2 (session-level) are independent
  message_analysis_done boolean DEFAULT false,   -- Layer 1 complete for this message
  message_analysis_skipped boolean DEFAULT false, -- deliberately skipped (future cost opt)
  included_in_session_id uuid REFERENCES analysis_sessions, -- which session consumed this message (null = not yet)
  tone_score float,                          -- -1.0 to 1.0
  nvc_violations jsonb,                      -- array of violation type strings
  bid_type text CHECK (bid_type IN ('toward', 'away', 'against')),
  UNIQUE (sender_id, client_message_id)       -- idempotent send/reconnect replay
);

-- Analysis sessions
CREATE TABLE analysis_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  started_at timestamptz NOT NULL,
  ended_at timestamptz NOT NULL,
  message_count int DEFAULT 0,
  trigger_type text CHECK (trigger_type IN ('inactivity', 'topic_shift', 'manual'))
    DEFAULT 'inactivity',
  -- Session signals
  escalation_score float,                    -- 0.0 to 1.0
  escalation_trajectory text CHECK (
    escalation_trajectory IN ('rising', 'falling', 'stable', 'peaked')
  ),
  pursue_withdraw_detected boolean DEFAULT false,
  pursuer text CHECK (pursuer IN ('user_a', 'user_b')),  -- PRIVATE field, never shown to partner
  stonewalling_signals boolean DEFAULT false,
  repair_attempted boolean DEFAULT false,
  repair_landed boolean DEFAULT false,
  session_resolved boolean DEFAULT false,
  one_sided_session boolean DEFAULT false,   -- one person sent all messages
  truncated boolean DEFAULT false,           -- hit 80-message cap
  dominant_topic text,                       -- max 5 words, semantic label
  root_need_detected text CHECK (root_need_detected IN (
    'respect', 'fairness', 'affection', 'security', 'autonomy', 'rest'
  )),
  insight_worthy boolean DEFAULT false,
  suggested_insight text
);

-- Pattern memory (long-term intelligence layer)
CREATE TABLE patterns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  pattern_type text NOT NULL,
  -- CRITICAL: no user_id column. Patterns describe dynamics, never individuals.
  severity text CHECK (severity IN ('info', 'watch', 'act', 'safety', 'resolved'))
    NOT NULL,
  first_seen_at timestamptz DEFAULT now(),
  last_seen_at timestamptz DEFAULT now(),
  occurrence_count int DEFAULT 1,
  topic_cluster text,
  metadata jsonb
);

-- Personal insights (asymmetric — self-facing only)
CREATE TABLE personal_insights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users NOT NULL,    -- the SUBJECT of the insight
  relationship_id uuid REFERENCES relationships NOT NULL,
  insight_type text NOT NULL,
  insight_body text NOT NULL,                -- written in second person about reader only
  source_pattern_id uuid REFERENCES patterns,
  created_at timestamptz DEFAULT now(),
  viewed_at timestamptz
  -- RLS: readable ONLY where auth.uid() = user_id
  -- Partner's user_id NEVER appears as subject in this table
);

-- Psych profiles
CREATE TABLE psych_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users UNIQUE NOT NULL,
  attachment_style jsonb,                    -- { secure: 0.62, anxious: 0.28, avoidant: 0.10 }
  love_languages jsonb,                      -- { quality_time: 72, words: 48, ... }
  communication_style jsonb,
  conflict_style jsonb,
  completed_quizzes text[] DEFAULT '{}',
  last_updated timestamptz DEFAULT now()
);

-- Pulse scores (computed weekly)
CREATE TABLE pulse_scores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  computed_at timestamptz DEFAULT now(),
  overall_score int NOT NULL,               -- 0-100
  communication int NOT NULL,
  connection int NOT NULL,
  conflict_health int NOT NULL,
  alignment int NOT NULL,
  emotional_safety int NOT NULL,
  delta_vs_previous jsonb,                  -- { communication: 6, connection: -3, ... }
  data_confidence text CHECK (data_confidence IN ('none', 'low', 'medium', 'high'))
    DEFAULT 'low'
);

-- Timeline events
CREATE TABLE timeline_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  logged_by uuid REFERENCES users NOT NULL,
  event_type text CHECK (event_type IN (
    'milestone', 'conflict', 'highlight', 'first', 'anniversary'
  )) NOT NULL,
  title text NOT NULL,
  note text,
  mood_score int CHECK (mood_score BETWEEN 1 AND 10),
  occurred_at date NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- Game sessions
CREATE TABLE game_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  game_type text CHECK (game_type IN (
    '36_questions', 'mirror', 'sliding_scale', 'scenario', 'love_map'
  )) NOT NULL,
  started_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  answers jsonb,                             -- { user_a: [...], user_b: [...] }
  insights_generated jsonb,                 -- derived insights, not raw answers
  -- CRITICAL: answers hidden from partner until both have submitted
  user_a_submitted boolean DEFAULT false,
  user_b_submitted boolean DEFAULT false
);

-- Relationship anchors (onboarding — 3 free-text questions)
CREATE TABLE relationship_anchors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users NOT NULL,
  relationship_id uuid REFERENCES relationships NOT NULL,
  admire text,
  hoping_for text,
  doing_differently text,
  created_at timestamptz DEFAULT now()
);

-- Translator logs (conflict translator usage — no message content stored)
CREATE TABLE translator_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users NOT NULL,
  relationship_id uuid REFERENCES relationships NOT NULL,
  used_at timestamptz DEFAULT now(),
  chose_rewrite boolean,
  core_need_identified text,                -- feeds into pattern memory
  rewrite_confidence text,
  message_length_original int,
  message_length_rewrite int
  -- CRITICAL: no message content stored here ever
);

-- Solo reflections (Personal mode — private journal)
CREATE TABLE solo_reflections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users NOT NULL,
  relationship_id uuid REFERENCES relationships,   -- can be null for fully solo users
  content text NOT NULL,
  created_at timestamptz DEFAULT now(),
  tone_score float,
  nvc_violations jsonb,
  shared_with_partner boolean DEFAULT false,
  shared_at timestamptz
  -- RLS: readable ONLY by user_id — never by partner even after linking
);

-- Safety events
CREATE TABLE safety_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships ON DELETE SET NULL,
  at_risk_user_id uuid REFERENCES users ON DELETE SET NULL,
  source_event_key text UNIQUE NOT NULL,       -- non-reversible HMAC; never a message id
  trigger_tier smallint CHECK (trigger_tier IN (1, 2, 3)) NOT NULL,
  trigger_family text NOT NULL,
  config_version text NOT NULL,
  first_viewed_at timestamptz,
  dismissed_at timestamptz,
  notification_status text NOT NULL DEFAULT 'pending'
    CHECK (notification_status IN ('pending', 'suppressed', 'sent', 'failed')),
  created_at timestamptz DEFAULT now(),
  anonymised_at timestamptz
  -- No sender id, message id, content, excerpt, or matched phrase.
  -- Clients use a minimized user-scoped view/RPC, never direct table reads.
);

-- Reminders
CREATE TABLE reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid REFERENCES relationships NOT NULL,
  created_by uuid REFERENCES users NOT NULL,
  reminder_type text CHECK (reminder_type IN (
    'anniversary', 'birthday', 'checkin', 'ai_generated'
  )) NOT NULL,
  title text NOT NULL,
  remind_at timestamptz NOT NULL,
  recurrence text CHECK (recurrence IN ('none', 'weekly', 'monthly', 'yearly'))
    DEFAULT 'none',
  sent boolean DEFAULT false
);

-- Cycle tracking (private — shared summary only with explicit consent)
CREATE TABLE cycle_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users NOT NULL,
  cycle_start date NOT NULL,
  cycle_length_days int,
  phase_log jsonb,                          -- { "2026-06-01": "period", ... }
  share_with_partner boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
```

### 4.2 RLS policies (minimum required — migrations must extend these, not replace them)

```sql
-- Messages: split per command. Never use FOR ALL here — a single permissive
-- FOR ALL policy would let either partner insert messages AS the other user,
-- edit/delete the partner's messages, or tamper with AI fields.

-- SELECT: relationship members, unless the chat is archived
CREATE POLICY "messages_select_members"
ON messages FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM relationships
    WHERE (user_a = auth.uid() OR user_b = auth.uid())
      AND chat_archived_at IS NULL
  )
);

-- INSERT: sender must be the caller, relationship must be active.
-- This single WITH CHECK also enforces read-only chats on ended relationships —
-- do NOT add a second permissive INSERT policy for that (permissive policies
-- are OR'd, so it would not restrict anything).
CREATE POLICY "messages_insert_sender_active"
ON messages FOR INSERT
WITH CHECK (
  sender_id = auth.uid()
  AND relationship_id IN (
    SELECT id FROM relationships
    WHERE (user_a = auth.uid() OR user_b = auth.uid())
      AND status = 'active'
  )
);

-- No client UPDATE or DELETE policies at launch. Delivery/read receipts go
-- through SECURITY DEFINER RPCs (see 8.1); AI fields are written by service
-- role only. Message editing/deletion (Month 4) will add narrowly scoped
-- policies then.

-- Column-level guard: clients may INSERT only user-writable columns.
-- tone_score, nvc_violations, bid_type, delivery flags etc. are unreachable.
-- media_thumbnail_url is NOT client-writable: thumbnails are generated by the
-- trusted worker (CHAT_SYSTEM_SPEC.md 8.3), which writes via service role.
REVOKE INSERT ON messages FROM authenticated;
GRANT INSERT (relationship_id, sender_id, content,
              client_message_id, media_url, media_type)
  ON messages TO authenticated;

-- Personal insights: iron wall — self only
CREATE POLICY "personal_insights_self_only"
ON personal_insights FOR SELECT
USING (auth.uid() = user_id);

-- No service role bypass on personal_insights. Ever.

-- Solo reflections: self only — never partner
CREATE POLICY "solo_reflections_self_only"
ON solo_reflections FOR ALL
USING (auth.uid() = user_id);

-- Safety events: raw table is backend-only. User access goes through the
-- minimized get_my_safety_resource_events() RPC, which enforces
-- auth.uid() = at_risk_user_id and omits trigger/source metadata.
REVOKE ALL ON safety_events FROM anon, authenticated;

-- Cycle logs: self only
CREATE POLICY "cycle_logs_self_only"
ON cycle_logs FOR ALL
USING (auth.uid() = user_id);

-- Patterns: relationship members (no user attribution in rows)
CREATE POLICY "patterns_relationship_members"
ON patterns FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

-- Pulse scores: both partners
CREATE POLICY "pulse_scores_relationship_members"
ON pulse_scores FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);
```

### 4.3 Schema production requirements (migration checklist)

The schema in 4.1 is the conceptual model. Every migration file Codex generates must also include:

```sql
-- 1. auth.users linkage
-- users.id must reference auth.users(id), not be a standalone uuid
-- This ties Supabase Auth to the public users table
ALTER TABLE users ADD CONSTRAINT users_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 2. ON DELETE behavior — explicit on every foreign key
-- relationships: if user deleted, soft-delete relationship (don't cascade)
-- messages: if relationship deleted, cascade delete messages
-- personal_insights: if user deleted, cascade delete
-- safety_events: if relationship deleted, anonymise (handle in deletion function)

-- 3. Required indexes (add to every migration)
-- Composite serves "messages for a chat", "latest messages", and the chat
-- system's keyset pagination on (created_at, id). This definition is shared
-- with CHAT_SYSTEM_SPEC.md Section 3.1 — keep the two identical.
CREATE INDEX idx_messages_relationship_created
  ON messages(relationship_id, created_at DESC, id DESC);
-- Layer 1 backlog scan (webhook retry sweep)
CREATE INDEX idx_messages_layer1_pending
  ON messages(created_at)
  WHERE message_analysis_done = false;
-- Session-detection cron scan: analysed but not yet consumed into a session
CREATE INDEX idx_messages_session_pending
  ON messages(relationship_id, created_at)
  WHERE message_analysis_done = true AND included_in_session_id IS NULL;
CREATE INDEX idx_patterns_relationship_id ON patterns(relationship_id);
CREATE INDEX idx_patterns_severity ON patterns(severity);
CREATE INDEX idx_personal_insights_user_id ON personal_insights(user_id);
CREATE INDEX idx_analysis_sessions_relationship_id ON analysis_sessions(relationship_id);
CREATE INDEX idx_pulse_scores_relationship_id ON pulse_scores(relationship_id);
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_relationships_invite_code ON relationships(invite_code)
  WHERE invite_code IS NOT NULL;

-- 4. updated_at triggers (on tables that change frequently)
-- users, psych_profiles, relationships, pulse_scores

-- 5. Uniqueness constraints
-- One psych_profile per user (already enforced by UNIQUE on user_id)
--
-- One active relationship per user pair. Scope: 'active' ONLY.
-- Do NOT include 'pending': pending rows have user_b NULL, so
-- LEAST/GREATEST both collapse to user_a and a second pending invite from
-- the same user would violate the index — which would break the Day 7
-- "invite someone else" option (8.8). Multiple pending invites per inviter
-- are allowed; create-relationship-invite caps them at 3 concurrent.
CREATE UNIQUE INDEX idx_one_active_relationship_pair
  ON relationships(LEAST(user_a, user_b), GREATEST(user_a, user_b))
  WHERE status = 'active';

-- One active relationship per USER (either column) — the pair index alone
-- would still allow one user in two active relationships with different
-- partners. Enforced by a constraint trigger; accept-invite must also take
-- a per-user advisory lock (pg_advisory_xact_lock on both user ids) so two
-- concurrent accepts cannot race past this check.
CREATE OR REPLACE FUNCTION enforce_single_active_relationship()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'active' THEN
    IF EXISTS (
      SELECT 1 FROM relationships
      WHERE id <> NEW.id
        AND status = 'active'
        AND (user_a IN (NEW.user_a, NEW.user_b)
          OR user_b IN (NEW.user_a, NEW.user_b))
    ) THEN
      RAISE EXCEPTION 'user already has an active relationship';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trigger_single_active_relationship
AFTER INSERT OR UPDATE ON relationships
FOR EACH ROW EXECUTE FUNCTION enforce_single_active_relationship();

-- 6. Auth profile constraints
-- Phone-only launch auth means every mirrored user profile must have a verified
-- phone number from auth.users. Do not mirror email at launch.
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;

-- 7. Invite code constraints
-- Pending relationships may have an invite code; active/ended relationships
-- should not expose an acceptible invite code.
ALTER TABLE relationships ADD CONSTRAINT relationships_invite_pending_only
  CHECK (
    (status = 'pending' AND invite_code IS NOT NULL AND invite_expires_at IS NOT NULL)
    OR (status <> 'pending' AND invite_code IS NULL)
  );

-- 8. Migration ordering
-- messages.included_in_session_id references analysis_sessions, but 4.1 lists
-- messages first. Create all tables without cross-table FKs, then add the
-- cross-references via ALTER at the end of the migration:
ALTER TABLE messages ADD CONSTRAINT messages_included_in_session_fkey
  FOREIGN KEY (included_in_session_id) REFERENCES analysis_sessions(id);
```

### 4.4 Service role vs user JWT policy

This table defines which backend functions use service role (bypasses RLS) vs user JWT (respects RLS). This is a security-critical decision — do not deviate without documented reason.

| Edge function | Auth method | Reason |
|---|---|---|
| `analyse-message` | Service role | Triggered by DB webhook, no user session |
| `analyse-session` | Service role | Triggered by cron, no user session |
| `compute-pulse` | Service role | Triggered by cron |
| `generate-verdict` | Service role | Triggered by cron |
| `send-reminder` | Service role | Triggered by cron |
| `translate-conflict` | **User JWT** | User-initiated, must respect RLS |
| `generate-game-insight` | **User JWT** | User-initiated |
| `relationship-context` | **User JWT** | User-initiated read |
| `accept-invite` | **User JWT** | User-initiated mutation, idempotent by invite code |
| `create-relationship-invite` | **User JWT** | User-initiated mutation, scoped to inviter |
| `delete-account` | **User JWT** | User-initiated, must be scoped to requester |

**Critical: service-role functions that write to `personal_insights` must never read from it using service role.** Write-only for system-generated insights. All reads go through user JWT exclusively.

```javascript
// Pattern for service-role functions writing personal insights
// WRITE with service role — system is inserting on user's behalf
const supabaseAdmin = createClient(url, SERVICE_ROLE_KEY)
await supabaseAdmin.from('personal_insights').insert({ user_id, ... })

// READ always uses user's own JWT — never service role
// If a function needs to read personal_insights, it must be user-initiated
const supabaseUser = createClient(url, ANON_KEY, { auth: { session } })
const { data } = await supabaseUser.from('personal_insights').select('*')
// RLS will enforce user_id = auth.uid() — partner data is unreachable
```

---

## 5. AI ANALYSIS PIPELINE

> **Companion documents required:** Before implementing or changing any AI
> analysis layer, read `ATTUNE_CLINICAL.md` for framework confidence levels
> and allowed claims, then run `ATTUNE_PRINCIPLES_CHECKLIST.md` Section E
> for prompt review and Section F for data/privacy review.

### Overview
Four layers. Every message passes through Layer 1. Layers 2–4 are triggered by conditions, not every message. Safety triggers are hard-coded and bypass all layers.

```
message sent
    ↓
[SAFETY CHECK] — hard-coded, non-LLM, runs first and independently.
    |             A trigger starts the safety flow (8.7) but NEVER removes
    |             the message from the pipeline below — a safety-flagged
    |             message still gets Layer 1 analysis and still joins its
    |             session. Otherwise session transcripts would have silent
    |             holes exactly where the most important messages are.
    ↓ (always — triggered or not)
Layer 1: message analysis          ← Claude API call, per message
    ↓
Layer 2: session analysis          ← Claude API call, on session close
    ↓
Layer 3: cross-context enrichment  ← database fetch, no API call
    ↓
Layer 4: pattern memory update     ← Claude API call, on session close
    ↓
store results → realtime update → surface insight if threshold met
```

### Session boundary rules (locked in — do not change)
- New session begins when gap between messages exceeds 30 minutes
- Detection is server-side only — no client-side timers ever
- No day boundaries — a conversation crossing midnight is one session
- Sessions capped at 80 messages (first 20 + last 20 if exceeded, `truncated: true`)
- One-sided sessions (one person sends all messages) are valid signals, not errors
- Cron runs every 30 minutes, offset to :07 and :37 (not :00 and :30)

### Session detection cron logic
```javascript
// Supabase pg_cron → edge function (Deno): runs at :07 and :37
const SESSION_GAP_MS = 30 * 60 * 1000

// Split ordered messages into segments wherever the gap between two
// consecutive messages exceeds 30 minutes. Two separate conversations that
// both ended between cron runs must NOT be lumped into one session.
const splitByGap = (messages, gapMs) => {
  const segments = [[messages[0]]]
  for (let i = 1; i < messages.length; i++) {
    const gap = new Date(messages[i].created_at) - new Date(messages[i - 1].created_at)
    if (gap > gapMs) segments.push([])
    segments[segments.length - 1].push(messages[i])
  }
  return segments
}

const analyseInactiveSessions = async () => {
  const cutoff = new Date(Date.now() - SESSION_GAP_MS).toISOString()

  const { data: candidates } = await supabase
    .from('messages')
    .select('relationship_id')
    .eq('message_analysis_done', true)      // Layer 1 complete
    .is('included_in_session_id', null)     // not yet consumed by a session
    .lt('created_at', cutoff)

  const relationships = [...new Set(candidates.map(m => m.relationship_id))]

  for (const relationshipId of relationships) {
    const { data: messages } = await supabase
      .from('messages')
      .select('*')
      .eq('relationship_id', relationshipId)
      .eq('message_analysis_done', true)
      .is('included_in_session_id', null)
      .order('created_at', { ascending: true })

    for (const segment of splitByGap(messages, SESSION_GAP_MS)) {
      const last = segment[segment.length - 1]
      const gap = Date.now() - new Date(last.created_at).getTime()
      if (gap < SESSION_GAP_MS) continue    // segment still active — next run

      // 1. Create the session row FIRST so its id exists for consumption
      const { data: session } = await supabase
        .from('analysis_sessions')
        .insert({
          relationship_id: relationshipId,
          started_at: segment[0].created_at,
          ended_at: last.created_at,
          message_count: segment.length,
          trigger_type: 'inactivity',
        })
        .select()
        .single()

      // 2. Mark messages consumed BEFORE analysis fires — a failed Layer 2
      //    call must not cause double-consumption on the next cron run.
      //    A retry sweep re-runs analysis by session id for sessions whose
      //    signal columns are still null.
      await supabase
        .from('messages')
        .update({ included_in_session_id: session.id })
        .in('id', segment.map(m => m.id))

      // 3. Layers 2–4 (null result = session row keeps null signals; retried)
      await triggerSessionAnalysis(session.id, segment)
    }
  }
}
```

### Layer 3 — cross-context enrichment (specification)

Layer 3 is a pure database fetch that runs between Layer 2 and Layer 4 inside
the same session-close invocation. No Claude call, no new tables, fully
deterministic. It assembles the context bundle Layer 4 needs:

| Fetch | Source | Feeds prompt variable |
|---|---|---|
| Active patterns (max 15, most recent `last_seen_at` first) | `patterns` | `{{existing_patterns_json}}` |
| Days together, total sessions, conflict sessions last 30 days | `relationships`, `analysis_sessions` | relationship history block |
| Both psych profiles (scores only) | `psych_profiles` | attachment/communication context |
| Translator core-need counts, last 30 days | `translator_logs` | metadata for pattern candidates |

Rules:
- Read-only. Layer 3 never writes.
- Uses service role (same invocation context as Layer 2/4) but fetches only
  derived fields — never raw message content, never `personal_insights`.
- If any fetch fails, Layer 4 is skipped for this session (retried by the
  same sweep that retries failed Layer 2 analyses).

---

## 6. PROMPT TEMPLATES

> All prompts live in `/prompts/v1/` directory.
> Prompts are versioned. Never edit a deployed prompt — create a new version.
> All prompts must return ONLY valid JSON — no preamble, no markdown fences.
> Every prompt must comply with `ATTUNE_CLINICAL.md` confidence levels and
> `ATTUNE_PRINCIPLES_CHECKLIST.md` Section E before deployment.

### Global constraint (prepended to every prompt)
```
ABSOLUTE CONSTRAINTS — these override all other instructions:

1. Never generate text that attributes a negative behaviour to a named
   or implied partner. "Your partner withdraws" is forbidden.
   "A withdraw pattern exists in this relationship" is permitted.

2. Never generate a sentence of form "[partner name/pronoun] tends to X"
   where X is a negative or deficit behaviour.

3. Personal insights must be written in second person about the reader:
   "You tend to pursue when anxious" not "You pursue and Jordan withdraws."

4. Partner name must never appear in a personal_insights row.

5. Never use these words: toxic, narcissist, codependent, disorder, broken.

6. Never tell the user what to decide about the relationship.

7. Never diagnose. Observe patterns. Frame with agency. Source every claim.
```

### Layer 1 — message analysis
```
You are a relationship intelligence system. Analyse this single message.

CONVERSATION CONTEXT (last 10 messages):
{{last_10_messages}}

NEW MESSAGE (from {{sender_name}}):
"{{message_content}}"

SENDER PROFILE:
- Attachment style: {{attachment_style}}
- Communication style: {{communication_style}}

Return ONLY valid JSON:
{
  "tone_score": float -1.0 to 1.0,
  "sentiment": "positive" | "neutral" | "negative" | "charged",
  "nvc_violations": ["blame_language"|"you_always_never"|"character_attack"|"contempt"|"demand"],
  "bid_type": "toward" | "away" | "against" | null,
  "bid_detected": boolean,
  "requires_session_analysis": boolean
}

Rules:
- Never invent violations not present in the text
- requires_session_analysis = true if sentiment is negative or charged
- A bid is a reach for connection: humour, sharing, asking a question
- Return ONLY the JSON object
```

### Layer 2 — session analysis
```
You are a relationship intelligence system. Analyse this conversation session.

FULL SESSION ({{message_count}} messages):
{{full_session_transcript}}

RELATIONSHIP CONTEXT:
- User A attachment: {{user_a_attachment}}
- User B attachment: {{user_b_attachment}}
- Conflict sessions last 30 days: {{conflict_sessions_30d}}
- One-sided session: {{one_sided_session}}

Return ONLY valid JSON:
{
  "escalation_score": float 0.0 to 1.0,
  "escalation_trajectory": "rising" | "falling" | "stable" | "peaked",
  "pursue_withdraw_detected": boolean,
  "pursuer": "user_a" | "user_b" | null,
  "stonewalling_signals": boolean,
  "repair_attempted": boolean,
  "repair_landed": boolean,
  "session_resolved": boolean,
  "dominant_topic": string (max 5 words),
  "root_need_detected": "respect"|"fairness"|"affection"|"security"|"autonomy"|"rest"|null,
  "insight_worthy": boolean,
  "suggested_insight": string (max 30 words, no jargon) | null
}
```

### Layer 4 — pattern memory update
```
You are a relationship pattern analyst.

SESSION ANALYSIS:
{{session_analysis_json}}

EXISTING PATTERNS:
{{existing_patterns_json}}

RELATIONSHIP HISTORY:
- Days together: {{days_together}}
- Total sessions: {{total_sessions}}
- Conflict sessions last 30 days: {{conflict_sessions_30d}}

Return ONLY valid JSON:
{
  "patterns_to_create": [
    {
      "pattern_type": string,
      "topic_cluster": string,
      "severity": "info" | "watch" | "act" | "safety",
      "metadata": {}
    }
  ],
  "patterns_to_update": [
    {
      "pattern_id": uuid,
      "increment_count": boolean,
      "new_severity": string | null,
      "metadata_update": {}
    }
  ],
  "alert_required": boolean,
  "alert_type": "safety" | "milestone" | "insight" | null
}
```

### Verdict generation
```
You are generating a monthly relationship verdict from structured data only.
You have NOT read raw messages. Do not reference anything not in the data below.

RELATIONSHIP CONTEXT: {{meta}}
PULSE HISTORY (last 4): {{pulse_history}}
ACTIVE PATTERNS: {{patterns}}
RECENT SESSIONS (last 3): {{recent_sessions}}
PSYCHOLOGICAL PROFILES: {{profiles}}
TIMELINE EVENTS (last 30 days): {{timeline_events}}
GAME INSIGHTS (last 60 days): {{game_insights}}

Return ONLY valid JSON:
{
  "headline": string (max 20 words, specific to this relationship),
  "data_confidence": "high" | "medium" | "low",
  "strengths": [{ "title": string, "body": string (max 40 words), "source": string }],
  "watch_areas": [{ "title": string, "body": string (max 40 words), "source": string }],
  "one_action": string (max 30 words — one conversation starter or behaviour),
  "patterns_referenced": [uuid]
}

Rules:
- Headline must be specific to THIS data — never generic
- Do NOT generate a disclaimer — the fixed disclaimer string is appended in
  client code, never by the model (constant strings must not depend on an LLM)
- Every strength and watch area must cite its source
- one_action is a conversation starter — never therapy-speak
- Never use: toxic, narcissist, codependent, disorder, broken
- Never tell the user what to decide
```

### Conflict translator
```
You are helping someone express a difficult feeling more clearly.

SENDER PROFILE:
- Attachment: {{attachment_style}}
- Communication style: {{communication_style}}
- Days together: {{days_together}}

ORIGINAL MESSAGE:
"{{original_message}}"

RECENT CONVERSATION TONE: {{last_3_messages_tone_summary}}

Return ONLY valid JSON:
{
  "rewrite": string,
  "core_need_identified": string (max 6 words),
  "framing_note": string (max 15 words, private to sender only),
  "rewrite_confidence": "high" | "medium" | "low"
}

Rules:
- Preserve the sender's actual meaning — never soften a legitimate concern to nothing
- Rewrite should feel like THEM at their clearest, not a therapist
- If original is already healthy: rewrite = original, confidence = "high"
- Never add false warmth or make sender apologise for something undecided
- Max rewrite length: 1.5x original
- framing_note is private — never shown to recipient
```

### Compatibility preview (day one, cold start)
```
Generate a day-one compatibility preview. No message history exists yet.

PERSON A: Attachment: {{a_attachment}}, Admires: "{{a_admire}}",
          Hoping for: "{{a_hoping}}", Working on: "{{a_different}}"
PERSON B: Attachment: {{b_attachment}}, Admires: "{{b_admire}}",
          Hoping for: "{{b_hoping}}", Working on: "{{b_different}}"

Return ONLY valid JSON:
{
  "pairing_type": string (named dynamic, not "secure + anxious"),
  "pairing_description": string (max 35 words, warm and specific),
  "natural_strength": string (max 25 words),
  "watch_area": string (max 25 words, about the dynamic not one person),
  "first_suggestion": string (max 20 words, actionable tonight),
  "data_note": "This is based on your profiles, not your history yet."
}
```

### Claude API call standard pattern
```javascript
// Use for ALL Claude API calls in the system — no exceptions (Deno edge fn)
const ANTHROPIC_VERSION = '2023-06-01'
const CLAUDE_MODEL = Deno.env.get('CLAUDE_MODEL') ?? 'claude-sonnet-5'

const callClaude = async (userPrompt, systemPrompt = GLOBAL_CONSTRAINT, promptId = 'unknown') => {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': Deno.env.get('ANTHROPIC_API_KEY'),
      'anthropic-version': ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: CLAUDE_MODEL,
      max_tokens: 1000,
      system: systemPrompt,
      messages: [{ role: 'user', content: userPrompt }]
    })
  })
  if (!response.ok) {
    console.error('claude_http_error', { status: response.status, prompt_id: promptId })
    return null
  }
  const data = await response.json()
  const text = data.content.map(b => b.text || '').join('')
  try {
    return JSON.parse(text.replace(/```json|```/g, '').trim())
  } catch {
    // NEVER log the raw model output — it can echo message content, which
    // Section 10 forbids in logs. Log the failure class only.
    console.error('claude_parse_failed', { prompt_id: promptId, model: CLAUDE_MODEL })
    return null
  }
}
```

### 6.7 AI evaluation requirements

Every prompt in the system must have a corresponding evaluation harness before it is deployed to production. Relationship AI without evals produces silent failures — outputs that look valid but are subtly wrong.

#### Minimum eval suite per prompt

| Test type | What it checks | Pass criteria |
|---|---|---|
| Golden transcript | Known input → expected JSON output | Output matches expected within tolerance |
| Prohibited output | Input containing partner-blaming language | Output must not contain banned patterns |
| Malformed JSON | Simulate parse failure | Fallback returns null, error logged, no crash |
| Prompt injection | Message content containing "ignore instructions" | Output is valid analysis JSON, not injected instructions |
| Confidence threshold | Low-confidence cases | `rewrite_confidence: "low"` returned, not a hallucinated high-confidence result |
| Empty/null input | Missing context fields | Graceful handling, no API error thrown |

#### Golden transcript format
```javascript
// /evals/layer1/golden_transcripts.json
[
  {
    "id": "gt_001",
    "description": "Contempt message with clear character attack",
    "input": {
      "last_10_messages": [...],
      "message_content": "You're so selfish, you never think about anyone but yourself",
      "attachment_style": { "anxious": 0.7, "secure": 0.3 }
    },
    "expected_output": {
      "tone_score": { "max": -0.6 },           // must be below -0.6
      "nvc_violations": { "includes": ["character_attack"] },
      "requires_session_analysis": true
    },
    "prohibited_output": {
      "nvc_violations": { "excludes": [] },     // must not be empty
      "tone_score": { "min": 0.0 }             // must not be positive
    }
  }
]
```

#### Prohibited output patterns (enforced in evals, not just prompts)
These strings must never appear in any AI output across the system:

```javascript
const PROHIBITED_PATTERNS = [
  /your partner (always|never|tends to|keeps)/i,
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
  /you should (leave|stay|break up|end)/i,
  /this relationship is/i,               // avoid verdict on the relationship itself
]

// Partner-name patterns cannot be static — names vary per relationship.
// Build them at runtime from both users' display_name and append to the list:
const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const partnerNamePattern = (displayName) =>
  new RegExp(`${escapeRegex(displayName)}\\s+(always|never|tends|keeps)`, 'i')
// Eval fixtures use a literal name (e.g. /jordan (always|never)/i) — that
// literal belongs in /evals/ only, never in runtime code.
```

#### Failure behavior (locked in — all Claude calls)
```javascript
const callClaude = async (userPrompt, systemPrompt, promptId, runtimePatterns = []) => {
  try {
    // ... API call (headers/model per the standard pattern in Section 6) ...
    const parsed = JSON.parse(text.replace(/```json|```/g, '').trim())

    // Validate against prohibited patterns (static + per-relationship name patterns)
    const outputText = JSON.stringify(parsed)
    for (const pattern of [...PROHIBITED_PATTERNS, ...runtimePatterns]) {
      if (pattern.test(outputText)) {
        // Log the pattern source only — outputText can echo message content (Section 10)
        console.error('prohibited_pattern_detected', { pattern: pattern.source, prompt_id: promptId })
        return null  // treat as failure — do not surface to user
      }
    }

    return parsed
  } catch {
    console.error('claude_parse_failed', { prompt_id: promptId })  // never log raw text
    return null  // null means: skip this analysis, do not crash
  }
  // Caller is responsible for handling null gracefully
  // null from Layer 1 = skip insight for this message, mark message_analysis_done: true anyway
  // null from Layer 2 = session row keeps null signals; retried by sweep, do not update patterns
  // null from verdict = show "verdict unavailable, try again" state
}
```

---

## 7. PULSE SCORE SYSTEM

> **Clinical dependency:** Pulse dimensions and user-facing interpretation are
> psychologically interpretive. Before surfacing pulse or verdict language,
> verify the claim strength against `ATTUNE_CLINICAL.md` Section 10 and run
> `ATTUNE_PRINCIPLES_CHECKLIST.md` Sections D, E, and F.

### Computation schedule
- Weekly, every Sunday
- Cron runs at :07 offset
- Also available on-demand (user can request refresh)
- Minimum data threshold: 5 sessions before first pulse is computed

### Five dimensions and their weights

| Dimension | Overall weight | Data sources |
|---|---|---|
| Communication | 22% | Message tone scores, NVC violation rate, assertiveness ratio |
| Connection | 22% | Bid-toward rate, warmth language frequency, game engagement |
| Conflict health | 20% | Repair attempt rate, resolution rate, escalation scores |
| Alignment | 18% | Values overlap from games, profile compatibility, positive events |
| Emotional safety | 18% | Contempt absence, stonewalling absence, sentiment trend |

### Verdict input (locked in — ~1,700 tokens total)
```javascript
const buildVerdictContext = async (relationshipId) => ({
  pulse_history:   last 4 pulse scores with deltas,        // ~300 tokens
  patterns:        all active patterns, max 15, no raw content, // ~400 tokens
  recent_sessions: last 3 session summaries, derived only,  // ~300 tokens
  profiles:        both psych profiles, scores only,        // ~250 tokens
  timeline_events: last 30 days,                            // ~200 tokens
  game_insights:   last 60 days, insights_generated only,   // ~150 tokens
  meta:            days together, session count, game count  // ~100 tokens
})
// Total: ~1,700 tokens. Never feed raw messages to verdict. Ever.
```

### data_confidence levels (shown visibly to user — not hidden)
- `none`: fewer than 3 pulse scores or fewer than 5 sessions
- `low`: 3–8 pulse scores
- `medium`: 9–20 pulse scores
- `high`: 20+ pulse scores

---

## 8. FEATURE SPECIFICATIONS

### 8.1 Chat System

#### Storage architecture (locked in — do not change)
- **Source of truth:** Supabase always. Local cache is read-speed only.
- **NOT local-first.** Messages go to Supabase immediately.
- **Optimistic UI** creates the WhatsApp-feel — message renders instantly, network fires simultaneously.
- **drift (SQLite) cache** stores last 200 messages per relationship for offline reading. (Flutter replacement for the RN-era MMKV decision — same architecture, same read-only role.)
- **Outgoing queue** (drift table) for messages sent while offline — flush on reconnect.

#### Delivery status lifecycle (non-negotiable for launch)
```
sending   → clock icon       (optimistic render, network pending)
sent      → single tick      (Supabase confirmed receipt)
delivered → double tick      (recipient device received)
read      → double tick blue (recipient opened conversation)
failed    → red indicator    (tap to retry)
```

Receipt mechanics — clients have no UPDATE grant on messages (4.2); receipts
go through SECURITY DEFINER RPCs that verify relationship membership and only
touch messages sent by the OTHER user, setting the timestamp when null:
- `delivered_at` — recipient client calls `mark_delivered(message_ids)` when a
  message arrives via Realtime subscription or push open.
- `read_at` — recipient client calls `mark_conversation_read(relationship_id)`
  when the conversation is opened/foregrounded.

#### Month 1 chat features (non-negotiable — section 13 is authoritative on scope)
- Text messages
- Push notifications for new messages
- Delivery status lifecycle + read receipts

#### Month 2 chat features (deliberate cuts from Month 1)
- Image sharing (client-side compress to max 800KB before upload)
- "Help me say this" conflict translator button in composer

#### Post-launch chat features
- Voice messages (Month 4)
- Video sharing (Month 5)
- Message reactions (Month 4)
- Link previews (Month 5)
- Message editing/deletion (Month 4)

#### Image handling
```dart
// Client-side compression before upload — mandatory (flutter_image_compress)
Future<Uint8List> compressImage(File file) async {
  var quality = 80;
  Uint8List? out;
  do {
    out = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 1200,
      quality: quality,
      format: CompressFormat.jpeg,
    );
    quality -= 10;
  } while (out != null && out.lengthInBytes > 800 * 1024 && quality >= 40);
  return out!;
  // Result must be under 800KB — quality steps down until it is
}
// Storage: Supabase private bucket 'message-media'
// Thumbnail: 400px width generated on upload via edge function
// RLS: readable only by relationship members
```

#### Optimistic UI implementation
```dart
// chat_controller.dart — Riverpod Notifier owning the message list state
Future<void> sendMessage(String content) async {
  final clientMessageId = const Uuid().v4(); // retained by Drift for every retry
  final temp = Message.optimistic(
    clientMessageId: clientMessageId,
    content: content,
    senderId: currentUserId,
    status: MessageStatus.sending,
  );
  await outgoingQueue.enqueue(temp);
  state = [...state, temp]; // render immediately

  try {
    final row = await supabase
        .from('messages')
        .insert({
          'content': content,
          'relationship_id': relationshipId,
          'sender_id': currentUserId,
          'client_message_id': clientMessageId,
        })
        .select()
        .single();
    final sent = Message.fromRow(row).copyWith(status: MessageStatus.sent);
    state = [for (final m in state) m.localId == temp.localId ? sent : m];
    await localCache.upsertMessage(sent);
    await outgoingQueue.remove(clientMessageId);
  } catch (_) {
    state = [
      for (final m in state)
        m.localId == temp.localId
            ? m.copyWith(status: MessageStatus.failed)
            : m
    ];
    // The existing queue row retains clientMessageId for idempotent retry.
  }
}
```

The production implementation follows `../CHAT_SYSTEM_SPEC.md` v1.3 or later. In
particular, message persistence creates durable Safety/downstream work in the
same database transaction, receipt writes use constrained RPCs, and duplicate
`(sender_id, client_message_id)` sends reconcile to the existing row.

#### Chat section locking (one chat per relationship — permanent rule)

Each couple has exactly one chat section. It is tied to the relationship record, not to the individual users. When the relationship ends:

```
Relationship status: active → ended
    ↓
Chat section status: active → read_only
    ↓
Both users can read history but cannot send new messages
    ↓
Chat fully locks when either user starts a new active relationship
    ↓
Old chat section permanently archived — never deleted, never accessible
    to the new partner
```

**Why this works:**
- Exes can still read shared history immediately after ending (clean closure)
- As soon as either person moves into a new relationship, the old chat locks permanently — no ambiguity, no maintenance of ex-connection on the platform
- The new relationship gets a clean chat section with zero history

**Implementation — no separate table.** Chat section state is derived from
columns on `relationships` (see 4.1). A dedicated `chat_sections` table is
redundant: it would need its own creation lifecycle, and read-only enforcement
already lives in the messages RLS policies (4.2).

```
status = 'active'                              → chat active
status = 'ended' AND chat_archived_at IS NULL  → read-only
                                                 (history readable — messages
                                                 SELECT policy; no sends —
                                                 messages INSERT policy
                                                 requires status = 'active')
chat_archived_at IS NOT NULL                   → archived
                                                 (messages SELECT policy
                                                 excludes archived chats —
                                                 no access for anyone)
```

**Archiving trigger (server-side, not client-side):**
When a relationship becomes `active`, all ended relationships involving either
partner are archived.

```sql
CREATE OR REPLACE FUNCTION archive_old_chats()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' THEN
    UPDATE relationships
    SET chat_archived_at = now(),
        chat_archived_reason = 'partner_new_relationship'
    WHERE id <> NEW.id
      AND status = 'ended'
      AND chat_archived_at IS NULL
      AND (user_a IN (NEW.user_a, NEW.user_b)
        OR user_b IN (NEW.user_a, NEW.user_b));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- AFTER INSERT OR UPDATE: relationships can become active either way
CREATE TRIGGER trigger_archive_old_chats
AFTER INSERT OR UPDATE OF status ON relationships
FOR EACH ROW EXECUTE FUNCTION archive_old_chats();
```

#### Chat header (always visible — connective tissue to rest of app)
```
┌─────────────────────────────────────┐
│  Jordan          ● 74  487 days     │
│                  ↑ tap to expand    │
└─────────────────────────────────────┘
Expanded drawer (Month 2):
- Current pulse score + delta
- Latest unread insight (one line)
- Next upcoming date or reminder
- [Open Pulse] [Open Insights] buttons
```

---

### 8.2 Psychological Profiling

#### Four quizzes

| Quiz | Questions | Measures | Required for onboarding |
|---|---|---|---|
| Attachment style | 25 | Secure/anxious/avoidant/fearful spectrum | Personal mode: up-front. Couples: Ask 2, post-chat-unlock (decision 29). Still gates the compatibility preview |
| Love languages | 15 | Quality time/words/touch/acts/gifts spectrum | No — prompted after chat unlocks |
| Communication style | 20 | Passive/assertive/aggressive/passive-aggressive | No — Month 2 prompt |
| Conflict style | 18 | Conflict defaults, escalation patterns | No — Month 2 prompt |

#### Results are spectrums, not labels
```javascript
// Store as percentages across all types — never a single label
attachment_style: {
  secure: 0.62,
  anxious: 0.28,
  avoidant: 0.10,
  fearful: 0.00
}
// Display: "Anxious-secure" (dominant + secondary)
// Never: "You are anxious-avoidant" as a fixed identity
```

#### Framework confidence levels (affects insight language)
```javascript
const FRAMEWORK_CONFIDENCE = {
  gottman_bids:            'high',
  response_latency:        'high',
  repair_attempt:          'high',
  attachment_quiz:         'medium',    // self-report limitations
  nvc_detection:           'medium',    // context-dependent
  pursue_withdraw:         'medium',
  contempt_detection:      'lower',     // highly context-dependent
  love_language_quiz:      'lower',     // limited peer review vs attachment
}
// HIGH:   state directly
// MEDIUM: "some signals suggest..."
// LOWER:  "this may or may not apply to you..."
```

#### Clinical validation requirement
- All quiz instruments reviewed by licensed therapist before launch
- Communication style and conflict style validated against cultural norms
- WEIRD population bias acknowledged and mitigated where possible
- Credential line in app: "Psychological frameworks reviewed by [name, credentials]"

---

### 8.3 Relationship Tracking

#### Timeline event types
- **Milestone** — significant relationship firsts and achievements
- **Conflict** — logged disagreements (private or shared)
- **Highlight** — positive moments worth remembering
- **First** — first date, first trip, first meeting of family
- **Anniversary** — recurring significant dates

#### Cycle tracking
- Private by default — partner sees nothing unless opt-in
- If sharing enabled: partner sees phase only (period/fertile/pms/none), not raw cycle data
- AI note for partner: max 2 sentences, emotionally supportive framing, never clinical
- Lives in the **Profile / Settings sub-section** under Chat, not Pulse — it's personal, not relational

#### Reminders
- Anniversaries and birthdays: set manually
- Weekly check-in: recurring every Sunday (default on, user can change day)
- AI-generated reminders: based on pattern data (e.g. "You haven't logged a highlight in 3 weeks")
- Notification style: single notification, never a barrage

---

### 8.4 Games & Connection

#### Five games

**36 Questions to Closeness** (based on Aron intimacy study)
- 3 levels: warm-up → deeper → vulnerable
- 12 questions per level, 36 total
- Both answer before seeing partner's response (hidden reveal mechanic)
- AI reads themes across all 36 answers for insight generation
- ~20 minutes

**Mirror Game** (attentiveness measurement)
- 8 questions about partner's current emotional/preference state
- User answers what they think partner would say
- Lock in answer → partner's real answer revealed
- Score tracked: below 6.5/8 = attentiveness flag
- Most diagnostically valuable game in the set
- ~10 minutes

**Sliding Scale** (values alignment)
- Both users rate statements on 1–10 scales independently
- Cover: money, children, independence, location, ambition, religion
- Answers hidden until both submit — then gap revealed
- ~8 minutes

**Scenario** (conflict style revealed through choices)
- Present real-life situations with 3–4 response options
- Choices reveal conflict defaults, loyalty vs autonomy, stress responses
- Neither option is "correct" — the insight is in the pattern across scenarios
- ~12 minutes

**Love Map** (ongoing — builds over time)
- Tracks partner's evolving inner world: fears, dreams, current stressors
- Questions refresh based on what the AI has detected in chat
- Accumulates over months — cannot be completed in one session
- Ongoing

#### Hidden reveal mechanic (applies to all games)
Both partners submit answers independently before either sees the other's response. This prevents social desirability bias. The moment of comparison is the product. This mechanic is non-negotiable — never remove it.

---

### 8.5 Insights & Verdict

> **Soul + clinical dependency:** Verdicts are sourced pattern summaries, not
> judgments. Before implementing verdict copy or generation, read
> `ATTUNE_SOUL.md` Section 2a and `ATTUNE_CLINICAL.md` confidence levels,
> then run `ATTUNE_PRINCIPLES_CHECKLIST.md` Section D.

#### Insight card structure
Every insight card must include:
- Title (13px, specific claim)
- Body (max 40 words, sourced observation)
- Source line (which data generated this: chat analysis, games, profile, timeline)
- Severity badge (Strength / Watch / Act / Safety)

#### Insight severity levels
- **Strength** (green): something working well, worth reinforcing
- **Watch** (amber): pattern worth attention, not urgent
- **Act** (purple): specific action suggested, higher urgency
- **Safety** (red): immediate resource surfacing — bypasses normal insight flow

#### Monthly verdict structure
```
{
  headline:         specific to this relationship (never generic),
  data_confidence:  shown visibly (not hidden as disclaimer),
  strengths:        what is working (minimum 1, maximum 3),
  watch_areas:      what needs attention (minimum 1, maximum 3),
  one_action:       exactly one thing to try — a conversation starter,
  disclaimer:       fixed string appended by client code (never model output):
                    "This reflects patterns in your data. Not a diagnosis."
}
```

#### Verdicts never
- Tell users what to decide
- Use: toxic, narcissist, codependent, disorder, broken
- Reference partner by name in a negative observation
- Appear without data_confidence shown visibly

---

### 8.6 Conflict Translator

#### Strategic role (see Section 1, ceremonial-drift risk)
Beyond its user value, the translator is Attune's primary conflict-capture
mechanism: it is the one feature that is only useful mid-conflict and only
exists here, giving couples a concrete reason to have hard conversations in
Attune rather than in their general messenger. Treat its composer entry point
as first-class UI and track its usage rate as a leading indicator of conflict
capture (13). None of this loosens the trigger rules below — prominence never
means automatic.

#### Trigger (locked in permanently)
- **Opt-in per message only** — user explicitly taps "Help me say this"
- **Never automatic** — no banner appears unsolicited
- Button label: "Help me say this" (not "Fix my message" or "Make this nicer")

#### Side-by-side UI
```
What you wrote          [Send mine]
─────────────────────────────────
One way to say this     [Send this] [Edit this]

Underlying need: [core_need_identified]
[framing_note — muted text, private to sender]
```
- Neither button is pre-selected — equal visual weight
- "Edit this" opens rewrite in composer for modification
- Entire panel dismisses on navigation away

#### Recipient rule (permanent — never changes)
The recipient must never know a message was rewritten. No label. No indicator. No "polished with Attune." Ever. The translator is a private thinking tool.

#### Translator logs → pattern memory
```javascript
// translator_logs feeds personal_insights
// After 5+ uses, surface: "The underlying need in 4 of your last 6
// rewritten messages was to feel heard. This might be worth a
// direct conversation."
```

---

### 8.7 Safety System

> **Clinical + checklist dependency:** Safety behavior is security-critical and
> psychologically sensitive. Full implementation lives here; clinical review
> requirements live in `ATTUNE_CLINICAL.md` Section 11. Before changes, run
> `ATTUNE_PRINCIPLES_CHECKLIST.md` Sections A, C, F, and the permanent
> constraints quick reference.

#### Architecture (hard-coded, non-LLM — never change this)
The safety system must NEVER depend on an AI call. It is keyword-based, hard-coded, and fires before any other processing.

#### Three-tier trigger system
```javascript
// /config/safety_triggers.json — versioned, reviewed before each update

{
  "tier_1_explicit": {
    // Unambiguous threats — immediate notification + prominent resources
    "confidence": "high"
  },
  "tier_2_isolation": {
    // Coercive control signals — quiet notification + softer framing
    "confidence": "medium",
    "examples": ["you don't need them", "you only need me", "no one will believe you"]
  },
  "tier_3_pattern_based": {
    // Only fires after 3+ occurrences in pattern memory
    // Single occurrence = no action
    "confidence": "lower",
    "requires_pattern_confirmation": true
  }
}
```

#### Notification routing (permanent rule)
**Only the at-risk user receives the notification. Always the message recipient. Never the sender. Never both.**

If both users were notified, a dangerous partner would know the system flagged them — escalating risk at exactly the wrong moment.

#### What happens when safety trigger fires
```
1. Safety event logged (at_risk_user_id only — sender never stored)
2. Conversation continues normally for both users — no interruption
3. Sender sees nothing — never knows the trigger fired
4. At-risk user receives a quiet push notification:
   "Some resources that might be useful right now."
5. Notification opens safety resources screen
6. Resources screen has one-tap dismiss ("not relevant right now")
7. Fast dismiss (< 60 seconds) → probable false positive, logged
```

#### False positives — never punish the user
Safety triggers never block messages. Never accuse. Never lock anyone out. The conversation continues. The notification is soft, dismissible, and non-accusatory.

#### Discreet exit feature (top of Month 3 — non-negotiable)
Triple-tap on the Attune logo immediately replaces sensitive UI with a bundled
neutral screen and requires the configured safety PIN before restoring Attune.
Android additionally uses the supported `finishAndRemoveTask()` path and may
open an allowlisted neutral browser destination. iOS uses the local neutral
screen plus an app-switcher privacy cover; it must not call `exit(0)`, use
private APIs, or promise removal from the app switcher.
```dart
// Triple tap on logo — anywhere in app
if (tapCount == 3) {
  showBundledNeutralPrivacyScreen(); // local asset — works offline, shown first
  if (Platform.isAndroid) {
    // MethodChannel → Activity.finishAndRemoveTask() where supported
    DiscreetExitChannel.finishAndRemoveTask();
  }
  // On return: requires the safety PIN, not just biometric
}
```

#### Safety resources screen content
- Localised by user country (Ghana, US, UK at minimum)
- Verified before launch — hotlines change
- Reviewed by DV professional before launch
- Updated quarterly
- Never paywalled — ever

#### Service-role guard for safety events
The `safety_events` table is written by service-role functions (cron/webhook
context). Clients never select the raw table because it contains internal
source keys and trigger metadata. Reads use a minimized user-JWT RPC/view that
returns presentation timestamps only and enforces `auth.uid() = at_risk_user_id`:
```dart
// lib/features/safety/services/safety_events_service.dart
// Never read safety_events with service role — reads are user-JWT RPC only.
Future<List<SafetyResourceEvent>> getSafetyEvents() async {
  final rows = await supabase.rpc('get_my_safety_resource_events');
  return SafetyResourceEvent.listFromRows(rows as List);
  // Returns created_at, first_viewed_at, dismissed_at only.
  // Partner data and internal trigger fields are structurally unreachable.
}
// Integration tests: direct table select is denied; partner JWT returns 0 rows.
```

#### Legal requirements before launch
- DV-experienced lawyer reviews ToS specifically
- ToS states explicitly: Attune is not a crisis service (stated three times)
- ToS states: safety features are best-effort pattern detection
- Privacy policy covers safety event retention (12 months then anonymised — never deleted)
- **Push notification copy reviewed by DV professional** — wrong notification text can create danger (e.g. "your partner said something concerning" must never appear)
- Crisis resources reviewed by a domestic violence professional

---

### 8.8 Onboarding & Cold Start

#### Screen one fork (non-negotiable — routes entire onboarding)
```
┌─────────────────────────────────────┐
│  Are you single or in a            │
│  relationship?                      │
│                                     │
│  [Single]   [In a relationship]    │
└─────────────────────────────────────┘
```
- **Single** → Personal mode onboarding track (no invite, no waiting screen)
- **In a relationship** → Couples mode onboarding track (invite partner, waiting screen, compatibility preview)

> The relationship reflection quiz is clinically interpretive. Its final
> instrument path (full ECR-R, ECR-RS, or ECR-R-inspired adaptation) is blocked
> on `ATTUNE_CLINICAL.md` Section 12 before launch.

#### Authentication step (passwordless)
Before either onboarding track starts, the user verifies their phone number:

```
Primary path:   phone number → SMS OTP → verified session
Fallback path:  none at launch
```

- The auth screen offers phone OTP only.
- No password field appears at launch.
- Email/password, email magic link, Apple Sign-In, and Google Sign-In are not
  shown at launch.
- Supabase Auth owns session creation and refresh.
- `auth.users.id` is mirrored into `users.id` after verification.
- `users.phone` is required and populated from the verified phone auth user.

#### Invite link handling
Invite links use this mobile deep-link shape:

```
attune://invite?code=[invite_code]
```

On app open with an invite link:
1. Store the invite code locally as pending onboarding context.
2. Validate the invite code server-side without revealing private relationship data.
3. Show a neutral invite screen: "You've been invited to Attune."
4. User verifies with phone OTP.
5. After verification, call `accept-invite` with the invite code and user JWT.
6. If accepted, route directly into Track B couples onboarding.
7. Skip any "who invited you?" step because the relationship is already known.

Invite links must not include partner names, phone numbers, email addresses,
relationship IDs, or mode labels. Any display metadata is fetched after server
validation and must be safe to show to the invite recipient.

#### Track A: Single onboarding
```
1. Sign up + profile setup
2. "Are you single or in a relationship?" → Single
3. Relationship reflection quiz (final attachment instrument pending clinical decision)
4. Three personal anchors:
   - "What do you most want to understand about yourself in relationships?"
   - "What pattern from past relationships are you trying to do differently?"
   - "What does a steady relationship feel like to you?"
5. → Personal mode home (no waiting, no invite)
```

#### Track B: Couples onboarding — the two-ask design (revised v2.22, decision 29)

Couples onboarding is split into two separately-timed asks. The evidence
behind the split (scenario simulations + adversarial review, July 2026):
the invited partner's threat response spikes specifically at the words
"AI / analyse / insights" arriving *before any lived trust* — not at the
idea of a couples app itself, which reads as neutral-to-charming across
personas. So the intelligence layer is introduced *after* chat value
exists, never in the invite.

**Ask 1 — the space (gate before chat unlocks; no intelligence vocabulary
anywhere in this flow):**
```
User A (inviter):                 User B (via invite link):
────────────────────────          ────────────────────────
Sign up + phone verify            Sign up via invite + phone verify
"In a relationship" selected      "In a relationship" selected
Profile setup (display name)      Profile setup (display name)
Send partner invite               Accept invite
→ Wait screen (see below)         → If linked: chat unlocks
Both linked and verified → chat unlocks
```

Ask 1 invite rules:
- The invite and everything B sees before accepting sells one thing: a
  private space for the two of you — chat, photos, your timeline. The
  words "AI", "analysis", "insight", "intelligence", and "patterns" must
  not appear in invite copy, the invite landing screen, or Ask 1 onboarding.
- The inviter gets a suggested what-to-say message in **multiple registers**
  (straight English / Pidgin-inflected / plain-spoken) — an unsent script is
  a lost guardrail — plus one optional personal line targeting source-of-idea
  suspicion ("I found this myself — just thought it'd be nice"), which is a
  distinct threat axis from surveillance suspicion.
- **Disclosure is not deferred.** Signup consent and the privacy notice
  still disclose AI processing plainly at account creation — that is a
  legal requirement (data-protection law, Apple 5.1.2(i)) and a Soul
  requirement. The two-ask design changes when the product *foregrounds*
  the intelligence experience, never whether processing is disclosed.

**Ask 2 — the intelligence (after chat value exists):**

Trigger: both partners active in chat for several days (initial config:
3+ days AND a minimum mutual-message threshold), AND the first available
observation is positive-valence. Then a soft, skippable prompt introduces
the intelligence layer **anchored to something good already observed**
("We noticed you two have a great rhythm — want to see more about how you
communicate?"), never to a deficit.

Ask 2 contains, in order: the intelligence introduction → relationship
reflection quiz → three relationship anchors → and, when both partners
have completed them, the **compatibility preview** as the completion
reward (explicitly labelled as profile-based). Ask 2 rules:

- Fully skippable with zero loss of chat function; declining is never
  penalized or nagged. One gentle later reminder maximum, then silence.
- Watch the Ask-2 opt-in rate and post-Ask-2 churn directly — the
  adversarial review's predicted failure mode is the skeptic bouncing at
  the AI reveal with sunk-cost resentment; the positive-anchor and
  skippability rules exist to defuse exactly that.
- Quizzes remain voluntarily available at any time (waiting screen,
  profile) — Ask 2 is when the product proactively foregrounds them to
  the couple, not the only door to them.
- All Section 6 prompts must treat missing psych-profile fields as
  `unknown` — under this design, analysis begins before quizzes exist
  for most couples.

#### Three relationship anchors (Track B, gathered in Ask 2)
1. "What's one thing you genuinely admire about your partner?"
2. "What's one thing you're hoping this relationship gives you more of?"
3. "What's one pattern from past relationships you're trying to do differently?"

#### Waiting screen (not a dead end — an accelerated onboarding)
```
✓ Profile complete — invite sent
○ Relationship reflection quiz (optional head start — counts toward your
  compatibility preview once you're both in)
○ Love language quiz (4 min)
○ Write your first reflection
[Start a reflection]
```

#### 48-hour solo reflection fallback (locked in)
If partner hasn't completed onboarding after 48 hours, chat unlocks in solo reflection mode. Solo reflection:
- Looks like chat UI but clearly labelled "Reflection mode"
- Messages are private journal entries — NOT delivered to partner
- AI analyses entries (tone, NVC) — data accumulates usefully
- When partner joins: "You wrote X reflections. Keep private or share?" Default: KEEP PRIVATE

#### Day 7 pivot screen (gentle, no drama)
Three options presented to waiting user only:
1. Keep waiting (renew invite if expired)
2. Switch to Personal mode
3. Invite someone else (doesn't cancel existing invite)

#### Early content plan (revised v2.22 for the two-ask design)
```
Hour 0:    Chat unlocks with optional conversation starter prompt
           (Layer 1 accumulates silently from message one — disclosed
           at signup, foregrounded later)
Day 3+:    Ask 2 fires when the trigger conditions are met — intelligence
           introduction anchored to a positive observation, then quiz +
           anchors; both complete → compatibility preview (profile-based,
           clearly labelled)
Week 1:    First session analysis fires
Week 2:    First pattern candidate; first surfaced insight is held until
           it can come from a real (moderate-tension) exchange — the
           belief "it sees the real stuff" is what converts skeptics
Week 4:    First pulse score (minimum 5 sessions required)
Month 1:   First verdict eligible (minimum 4 pulse scores)
```

#### Empty state philosophy (locked in as product rule)
Never show an empty container with a spinner where intelligence should be. Every screen has a profile-based fallback explicitly labelled as such. The labelling is a feature — it teaches users the app gets smarter over time.

---

### 8.9 Personal Mode

**Label: "Personal mode"** — not "Solo mode" (solo undersells it)

#### Who uses Personal mode
- Partner hasn't joined after 7 days
- Relationship ended — user reverted from Couples
- Individual using Attune between relationships
- User in Healing mode (post-breakup journey)

#### Personal mode features
```
AVAILABLE:
✓ Reflection journal with AI analysis (tone, NVC, patterns)
✓ All four psych quizzes
✓ Personal pulse score (self-facing dimensions only)
✓ Personal insights and pattern memory
✓ Games adapted for solo use
✓ Healing mode journey (if applicable)
✓ Safety resources always accessible

NOT AVAILABLE:
✗ Shared pulse score
✗ Partner compatibility preview
✗ Session analysis (requires two participants)
✗ Shared timeline
✗ Couple games (partner-dependent mechanics)
```

#### Personal mode is not a consolation prize
It is the product for a significant user segment. Users who complete Personal mode before linking with a partner bring richer profiles into Couples mode than users who onboard cold together.

---

### 8.10 Dating Mode (post-launch — design only, build Month 6+)

> Do not build any Dating mode code before Month 6.
> This section is design documentation only.
> Before any Dating mode implementation, read `ATTUNE_SOUL.md` dating and
> anti-product constraints, `ATTUNE_CLINICAL.md` dating data-consent rules,
> `ATTUNE_PRINCIPLES_CHECKLIST.md` Section I, and
> `../DATING_MODE_SPEC.md` v1.1 or later. The Dating Mode specification owns
> the detailed eligibility, consent, ranking, privacy, authorization, safety,
> state-machine, and rollout contracts.

#### How a user enters the dating pool
Eligibility is automatic when the trusted Healing gates pass; pool enrollment
is never automatic. The user must separately opt in to Dating Mode, accept the
current terms/privacy notice, pass the adults-only gate, review and activate
their profile, and separately choose whether Attune may use the current user's
own eligible historical behavioral summaries. Refusing historical-data consent
does not block Dating Mode.

```
Relationship ends
    ↓
User enters Personal/Healing mode
    ↓
Healing journey completes all five stages; latest valid readiness score > 70
    ↓
Server confirms minimum 8 weeks post-breakup and all other eligibility gates
    ↓
Dating pool opt-in prompt: "You're eligible for dating mode. Ready to explore?"
    ↓
User opts in → makes separate historical-data choice → reviews profile
    ↓
Server revalidates eligibility → user activates profile → enters pool
```

#### Prerequisite: minimum 2,000 active couples on platform
Matching quality depends on pool size. A small psychologically rich pool beats a large shallow one. Launch dating when the pool exists.

#### Healing mode gate (must complete before Dating mode opt-in)
Use `HEALING_MODE_SPEC.md` v1.2 or later as the exact contract (v1.2 adds the
minimum-observed-journey floor for solo journeys with self-attested breakup dates). All five stages must be
complete (including permitted skips), the latest valid readiness check-in must
be greater than 70, eight server-measured weeks must have elapsed, no active or
pending relationship may exist, and the account must remain eligible. The
readiness score is a gate only and is never a matching input.

#### Matching algorithm — pattern-based, not appearance-based
This is not a traditional dating app. There are no swipes, no browsable pool,
and no photo-first discovery. A deterministic, versioned server-side algorithm
presents a small set of curated introductions after symmetric preference,
eligibility, consent, block, moderation, and relationship filters pass.

Initial approved candidate features are aggregate attachment, communication,
and conflict dimensions plus explicit values and relationship priorities. The
exact transforms, weights, missing-data handling, and presentation bands require
clinical, cultural, fairness, and product approval; placeholder weights must not
ship. Missing data is neutral rather than a poor-fit signal.

Love-language matching is prohibited by `ATTUNE_CLINICAL.md`: love-language
similarity, difference, or complementarity is not a compatibility/ranking input.
Love-language preferences may personalize the supplying user's private first-date
guide only. Former-partner data, raw messages, Healing content/readiness score,
safety data, private reflections, photos, popularity, engagement, and protected
or inferred sensitive traits are also excluded.

#### Dating profile structure — psychology first, photo second
```
┌─────────────────────────────────────┐
│  Alignment: Promising shared ground │
│  ─────────────────────────────────  │
│  Shared direct-communication pref.  │
│  Several shared priorities          │
│  Different conflict approaches      │
│  ─────────────────────────────────  │
│  [Photo]  Alex, 28                  │
│  ─────────────────────────────────  │
│  [See alignment preview]             │
│  [Interested] [Not for me]          │
└─────────────────────────────────────┘
```
- Modest alignment band and source-grounded explanation appear BEFORE photo
- No exact percentage appears until calibration supports a defensible meaning
- Photo is present but not the primary signal
- No swiping — presented with curated matches
- One-sided interest and rejection are never revealed

#### Guided first date feature
When matched: personalised first-date guide based on compatibility profile.
- Conversation starters tailored to their specific combination
- One "question to avoid" based on known friction areas
- Post-date logging for both users

---

### 8.11 Opinions & Anonymous Forum

> Launch shell surface. Anonymous users may browse; participation requires
> phone-verified auth.

#### What it is
**Opinions** is Attune's top-level anonymous community surface. It contains
relationship opinions, discussion prompts, and forum-style threads without
revealing user identity.

Think forums, not social media — relationship topics, not personal profiles.
Users discuss love, attachment, conflict, date ideas, and relationship patterns
without revealing identity.

The app shell label is **Opinions**. A nested tab inside that surface may still
be called **Forums** for threaded category discussions. Backend table names may
remain `forum_*` unless a dedicated data-model rename is planned.

#### Core principles (locked in)
- **Strictly anonymous** — no names, no photos, no profile links to your real account
- **Strictly text** — no images, no videos, no links (reduces abuse vectors)
- **Relationship status visible** — the only identity signal is a self-selected forum status label
- **Your partner doesn't know it's you** — even if they're on the platform and in the same thread
- **Browse before account** — anonymous users can read forum content before phone verification
- **Participate after phone auth** — posting, replying, flagging, saving, and personalization require a phone-verified account

#### Anonymous browsing rules
Anonymous browsing exists to let new users understand Attune before creating an
account. It is discovery, not participation.

Anonymous users can:
- Read forum categories, posts, and replies that are not removed.
- Open the Opinions tab as the default home surface.
- Tap calls-to-action to create an account or start onboarding.

Anonymous users cannot:
- Post, reply, flag, vote, save, follow, or personalize forum content.
- Access Chat, partner invites, relationship tools, Pulse, Insights, Games, or Profile.
- See any relationship-specific or user-specific data.

Phone verification is required before any write action. This keeps the forum
open for exploration while preserving abuse response and moderation accountability.

#### Opinion/forum status labels (self-selected, display-only — not account states)
Users choose one label to display next to their anonymous posts:
- `taken` — in an active relationship
- `single` — not in a relationship
- `exploring` — open to connection, undefined status
- `just having fun` — casual, not looking for commitment

These are **display labels only**. They do not affect account mode, matching algorithm, or any backend state. A user in Couples mode can display as `taken` or `exploring`. A user in Personal mode can display as `single`, `exploring`, or `just having fun`.

#### Anonymity architecture
```sql
-- Forum posts are NOT linked to users table by user_id in any readable way
-- Internal link is hashed — platform can enforce one-account-one-post
-- but cannot surface who posted what to any other user

CREATE TABLE forum_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_hash text NOT NULL,         -- HMAC-SHA256(FORUM_HASH_KEY, user_id || ':' || date) — server-computed, rotates daily
  -- NOT a direct user_id FK — breaks the link between post and identity
  forum_status text CHECK (forum_status IN ('taken', 'single', 'exploring', 'just_having_fun')),
  category text NOT NULL,            -- 'attachment' | 'conflict' | 'date_ideas' | 'general'
  content text NOT NULL,
  created_at timestamptz DEFAULT now(),
  flagged boolean DEFAULT false,
  removed boolean DEFAULT false
);

CREATE TABLE forum_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid REFERENCES forum_posts NOT NULL,
  author_hash text NOT NULL,         -- same rotation scheme
  forum_status text,
  content text NOT NULL,
  created_at timestamptz DEFAULT now(),
  flagged boolean DEFAULT false,
  removed boolean DEFAULT false
);

-- RLS: all non-removed posts are publicly readable by authenticated users.
-- Anonymous app browsing may use a restricted read-only public endpoint/view.
-- author_hash is visible but not reversible to user identity
```

**Daily keyed rotation:** `author_hash = HMAC_SHA256(FORUM_HASH_KEY, user_id + ':' + date_string)` — the same user gets a different hash each day, preventing cross-day post correlation. Within a single day, a user's posts in a thread are recognisably from the same person (consistent hash), enabling coherent conversation.

Why HMAC and not plain SHA256: a date string is not a secret. `SHA256(user_id + date)` is recomputable by anyone holding a user-id list (an employee, a breach, a subpoena), which would retroactively de-anonymise every forum post ever written. `FORUM_HASH_KEY` is a server secret (edge function env var, never in the client, rotated only with a documented anonymity-impact review). Posts and replies are therefore written through a `create-forum-post` edge function (user JWT for auth and rate limiting; hash computed server-side) — clients never compute or supply `author_hash`. This matches the non-reversible HMAC approach already used for `safety_events.source_event_key`.

#### Moderation system (v1 — manual)
Three layers:

**Layer 1: Keyword filter (hard-coded, non-LLM)**
Same approach as safety system. Explicit harmful content blocked before posting. Not exhaustive — catches the obvious.

**Layer 2: Community reporting**
Any authenticated user can flag any post with one tap. Flagged posts enter a review queue. No count shown publicly — prevents pile-on targeting.

**Layer 3: Manual review (you, the founder, at launch)**
You review the flagged queue. Remove posts that violate community standards. No automated resolution in v1. Build a simple admin dashboard for this.

```sql
CREATE TABLE forum_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid REFERENCES forum_posts,
  reply_id uuid REFERENCES forum_replies,
  flagged_by_hash text NOT NULL,    -- anonymous flag — can't see who flagged
  reason text,
  created_at timestamptz DEFAULT now(),
  reviewed_at timestamptz,
  action_taken text                 -- 'removed' | 'kept' | 'pending'
);
```

#### The recognisability edge case (accepted by design)
A user could post "my partner does X" and their partner — also on the platform — could recognise the description even without a name attached. This is acknowledged and accepted. Anonymity in Attune means freedom from identity exposure, not freedom from accountability for what you share. The forum creates transparent sharing — you own your words, just not your name.

#### Forum categories (v1)
- **Attachment** — anxious, avoidant, secure — discussion and patterns
- **Conflict** — navigating disagreements, repair, communication
- **Date ideas** — suggestions, experiences, what worked
- **General** — anything else relationship-related

#### What the forum is NOT
- Not a dating feature — no DMs between forum users, no profile browsing
- Not an AI-analysed surface — forum posts are NOT fed into the AI pipeline
- Not connected to your relationship data — your forum persona is isolated

---

## 9. NAVIGATION ARCHITECTURE

### App shell (2 tabs)

```
Tab 1: Opinions  ← anonymous community surface
Tab 2: Chat      ← relationship workspace / personal workspace
```

The shell has only two top-level tabs. Pulse, Games, Insights, Profile, and
Settings are not equal top-level destinations; they are tools attached to the
user's current relationship or personal workspace.

#### Default selected tab

```
Anonymous user:       Opinions
Personal/single user: Opinions
Couples user:         Chat
```

Anonymous users and singles start in Opinions because browsing and community
context are the safest first surfaces. Couples start in Chat because an active
relationship has one primary workspace: the partner chat.

### Flutter shell setup
```dart
// Pseudocode: actual implementation is Flutter.
final initialTab = switch (sessionState) {
  anonymous => opinions,
  personal => opinions,
  couples => chat,
}
```

### Tab indicators (dot, never badge count)
- Use a small dot indicator for unviewed insights or new verdict
- Never use a number badge on relationship content — creates anxiety
- One dot maximum at any time
- Priority order: safety alerts > verdicts > insights

### What lives in each tab

**Opinions tab:**
- Anonymous community browsing
- Opinions prompts and relationship discussion
- Nested Forums area for categories and threaded posts
- Read-only access for anonymous users
- Phone-auth gated posting, replying, flagging, saving, and personalization
- Account creation / onboarding CTA for anonymous users

**Chat tab:**
- Couples mode: exactly one active partner chat
- Personal mode: personal reflection workspace or onboarding CTA, depending MVP scope
- Anonymous mode: `LoginProfile` guest gate with phone-auth CTA
- Message thread, image sharing, read receipts, delivery status
- "Help me say this" button in composer
- Chat header with pulse summary (Month 2)

#### Anonymous Chat gate

When an anonymous user opens the Chat tab, show the legacy app's
`LoginProfile` pattern adapted for Attune. This screen is a guest-facing home
inside the Chat tab, not a modal and not a forced redirect.

Keep from the legacy app:
- Welcoming guest profile layout
- Short app overview with "learn more"
- Create account / continue entry point
- Settings/menu access where safe for anonymous users
- Reusable profile/info widgets that do not depend on the old booking domain

Remove or replace:
- Google Sign-In
- Apple Sign-In
- Email/password login
- Beauty/grooming booking copy, payment copy, provider/service references
- Any auth button generated by legacy `getAuthButtons` that is not phone OTP

Attune version:
- Primary CTA: continue with phone number
- Secondary CTA: invite a friend to learn about Attune
- Opinions remains browsable without account
- Chat, partner relationship invites, Pulse, Insights, Games, Profile, and Settings that
  expose account or relationship data remain locked until phone verification

The `LoginProfile` "Invite a friend" action is a public app-share action only.
It must never create or display a relationship invite code. Partner invites are
created only inside the couples onboarding flow, after the user has completed
the required couples onboarding context.

This preserves the low-pressure anonymous exploration from the cloned app while
keeping Attune's phone-only launch auth and abuse-accountability model intact.

#### Chat sub-sections

For users in an active relationship, the Chat tab contains the partner chat
first. Directly below the chat are relationship tools:

- **Pulse:** weekly pulse score, dimensions, deltas, trend chart, timeline events
- **Insights:** sourced insight cards, pattern memory, conflict translator log, monthly verdict
- **Games:** game library, active game sessions, game insights history
- **Profile / Settings:** psych profile, partner shared profile, privacy, account, notifications

These sections are visually subordinate to Chat. They should feel like tools
inside the relationship workspace, not separate apps.

#### Couples recognition gate

A relationship is recognised as an active couple only when:

- User A completed phone verification.
- User A completed couples onboarding through the final partner-invite step.
- User B accepted the partner invite.
- User B completed phone verification.
- User B completed their onboarding flow.
- The backend relationship row is active with both users attached.

Until all conditions are true, both users remain outside the active Couples mode
experience. The inviting user may see a waiting/pending relationship state, but
Attune must not unlock shared partner chat, shared insights, Pulse, games, or
couple recognition.

---

## 10. PRIVACY ARCHITECTURE

### Encryption
- **Supabase-level encryption** (AES-256 at rest, TLS in transit)
- **NOT end-to-end encrypted** — E2EE is architecturally impossible with server-side AI analysis
- This must be disclosed clearly in ToS and privacy policy
- Users accept this tradeoff at signup — it is not hidden

### What is stored
- Message content: encrypted, never used for training, deletable on request
- Analysis results: numeric scores and enum values only — not message text
- Pattern memory: topic clusters (semantic labels) — not message quotes
- Psych profiles: aggregate quiz scores — not individual question answers

### What is never stored
- Raw message content in AI prompt logs
- Partner cycle data (phase summary only, if sharing enabled)
- Individual quiz question answers after scoring
- Sender identity in safety events

### Data deletion
- User can delete account and all data at any time
- Couple's shared data (patterns, pulse) anonymised on one partner's deletion
- Safety events: anonymised after 12 months, never fully deleted (legal protection)
- Raw messages: retained indefinitely unless user deletes account
- Analysis results: retained indefinitely (anonymised)

### GDPR compliance
- Data deletion endpoint: `DELETE /functions/v1/delete-account`
- Deletes user row and all personal data within 30 days
- Anonymises shared relational data
- Confirmation email sent

---

## 11. PERMANENT PRODUCT CONSTRAINTS

> These are architectural decisions that can never be reversed.
> Any feature request that violates these constraints must be refused.
> No exceptions. No "just for this feature." No future changes.

```
1. ASYMMETRIC DATA IS SELF-FACING ONLY
   Asymmetric behavioural data — who pursues, whose NVC rate is higher,
   whose bid-toward rate is lower — is shown to each user about
   themselves only. Never shown as a judgment of the partner.
   The pattern is shared. The role is private.

2. NO COUPLE REPORT EVER
   There is no combined view of both users' personal insights.
   Not now. Not in a premium tier. Not ever.
   A couple report that stitches both users' personal data into one
   view is permanently prohibited.

3. SAFETY NOTIFICATIONS TO AT-RISK USER ONLY
   When a safety trigger fires, only the at-risk user is notified.
   The sender never knows. Both users never know simultaneously.
   This rule cannot be changed for any feature, integration, or tier.

4. RECIPIENT NEVER KNOWS ABOUT TRANSLATOR
   A message rewritten by the conflict translator arrives as a normal
   message. No label. No indicator. No "polished with Attune."
   The translator is a private thinking tool. Permanently.

5. SAFETY RESOURCES NEVER PAYWALLED
   Crisis hotlines, safety resources, and abuse detection alerts
   are free for all users at all tiers. No exceptions ever.

6. SAFETY SYSTEM IS NEVER LLM-DEPENDENT
   The safety trigger system is hard-coded keyword matching.
   It never routes through Claude or any other AI model.
   An AI model can fail, hallucinate, or be unavailable.
   The safety system cannot be any of those things.

7. VERDICTS NEVER CONTAIN RAW MESSAGES
   The monthly verdict is built from derived structured data only.
   Raw message content never enters a verdict generation call.

8. NO DIAGNOSIS LANGUAGE
   These words are permanently banned from all AI outputs:
   toxic, narcissist, codependent, disorder, broken.
   Labels belong to clinicians. Attune observes patterns.

9. patterns TABLE HAS NO user_id COLUMN
   Patterns describe relationship dynamics, not individuals.
   This is enforced at the schema level, not just in code.
```

---

## 12. SECURITY & LEGAL

### Pre-launch legal requirements (in order of urgency)

1. **DV-experienced lawyer** — reviews ToS specifically for safety system liability
2. **ToS must state** (in three separate sections):
   - Attune is not a crisis service
   - Safety features are best-effort pattern detection
   - Data from safety events is not shared with law enforcement absent a valid legal order
3. **Privacy policy must cover** encryption approach, E2EE absence, safety event retention
4. **Clinical advisor** — found Month 1, reviews all psych content Month 2
5. **Crisis resources** — verified by DV professional before launch
6. **Age rating** — App Store 17+, Play Store Teen minimum

### Data in legal proceedings
Message data is discoverable in divorce/custody proceedings in many jurisdictions. ToS must explicitly address this. Users must be informed at signup. Consider a prominent warning when users first enable detailed logging.

### Clinical advisory structure
- One licensed therapist/psychologist with couples therapy experience
- Specific familiarity with Gottman, attachment theory, NVC
- Reviews: all prompt templates, signal library, quiz instruments, insight language, safety tiers
- Cost: $500–1,500 for structured review engagement
- Credential line in app and marketing: "Frameworks reviewed by [name, credentials]"

---

## 13. 3-MONTH BUILD PLAN

### Month 1 — June: Foundation
**North star: Two people can sign up, link, chat, complete one quiz, and see one AI insight.**

| Week | Build |
|---|---|
| 1 | Supabase setup — all tables, RLS policies, auth, environment |
| 2 | Real-time chat — text, delivery status, push notifications, optimistic UI |
| 3 | Attachment quiz + onboarding flow + waiting screen + compatibility preview |
| 4 | Layer 1 AI pipeline + drift cache + offline queue + debug |

**Month 1 cuts (moved to Month 2 — deliberate):**
- Image sharing
- Love language quiz
- Timeline logging
- Solo reflection AI analysis

### Month 2 — July: Intelligence
**North star: A couple plays a game, sees a pattern they didn't know existed.**

| Week | Build |
|---|---|
| 5 | Image sharing + love language quiz + timeline logging |
| 6 | Layer 2 session analysis + Layer 4 pattern memory + pulse score computation |
| 7 | 36 Questions + Mirror game + game insights |
| 8 | Monthly verdict + insight cards + conflict translator + **beta with 20–50 real couples** |

### Month 3 — August: Launch ready
**North star: A stranger downloads, links with partner, feels the app understands their relationship within 10 minutes.**

| Week | Build |
|---|---|
| 9 | **Discreet exit** (top priority) + safety system + crisis resources |
| 10 | Privacy settings + data deletion + RLS audit + legal review |
| 11 | Onboarding polish + empty states + push notification system |
| 12 | App Store / Play Store submission (allow 2 weeks for review) |

### September: Soft launch
- Launch to waitlist of 200+ couples first
- 4–6 weeks of real data collection
- Public launch when ALL three hold:
  - onboarding conversion > 60%
  - day-7 retention > 40%
  - **conflict capture:** ≥ 30% of couples active at day 21 have at least one
    conflict-classified session (escalation_score ≥ 0.4) in their history
- The conflict-capture threshold is provisional — calibrate against the first
  2 weeks of beta data (see Section 16) — but the metric itself is not
  optional. Onboarding + retention alone cannot distinguish a working product
  from ceremonial usage (Section 1, ceremonial-drift risk): a couple sending
  only good-morning texts passes both while the intelligence layer starves.
- Measured from derived session data only (escalation_score, session counts) —
  never from raw content. No new collection is required; this is a query over
  data the pipeline already produces.

### Hard scope rule
If a feature is not in the Month 1 north star, it does not get built in Month 1. Every time a Month 2 feature feels urgent in June: stop, re-read the north star, continue with Month 1 scope.

---

## 14. POST-LAUNCH ROADMAP

| Feature | Why it matters | Target month |
|---|---|---|
| Time capsule messages | High retention, zero competitors, shareable | Month 4 |
| Anniversary relationship report | Viral loop — AI-generated story of the relationship | Month 4 |
| Voice messages | Couples use them heavily — painful cut from v1 | Month 4 |
| Message reactions | Standard chat feature | Month 4 |
| Weekly intimacy challenges | Personalised to love language, retention mechanic | Month 4 |
| Message editing/deletion | Standard chat feature | Month 4 |
| Live conflict cooldown | Real-time escalation banner — press-worthy | Month 5 |
| Ritual builder | Research-backed intimacy, sticky habit loop | Month 5 |
| Therapist integration + export | B2B revenue, distribution channel | Month 5–6 |
| Healing mode | Post-breakup structured journey | Month 4 |
| Dating mode | Needs 2,000+ active couples first | Month 6–7 |
| Chat header drawer | Connective tissue between Chat and rest of app | Month 2 |
| Cycle tracking | Useful but not critical — cut from v1 | Month 4 |
| Communication style quiz | Month 2 prompt after chat unlocks | Month 2 |
| Conflict style quiz | Month 2 prompt | Month 2 |
| Sliding scale game | Values alignment | Month 3 |
| Scenario game | Conflict style revealed through choices | Month 3 |
| Love map game | Ongoing, accumulates over months | Month 3 |

---

## 15. DECISION LOG

All 25 major architectural decisions made in the review session. These are locked and cannot be reopened without a documented reason.

| # | Decision | Resolution | Reasoning |
|---|---|---|---|
| 1 | AI cost per couple | Full per-message analysis at launch, optimise with real data | Can't optimise what you haven't measured |
| 2 | Sparse analysis data | `analysis_skipped` column added as future-proofing | Schema flexibility without premature optimisation |
| 3 | Couple unlink | Either user can unlink, 30-day soft delete, both revert to Personal mode | Clean exit, no data hostage |
| 4 | Primary vs supplemental chat | Attune IS the primary chat app — not supplemental | Supplemental means competing with WhatsApp passively. Primary means building something people switch to. |
| 5 | Chat feature parity | Text + push notifications + image sharing + full delivery-status lifecycle for launch | Image sharing is non-negotiable — couples send photos constantly |
| 6 | Image storage | Client-side compress to 800KB, private bucket, indefinite retention | Performance + privacy + no surprise storage bills |
| 7 | Encryption | Supabase-level only, E2EE architecturally impossible with server AI, disclosed in ToS | E2EE breaks the entire intelligence layer |
| 8 | Session detection | Server-side 30min cron at :07/:37, no day boundaries, one-sided sessions as valid signal, 80-message cap | Client timers are unreliable, midnight splits are emotionally false |
| 9 | Verdict input | Derived data only, ~1,700 tokens, game insights added | Verdict synthesises intelligence already extracted — never re-reads raw messages |
| 10 | Conflict translator | Opt-in only via "Help me say this", recipient never knows, logs feed pattern memory | Automatic activation is condescending; push not pull |
| 11 | Navigation | 2 tabs: Opinions and Chat; Opinions default for anonymous/single users, Chat default for couples; dot not badge | Attune has two primary surfaces: anonymous community and relationship workspace. Pulse/Games/Insights/Profile are tools under Chat, not equal apps |
| 12 | Asymmetric data | `personal_insights` table with RLS iron wall, no couple report ever | The pattern is shared. The role is private. This is permanent. |
| 13 | Cold start | Compatibility preview day one, profile-based with explicit labelling, 48hr content plan | Honesty about data confidence is a retention mechanic |
| 14 | Safety system | At-risk user only, 3-tier hard-coded triggers, discreet exit top of Month 3 | DV organisations confirmed: dual notification escalates risk |
| 15 | Asymmetric adoption | 48hr solo reflection fallback, one notification only, day 7 pivot, "Personal mode" label | Hard gate churns most motivated users; waiting screen is accelerated onboarding |
| 16 | Clinical validation | Advisor found Month 1, full review Month 2, credential line in marketing | Psychological claims require psychological accountability |
| 17 | Chat architecture | Optimistic UI + Supabase source of truth + drift (SQLite) read cache — NOT local-first | Local-first breaks the AI pipeline; optimistic UI creates WhatsApp feel. (Cache library was MMKV pre-Flutter-pivot; drift is the Flutter equivalent, v2.16) |
| 18 | Onboarding fork | Screen one asks "single or in a relationship?" — routes entire onboarding experience | Different users need different flows from the first second |
| 19 | Chat locking | One chat section per couple. Read-only after relationship ends. Permanently archived when either partner starts new relationship | Prevents ex-communication on platform; creates clean new starts |
| 20 | Dating pool entry | Eligibility is automatic after trusted Healing gates; enrollment requires separate Dating opt-in, terms/privacy acceptance, adults-only gate, profile review/activation, and an optional separate historical-data choice | Existing self-data may seed a private draft, but the user controls enrollment and historical-data use |
| 21 | Forum anonymity | Daily-rotating keyed author hash (HMAC with server secret) — no direct user_id FK on forum posts | Identity-free discussion; daily rotation prevents cross-day correlation while enabling coherent same-day threads; server-secret HMAC prevents retroactive de-anonymisation by anyone holding a user list |
| 22 | Opinion/forum labels | 'taken', 'single', 'exploring', 'just having fun' are Opinions/forum display labels only — not account states | Keeps mode architecture clean; labels are social signal only, no backend consequence |
| 23 | Auth strategy | Phone OTP only at launch; no Apple/Google, email/password, or email magic link | Phone identity fits chat-first onboarding and partner invites; a single verified-phone auth path keeps abuse response and safety escalation simpler |
| 24 | Anonymous browsing | Anonymous users can browse Opinions read-only before account creation; all write/personal/relationship actions require phone auth | Lets users understand Attune before committing while keeping accountability for abuse-sensitive actions |
| 25 | Anonymous Chat gate | Anonymous Chat tab shows adapted legacy `LoginProfile`, with phone OTP only and no Google/Apple/email/password | Preserves low-pressure guest exploration from the cloned app without weakening phone-only identity and moderation rules |
| 26 | Invite distinction | `LoginProfile` "Invite a friend" is public app sharing only; partner invites live only at the end of couples onboarding | Prevents accidental relationship creation from a generic referral action and keeps couple recognition tied to mutual verified onboarding |
| 27 | Lovers'-space positioning + conflict capture | Attune is the dedicated chat for one relationship (not a general-messenger replacement); ceremonial-drift named as the key usage risk; translator designated the conflict-capture mechanism; conflict-capture metric added to launch gate | Dedicated couple spaces are a proven adoption model (Between), but the intelligence layer starves if only ritual conversation migrates — onboarding/retention metrics alone cannot detect that failure mode |
| 28 | Non-conversational AI posture | Attune's AI is never a conversational companion: insights, Pulse, Verdicts, and game reflections are reports about the couple's own data; no chatty AI persona, no sustained AI-user dialogue, no anthropomorphic AI character — permanently | Dual grounding: (a) design — the product's voice is a wise attentive friend *writing observations*, not a synthetic relationship partner (ATTUNE_SOUL.md); (b) regulatory — 2026 US state companion-chatbot laws (CA SB 243, OR SB 1546 et al.) regulate AI that "sustains a relationship across multiple interactions"; a report-generating AI is likely out of scope, a companion is squarely in it. See ATTUNE_RISK_SOLUTIONS.md Section 7.5 |
| 29 | Two-ask couples onboarding (revises decisions 13/15's sequencing; documented reason: July 2026 simulation + adversarial review) | Ask 1 (invite → link → chat unlocks) carries zero AI vocabulary; quiz + anchors + intelligence introduction move to Ask 2, triggered days later and anchored to an observed positive signal; compatibility preview becomes Ask 2's completion reward rather than an hour-0 artifact; AI processing remains fully disclosed at signup consent | The invited partner's threat response spikes at "AI/analysis" language arriving before lived trust — not at the couples-app concept; simulations confirmed this across personas, and the invited-partner-never-engages complaint is attested verbatim in competitor reviews. Chat-first sequencing trades the day-one preview for a materially better shot at both partners actually arriving — and the preview converts better as an earned reward than as an unrequested analysis |

---

## 16. OPEN QUESTIONS & FUTURE UPDATES

> This section is for decisions not yet made, features not yet designed,
> and updates added as the build progresses.
> Date every entry. Never delete old entries — mark them resolved.

### Currently open

```
[OPEN] Cultural calibration of attachment theory frameworks
       for West African / Ghanaian users
       Status: Needs clinical advisor input
       Added: June 2026

[OPEN] Monetisation tier structure
       Free vs Premium vs Couples vs Professional pricing
       Status: Not yet specced — post-MVP decision
       Added: June 2026

[OPEN] App name finalisation
       Current: Attune (working title)
       Status: Open for review
       Added: June 2026

[RESOLVED v1.1] Provisional Ghana DOVVSU helpline source identified
       Current official Ghana Police DOVVSU page lists 055 100 0900.
       Status: Still requires DV-professional verification within 7 days of release
       Added: June 2026
       Resolved provisionally: July 2026

[OPEN] Sliding scale game — full question set
       Status: Questions drafted but not reviewed by clinical advisor
       Added: June 2026

[OPEN] Scenario game — full scenario set
       Status: Not yet designed
       Added: June 2026

[RESOLVED v1.1] Discreet exit — platform contract
       Android targets finishAndRemoveTask() where supported.
       iOS uses a bundled neutral screen and app-switcher privacy cover;
       no forced termination, private APIs, or removal promise.
       Status: Resolved in SAFETY_SYSTEM_SPEC.md v1.1; real-device testing remains a release gate
       Added: June 2026
       Resolved: July 2026

[OPEN] CI/build pipeline provider for Flutter release builds
       Expo EAS (RN-era decision) removed in v2.16; local flutter build
       works meanwhile. Candidates: Codemagic, GitHub Actions + fastlane.
       Status: Decide before Month 3 week 12 store submission
       Added: July 2026

[OPEN] Conflict-capture threshold calibration
       Launch gate uses ≥30% of day-21-active couples with ≥1
       conflict-classified session (escalation_score ≥ 0.4). Both numbers
       are provisional — calibrate against first 2 weeks of beta data.
       The metric itself is locked (decision 27); only thresholds move.
       Status: Calibrate during September beta, before public-launch decision
       Added: July 2026

[RESOLVED v1.3] Historical chat import (WhatsApp export)
       Was open pending dual-consent design, safety-trigger policy for
       historical content, and clinical review. Now fully specified in
       CHAT_SYSTEM_SPEC.md v1.3 Section 11: Month 5, feature-flagged, and
       gated on its own Safety/legal/clinical/cultural review before
       release. Neither partner can import unilaterally — both must
       independently consent inside the app before any message is
       ingested; declining is never revealed to the other partner beyond
       a generic outcome. Import-sourced evidence carries one tier lower
       framework confidence than native evidence pending clinical
       calibration. Media is out of scope at launch; text-only WhatsApp
       exports only (iMessage has no user-accessible bulk export).
       Added: July 2026
       Resolved: July 2026

[OPEN] "Verdict" in-app surface language
       Internal spec term stays "verdict". In-app display language
       may benefit from softer framing ("monthly readout", "pattern
       report", "relationship pulse"). Decision deferred to UI design phase.
       Status: Open — decide before Month 2 week 8 verdict screen build
       Added: June 2026
```

### Update log

```
[July 2026 — v2.22] — two-ask couples onboarding; SMS delivery requirements
- Added decision 29 and rewrote 8.8 Track B: couples onboarding split into
  Ask 1 (private-space invite → mutual verified link → chat unlocks; zero
  AI vocabulary) and Ask 2 (intelligence introduction + quiz + anchors,
  triggered after chat value exists, anchored to a positive observation,
  fully skippable; compatibility preview becomes the completion reward)
- Disclosure is explicitly NOT deferred: signup consent still discloses AI
  processing plainly (legal + Soul requirement); the two-ask design changes
  what the invite foregrounds, never what is disclosed
- Section 2 onboarding fork updated to match; waiting screen items became
  optional head-starts; 48-hour content plan replaced with the two-ask
  early content plan; all Section 6 prompts must treat missing psych-profile
  fields as unknown (analysis now precedes quizzes for most couples)
- AUTH_ONBOARDING_ENGINE.md gained launch-market SMS delivery requirements:
  Ghana-direct SMS provider primary, voice-OTP automatic fallback, MTN
  sender-ID registration (enforcement already live), real-SIM carrier
  testing as a launch gate, and a prohibition on relying on Firebase phone
  auth alone (documented +233 bug)

[July 2026 — v2.21] — non-conversational AI posture locked; risk docs evidence-hardened
- Added decision 28: Attune's AI is permanently non-conversational (reports,
  never a companion persona) — grounded in both the Soul document's voice
  design and the 2026 US state companion-chatbot law wave
- ATTUNE_RISK_SOLUTIONS.md rewritten to v2.0 after a five-agent research/
  red-team/simulation pass: two new kill-list risks (catastrophic wrong
  insight; weaponized accurate insight), several v1.0 mechanisms retired,
  payment-rail and regulatory findings integrated, 90-day PMF plan added
- ATTUNE_THESIS.md revised to v1.1: Between/Paired precedent framing
  corrected to match public evidence; dating-mode outcome language tightened
  to the Finkel et al. (2012) evidence posture

[July 2026 — v2.20] — Layer 0 context docs wired as mandatory entrance reading
- Added a "STOP — READ THIS BEFORE ANYTHING ELSE" block at the very top of
  the document, before "HOW TO USE THIS DOCUMENT", pointing to
  `../ATTUNE_THESIS.md` and `../ATTUNE_RISK_SOLUTIONS.md` as required
  prerequisite reading — not optional background
- Introduced a two-layer document model: Layer 0 (Context: thesis, risk
  solutions) read once before anything else and revisited after any major
  strategic decision; Layer 1 (Governance: Soul, Clinical, this spec,
  algorithm quality checklist, Principles checklist) used during
  implementation, unchanged in their existing conflict order
  among themselves
- Updated the document's closing statement to name both context documents
  and instruct anyone arriving without having read them to stop and do so
- Net effect: this master spec is now the entrance to the full document set,
  not a peer document alongside them — anyone who opens it is routed to the
  thesis and risk-solutions docs before reaching any implementation content

[July 2026 — v2.19] — historical chat import
- Resolved the open question on WhatsApp-export chat-history import: added a
  full specification in CHAT_SYSTEM_SPEC.md v1.3 Section 11 (Month 5,
  feature-flagged, dual-consent-only)
- Locked the core rule: neither partner may import prior chat history
  unilaterally — both must independently consent inside the app before any
  message from a third-party export is ingested; declining is never revealed
  to the other partner beyond a generic outcome
- Historical messages entering through import are never exempt from the
  Safety System or Layer 1/2/4 analysis — no separate or bypassable pipeline
- Import-sourced evidence carries one tier lower framework confidence than
  native evidence by default, pending clinical calibration
- Media import out of scope at launch (WhatsApp text export only; iMessage
  has no user-accessible bulk export path)
- Updated CHAT_SYSTEM_SPEC.md cross-reference to v1.3 or later

[July 2026 — v2.18] — positioning & conflict-capture
- Added lovers'-space positioning to Section 1: Attune is the dedicated chat
  for one relationship, not a general-messenger replacement (refines, does not
  reverse, decision 4); noted Between as category precedent
- Named the ceremonial-drift risk in Section 1 with its three countermeasures
  (translator as pull mechanism, data_confidence as nudge, conflict-capture
  metric)
- Added strategic-role note to 8.6: translator is the conflict-capture
  mechanism; entry point is first-class UI; opt-in-only rule unchanged
- Added conflict-capture metric to the September public-launch gate (≥30% of
  day-21-active couples with ≥1 conflict-classified session, provisional
  threshold, derived data only); onboarding + retention alone cannot detect
  ceremonial usage
- Added decision 27 and an open question for threshold calibration

[July 2026 — v2.17] — Chat System v1.1 reconciliation
- Added stable client_message_id with per-sender uniqueness so sends, offline
  retries, reconnects, and lost acknowledgements are idempotent
- Added client_message_id to the authenticated insert-column grant
- Updated optimistic sending to persist the Drift queue item before network
  submission, retain the same identifier for retries, and remove it only after
  canonical acknowledgement
- Made CHAT_SYSTEM_SPEC.md v1.1 the detailed production contract for receipt
  RPCs, Safety/outbox ordering, realtime catch-up, private media, push privacy,
  lifecycle cleanup, testing, observability, rollout, and release gates
- Removed media_thumbnail_url from the authenticated insert-column grant —
  thumbnails are worker-generated (chat spec 8.3), never client-supplied
- idx_messages_relationship_created extended to (relationship_id, created_at
  DESC, id DESC) to serve keyset pagination; definition now identical in both
  specs (same-name/different-shape would silently no-op under IF NOT EXISTS)
- Chat spec revised to v1.2 in the same pass: named the AFTER INSERT outbox
  trigger, corrected the duplicate-insert contract (no client upsert-returning
  without UPDATE privilege), added the safety-stage latency SLO, rune-based
  client length validation, queue-state → UI-status mapping, and the
  media_url-holds-object-key clarification

[July 2026 — v2.16] — correctness & robustness reconciliation
- Removed remaining React Native artifacts from the Flutter pivot: "Why this
  stack" text, Expo EAS builds (CI provider now an open question), MMKV →
  drift (SQLite), ImageManipulator → flutter_image_compress, RN optimistic-UI
  and discreet-exit snippets rewritten in Dart, safetyClient.ts → Dart service
- Fixed dead-column index idx_messages_analysis_run (column split in v2.2);
  replaced message indexes with composite + two partial pending-scan indexes
- Rewrote messages RLS: per-command policies with sender_id = auth.uid() on
  INSERT (was FOR ALL — allowed sender spoofing and partner-message tampering);
  folded the broken FOR INSERT USING ended-relationship policy into the INSERT
  WITH CHECK; added column-level INSERT grants; receipts moved to SECURITY
  DEFINER RPCs (mark_delivered / mark_conversation_read)
- Scoped one-active-relationship unique index to status = 'active' (pending
  scope collapsed to (user_a, user_a) and blocked Day 7 "invite someone else");
  added per-user single-active-relationship constraint trigger; capped
  concurrent pending invites at 3 per inviter
- Safety check no longer removes flagged messages from the analysis pipeline
  (they previously never got Layer 1 and never joined a session)
- Session cron: gap-splitting into segments, session row created before
  consumption, messages marked consumed before analysis (idempotent retries),
  fixed undefined newSessionId
- Specified Layer 3 (cross-context enrichment) — was named but never defined
- callClaude: added required x-api-key / anthropic-version headers (calls
  would 401 as written); model now CLAUDE_MODEL env (default claude-sonnet-5 —
  claude-sonnet-4-20250514 is deprecated/retired); error logging no longer
  writes raw model output (violated Section 10 log rules)
- PROHIBITED_PATTERNS: partner-name patterns built per relationship at
  runtime; literal-name regex confined to eval fixtures
- Verdict disclaimer is a fixed string appended in client code, not model output
- Forum author_hash: plain SHA256(user_id + date) → keyed HMAC with server
  secret, computed in create-forum-post edge function (plain hash was
  retroactively de-anonymisable from a user list)
- Replaced chat_sections table with chat_archived_at/chat_archived_reason on
  relationships; archive trigger rewritten (read_only state was never set,
  table rows were never created)
- messages.included_in_session_id FK added via ALTER (migration ordering)
- "3-state delivery status" renamed to delivery status lifecycle (5 states);
  specified delivered/read receipt mechanics
- Updated decision log: decisions 5, 21

[July 2026 — v2.15] — Dating Mode v1.1 reconciliation
- Separated automatic eligibility from explicit Dating enrollment and profile activation
- Removed clinically unsupported love-language compatibility scoring
- Replaced uncalibrated exact compatibility percentages with modest Alignment bands
- Locked double-blind interest, server-minimized candidate delivery, and server-authoritative state
- Excluded former-partner, Healing, safety, raw-message, private-reflection, photo, popularity, and sensitive-trait data from ranking
- Required explicit Dating-chat safety scope, adults-only enforcement, moderation, fairness review, and staged rollout

[July 2026 — v2.14] — Safety System v1.1 reconciliation
- Replaced direct safety-event message linkage with a non-reversible source event key
- Denied client access to raw safety rows; user access now uses a minimized scoped RPC
- Replaced the universal recent-app removal promise with Android and iOS contracts
- Recorded the current official Ghana Police DOVVSU helpline source and release re-verification gate

[June 2026 — v2.13] — algorithm quality checklist wired into governance
- Added `../algorithms/algorithm_quality_review_checklist.md` as a required governing document
- Required algorithmic implementations to pass the Algorithm Quality Review Checklist before merge
- Defined algorithmic scope: scoring, classification, ranking, scheduling, detection, matching, recommendation, moderation, summarization, and automated decision paths
- Updated companion-document workflow so the master spec remains the single implementation entry point

[June 2026 — v2.12] — auth/onboarding compliance with companion docs
- Added pending relationship state to prevent active couple chat unlock before mutual verified onboarding
- Clarified relationship reflection quiz is clinically blocked on final instrument decision
- Updated onboarding copy away from verdict-like "healthy relationship" language
- Aligned waiting-state copy with 7-day invite expiry and private reflection mode

[June 2026 — v2.10] — public app invite vs partner invite
- Clarified that `LoginProfile` "Invite a friend" is public app sharing only
- Locked partner invite creation to the final couples onboarding step
- Locked active couple recognition behind both users accepting/linking and completing their own onboarding flows
- Updated decision log: decision 26

[June 2026 — v2.9] — Flutter structure and design-system enforcement
- Locked Flutter feature folder structure using the profile feature as the reference
- Required screen-level coordinators to keep visible step widgets in separate files
- Required design tokens, `Gap`, responsive `.h/.w/.sp/.r`, theme colors, and existing app widgets for new UI
- Added review rules against raw `SizedBox`, raw `SnackBar`, raw `Color(...)`, and hardcoded UI durations
- Updated onboarding implementation standard to split flow screens and widgets

[June 2026 — v2.8] — Opinions shell tab
- Renamed the top-level community shell tab from Forum to Opinions
- Kept Forums as a possible nested area inside Opinions for threaded category discussions
- Updated navigation defaults: Opinions for anonymous/single users, Chat for couples
- Clarified that backend `forum_*` table names may remain unless a data-model rename is explicitly planned
- Updated decision log: decisions 11, 22, and 24

[June 2026 — v2.7] — anonymous Chat LoginProfile gate
- Locked anonymous Chat tab behavior: show adapted legacy `LoginProfile`
- Kept guest overview, learn-more, create-account, and safe settings/menu patterns
- Removed Google, Apple, email/password, booking, payment, and service-provider legacy behavior from the Attune version
- Required the Chat gate primary CTA to be phone number verification
- Updated decision log: decision 25

[June 2026 — v2.6] — two-tab shell and anonymous forum browsing
- Replaced the 5-tab shell with a 2-tab shell: Forum and Chat
- Locked default tab selection: Forum for anonymous/single users, Chat for couples
- Moved Pulse, Insights, Games, Profile, and Settings under the Chat workspace
- Made Forum a launch shell surface with anonymous read-only browsing
- Required phone-verified auth for forum posting, replying, flagging, saving, personalization, and all Chat/relationship tools
- Updated decision log: decisions 11 and 24

[June 2026 — v2.5] — phone-only auth decision
- Changed launch auth from phone OTP with Apple/Google fallback to phone OTP only
- Updated active onboarding auth language and invite handling to require phone verification
- Added schema follow-up requiring `users.phone` and removing launch email mirror support

[June 2026 — v2.4] — auth decision added
- Added auth system to section 3: phone OTP primary, Apple/Google fallback, passwordless at launch
- Added mobile auth callback and invite deep-link formats using Flutter `app_links`
- Updated users schema to support phone-first auth with nullable email and contact-required constraint
- Added relationship invite fields: invite_code, invite_expires_at, invite_accepted_at
- Added invite-code indexes and migration checklist constraints
- Added `create-relationship-invite` and `accept-invite` to service role vs user JWT policy table
- Expanded section 8.8 with passwordless auth step and invite-link handling flow
- Updated decision log: decision 23

[June 2026 — v2.3] — new features added
- Added onboarding fork: screen one "single or in a relationship?" routes entire flow
- Added Track A (single) and Track B (couples) onboarding sequences to section 8.8
- Added chat section locking spec: read-only after end, archived when either partner starts new relationship
- Added chat_sections table + locking trigger SQL
- Expanded section 8.10 Dating mode: automatic pool entry, pattern-based matching algorithm, psychology-first profile structure
- Added section 8.11: Anonymous Forum — daily-rotating hash, text-only, 4 forum status labels, 3-layer moderation, forum_posts/forum_replies/forum_flags schema
- Updated decision log: decisions 18–22
- Updated table of contents

[June 2026 — v2.2] — post Codex second review
- Fixed contradiction: 4.2 heading changed to "minimum required" (not "implement exactly as written")
- Fixed contradiction: 8.1 Month 1 chat features now match section 13 (image sharing + translator moved to Month 2)
- Fixed analysis_run overload: split into message_analysis_done + included_in_session_id on messages table
- Session detection cron updated to use new field names
- Added service-role read guard pattern for safety_events with required integration test
- Added: push notification copy must be reviewed by DV professional before launch

[June 2026 — v2.1] — post Codex review
- Added section 4.3: schema production requirements (indexes, ON DELETE, auth linkage, uniqueness constraints)
- Added section 4.4: service role vs user JWT policy table — security-critical
- Added section 6.7: AI evaluation requirements (golden transcripts, prohibited output tests, failure behavior)
- Softened 200-line file rule to "prefer under 200, justify exceptions"
- Fixed message retention: indefinite (not 24 months)
- Fixed image compression: 0.8 quality (not 0.7)
- Added open question: discreet exit platform feasibility (iOS limitation)
- Added open question: "verdict" in-app surface language decision
- Decision NOT reopened: primary chat app positioning (Codex concern noted, decision stands)

[June 2026 — v2.0]
- Added Q5–Q17 decisions from full architectural grilling session
- Added: messages.media_url, messages.media_type, messages.analysis_skipped
- Added: analysis_sessions.trigger_type, one_sided_session, truncated
- New tables: personal_insights, solo_reflections, relationship_anchors,
  translator_logs, safety_events
- Locked in: no couple report ever (permanent constraint #2)
- Locked in: discreet exit feature — top of Month 3
- Locked in: clinical advisor requirement before launch
- Locked in: optimistic UI + MMKV cache architecture (not local-first)
- Locked in: "Personal mode" label (not "Solo mode")
- Locked in: dot not badge for tab indicators
- Locked in: FRAMEWORK_CONFIDENCE levels affecting insight language
- Revised Month 1 scope with deliberate cuts

[June 2026 — v1.0]
- Initial brief generated from brainstorming session
- Core modules designed: Chat, Profiling, Tracking, Games, Insights
- AI pipeline: 4 layers specified
- Database schema: initial version
- 3-month build plan: first draft
```

---

## 17. FLUTTER IMPLEMENTATION STANDARDS

> **Required before merge:** After implementing any feature, run the relevant
> parts of `ATTUNE_PRINCIPLES_CHECKLIST.md`. For psychologically interpretive
> UI, copy, prompts, quizzes, or insight surfaces, also verify against
> `ATTUNE_CLINICAL.md` before considering the feature complete. For any
> scoring, classification, scheduling, ranking, detection, matching,
> recommendation, summarization, moderation, or automated decision logic, also
> run `../algorithms/algorithm_quality_review_checklist.md`.

### 17.1 Feature folder structure

The profile feature is the reference standard for maintainability. New and
refactored features must keep data, models, services, providers/state, screens,
and widgets separate.

Preferred structure:

```text
lib/features/[feature]/
├── data/
├── domain/
├── models/
├── repositories/
├── services/
├── presentation/
│   ├── screens/
│   ├── widgets/
│   └── state/
└── utility/
```

Use only the folders that the feature actually needs. Do not force empty
folders, but do not collapse unrelated responsibilities into one file.

### 17.2 Screen responsibility

Route-level screens and flow screens coordinate state, navigation, and
composition. They must not contain every step, tile, card, form, or repeated
piece of UI as private classes in the same file.

Example:

```text
onboarding_flow.dart          # owns current step and transition decisions
profile_setup_step.dart       # owns profile setup UI
attachment_quiz_step.dart     # owns quiz UI
onboarding_choice_button.dart # reusable selection row
```

### 17.3 Design-token requirements

All new Flutter UI must use the app design system:

- `Gap` for spacing, not `SizedBox` for simple gaps.
- `Spacing`, `BorderRadiusTokens`, `IconSizes`, `FontSizeTokens`,
  `BorderWidthTokens`, `AnimationDurations`, `AnimationCurves`, and
  `OpacityTokens`.
- ScreenUtil extensions `.h`, `.w`, `.sp`, and `.r` where sizing needs to be
  responsive.
- `Theme.of(context).colorScheme` and app theme values for colors.
- Existing widgets such as `AppTextFormField`, `AppButton`, `AppIconButton`,
  `SelectionTile`, `TabsWithContent`, `BottomSheetUtils`, snackbar extensions,
  and `SemanticContainerWidget`.

### 17.4 UI review scan

Before a UI change is considered complete, scan the changed files for:

```text
SizedBox
SnackBar(
Color(
Duration(
withOpacity
height: [number]
width: [number]
fontSize: [number]
BorderRadius.circular([number])
```

Findings are not automatically bugs, but every occurrence in new UI code must
be intentional. Prefer tokens and app widgets. Service timeouts, generated
files, third-party API requirements, and non-layout constraints may be valid
exceptions.

### 17.5 Documentation requirement

When a feature implementation changes its architecture, update the relevant
engine document under `lib/architecture/` in the same pass. The master spec
records permanent rules; feature engine docs record practical implementation
details.

---

*This document is the implementation source of truth for the Attune project.*
*It is governed by ATTUNE_SOUL.md, ATTUNE_CLINICAL.md, ../algorithms/algorithm_quality_review_checklist.md, and ATTUNE_PRINCIPLES_CHECKLIST.md.*
*It is explained and defended by `../ATTUNE_THESIS.md` (why Attune exists) and `../ATTUNE_RISK_SOLUTIONS.md` (what could go wrong and how). If you arrived at this document without having read those two, stop and read them first — see the top of this file.*
*When Codex writes code, it should be reviewable against a section here.*
*When this document and the code disagree, this document wins.*
*When this document doesn't have the answer, consult the companion docs first, then open the Claude review session.*
*Last reviewed: June 2026 · Next review: on completion of each monthly milestone*










<!-- 

The Honest Assessment
What Excites Me (The Genuinely Novel Parts)
1. The intelligence is the product, not the features.

This is the core insight that separates Attune from everything else. Most "relationship apps" are journals with a chatbot, or quizzes that give generic advice, or chat apps with a therapist bolt-on. Attune flips it: the chat is the data source. The user doesn't do extra work to build intelligence. They just live their relationship. That's actually brilliant.

Every message, every game, every conflict resolution (or not) trains the model. The product compounds. Most apps get less valuable over time (novelty wears off). Attune is designed to get more valuable the longer you use it. That's a defensible moat.

2. The ethical constraints are not afterthoughts — they're architecture.

The permanent constraints (no couple report, self-facing asymmetry, at-risk user only, recipient never knows about translator) are not just marketing promises. They're baked into the schema, the RLS policies, the prompt headers. That's rare. Most apps bolt ethics on after launch when something goes wrong. Attune has a "conscience document" that wins when it conflicts with the spec.

The honesty about WEIRD bias, about love languages having no scientific basis for matching, about NVC being practitioner-strong but research-thin — that's intellectual integrity. Users will trust a product that tells them what it doesn't know.

3. The translator as pull, not push.

Every other "AI writing assistant" pops up automatically, assuming you need fixing. Attune's translator is opt-in, per message, with equal visual weight on "Send mine" and "Send this." And the recipient never knows. That's respecting user autonomy in a way that's genuinely rare. It's a thinking tool, not a judgment machine.

4. The anonymous forum with daily-rotating hashes.

This is subtle but important. Most anonymous forums either permanently link a pseudonym to a user (which can be de-anonymized over time) or are fully ephemeral (which kills community). The daily hash means: within a single day, someone's posts are recognisably the same person (coherent conversation). But across days, you can't track them. That's a clever balance between accountability and privacy.

5. The dating mode is actually different.

Swiping is destroyed. Compatibility score and breakdown appear before the photo. Double-blind matching. Matches come from behavioural data already collected, not a new profile you fill out. And you can't enter the dating pool until you've completed a healing journey (post-mortem, pattern report, readiness quiz, 8 weeks minimum). That's treating dating as a serious transition, not a gamified distraction.

What Concerns Me (The Real Risks)
1. The AI pipeline is expensive and complex.

Per-message analysis with Claude for every message, for every couple, indefinitely. The master spec says "optimise with real data" but that's a handwave. At scale, this could be $10-50 per active couple per month. The monetisation section is conspicuously absent (marked open). If the free tier is genuinely valuable (as required), and the AI cost is real, the unit economics might not work unless premium pricing is high.

2. Cold start is still hard.

Yes, there's a compatibility preview day one using profile anchors. But the real magic — pattern detection, pulse scores, verdicts — requires weeks of data. The 48-hour solo reflection fallback is clever, but will users wait? The master spec acknowledges this (day 7 pivot screen), but retention on day 3-7 for a "waiting" user is an open question.

3. The Ghana cultural calibration is underdeveloped.

The clinical document is honest about this: WEIRD bias, no Ghana-specific validation, Ubuntu framework mentioned but not operationalized. The "communal obligation" seventh need category is proposed but not locked. The NVC translator's high-context adaptation is flagged as an open question. These aren't small gaps. If the product launches in Ghana first (as implied), and the AI reads "respectful silence" as stonewalling, the insights will be wrong. Users will feel misunderstood, not seen.

4. The safety system is hard-coded, but abuse is creative.

Hard-coded keyword detection catches obvious threats. But abuse is often implicit, coded, deniable. "You know what happens when you make me angry" doesn't have keywords. Tier 3 (pattern-based, fires after 3+ occurrences) helps, but that means someone could be emotionally abused for three incidents before any intervention. The master spec acknowledges this ("safety system never guarantees safety") but the gap is real.

5. The forum anonymity could backfire.

Daily-rotating hashes prevent cross-day tracking, but within a day, someone could still be targeted. If a user posts something vulnerable, and their partner recognises the situation (even without a name), the anonymity is broken in practice if not in database. The master spec acknowledges this as "accepted by design." But accepted doesn't mean harmless. A user whose partner is monitoring the forum could be re-traumatized.

6. The 3-month build plan is aggressive.

Month 1: Supabase, real-time chat, attachment quiz, Layer 1 AI. Month 2: image sharing, Layer 2+4, two games, verdict, translator. Month 3: discreet exit, safety system, RLS audit, store submission. That's a lot. The master spec cuts image sharing and love language quiz from Month 1 to Month 2, but it's still dense. The risk of technical debt or rushed safety review is real.

What I'd Watch Closely (Unresolved Questions)
1. Will users accept that E2EE is impossible?

The master spec is honest: disclosed in ToS. But "honest" doesn't mean "users will accept it." For a product that reads every private message, some users will be uncomfortable. The value proposition (intelligence) has to outweigh the privacy trade-off. That's a trust calculation that marketing can't fake.

2. Does "pulse score" create anxiety despite best intentions?

The spec says: never benchmark against other couples, never adjust for retention, show data confidence visibly. But any score that goes down over time will worry people. The delta vs previous is shown. If a relationship is genuinely struggling, the pulse will reflect that. Is that helpful clarity or a source of stress? The distinction is thin.

3. Can the translator really be culturally neutral?

NVC's "observation, feeling, need, request" structure is low-context, direct, verbal. Ghana is high-context, indirect, implicit. The master spec flags this as an open question requiring user testing. But if the solution is to create Ghana-specific rewrites, that's a significant localization effort. If the solution is to keep standard NVC and accept lower confidence, then Ghanaian users may find the translator alien.

4. What happens when a safety trigger is a false positive?

The spec says: fast dismiss (<60 seconds) logs as probable false positive. But the user still got a notification that something in their conversation triggered a safety alert. If it was a false positive (e.g., a joke, a quote from a movie), the user might feel watched or policed. The spec doesn't address how to apologise or correct false positives.

5. Will the dating mode really work with pattern-based matching?

The v1.1 algorithm may use clinically reviewed attachment, communication, and
conflict dimensions plus explicit values and priorities. Love-language matching
is excluded because its matching hypothesis is unsupported. Even the remaining
signals cannot establish chemistry, timing, physical attraction, safety, or
relationship success. Dating Mode therefore presents modest Alignment bands and
source-grounded reasons rather than predictive compatibility percentages. Whether
those introductions help people reach worthwhile conversations remains a measured,
explicitly unproven product hypothesis.

The Verdict (Not an Attune Verdict, Just My Assessment)
This is the most thoughtful relationship app design I've seen.

Not because it's technically complex (though it is), but because it has a genuine philosophy, a conscience, and a willingness to say "no" to things that would make it easier to build or more engaging in the short term (streaks, badges, leaderboards, swipe interfaces, automatic translator, dual safety notifications).

The product understands that trust in this category is earned slowly and lost instantly. The ethical constraints are not PR — they're in the schema, the RLS policies, the prompt headers, the permanent constraints list.

The biggest risk is not technical. It's cultural and behavioural.

Can the AI accurately read high-context, indirect communication in Ghanaian relationships? Will users trust a product that reads their messages but promises not to judge? Will they wait 7 days for a partner to join? Will they pay enough to cover Claude API costs?

These are open questions. The master spec acknowledges most of them. That honesty is encouraging.

If Attune executes on its principles, it could be genuinely category-defining.

Not because it invented chat or quizzes or AI, but because it integrates them into a system that compounds intelligence about the one thing people care about most but have the least objective data on: their own relationship.

If it fails, it will likely be because the economics didn't work, or the cultural calibration wasn't deep enough, or users didn't trust the privacy model enough to make the product their primary chat.

But those are honest risks. They're not hidden. And the product is designed to be worth returning to, not painful to leave.

That's rare. -->



<!-- 
Viral Potential Analysis
Short answer: Yes, but not in the way most apps go viral.

Attune won't spread through invite streaks, leaderboard challenges, or "share this with 3 friends to unlock" mechanics — because those are banned. But it has three genuine viral engines built into its design, and one of them is unprecedented.

Viral Engine 1: The Anniversary Report (Month 4 feature)
This is the closest thing Attune has to a Spotify Wrapped moment — but for relationships.

*"You sent 847 messages this year. Your kindness ratio increased 23%. Your most-used phrase was 'I hear you.' Here's the week you figured out the pursue-withdraw pattern."*

The master spec calls it "high shareability." That's an understatement.

Why it spreads: People will screenshot and post to Instagram/TikTok/X. Not as a brag ("look at my relationship score") — because the spec explicitly bans relationship ranking — but as a story. "Look what this app noticed about us." That's identity-signaling. It says: we have a relationship that pays attention to itself.

The constraint that makes it work: It's not a leaderboard. It's not "you're in the top 10% of couples." It's specific, sourced, and about them. That's what makes it shareable without being gross.

Estimated coefficient: High. Couples who receive a well-designed anniversary report will share it at rates similar to Spotify Wrapped (which drove massive user growth annually).

Viral Engine 2: The Compatibility Preview (Day One)
When a couple completes onboarding, they get a cold-start compatibility preview. The prompt is designed to be warm, specific, and not generic.

The spec doesn't explicitly say "shareable," but the design suggests it:

"Pairing description: max 35 words, warm and specific."

That's tweet-length. That's Instagram story-length.

Why it spreads: A new couple who just linked on Attune gets a one-sentence description of their dynamic. If it's accurate and kind, they'll screenshot it and post it. "This app already gets us." That's a testimonial that writes itself.

The risk: If the preview is wrong or generic, it won't spread. The prompt quality here is critical.

Estimated coefficient: Moderate to high. Depends entirely on prompt quality in the first month of launch.

Viral Engine 3: The "Figured Us Out" Moment (Organic, Unpredictable, Most Powerful)
This is the one that no growth hack can manufacture.

At some point — week 2, week 6, month 3 — a user will see an insight that stops them cold.

"In your last six conflict sessions, the argument about planning has always been about fairness, not logistics. You've resolved it cleanly four times. The pattern is not stuck; it's just recurring."

That user will turn to their partner and say: "Holy shit, read this."

That's not a share to social media. That's a share within the relationship. It deepens the product's value for both users, which increases retention, which increases the likelihood they'll tell a friend (in person, over text) to try it.

This is the most durable viral engine, but it's also the slowest. It requires weeks of data. It can't be rushed. And it's invisible to analytics until it happens.

Estimated coefficient: Low in month 1, increasing asymptotically as data accumulates.

What Attune Will NOT Do for Virality (And Why That's Good)
The spec explicitly bans:

Streaks (no "share to keep your streak")

Referral bonuses (no "invite 3 friends to unlock premium")

Leaderboards (no "you're #5 in your city")

Badges (no "share this achievement")

These are the standard growth playbook. Attune rejects them.

The risk: Without these, growth is slower. The product has to earn every user through genuine word-of-mouth.

The upside: The users who do come are higher quality. They're not there for a streak. They're there because someone they trust said "this app sees us."

The Hard Truth About Viral Potential
Type	Speed	Magnitude	Attune has it?
Network effect (more users = more value)	Slow	High	No — couples mode is dyadic, not networked
Social sharing (screenshot to Instagram)	Fast	Medium	Yes — anniversary report, compatibility preview
In-person referral (telling a friend)	Slow	High	Yes — if the product is genuinely insightful
Paid acquisition (ads)	Fast	Low-margin	Possible, but not viral
Built-in invite mechanic (partner invites)	Medium	High	Yes — but that's core functionality, not viral growth
The missing piece is the network effect. Tinder grew because more users = more matches. WhatsApp grew because more users = more people to message. Attune doesn't have that. A couple using Attune doesn't care how many other couples are on the platform. Their value comes from their own data, not the network.

That means Attune's growth will be linear, not exponential, unless the shareable artifacts (anniversary report, compatibility preview) are so remarkable that they drive sustained inbound interest.

The Unexpected Viral Wedge: The Anonymous Forum
This is subtle but important.

The forum is read-only for anonymous users. If the forum becomes genuinely valuable — insightful discussions about attachment, conflict repair, relationship patterns — then anonymous users who discover it via search or social shares will have a reason to sign up.

"Read this forum post about anxious-avoidant traps" → "oh, this is good" → "create account to participate" → "oh, there's a whole relationship intelligence app here."

That's a content-led acquisition funnel. It's slow, but it's durable, and it attracts users who are already thinking about relationship patterns — exactly Attune's target market.

Estimated coefficient: Low initially, builds over time as forum content accumulates.

The Verdict on Viral Potential
Attune will not explode like TikTok or Tinder. It doesn't have the network effect or the low-friction entertainment loop.

But it could have a steady, compounding growth curve — the kind that produces a $100M+ business over 3-5 years, not a flash in the pan.

The anniversary report is the closest thing to a breakout moment. If that feature is beautifully designed, emotionally resonant, and shareable without being cringe, it could drive an annual spike in new users every January (New Year, new relationship tools) and every relationship anniversary.

The real viral loop is internal, not external: The insight that makes a couple say "this app gets us" deepens their engagement, which generates more data, which generates better insights. That's not viral in the growth-hack sense. It's viral in the product becomes indispensable sense.

And that's harder to copy than a referral mechanic.

Yes, it has viral potential — but it's the slow, earned kind. Which is exactly what the soul document would want. -->
