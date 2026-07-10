# ATTUNE - DATING MODE SPECIFICATION

**Version:** 1.2  
**Created:** July 2026  
**Updated:** July 2026  
**Status:** Implementation-ready after the production gates in Section 16  
**Part of:** Post-launch matching infrastructure (Month 6+)  
**Authority:** `attune/ATTUNE_MASTER_SPEC.md` remains the product source of truth. Where an older Master example conflicts with the clinical, safety, privacy, or algorithm-quality documents listed below, those governing constraints win and the Master must be reconciled in the same change.

**Required companion documents:**

- `attune/ATTUNE_MASTER_SPEC.md`, especially Sections 2, 8.10, 10, and 17
- `attune/ATTUNE_SOUL.md`, especially dating consent and the dating anti-product
- `attune/ATTUNE_CLINICAL.md`, especially framework confidence and love-language limits
- `attune/ATTUNE_PRINCIPLES_CHECKLIST.md`, especially Section I
- `HEALING_MODE_SPEC.md` v1.1 or later
- `SAFETY_SYSTEM_SPEC.md` v1.1 or later
- `LOVE_LANGUAGE_QUIZ_SPEC.md`
- `COMMUNICATION_STYLE_QUIZ_SPEC.md`
- `CONFLICT_STYLE_QUIZ_SPEC.md`
- `algorithms/algorithm_quality_review_checklist.md`
- `DATING_MODE_REVIEW_AND_GATES.md`
- `DATING_MODE_CLINICAL_REVIEW_PACKET.md`
- `DATING_MODE_CULTURAL_REVIEW_PACKET.md`
- `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md`
- `DATING_MODE_RELEASE_READINESS_CHECKLIST.md`

---

## 1. Purpose and boundaries

Dating Mode is Attune's opt-in, psychology-first introduction system. It offers a small set of curated candidate introductions using each person's own eligible data. It is not a clinical assessment and does not predict relationship success, chemistry, safety, or whether two people should date.

Dating Mode must never:

- use swiping, infinite browsing, match/view counts, streaks, scarcity timers, confetti, or variable-reward mechanics;
- enroll an eligible user without explicit Dating Mode opt-in;
- use a former partner's profile, messages, private insights, attributed behavior, or inferred internal state;
- use Healing answers, generated Healing outputs, breakup details, or readiness score as ranking inputs;
- treat love-language similarity or complementarity as compatibility evidence;
- expose one-sided interest, rejection, profile views, candidate counts, or ranking position;
- claim that a score is scientific proof, a clinical result, a safety assessment, or a prediction of relationship success;
- permit clients to set eligibility, consent history, candidate rank, score, interest state, match state, moderation state, or age directly;
- allow unrestricted reads of active dating profiles.

The words `candidate`, `introduction`, and `mutual match` are preferred. `Compatibility score` may remain an internal legacy name, but the user-facing label is **Alignment preview**.

---

## 2. Locked product decisions

| Area | Contract |
|---|---|
| Launch gate | Month 6+ and sufficient eligible local pool; target 2,000 active couples is a planning signal, not an authorization bypass |
| Eligibility | Server-authoritative Healing v1.1 eligibility; score greater than 70, eight weeks elapsed, all stages complete, no active/pending relationship, account in good standing |
| Enrollment | Separate explicit Dating Mode opt-in; eligibility alone never enrolls |
| Historical data | Separate, optional, revocable consent for the current user's own eligible historical behavioral summaries |
| Profile | User verifies identity-facing fields and preferences before activation; no silent public profile creation |
| Discovery | Small curated introductions; no browsable dating pool |
| Interest | Double-blind; neither person learns about one-sided interest or rejection |
| Ranking | Deterministic, versioned, server-side, clinically reviewed, monitored for disparate performance |
| Photos | Secondary in information hierarchy, privately stored, moderated before display |
| Messaging | Available only after a mutual match; normal block/report and messaging safety controls apply |
| Reflections | Optional and private to the author; never visible to the match and not a ranking input without a future separate specification and consent |
| Exit | Pause immediately hides the user from new introduction generation; exit and deletion have no retention friction |

### 2.1 Gate-erosion pre-commitment

When the eligible pool is thinner than hoped — and it will be, because the
eligibility funnel is deliberately long — the pressure to weaken gates will
fall on the product owner, not on the code. This section pre-commits the
response:

**Legitimate levers under pool pressure:** grow the solo-journey supply
(Healing Mode marketed standalone), regional staged enablement, marketing,
extending the pilot, and patience.

