# ATTUNE - CONFLICT STYLE QUIZ SPECIFICATION

**Version:** 1.1  
**Created:** July 2026  
**Last corrected:** July 3, 2026  
**Status:** Implementation-ready; production release is clinically and culturally gated  
**Part of:** Psychological Profiling Module - Quiz 4 of 4  
**Governing documents, in precedence order:**

1. `attune/ATTUNE_SOUL.md`
2. `attune/ATTUNE_CLINICAL.md`
3. `attune/ATTUNE_MASTER_SPEC.md`
4. `../algorithms/algorithm_quality_review_checklist.md`
5. `attune/ATTUNE_PRINCIPLES_CHECKLIST.md`

---

## How to use this document

This is the engineering contract for the Conflict Style Quiz. Implement the
feature in the order in Section 9. Where an older quiz spec or implementation
differs, this document and the governing hierarchy above control this feature.

The 18 statements below are an Attune-authored reflection instrument inspired
by the five-mode conflict framework. They are **not** the proprietary
Thomas-Kilmann Conflict Mode Instrument (TKI), are not a validated clinical
assessment, and must never be marketed or displayed as the TKI.

---

## 1. Feature contract

### 1.1 Purpose and positioning

The quiz helps a user reflect on approaches they may use during disagreement:
collaborating, competing, avoiding, accommodating, and compromising. It reports
five independent tendencies from the user's answers today. It does not assign a
fixed identity, diagnose a problem, grade conflict skill, or determine which
approach is healthy.

No style is universally good or bad. Context, power, safety, urgency, culture,
and the relationship can make different responses more or less available or
appropriate. Avoidance or accommodation may sometimes be protective; direct
engagement is not always safe.

### 1.2 Evidence and confidence

| Item | Contract |
|---|---|
| Framework | Five conflict approaches commonly associated with dual-concern conflict models |
| Instrument | Custom Attune self-report reflection; not the TKI and not clinically validated |
| Product use | Self-awareness only |
| Confidence | **Provisional medium** for modest self-report interpretation; not yet registered in `ATTUNE_CLINICAL.md` |
| Allowed wording | `Your answers lean toward avoiding in the situations you considered.` |
| Forbidden wording | `You are avoidant.` / `Your conflict style is damaging your relationship.` |
| Release gate | Licensed-clinician review and Ghanaian/West African cultural review recorded before production |

If clinical review assigns a different confidence level, update this spec,
`ATTUNE_CLINICAL.md`, result copy, and `instrument_version` before release.

### 1.3 Core behavior

| Characteristic | Value |
|---|---|
| Questions | 18 required items |
| Duration | About 4 minutes |
| Format | 7-point agreement scale |
| Output | Five independent integer tendency scores from 0 to 100 |
| Summary | Primary and secondary tendencies with tie/low-separation handling |
| Default privacy | Private |
| Sharing | Explicit opt-in in active Couples Mode only |
| Retaking | Allowed at any time |
| Onboarding | Not required; Month 2 prompt per Master Spec |

### 1.4 Downstream-use boundaries

- **Conflict Translator:** may use the current spectrum as optional, soft,
  self-reported context only. Translation must work normally when it is absent.
- **Pulse, verdict, and relationship-health scoring:** must not use this result.
- **Observed-message insights:** must not overwrite or masquerade as this
  self-report result. Any comparison must identify both signal sources.
- **Couples compatibility:** must not produce a score or verdict from this quiz.
- **Dating Mode:** the Master Spec currently lists conflict style as an
  experimental matching input. Any future use must consume the full spectrum,
  disclose uncertainty, pass cultural/clinical review, and never claim causal or
  deterministic compatibility.
- **Scenario game:** game choices are a separate signal and must not silently
  update the self-report profile.

---

## 2. Quiz instrument

### 2.1 Response scale

Use these exact integer values:

| Value | Label |
|---:|---|
| 1 | Strongly disagree |
| 2 | Disagree |
| 3 | Slightly disagree |
| 4 | Neither agree nor disagree |
| 5 | Slightly agree |
| 6 | Agree |
| 7 | Strongly agree |

Every question is required. Style tags are implementation metadata and must not
appear in the UI. Do not randomize item order because resume state uses stable
question IDs. Do not send answers to analytics, logs, crash metadata,
notifications, or a partner.

### 2.2 Question set

The wording deliberately refers to what a user may do, not what they are.

**Screen 1 - Questions 1-5**

