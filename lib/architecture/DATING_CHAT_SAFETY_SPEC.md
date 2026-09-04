# ATTUNE — DATING CHAT SAFETY SPECIFICATION

**Status:** Draft for safety-owner review. Nothing in this document is
approved. Dating chat may not ship until Section 12's blockers are checked.

**Supersedes:** the "required decision" in
`DATING_MODE_DATING_CHAT_SAFETY_PLAN.md` §2. That plan recorded a working
product-owner decision (July 2026) to write a *separate* dating-chat safety
specification rather than extend the couples Safety System. This is that
document. The plan remains the operating checklist; this is the scope it
was waiting on.

**Reads with:** `SAFETY_SYSTEM_SPEC.md` (couples; the system this one
deliberately does not reuse), `DATING_MODE_SPEC.md` (§8 messaging, §9
guided date, §14 edge cases), `algorithms/algorithm_quality_review_checklist.md`.

---

## How to use this document

Section 2 is the whole argument: dating chat and couples chat share a
transport and share almost nothing else. If you read one section, read that
one — every later decision follows from it.

Sections 3–7 are the safety contract proper and are what the safety owner is
being asked to approve. Sections 8–11 are engineering consequences. Section
12 is the release gate.

---

## 1. Scope and permanent boundaries

### 1.1 Purpose

Dating chat carries conversation between two people who have mutually
matched and, in most cases, have never met. This system exists to make that
conversation survivable for the person on the receiving end of harassment,
sexual pressure, impersonation, or a romance scam — without turning the
product into a surveillance layer over ordinary flirtation.

It is not the couples Safety System pointed at a new table. See §2.

### 1.2 Permanent invariants

Inherited from `SAFETY_SYSTEM_SPEC.md` §1.2 unchanged, because they are
correct for any recipient in any chat:

| Invariant | Required behavior |
|---|---|
| Non-LLM detection | Only the versioned deterministic rules engine decides triggers |
| Recipient-only routing | The at-risk user is the authenticated match member *receiving* the message |
| Fail-open delivery | Safety subsystem failure never blocks or delays message delivery |
| Private resources | Safety events and dismissals are readable only by the at-risk user |
| Free access | Resources, block, report, unmatch, and quick exit are never paywalled |
| No training | Messages, matches, events, and dismissals never train a model |
| No personalization suppression | A dismissal never weakens later detection for that user |
| No client-side detection | No detection, delay, or scoring runs on the device |

Departures from the couples spec, each deliberate:

| Couples invariant | Dating behavior | Why |
|---|---|---|
| **Sender secrecy** — no signal ever reveals a trigger | **Retained for detection. Abandoned for enforcement.** A trigger is invisible to the sender; a *moderation action* following a report is not. | In couples chat the sender is someone the recipient lives with, and a visible flag escalates danger at home. A dating sender is a stranger the recipient can be permanently separated from. Hiding enforcement from a harasser protects nobody. |
| **No punishment** — no report, lock, or enforcement follows a trigger | **Retained for triggers. Explicitly rejected as a system property.** Triggers still cause no automatic enforcement, but reports do, through moderation. | The couples system refuses to adjudicate an intimate relationship. Dating is a platform with strangers on it, and declining to remove a predator is not neutrality. |
| **No accusation** — copy never says the partner is dangerous | **Retained in trigger copy. Relaxed in scam education.** Scam copy may name the pattern plainly ("people asking for money this early are usually scamming"). | Naming a coercive partner as abusive is a clinical judgment we will not make for someone. Naming an advance-fee scam is a factual description of a known fraud pattern. |

### 1.3 Included surfaces in v1

- incoming one-to-one messages in an **active dating match chat**
- the block / report / unmatch controls reachable from that chat
- the guided first-date financial-safety education (`DATING_MODE_SPEC.md` §9)
- manual Safety Resources access from dating surfaces

### 1.4 Explicitly excluded surfaces

Not connected to this pipeline without a further spec and review:

- images, audio, video, links, and attachments — see §5.4, the single largest
  known gap in v1
- profile bios and photos, which have their own moderation path
- introduction state before a mutual match, where no chat exists
- post-date reflections, which are private and single-authored
- sender-authored self-harm statements — the recipient-only rule would route
  help to the wrong person, exactly as in couples chat
- automatic police, emergency-service, or family contact
- any cross-referencing of dating chat with couples chat, Healing content,
  or a user's relationship history

---

## 2. Why not the couples system

This section is the decision. Everything else implements it.

### 2.1 The threat models barely overlap

The couples Safety System detects **coercive control by an intimate
partner**: isolation, monitoring, financial control, threat, and degradation
delivered by someone with sustained access to the recipient's life. Its rule
families are named for that — `pattern_control` is the tier-3 family, and
the at-risk user is a *relationship member*.