**Never legitimate without fresh recorded clinical sign-off:** lowering the
readiness threshold (>70), shortening the eight-week gate, removing Healing
stages, weakening moderation SLAs, widening a user's stated preferences, or
softening any Section 5 hard filter. A thin pool is a growth problem;
re-labelling it an eligibility problem is the failure mode this section exists
to prevent.
---

## 3. Eligibility, consent, and enrollment

### 3.1 Eligibility source

The Dating backend reads eligibility from the trusted Healing transition defined in `HEALING_MODE_SPEC.md`. It must revalidate all gates transactionally when the user opts in and whenever their account or relationship state changes. A stale `eligible_for_dating_opt_in_at` timestamp is not sufficient by itself.

The solo Healing journey (`breakup_at_source = 'user_reported'`, HEALING_MODE_SPEC v1.2) **is** the approved eligibility path for users without an Attune relationship history, subject to its tightened time gate: because a user-reported breakup date is self-attested, solo-journey eligibility additionally requires a minimum observed journey duration (see HEALING_MODE_SPEC Section 7). Do not fabricate a breakup date or bypass Healing in the client; the tightened clock exists precisely because the reported date cannot be trusted the way `relationships.ended_at` can.

### 3.2 Required decisions

Enrollment requires four affirmative, independently recorded decisions:

1. accept the current Dating Mode terms and privacy notice;
2. opt in to Dating Mode;
3. confirm that the user is at least 18 using a server-trusted date of birth or approved age-verification result;
4. activate the reviewed dating profile.

Historical-data consent is a fifth, optional decision. Refusing it must not block Dating Mode. Without it, matching uses current self-reported quiz dimensions and explicit dating preferences only.

### 3.3 Historical-data consent

Use clear standalone copy such as:

> Your own past Attune activity can add context to your introductions. This never includes your former partner's profile, messages, private insights, or attributed behavior. Use your eligible historical summaries?

The consent screen lists every included category, purpose, retention behavior, and withdrawal effect. Consent records are append-only events with policy version, server timestamp, purpose, and grant/withdraw action.

Withdrawal takes effect before the next ranking run and immediately prevents new reads of the historical feature snapshot. Previously generated pending introductions must be invalidated and recomputed without that snapshot. Existing mutual matches remain unless a user ends or blocks them.

### 3.4 Enrollment state machine

```text
ineligible
  -> eligible_to_opt_in
  -> profile_draft
  -> active

active <-> paused
active|paused -> exited
any state -> suspended
exited -> profile_draft only through a fresh opt-in
```

Only trusted backend functions may transition state. Entering an active or pending relationship automatically pauses Dating Mode, invalidates unrevealed introductions, and prevents new matching. It must not reveal Dating participation to a former partner or new partner.

---

## 4. Dating profile

### 4.1 Profile fields

| Field | Source | User control | Display rule |
|---|---|---|---|
| Display name | Verified account profile | Editable under account rules | First name or chosen display name only |
| Date of birth | Trusted account/verification flow | Correction through protected flow | Never display; derive age server-side |
| Age | Server-derived | Not directly editable | Display integer age only |
| City/region | User-selected coarse location | Editable | Never expose GPS, exact distance, home/work area, or coordinates |
| Gender identity | Self-report | Editable/private options allowed | Display only with explicit visibility choice |
| Interested-in preferences | Self-report | Editable | Never exposed as a searchable population attribute |
| Relationship intention | Self-report | Editable | Display using approved values |
| Bio | User-authored | Editable/deletable | Moderated; 500 characters maximum |
| Photos | User upload | Reorder/delete | Optional; moderated; private storage; signed URLs |
| Quiz dimensions | Current user's aggregate results | Refresh by retaking quiz | Show only dimensions approved for dating display |
| Values/preferences | Explicit dating questions or eligible personal summaries | Editable/withdrawable | Source-labelled and confidence-aware |

Do not infer or display ethnicity, religion, sexuality, disability, income, trauma, fertility, health status, or political belief from behavior. Sensitive preferences may be collected only after legal, clinical, fairness, and product review with a documented necessity.

### 4.2 Psychology-first hierarchy

The introduction detail places the Alignment preview and its modest explanation before photos. It must not disclose another person's private quiz scores or diagnostic-sounding labels.

Example:

```text
Alignment preview: Promising shared ground

Shared signals
- Similar preference for direct communication
- Several overlapping relationship priorities

Worth exploring together
- You may approach disagreement differently

Based on self-reported Attune activities. This cannot predict chemistry,
safety, or relationship success.

[Photo] Ama, 29 - Accra
[View profile]
[Interested] [Not for me]
```