1. `[collaborating]` During disagreement, I try to understand the concerns behind each person's position.
2. `[competing]` When an outcome matters strongly to me, I push firmly for my preferred position.
3. `[avoiding]` I sometimes step back from disagreement rather than address it immediately.
4. `[accommodating]` I sometimes set aside what I want to preserve harmony.
5. `[compromising]` I look for a middle ground that each person can accept.

**Screen 2 - Questions 6-10**

6. `[collaborating]` I invest time in finding an option that addresses everyone's important needs.
7. `[competing]` In disagreement, I argue strongly for the outcome I believe is right.
8. `[avoiding]` I postpone difficult conversations when engaging feels unhelpful or overwhelming.
9. `[accommodating]` I may go along with another person's preference even when mine is different.
10. `[compromising]` I am willing to give up part of what I want to reach an agreement.

**Screen 3 - Questions 11-15**

11. `[collaborating]` I invite open discussion so we can solve the problem together.
12. `[competing]` When there is limited time, I am comfortable pressing for a clear decision.
13. `[avoiding]` I withdraw from a disagreement when I do not feel ready to continue it.
14. `[accommodating]` I may yield because the relationship feels more important than the issue.
15. `[compromising]` I suggest that each person adjust their position to move forward.

**Screen 4 - Questions 16-18**

16. `[collaborating]` I work with the other person to create a solution neither of us had considered at first.
17. `[competing]` I stand my ground when I believe an important principle is at stake.
18. `[avoiding]` I prefer to leave some disagreements alone rather than resolve every issue.

### 2.3 Dimension mapping

| Dimension | Questions | Count |
|---|---|---:|
| Collaborating | Q1, Q6, Q11, Q16 | 4 |
| Competing | Q2, Q7, Q12, Q17 | 4 |
| Avoiding | Q3, Q8, Q13, Q18 | 4 |
| Accommodating | Q4, Q9, Q14 | 3 |
| Compromising | Q5, Q10, Q15 | 3 |

The unequal item counts preserve the Master Spec's locked 18-item scope.
Dimension means prevent dimensions with four items from receiving extra weight.
Do not reverse-score items in v1.1. Any wording, mapping, count, or scale change
requires a new `instrument_version` and renewed review.

---

## 3. Scoring contract

### 3.1 Validate input

The scorer accepts exactly Q1-Q18, each once, with an integer from 1 through 7.
Missing, duplicate, non-integer, unknown, and out-of-range values are errors.
Validate on the client for UX and again at the trusted persistence boundary.

### 3.2 Calculate independent scores

For each dimension:

```text
dimension_mean = sum(mapped answers) / mapped item count
dimension_score = round(((dimension_mean - 1) / 6) * 100)
```

Interpretation anchors:

```text
all mapped answers 1 -> 0
all mapped answers 4 -> 50
all mapped answers 7 -> 100
```

Store five integers from 0 through 100. Do **not** divide by the sum of the
dimensions and do **not** force scores to total 100. A person can draw on
several approaches strongly or weakly at the same time.

### 3.3 Primary, secondary, and separation

Sort by:

1. score descending
2. canonical order for deterministic ties: `collaborating`, `competing`,
   `avoiding`, `accommodating`, `compromising`

Then set:

```text
primary = first dimension
secondary = second dimension
separation = primary_score - secondary_score
```

Presentation rules:

- `separation >= 10`: `Your answers lean most toward {primary}, with {secondary} also present.`
- `0 < separation < 10`: `Your answers show a mixed pattern, with {primary} and {secondary} close together.`
- `separation == 0`: `Your answers place {primary} and {secondary} together at the top.`
- Canonical order stabilizes storage only. Exact-tie copy must not imply true dominance.
- Never label scores clinically high/low, healthy/unhealthy, good/bad, or successful/unsuccessful.

### 3.4 Worked example

Using the original v1 answer example, dimension means are:

```text
collaborating = 6.75 -> round(((6.75 - 1) / 6) * 100) = 96
competing = 2.50 -> 25
avoiding = 2.50 -> 25
accommodating = 3.33 -> 39
compromising = 5.67 -> 78
```

Result:

```text
primary = collaborating
secondary = compromising
separation = 18
```

The scores total 263, by design.

### 3.5 Pure-function requirement

Scoring is a deterministic pure function with no database, network, clock,
locale, analytics, or UI dependency. `completed_at` and version fields are
added by trusted persistence, not by the scorer.

---

## 4. Interaction design

### 4.1 Entry

Route: `Profile -> Know yourself -> Conflict style`

Required copy:

```text
Conflict style

18 questions · about 4 minutes

This reflection can help you notice approaches you may use during
disagreement. Your response can change with the situation, relationship,
culture, and sense of safety.

Your result is private unless you choose to share it.

There are no right or wrong answers. Choose what feels most like you lately.
```