Dating chat's dominant threats are the opposite shape: **harm by a stranger
with no sustained access**, principally harassment, unsolicited sexual
content, grooming of a young-presenting user, impersonation, and romance
scams. These are single-message or short-arc threats from someone the
recipient can be permanently cut off from in one tap.

### 2.2 What running couples rules on dating chat would actually do

Both failure directions are real and both are bad:

**False negatives on what matters.** The couples rules contain nothing for
advance-fee patterns, sextortion, requests to move to an off-platform
channel, or age-probing. A romance scammer's opening months are warm,
attentive, and entirely unremarkable to a coercive-control detector. The
system would watch the whole grooming arc and say nothing.

**False positives on what doesn't.** Couples rules assume shared life and
sustained access. Two strangers negotiating a first date produce exactly the
surface forms those rules watch for — where are you, who are you with, when
are you free — with none of the meaning. Surfacing coercive-control
resources at ordinary first-date logistics teaches users the safety system
is noise, which is the one thing a safety system cannot afford.

### 2.3 The structural argument

`enqueue_message_downstream_work` fires on every `messages` insert and does
three couples-specific things: increments `relationships.message_count`,
enqueues safety analysis against the couples config, and enqueues the
relationship-health notification. `analyse-session` — the AI relationship
analysis — references relationships throughout.

A dating message routed through that trigger would corrupt a couple's
message count, feed strangers' conversation into relationship-health
analysis, and evaluate it against the wrong rule set. None of that is a
tuning problem.

### 2.4 What IS shared

The transport, and deliberately all of it: composer, bubbles, realtime
subscription, delivered/read receipts, keyset pagination, media upload
intents, presence, typing. That machinery does not know or care whether two
people are a couple, and maintaining a second copy of it would guarantee
drift. See §8 for how.

---

## 3. Rule families

Detection is deterministic phrase-family matching against a versioned,
reviewed configuration — the same engine contract as `SAFETY_SYSTEM_SPEC.md`
§3, with a different config. Rules are server-side only and are never shipped
to a device.

### 3.1 Families in v1

| Family | Tier | What it targets | Recipient outcome |
|---|---|---|---|
| `sexual_pressure` | 1 | Unsolicited explicit content or persistent sexual pressure after disinterest | Resources + one-tap report |
| `harassment_abuse` | 1 | Insults, degradation, or hostility directed at the recipient | Resources + one-tap report |
| `threat_intimidation` | 2 | Threats to the recipient's person, reputation, or contacts, including sextortion framing | Resources + report, prominently |
| `financial_request` | 2 | Requests for money, bank/mobile-money details, gift cards, crypto, or investment participation | Scam education + one-tap scam report |
| `contact_migration_pressure` | 1 | Early, insistent pressure to move to an unmonitored channel, especially paired with any other family | Gentle education only |
| `age_signal` | 3 | Language suggesting the *sender* may be a minor, or probing the recipient's age in a grooming pattern | No recipient copy; moderation queue |
| `identity_inconsistency` | 3 | Impersonation markers — scripted-persona phrasing, claimed-identity contradictions | No recipient copy; moderation queue |

### 3.2 Tier semantics

Tiers are internal routing metadata and are never shown to either user —
the same contract as `SAFETY_SYSTEM_SPEC.md` §3.2. What differs is what the
tiers *route to*: the couples tiers differ mainly in how many matches are
needed before the same neutral notification fires, whereas these differ in
whether a recipient sees anything at all.

- **Tier 1** — single-message match; recipient sees resources; no queue entry.
- **Tier 2** — single-message match; recipient sees resources; **also** a
  moderation queue entry, because these families predict harm to *other*
  users of the platform, not only this recipient.
- **Tier 3** — never produces recipient-facing copy. Routes to moderation
  only. `age_signal` and `identity_inconsistency` are inferences about the
  *sender* that we are not confident enough to tell a recipient, and telling
  them would both accuse a possibly-innocent person and tip off a
  possibly-guilty one.

### 3.3 Thresholds for newly matched users

The plan asks whether thresholds differ for new matches. **They do, in one
direction only: `financial_request` and `contact_migration_pressure` are
strictly more sensitive in the first 14 days of a match.**

Rationale: a money request in week one is close to definitionally a scam,
while the same words between people who have met several times may be
ordinary. Sensitivity may *increase* with unfamiliarity; it may never
*decrease* with familiarity — a long conversation is precisely what
successful grooming produces, so decay would disable protection at the point
of maximum risk.

No other family varies by match age.

### 3.4 Normalization and matching