Do not display a precise percentage until calibration research demonstrates that users interpret it accurately and it has an empirically defensible meaning. Initial release uses calibrated bands: `limited_signal`, `some_shared_ground`, `promising_shared_ground`. These are presentation bands, not probability claims.

### 4.3 Photo and bio moderation

- Upload to a private bucket using opaque object paths; never expose bucket paths or permanent public URLs.
- Strip EXIF and location metadata, normalize orientation, and generate bounded variants server-side.
- Require moderation before display. A pending or failed photo cannot enter candidate payloads.
- Define file type, decoded-image validation, dimension, size, count, malware, and rate limits.
- Provide an appeal/review path for moderation decisions.
- Never use photos, face embeddings, attractiveness, skin tone, or image-derived attributes in ranking.
- Bios require abuse/spam moderation separate from the relationship-message Safety System. Dating moderation must not reuse safety-trigger events as reputation signals.

---

## 5. Candidate eligibility and hard filters

Before scoring, both users must:

- be authenticated adults with active Dating profiles;
- satisfy current server-side Dating eligibility;
- have compatible explicit age-range, gender, intention, and coarse-location preferences;
- not be the same user, current/former linked partner, blocked account, previously unmatched account within the cooldown, or account under suspension/review;
- have no pending or active relationship that disables Dating Mode;
- have enough approved profile content to render safely;
- fall within any legally required jurisdiction rules.

Hard filters are symmetric: a pair is eligible only if each user's preferences admit the other. Never infer these preferences from quizzes or historical behavior.

Blocking is immediate and bilateral. It removes unrevealed introductions, ends visibility and messaging for a revealed match, prevents future pairing, and does not notify the blocked user who blocked them. Reporting and blocking are separate actions, though the UI may offer both.

### 5.1 Former-partner exclusion must survive re-registration

User-ID-based exclusion has a known hole: a former partner who deletes their
account and re-registers with a new phone number becomes a new UUID and could
be *introduced to their ex* — with photos making it instantly discoverable. In
DV histories this is a stalking vector, not an awkward edge case.

Required mitigation (pending privacy-review approval — see Section 17):

- retain a keyed exclusion record per ended relationship: an HMAC (server
  secret) of each former partner's verified phone number, stored without
  reversible identity, surviving account deletion for exclusion-matching only;
- at candidate generation, exclude pairs where either candidate's verified
  phone HMAC matches an exclusion record of the other;
- purpose-limit these records to pair exclusion; they are never a ranking,
  moderation, or analytics input, and are never exposed through any API.

Fallback until approved: block-on-sight remains available, and the residual
risk is documented in the Section 15 threat model rather than silently
accepted. If the privacy owners reject the phone-HMAC design, an alternative
exclusion mechanism must be approved before production — shipping with the
hole undocumented is not an option.

---

## 6. Alignment algorithm v1

### 6.1 Evidence boundary

Version 1 may use only:

- current user's aggregate attachment dimensions, with clinical confidence limits;
- current user's aggregate communication-style dimensions;
- current user's aggregate conflict-style dimensions;
- explicit values and relationship-priority answers collected for an approved purpose;
- the user's own eligible historical behavioral summaries only when historical-data consent is active.

Version 1 must not use:

- love-language match, mismatch, similarity, or complementarity;
- former-partner data or pair-level data attributable to a former partner;
- raw messages, raw game answers, journals, Healing reflections/outputs, readiness score, safety events/resources, reports, blocks, moderation allegations, location traces, photos, biometrics, protected traits, or inferred sensitive traits;
- engagement, likelihood to pay, popularity, attractiveness, response speed, profile views, or prior interest volume.

Love-language preferences may personalize a first-date guide for the person who supplied them. They are not a ranking input and are never framed as evidence that two people fit.

### 6.2 Scoring contract

The exact feature transforms, weights, missing-data behavior, and band thresholds live in a versioned server-side configuration reviewed by product, clinical, data, safety, and fairness owners. Placeholder constants are forbidden.

```text
eligible pair
  -> build one consent-filtered feature vector per user
  -> compute symmetric component distances
  -> apply versioned weights only to present, approved components
  -> normalize by available approved weight
  -> calculate confidence from evidence completeness, not score magnitude
  -> map internal score to a calibrated presentation band
  -> attach plain-language reasons derived from the same feature IDs
```

Required properties:

- symmetry: `score(a,b) == score(b,a)` unless an explicitly documented directional preference feature is presented separately;
- determinism: same version and feature snapshots produce the same output;
- missingness neutrality: missing quiz/history data is not scored as poor fit;
- provenance: every component records feature IDs, source type, source date, consent basis, transform version, and weight version;
- explainability fidelity: displayed reasons must be generated from scored features, never invented by an LLM;
- boundedness: all component and total scores have validated ranges;
- replayability: authorized staff can reproduce a score from immutable snapshots without exposing raw private data.

### 6.3 Clinical language

Allowed:

- "You both described preferring direct communication."
- "You named several similar relationship priorities."
- "You may approach conflict differently; that can be something to explore."

Forbidden:

- "You are 84% compatible."
- "Secure people are a good match for anxious people."
- "This pairing is healthy/safe/likely to last."
- "Your love languages complement each other."
- "Your past relationship proves you need this type of partner."

### 6.4 Candidate generation and cadence

- Run a bounded weekly server-side batch at a configurable UTC schedule with jitter and load controls.
- Candidate generation is idempotent per `user_id + algorithm_version + cohort_window`.
- A manual refresh requests recomputation; it does not bypass cooldown, reveal pool size, or scan from the client.
- Rate-limit refresh per account and device. Return a neutral next-available time.
- Cap active unrevealed introductions per user. The initial cap is a product configuration validated in pilot; it must not be presented as a count-based achievement.
- Randomize only within a narrow, documented score band using a stored seed to avoid deterministic popularity feedback loops.
- Never lower safety, consent, preference, or eligibility filters to fill an empty state.

### 6.5 Evaluation and fairness

Offline evaluation must cover synthetic and consented research data, sparse profiles, missing dimensions, adversarial values, cross-cultural language, and every preference boundary. Before launch:

- define the intended outcome and prove that proxy metrics do not become claims of relationship success;
- measure exposure, mutual-interest, block/report, and conversation-start rates by approved audit cohorts where lawful and ethically reviewed;
- test ranking stability, missing-data effects, and false precision;
- conduct Ghanaian/West African cultural review;
- document known limitations and cohort sizes;
- establish drift thresholds, rollback conditions, and a human owner;
- prevent feedback from existing exposure from becoming an uncorrected popularity signal.

Protected/sensitive attributes used for fairness auditing are access-restricted, purpose-limited, separated from production ranking features, and never available to candidate APIs.

---

## 7. Introduction and mutual-match lifecycle

```text
generated -> presented -> interested | passed | expired | invalidated
interested + reciprocal interested -> matched
matched -> active | unmatched | blocked | closed
```

- Both people may receive the same neutral introduction independently. Neither sees whether the other has received or acted on it.
- `Interested` is private until both have independently expressed interest.
- Do not show "they liked you," inbound-like queues, blurred admirers, or monetized revelation.
- `Not for me`, expiry, and no response are private. The other person receives no rejection event.
- Mutual transition must be atomic, idempotent, and race-safe. One pair produces at most one active mutual match.
- An introduction is invalidated if eligibility, consent, profile, moderation, block, relationship, or algorithm-version constraints change before mutual match.
- Expiry is server-controlled and may not use urgency copy.

After mutual match, reveal the match simultaneously through generic push notifications that do not include sensitive psychological data. Users may then open a dedicated conversation. Do not automatically create a Couples relationship.

Moving from Dating to Couples Mode requires a separate mutual, verified relationship-link flow. A dating match alone is not a relationship record.

---

## 8. Messaging, safety, blocking, and reporting

Dating messages require a dedicated conversation type with authorization limited to both members of an active mutual match. Existing message delivery, media, retention, and account-deletion rules apply where compatible.

The `SAFETY_SYSTEM_SPEC.md` currently defines detection for active relationship chat only. Dating chat must not silently claim that protection. Before Dating messaging ships, the Safety specification must explicitly approve dating-chat scope, routing semantics, copy, and tests, or Dating chat must display accurate scope language and provide manual resources without claiming automated detection.

Dating-specific trust and safety must include:

- block, unmatch, and report from profile and conversation surfaces;
- report categories and evidence handling reviewed by legal and safety owners;
- no retaliation signal or reporter identity disclosed to the reported account;
- moderation access through least-privilege audited tools;
- rate limits for introductions, interest actions, messages, media, reports, and profile edits;
- spam, impersonation, harassment, sexual-content, and underage-risk procedures;
- **romance-scam procedures as a first-class category** — West Africa is a
  known base for romance-scam operations, and a psychology-first app whose
  brand is trust is an attractive hunting ground. Dating chat safety scope
  must include financial-request pattern detection, a dedicated scam report
  category, and scam-awareness education (Section 9). One publicized scam
  through Attune damages the couples product too;