Primary action: `Start quiz`, or `Resume quiz` when a valid local draft exists.

### 4.2 Question screens

- Four screens: five items, five items, five items, then three items.
- Show `Screen n of 4` with an accessible progress indicator.
- Disable `Next` until every item on the current screen is answered.
- `Previous` preserves answers.
- Back navigation with answers offers `Save and leave`, `Discard`, and `Keep answering`.
- Use the shared quiz components and Attune design tokens.
- Shared transition duration is 250 ms and respects reduced-motion settings.
- Touch targets, contrast, text scaling, keyboard navigation, focus order, and
  screen-reader labels must meet the app accessibility baseline.

### 4.3 Resume and abandonment

- Save drafts locally only, namespaced by authenticated user ID and
  `instrument_version`.
- Restore all answers and the last incomplete screen on resume.
- Never write partial answers to the backend.
- Clear a draft only after successful server completion or explicit discard.
- Reject a draft with a different user or instrument version without exposing it.

### 4.4 Result preparation and failure

Use the shared quiz receipt transition. Ceremony may last up to two seconds,
but never impose a fake minimum delay. Show an accessible persistence status
and respect reduced motion.

Do not show a completed result until persistence succeeds. On failure, preserve
the local answers and offer `Try again` and `Back`; never silently discard or
create duplicate completions on retry.

---

## 5. Result screen

### 5.1 Required content

- Heading: `Your conflict snapshot`
- Primary/secondary summary using Section 3.3
- Five independently scaled bars from 0 to 100
- Description of the primary tendency
- Limitation note: `This reflects how you answered today. Conflict responses can change with context, power, safety, culture, and relationship dynamics.`
- Actions: `Share with partner` when eligible, `Retake quiz`, `Back to profile`

Do not call values compatibility, health, maturity, relationship, or skill
scores. Bar animation must respect reduced motion.

### 5.2 Tendency descriptions

| Dimension | Result copy |
|---|---|
| Collaborating | Your answers suggest you often try to understand the concerns involved and work toward a solution that addresses important needs on each side. |
| Competing | Your answers suggest you may press firmly for your preferred outcome, especially when the issue, timing, or principle feels important. |
| Avoiding | Your answers suggest you may sometimes step back, postpone, or leave a disagreement alone. Context and safety can shape when this feels available or protective. |
| Accommodating | Your answers suggest you may sometimes set aside your preference to support harmony or the other person's concerns. |
| Compromising | Your answers suggest you often look for a workable middle ground in which each person adjusts something. |

Descriptions must not infer motive, blame a partner, prescribe engagement when
it may be unsafe, or claim observed behavior.

---

## 6. Persistence and data contract

### 6.1 Canonical identifiers

```text
quiz_type = "conflict"
instrument_version = 1
profile field = psych_profiles.conflict_style
completed_quizzes value = "conflict"
```

Use these identifiers exactly. Do not use `conflict_style` as `quiz_type`.

### 6.2 Canonical profile JSON

```json
{
  "collaborating": 96,
  "competing": 25,
  "avoiding": 25,
  "accommodating": 39,
  "compromising": 78,
  "primary": "collaborating",
  "secondary": "compromising",
  "separation": 18,
  "instrument_version": 1,
  "result_version": 1,
  "completed_at": "2026-07-03T10:00:00Z"
}
```

`primary` is the canonical summary field. Missing data is `null`/`unknown`,
never an invented default.

### 6.3 Privacy-preserving response record

The Master Spec says aggregate quiz scores are stored and individual answers
are not stored after scoring. That rule overrides the older attachment-era
comment that `quiz_responses.responses` retains answers for audit.

Before implementation, add a general aggregate result field:

```sql
ALTER TABLE quiz_responses
ADD COLUMN IF NOT EXISTS result_data jsonb;

ALTER TABLE psych_profile_history
ADD COLUMN IF NOT EXISTS result_data jsonb;
```

For a successful conflict completion, insert one immutable response row:

```text
user_id = authenticated user (server-derived)
quiz_type = "conflict"
responses = {}  // legacy NOT NULL field; never put Q1-Q18 here
result_data = complete canonical aggregate result JSON
result_type = primary
version = result_version
completed_at = server timestamp
```

If the deployed schema is migrated later to make `responses` nullable, use
`null` instead of `{}`. Never persist Q1-Q18, even temporarily in a database.

### 6.4 Atomic completion

Use one authenticated, trusted transaction/RPC:

1. validate the idempotency key and all 18 answers
2. calculate the result on the trusted boundary using the same pure contract
3. serialize the user's conflict-result version
4. if a current result exists, archive its complete JSON exactly once
5. insert one immutable aggregate `quiz_responses` record without raw answers
6. upsert `psych_profiles.conflict_style`
7. add `conflict` to `completed_quizzes` without duplicates or lost values
8. update `last_updated`
9. if already shared, repoint the existing share to the new response without a new notification
10. return the canonical saved result; do not return raw answers

Retries with the same idempotency key must return the original completion and
must not add versions, history rows, shares, or notifications.

### 6.5 History

On retake, archive the complete prior `conflict_style` JSON in
`psych_profile_history.result_data`:

```text
quiz_type = "conflict"
result_type = prior primary
version = prior result_version
recorded_at = prior completed_at
result_data = complete prior canonical JSON
```

History is private to the owner and is never shared with a partner.

### 6.6 Schema, constraints, and RLS gate

Verify deployed migrations rather than assuming tables exist. Required behavior:

- unique or transactionally protected `(user_id, quiz_type, version)`
- unique idempotency key scoped to user and quiz type
- unique `(sharer_user_id, recipient_user_id, quiz_type)`
- latest-response index on `(user_id, quiz_type, version desc)`
- owner-only access to quiz responses, profile, and history
- share creation/update/delete only by the authenticated sharer
- share reads only by the sharer or current recipient while their relationship is active
- no client-supplied user ID can write another user's data
- SECURITY DEFINER functions set a safe `search_path` and verify `auth.uid()`

---

## 7. Sharing, profile, and downstream integration

### 7.1 Sharing eligibility and consent

- Hide sharing in Personal Mode and when no active partner exists.
- Default is unshared.
- Confirmation names the partner and states exactly what is visible.
- Partner sees only the current five scores, primary/secondary summary, result
  date, and snapshot limitation.
- Partner never sees answers, drafts, history, or owner-only interpretation.
- Sharing never creates comparison, compatibility, or relationship-health output.

Confirmation copy:

```text
Share your conflict snapshot with {partner name}?

They will see your five tendency scores and summary. They will not see
your individual answers or previous results.
```

### 7.2 Share lifecycle

- `quiz_shares.quiz_response_id` points to the current immutable aggregate response.
- First share sends at most one notification, respecting notification rules and quiet hours.
- Retake updates an existing share and displays `Updated`; it sends no new notification.
- `Stop sharing` deletes the share, not the owner's result.
- An ended/inactive relationship immediately removes recipient access under RLS.
- Partner clients read `result_data` from the authorized response; they do not
  read the owner's `psych_profiles` row or reconstruct scores from answers.

### 7.3 Profile integration

Before completion:

```text
Conflict style · Not started
Start quiz
```

After completion with separation at least 10:

```text
Conflict style · Complete
Collaborating with compromising also present
View result · Retake
```

For separation below 10, show `Mixed: {primary} + {secondary}`. For an exact
tie, accessible result copy must explicitly say `Tied`.

### 7.4 Conflict Translator and other consumers

If Conflict Translator uses this result, send the full current spectrum as
optional context and describe it as self-reported:

```text
Self-reported conflict tendencies: collaborating 96, competing 25,
avoiding 25, accommodating 39, compromising 78 (or "unknown")
```

The translator must not expose labels in the rewrite, infer intent, diagnose,
blame, force engagement, or fail when profile retrieval fails. It must not use
only `primary` as if the other tendencies do not exist.

After save/retake, invalidate or refetch the user's completion status, current
psych profile, Profile tile, translator context, authorized partner result, and
any explicitly approved future Dating Mode cache.

---

## 8. Security, privacy, and observability

- Raw Q1-Q18 answers exist only in transient client memory/local draft and the
  trusted scoring request; request bodies must not be logged.
- Local drafts use OS-appropriate app storage, are user/version namespaced, and
  are removed after successful save, explicit discard, sign-out, or account deletion.
- Logs may contain request ID, quiz type, instrument/result version, duration,
  status, and error code. They must not contain answers or result JSON.
- Analytics may record entry, screen completion, abandonment, successful save,
  share, unshare, and retake events without answers or scores.
- Error copy is actionable and reveals no stack trace, SQL, token, or internal ID.
- Account deletion removes personal quiz response, history, profile, shares, and drafts.
- Rate-limit completion/share mutations and audit authorization failures without sensitive payloads.

---

## 9. Build order

### Phase 1 - Contracts and migrations