Inherits `SAFETY_SYSTEM_SPEC.md` §3.3–3.4 unchanged: the same normalization
(case, diacritics, whitespace, common substitutions), the same word-boundary
matching, the same versioned config with a recorded hash. Reusing the engine
while replacing the config is the whole point of this document.

---

## 4. Recipient experience

### 4.1 What a trigger does

A tier-1 or tier-2 match makes support available to the recipient. It does
not block the message, delay it, mark it, or alter what the sender sees.

Copy requirements:

- never assert the sender is a predator, scammer, or minor;
- always describe the *pattern*, never the person ("messages asking for money
  this early are almost always a scam" — not "this person is a scammer");
- always name the concrete next actions available: block, report, unmatch;
- never imply the recipient invited it or should have known.

### 4.2 Scam education is the exception that names the pattern

For `financial_request`, copy may state plainly that advance-fee and
emergency-money requests are a known fraud pattern, and link directly to the
`romance_scam` report category. This is the one place the "no accusation"
posture relaxes, and only because the claim is about a documented fraud
pattern rather than a psychological judgment about a person.

This education is the same copy the guided first-date support already
carries (`DATING_MODE_SPEC.md` §9), so a user meets it twice: once
proactively before a date, once at the moment it matters.

### 4.3 Controls

Per `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md` §3:

- block and report are at most **two taps** from the chat screen, present in
  the chat header, and never behind an overflow menu;
- Safety Resources is reachable from dating chat;
- Quick Exit works on dating chat surfaces exactly as elsewhere;
- no send delay and no client-side detection is introduced.

### 4.4 Blocking must hold against stale state

A blocked or unmatched pair must not be able to continue messaging through a
client that still holds the old chat open. Enforcement is server-side in
RLS, not in the UI, and §12 requires a test proving it.

---

## 5. Moderation, enforcement, and operations

### 5.1 Reports drive enforcement; triggers do not

A tier-2 or tier-3 trigger creates a moderation queue entry. It never
directly restricts an account. Restriction follows human moderation review,
recorded in `dating_account_restrictions`, whose existing types
(`suspended`, `under_review`, `age_review`, `moderation_hold`) are the
enforcement vocabulary.

This preserves the useful half of the couples system's no-punishment
posture — an automated phrase match must never suspend a person — while
rejecting the half that would leave a reported predator in the pool.

### 5.2 Report categories

The categories already exist in `dating_reports` and are unchanged:
`harassment`, `impersonation`, `romance_scam`, `spam`, `underage_risk`,
`other`. `romance_scam` is the dedicated scam category the plan requires.

### 5.3 Runbook ownership

Required before launch, owned by the safety owner, not by engineering:

- triage SLA per report category, with `underage_risk` and
  `threat_intimidation` given the shortest;
- who reviews tier-3 queue entries, and on what evidence;
- evidence retention window and admin access process, minimized per §7;
- appeal path for a restricted account;
- escalation path for credible threat-to-life, which is a human decision and
  never automated.

### 5.4 Known gap: media is not scanned

v1 detection is text-only. Unsolicited explicit *images* — a common
first-contact harassment vector on dating platforms — are not detected by
this pipeline. Mitigations available today are the recipient's report and
block controls, and profile-photo moderation, which does not cover chat.

This is stated plainly rather than buried: it is the largest known gap in
v1, and closing it requires an image-moderation path with its own review.

---

## 6. Privacy

Per the plan's §3 privacy requirements and `DATING_MODE_SPEC.md` §13:

- **No one-sided interest leakage through notifications.** A dating-chat
  notification must reveal nothing about the other person's actions beyond
  the fact that a matched conversation has a new message.
- **No prohibited dating data in push previews, logs, traces, analytics, or
  support tooling.** Message content never appears in a push preview by
  default, and never in a log line under any setting.
- **Safety event storage is minimized:** the rule id, family, tier, config
  version, at-risk user, match id, and a source event key. Never the message
  text. Anonymization follows the couples contract
  (`SAFETY_SYSTEM_SPEC.md` §4.2).
- **Dating chat is never cross-referenced** with couples chat, Healing
  content, readiness scores, or relationship history — in either direction.
  The alignment algorithm's evidence boundary (`DATING_MODE_SPEC.md` §6.1)
  already forbids the reverse; this states the forward direction.

---

## 7. Retention

| Data | Retention |
|---|---|
| Dating chat messages | Deleted when the match closes plus the moderation evidence window; never retained past account deletion |
| Safety events | Per `SAFETY_SYSTEM_SPEC.md` §4.2 anonymization contract |
| Moderation queue entries | Retained for the evidence window defined by the runbook, then anonymized |
| Reports | Retained per the moderation runbook; reporter identity never exposed to the target |

Exact windows are a privacy-review decision, recorded here once approved.

---

## 8. Engineering shape

Consequence of §2, recorded so the review knows what is being approved.

### 8.1 Separate table, shared surface

Dating messages live in their own table with their own RLS and their own
`AFTER INSERT` trigger. They do not live in `public.messages`.

Reason: `messages.relationship_id` is `NOT NULL` and references
`relationships`, and its insert trigger performs couples-specific work.
Making that column nullable to accommodate dating would put both message
kinds one policy mistake away from each other, and the failure mode is a
stranger's message appearing in someone's relationship chat.

A separate table makes the isolation structural rather than
policy-dependent. The Flutter chat surface is abstracted over a message
source so the composer, bubbles, pagination, and receipts are shared code.

### 8.2 Separate outbox and worker

Dating messages enqueue to their own safety outbox, processed against the
dating config by its own worker. The couples worker is untouched.

### 8.3 No relationship-health analysis

Dating chat is never fed to `analyse-session`, `analyse-message`, or any
relationship-health pipeline. Those exist to help a couple understand their
relationship; two strangers on a third conversation have no such object, and
producing a "health score" for them would be both meaningless and a privacy
violation.

**This is the answer to "could the AI analysis be different?" — for v1 it is
absent, not different.** Any future dating-side analysis requires its own
spec, its own purpose statement, and its own consent basis.

---

## 9. Failure behavior

- Safety processing failure never blocks, delays, or alters message delivery
  (fail-open, inherited).
- A worker failure retries with bounded attempts and lands in dead-letter,
  visible in operational health.
- Detection unavailability is never surfaced to users as a safety claim;
  manual controls and resources remain reachable at all times.
- Config load failure means **no detection**, never a fallback to the
  couples config. Cross-contaminating rule sets is a worse outcome than a
  gap, because it produces confident wrong answers.

---

## 10. Observability

Per the quality checklist §4:

- queue depth, processing lag, dead-letter count for the dating safety outbox;
- trigger rate by family and tier, to catch a rule that is firing far too
  often or has gone silent;
- report volume by category, and time-to-triage against the runbook SLA;
- alert on: zero triggers over a window where message volume is normal (a
  silently broken detector), dead-letter growth, and triage SLA breach.

No metric may include message content or be attributable to an individual
recipient in a shared dashboard.

---

## 11. Testing requirements

Before the §12 blockers can be checked:

- golden fixtures per rule family: true positives, and the near-miss
  negatives that would produce the §2.2 false-positive failure;
- a test proving a blocked or unmatched pair cannot message through stale
  client state;
- a test proving dating messages never enter `public.messages`, never
  increment `relationships.message_count`, and never enqueue to the couples
  safety outbox;
- a test proving no client role can read another user's safety events;
- a test proving push payloads and log lines carry no message content;
- real-device validation of Quick Exit and Safety Resources from dating chat.

---

## 12. Release blockers

Carried from `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md` §5, now answerable
against this document:

- [ ] Safety scope explicitly approved for dating chat — **this document**
- [ ] Reviewed user copy approved — §4 copy requirements, actual strings
      pending
- [ ] Moderation and support runbook approved — §5.3
- [ ] Privacy/security review approved — §6, §7
- [ ] Real-device validation complete — §11

Plus, specific to this spec:

- [ ] Rule families and tier routing (§3.1–3.2) reviewed by the safety owner
- [ ] The new-match threshold asymmetry (§3.3) reviewed
- [ ] The three departures from couples invariants (§1.2) explicitly accepted
- [ ] The media gap (§5.4) accepted as a known v1 limitation, or closed

---

## 13. Open questions for the reviewer

Stated rather than silently resolved:

1. **Is tier-3 silence right?** `age_signal` produces no recipient copy. The
   alternative — telling a recipient we suspect the other person is a
   minor — risks accusing an adult who writes casually and tipping off a
   groomer. This spec chose silence plus moderation. That is a judgment
   call and it may be wrong.
2. **Should `financial_request` ever hard-block a message?** This spec says
   no, on fail-open grounds. A reviewer may reasonably argue that a first
   message asking for mobile-money details is worth blocking outright.
3. **What is the evidence-retention window?** §7 leaves it to privacy
   review; moderation wants it long, privacy wants it short.
4. **Does the media gap (§5.4) block launch?** Unsolicited explicit images
   are a real and common harm. Shipping text-only detection is defensible
   only if the report path is fast enough to compensate.

---

## Changelog

- **2026-09-04** — Initial draft. Written against
  `DATING_MODE_DATING_CHAT_SAFETY_PLAN.md` §2's recorded option-2 decision.
  Not approved.