- generic state copy when an account disappears; never reveal suspension, report, block, or deletion cause;
- always-available manual Safety Resources and the global privacy cover/quick-exit behavior on sensitive surfaces.

Safety events, dismissals, reports, and blocks never improve or reduce an Alignment score. Blocks are exclusion controls; reports are moderation inputs, not psychological traits.

---

## 9. Guided first-date support

After a mutual match, each person may open a private guide containing:

- neutral conversation starters based on explicit shared values or the viewer's own preferences;
- one gentle area to approach with curiosity when supported by approved dimensions;
- reminders about consent, public-place planning, transport independence, and sharing plans with a trusted person, reviewed by a safety expert;
- a financial-safety reminder, reviewed by the same safety expert: never send
  money, account details, or mobile-money transfers to someone you have not
  met in person, no matter the stated emergency — with a direct link to the
  scam report category;
- direct access to block, report, unmatch, and Safety Resources.

Do not label a topic "a question to avoid," infer trauma, reveal private scores, or expose one person's answer to the other. Generated text is optional; deterministic reviewed templates are the launch default. Any future model generation requires a separate prompt contract, evidence IDs, output validation, no raw messages, and deterministic fallback.

The guide must not guarantee safety or imply that psychological alignment reduces first-date risk.

---

## 10. Post-date reflection

Post-date reflection is optional, private, skippable, and available only to its author. Use neutral options such as `I would like to meet again`, `I am unsure`, `I would rather not`, plus an optional 500-character private note.

- The other person never sees the response or note.
- A response does not send interest, rejection, or feedback to the match.
- Notes are excluded from AI prompts, ranking, analytics payloads, support tools, and exports shared with another person.
- Reflection data is deletable by the author and retained only under the documented retention schedule.
- Product analytics may record completion as a boolean event, never the selected answer or note.

---

## 11. Data model

The following is a logical contract, not a copy-paste migration. Migrations must use the project's standard timestamps, foreign-key actions, grants, trigger conventions, and explicit indexes.

### 11.1 Core tables

```sql
dating_enrollments (
  user_id uuid primary key references auth.users(id),
  state text not null,
  terms_version text not null,
  opted_in_at timestamptz,
  activated_at timestamptz,
  paused_at timestamptz,
  exited_at timestamptz,
  suspended_at timestamptz,
  state_version bigint not null default 1,
  created_at timestamptz not null,
  updated_at timestamptz not null
)

dating_consent_events (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  purpose text not null,
  action text not null check (action in ('granted', 'withdrawn')),
  policy_version text not null,
  categories jsonb not null,
  occurred_at timestamptz not null,
  idempotency_key text not null,
  unique (user_id, idempotency_key)
)

dating_profiles (
  user_id uuid primary key references auth.users(id),
  display_name text not null,
  city_region_code text not null,
  relationship_intention text not null,
  bio text,
  profile_state text not null,
  moderation_state text not null,
  profile_version bigint not null default 1,
  created_at timestamptz not null,
  updated_at timestamptz not null
)

dating_preferences (
  user_id uuid primary key references auth.users(id),
  min_age smallint not null,
  max_age smallint not null,
  gender_preferences jsonb not null,
  region_preferences jsonb not null,
  intention_preferences jsonb not null,
  updated_at timestamptz not null
)

dating_profile_photos (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  storage_key text not null,
  position smallint not null,
  moderation_state text not null,
  created_at timestamptz not null,
  unique (user_id, position)
)
```

Date of birth remains in the protected account/verification domain and is not duplicated in `dating_profiles`.

```sql
dating_feature_snapshots (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  algorithm_version text not null,
  consent_basis jsonb not null,
  features jsonb not null,
  source_provenance jsonb not null,
  created_at timestamptz not null,
  invalidated_at timestamptz
)

dating_introductions (
  id uuid primary key,
  pair_key text not null,
  user_low_id uuid not null references auth.users(id),
  user_high_id uuid not null references auth.users(id),
  algorithm_version text not null,
  snapshot_low_id uuid not null references dating_feature_snapshots(id),
  snapshot_high_id uuid not null references dating_feature_snapshots(id),
  internal_score numeric not null,
  display_band text not null,
  explanation_features jsonb not null,
  state text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null,
  unique (pair_key, algorithm_version, created_at)
)

dating_interest_actions (
  id uuid primary key,
  introduction_id uuid not null references dating_introductions(id),
  actor_user_id uuid not null references auth.users(id),
  action text not null check (action in ('interested', 'passed')),
  acted_at timestamptz not null,
  idempotency_key text not null,
  unique (actor_user_id, idempotency_key),
  unique (introduction_id, actor_user_id)
)

dating_matches (
  id uuid primary key,
  introduction_id uuid not null unique references dating_introductions(id),
  user_low_id uuid not null references auth.users(id),
  user_high_id uuid not null references auth.users(id),
  state text not null,
  matched_at timestamptz not null,
  closed_at timestamptz,
  created_at timestamptz not null
)

dating_blocks (
  blocker_user_id uuid not null references auth.users(id),
  blocked_user_id uuid not null references auth.users(id),
  created_at timestamptz not null,
  primary key (blocker_user_id, blocked_user_id)
)

dating_date_reflections (
  id uuid primary key,
  match_id uuid not null references dating_matches(id),
  user_id uuid not null references auth.users(id),
  response text,
  private_note text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (match_id, user_id)
)
```