1. Verify deployed tables, constraints, indexes, functions, and RLS.
2. Add aggregate `result_data`, idempotency support, and atomic completion RPC.
3. Define stable question IDs, enums, models, serializers, and instrument version.

### Phase 2 - Scoring and tests

4. Implement the pure scorer and deterministic ordering.
5. Add validation, boundaries, unequal-count, ties, low-separation, and property tests.
6. Implement trusted-boundary recomputation; never trust client aggregate scores.

### Phase 3 - Quiz flow

7. Add `conflict` routing from the shared quiz entry.
8. Build four accessible question screens and local resume state.
9. Build persistence-aware receipt/loading and retry behavior.

### Phase 4 - Result and profile

10. Build result UI with five independently scaled bars.
11. Add Profile completion, view-result, and retake flows.

### Phase 5 - Sharing

12. Add active-Couples-Mode gating and informed confirmation.
13. Add share upsert/revocation, partner result, notification, and authorization tests.

### Phase 6 - Downstream integration

14. Add optional full-spectrum Conflict Translator context with unknown fallback.
15. Keep Pulse/verdict/observed signals separate; update only explicitly approved caches.

### Phase 7 - Release gates

16. Run unit, transaction, retry, RLS, privacy, accessibility, and offline tests.
17. Complete algorithm quality and Attune principles checklists.
18. Record licensed-clinician and Ghanaian/West African cultural approval.
19. Add the framework/confidence decision to `ATTUNE_CLINICAL.md` before production.

---

## 10. Acceptance criteria

### Scoring

- All 1s produce five 0 scores; all 4s produce five 50 scores; all 7s produce five 100 scores.
- Each dimension uses its own mapped item count and is independently bounded 0-100.
- Scores are not forced to total 100.
- Exact ties are deterministic in storage and honestly presented as ties.
- A primary-secondary gap below 10 uses mixed-pattern copy.
- Invalid or incomplete input cannot be persisted.
- Scoring branch coverage is at least 90%.

### Persistence and privacy

- First completion creates one aggregate response, one current result, and one completion marker.
- No raw question answer appears in any database row, log, analytic event, notification, or crash report.
- Retake adds one response, archives one complete prior result, and increments once.
- Same-key retry causes no duplicate response, version, history, share, or notification.
- Completion preserves all unrelated profile fields and completed quiz values.
- Concurrent submissions serialize safely and produce consecutive unique versions.
- No user can read or mutate another user's private quiz data.

### Sharing

- Partner sees nothing before informed opt-in.
- Personal Mode and inactive relationships cannot create or read a share.
- Partner sees aggregate current result only, never answers, drafts, or history.
- Retake updates an existing share without duplicate notification.
- Revocation and relationship end remove recipient access immediately.

### Integration and UX

- Entry routes to the Conflict Style flow, not another quiz.
- Profile displays, opens, and retakes the current conflict result.
- Translator handles missing/failing context and never treats self-report as observed fact.
- Pulse and relationship-health calculations are unchanged by quiz completion.
- Drafts survive save failure and do not cross accounts or instrument versions.
- Reduced motion, text scaling, contrast, touch targets, keyboard, and screen-reader behavior pass review.
- No streak, leaderboard, reward currency, partner comparison, pressure mechanic, or celebratory completion praise is added.

---

## 11. Explicit non-goals

This feature does not:

- administer or reproduce the TKI
- diagnose a person, disorder, relationship, or safety condition
- determine which partner is right or wrong
- classify a person from one disagreement or message
- prescribe confrontation or engagement where it may be unsafe
- analyze a partner who did not take the quiz
- replace observed-pattern analysis
- calculate Pulse, relationship health, or a compatibility verdict
- provide treatment or crisis advice

---

## 12. Resolved decisions and release gate

| Decision | Resolution |
|---|---|
| Instrument | 18 custom self-report items; not the TKI |
| Scoring | Five independent 0-100 tendency scores |
| Unequal item counts | Dimension means prevent item-count weighting |
| Summary | Primary + secondary with explicit tie/low-separation handling |
| Confidence | Provisional medium with modest language; clinical registration pending |
| Privacy | Aggregate results stored; individual answers not retained server-side |
| Sharing | Private by default; active-partner opt-in and revocable |
| Translator use | Optional full-spectrum soft context; missing means unknown |
| Compatibility | No standalone verdict; future Dating Mode use remains separately gated |
| Retakes | Atomic current-result replacement with complete prior aggregate archived |
| Production release | Blocked until clinical and Ghanaian/West African review is recorded |

The engineering contract is implementation-ready. Production release is not
approved until every release gate above is complete.