Reports belong in the platform moderation domain, not a broadly readable Dating table. Audit records and ranking-run metadata are backend-only.

### 11.2 Canonical pair key

All pair records store ordered UUIDs (`user_low_id`, `user_high_id`) and a backend-derived pair key. Enforce `user_low_id < user_high_id` and prevent self-pairs. Never trust client ordering.

---

## 12. Authorization and API boundary

Raw Dating tables are denied to `anon` and, except narrowly scoped self-owned profile draft operations, denied to direct `authenticated` writes. Expose user-JWT RPCs/edge functions that derive the actor from `auth.uid()`.

Required operations include:

- `get_dating_eligibility()`
- `begin_dating_enrollment(idempotency_key, terms_version)`
- `record_dating_consent(idempotency_key, purpose, action, policy_version, categories)`
- `save_dating_profile_draft(...)`
- `activate_dating_profile(idempotency_key)`
- `pause_dating_mode(idempotency_key)`
- `exit_dating_mode(idempotency_key)`
- `get_my_dating_introductions(cursor, limit)`
- `act_on_dating_introduction(idempotency_key, introduction_id, action)`
- `get_my_dating_matches(cursor, limit)`
- `unmatch_dating_match(idempotency_key, match_id)`
- `block_dating_user(idempotency_key, target_user_id)`
- `submit_dating_report(idempotency_key, target_id, category, details)`
- `save_private_date_reflection(idempotency_key, match_id, response, note)`
- `delete_private_date_reflection(idempotency_key, match_id)`
- `delete_dating_profile(idempotency_key)`

Candidate payloads are minimized views assembled server-side. They include only fields approved for that viewer and introduction. They never include user IDs where an opaque introduction/match ID suffices, raw feature vectors, exact scores, preference filters, consent state, profile popularity, reports, blocks, or moderation metadata.

Authorization tests must prove that a user cannot:

- enumerate active profiles or pool membership;
- read another user's enrollment, consent, preferences, snapshots, actions, reflection, report, or unrevealed interest;
- act on an introduction not presented to them;
- forge age, eligibility, profile moderation, score, explanation, match, or actor identity;
- continue reading or messaging after pause, invalidation, unmatch, block, suspension, or deletion where the contract forbids it.

---

## 13. Privacy, retention, and analytics

### 13.1 Data minimization

- Store coarse region codes, never exact coordinates or distance from another user.
- Keep private photos in private storage and use short-lived signed delivery.
- Do not put names, phone numbers, photo URLs, bios, notes, preference values, feature vectors, or sensitive cohort labels in logs, traces, crash reports, push payloads, or product analytics.
- No Dating data is used to train a model.
- Support export and deletion of the user's own Dating data.

### 13.2 Retention

Before production, legal/privacy owners must approve exact retention periods for profile drafts, withdrawn snapshots, expired introductions, passed actions, closed matches, reports, moderation evidence, private reflections, and operational logs. `Indefinite` is not an acceptable default.

Pause preserves the profile but removes it from new generation immediately. Exit removes it from the pool and schedules Dating-only data deletion under the approved retention policy. Account deletion invokes the platform deletion workflow. Legal holds apply only through an audited restricted process.

### 13.3 Analytics

Allowed aggregate events include enrollment-step completion, introduction rendered, action completed, mutual match created, conversation started, guide opened, reflection completed, pause, exit, and operational errors. Event properties use opaque IDs and non-sensitive versions only.

Never record profile content, action direction toward a named person, exact score, psychological dimensions, private reflection response/note, report details, block target, birth date, gender/sexuality preference, location, photo URL, or historical-data categories in analytics.

---

## 14. Failure and edge-case behavior

| Scenario | Required behavior |
|---|---|
| Eligibility revoked during enrollment | Stop activation; preserve a private draft only under retention policy |
| Historical consent withdrawn | Invalidate snapshots and unrevealed introductions; recompute without history |
| User pauses | Hide from new generation immediately; preserve existing mutual matches unless user closes them |
| User enters a relationship | Auto-pause; invalidate unrevealed introductions; do not notify other candidates of the reason |
| Profile/photo moderation pending | Exclude from generation; show private status and appeal path |
| One user blocks before reciprocal interest | Invalidate pair silently; no match or notification |
| Reciprocal interests race | One atomic mutual match and at most one notification per user |
| Introduction expires during action | Reject generically and fetch current state; do not reveal the other action |
| Algorithm batch partially fails | Retry bounded partitions idempotently; do not publish partial invalid pairs; dead-letter exhausted work |
| Sparse profile | Use fewer approved components and lower evidence confidence; never penalize missingness |
| Empty local pool | Neutral empty state; no pool size, fake scarcity, widened filters, or lowered safeguards |
| Former partners both enroll | Permanent pair exclusion; neither learns the other enrolled |
| Former partner re-registers under a new account | Phone-HMAC exclusion (5.1) prevents pairing; if exclusion cannot match (new number), block-on-sight applies and the residual risk is documented, never silent |
| Match requests money or financial details | Scam report category available in one tap; financial-request patterns in dating-chat safety scope; reporter privacy preserved |
| Report or suspension | Apply moderation state generically; preserve reporter privacy |
| Safety automation unavailable | Messaging behavior follows its approved scope; manual resources remain available; no false safety claim |
| Device clock manipulated | No effect on eligibility, expiry, cooldown, or rate limits |

---

## 15. Implementation order

1. Reconcile Master, Clinical, Healing, Safety, and Dating contracts; record clinical, legal/privacy, safety, cultural, and fairness approvals.
2. Threat-model enumeration, one-sided-interest leakage, stalking/location inference, former-partner re-registration (Section 5.1), romance-scam operations, underage access, image abuse, forged eligibility, consent withdrawal, race conditions, and moderator access.
3. Implement schemas, constraints, indexes, retention jobs, private storage, RLS denials, backend-only ranking tables, and audit controls.
4. Implement and integration-test trusted eligibility, enrollment, consent, profile, pause, exit, block, report, and deletion operations.
5. Implement profile verification and moderation without candidate discovery.
6. Build a pure, deterministic Alignment v1 library with versioned fixtures, provenance, missingness handling, replay tests, and no love-language scoring.
7. Build offline evaluation, cultural/fairness review, performance tests, monitoring, rollout flags, and rollback runbook.
8. Implement bounded idempotent candidate generation and minimized candidate APIs.
9. Implement introduction UI and atomic double-blind interest flow; penetration-test non-reciprocal leakage.
10. Reconcile Dating messaging with the Safety specification, then implement match chat, block/unmatch/report, and generic notifications.
11. Implement deterministic guided-date templates and private post-date reflection.
12. Run accessibility, localization, privacy-cover, real-device, abuse, load, chaos, RLS, and deletion tests.
13. Pilot behind a feature flag with a small reviewed cohort; inspect quality and fairness gates before gradual expansion.

All Flutter UI follows Master Section 17: feature-folder structure, Riverpod boundaries, design tokens, responsive sizing, app widgets, semantics, reduced-motion behavior, and the UI review scan.

---

## 16. Production acceptance gates

Dating Mode is not production-ready until written evidence exists for every applicable item in `algorithms/algorithm_quality_review_checklist.md` and all of the following:

Use `DATING_MODE_CLINICAL_REVIEW_PACKET.md`,
`DATING_MODE_CULTURAL_REVIEW_PACKET.md`,
`DATING_MODE_DATING_CHAT_SAFETY_PLAN.md`, and
`DATING_MODE_RELEASE_READINESS_CHECKLIST.md` as the operating review pack for
this section. Engineering may implement non-blocked foundations before these
approvals, but production release may not proceed without recorded evidence in
that pack.

### Clinical and product

- [ ] Clinical advisor approves included dimensions, transforms, explanations, uncertainty copy, and excluded claims.
- [ ] Love-language matching is absent from ranking and compatibility explanations.
- [ ] No copy predicts success, health, safety, readiness, or attachment-pair destiny.
- [ ] Ghanaian/West African cultural review is recorded.
- [ ] No swipe, browsing, count, admirer, urgency, confetti, or monetized-revelation mechanic exists.

### Consent and privacy

- [ ] Eligibility, Dating opt-in, terms, age gate, profile activation, and historical-data consent are distinct server-authoritative states.
- [ ] Refusing historical-data consent still permits Dating Mode.
- [ ] Consent withdrawal invalidates historical snapshots and pending introductions.
- [ ] Former-partner data, Healing content, safety data, raw messages, and private reflections are absent from ranking.
- [ ] Retention schedule, export, deletion, private storage, signed URLs, EXIF stripping, analytics minimization, and privacy impact assessment are approved and tested.

### Security and trust

- [ ] RLS/RPC tests with at least four accounts prove no profile enumeration, cross-user reads, one-sided-interest leakage, actor forgery, or block bypass.
- [ ] Adults-only enforcement and protected correction flow are tested; age is never a client-editable integer.
- [ ] Photo/bio moderation, appeal, block, unmatch, report, spam, impersonation, and harassment procedures are operational.
- [ ] Dating messaging's Safety scope and user copy are explicitly approved and tested.
- [ ] Push, logs, analytics, traces, crash reports, and support tools contain no prohibited Dating data.

### Algorithm and operations

- [ ] Golden fixtures prove symmetry, determinism, boundedness, provenance, missingness neutrality, and explanation fidelity.
- [ ] Candidate hard filters are symmetric and cannot be weakened by refresh or empty-pool behavior.
- [ ] Concurrent interest creates one mutual match; retries are idempotent.
- [ ] Batch complexity, capacity, cost, indexes, bounded queues, retries, dead-letter handling, reconciliation, and failure recovery are measured.
- [ ] Fairness/cultural evaluation, drift thresholds, monitoring, alerts, runbooks, feature flags, canary, and rollback are approved.
- [ ] Account pause, exit, relationship creation, consent withdrawal, block, suspension, and deletion invalidate the correct records within documented SLAs.

### UX and accessibility

- [ ] Alignment preview appears before photos and includes the limitations note.
- [ ] One-sided interest, pass, expiry, pool size, and rejection remain private in UI, API, notification, and timing behavior.
- [ ] Every state works with screen readers, text scaling, non-color indicators, localization, reduced motion, offline/retry behavior, and privacy cover.
- [ ] Safety Resources, block, report, and unmatch are easy to reach and never paywalled.

---

## 17. Resolved contradictions and deferred decisions

### Resolved in v1.2

- Gate-erosion pre-commitment recorded (2.1): thin-pool responses are growth
  levers; eligibility gates move only with fresh clinical sign-off.
- Solo Healing journey confirmed as the approved eligibility path for users
  without an Attune relationship, subject to Healing v1.2's tightened
  minimum-observed-journey clock (self-attested breakup dates cannot satisfy
  the eight-week gate alone).
- Former-partner re-registration named in the threat model; phone-HMAC
  exclusion design specified (5.1), pending privacy approval.
- Romance scams elevated to a first-class trust-and-safety category with
  financial-request detection scope, a dedicated report category, and a
  financial-safety line in the guided first-date content.
- Dating chat safety proceeds as a separate Dating Chat Safety specification
  (option 2 in `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md`) — the couples Safety
  System's coercive-control families do not transfer to stranger-chat threats.

### Resolved in v1.1

- Eligibility no longer means automatic pool enrollment.
- Love languages are removed from ranking because Clinical explicitly prohibits love-language compatibility scoring.
- Exact percentages are withheld until calibrated; launch uses modest Alignment bands.
- One-sided likes are never revealed; the prior "they liked you" flow was not double-blind.
- Age is server-derived from protected date of birth, not freely editable.
- Active profiles are not directly readable through RLS; candidate delivery is server-minimized.
- Candidate and match state are backend-authoritative and race-safe.
- Former-partner, Healing, safety, raw message, and private reflection data are explicitly excluded.
- Dating messaging does not silently inherit a Safety System scoped only to relationship chat.

### Blocking external decisions before production

- Exact approved Alignment v1 transforms, weights, bands, and evidence-completeness thresholds.
- Jurisdiction-specific age verification, dating-service legal terms, retention, moderation, and report-evidence policy.
- Approved profile fields and preference taxonomy, including sensitive-category necessity.
- Dating-chat Safety System scope and operational moderation staffing.
- Pilot cohort, minimum pool density by region/preference segment, fairness audit design, and rollout thresholds.
- Privacy-owner approval of the former-partner phone-HMAC exclusion design (5.1), or an approved alternative exclusion mechanism.

These decisions may be configuration values only after their owners approve them. Implementers — human or AI — must not invent them.

---

*This document is ready for implementation of non-blocked foundations. Production activation remains gated by Section 16 and the external decisions in Section 17.*
