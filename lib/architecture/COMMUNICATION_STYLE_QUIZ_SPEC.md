# ATTUNE — COMMUNICATION STYLE QUIZ SPECIFICATION

**Version:** 1.1  
**Updated:** July 2026  
**Status:** Implementation-ready; production release requires clinical and Ghanaian cultural review  
**Part of:** Psychological Profiling Module — Quiz 3 of 4  
**Canonical dependencies:**
- `attune/ATTUNE_MASTER_SPEC.md`
- `attune/ATTUNE_CLINICAL.md`
- `attune/ATTUNE_SOUL.md`
- `attune/ATTUNE_PRINCIPLES_CHECKLIST.md`
- `CONFLICT_TRANSLATOR.md`
- `ATTACHMENT_STYLE_QUIZ.md` (shared persistence and sharing contracts)
- `algorithms/algorithm_quality_review_checklist.md`

If this document conflicts with the Master, Clinical, Soul, or Principles documents, those documents win. Do not silently invent behavior; record and resolve the conflict before implementation.

---

## 1. Feature Contract

### 1.1 Purpose

The quiz is a private self-reflection tool that helps a user notice how they currently report communicating, especially when needs, disagreement, or pressure are present. It measures four familiar communication-style dimensions:

- assertive
- passive
- aggressive
- passive-aggressive

The result is a snapshot of self-reported tendencies, not a diagnosis, fixed identity, moral judgment, or direct observation of behavior.

### 1.2 Clinical position

| Aspect | Requirement |
|---|---|
| Framework | Four communication-style dimensions |
| Evidence position | Common psychoeducational model; this Attune questionnaire is not a validated clinical instrument |
| Confidence | **MEDIUM, provisional**; release is gated on licensed-clinician and Ghanaian cultural review |
| Required result framing | “Your answers suggest you may lean toward direct, respectful communication in many situations.” |
| Forbidden framing | “You are passive-aggressive.” / “Your communication style damages relationships.” |
| Known limitations | Self-report and social-desirability bias; behavior changes by relationship, power, safety, setting, language, and culture |

The words `aggressive` and `passive-aggressive` may appear as framework labels in a private result. They must never be used as identity labels, partner-facing accusations, diagnoses, or automated judgments.

### 1.3 Product rules

| Characteristic | Value |
|---|---|
| Questions | 20 |
| Duration | About 4 minutes |
| Response format | 7-point agreement scale |
| Output | Four independent 0–100 tendency scores |
| Summary | Primary and secondary tendencies, with low-separation handling |
| Default privacy | Private |
| Sharing | Explicit opt-in in active Couples Mode only |
| Retaking | Allowed at any time |
| Onboarding | Not required; Month 2 prompt per Master Spec |

### 1.4 Downstream-use boundaries

- **Conflict Translator:** may use the user's current primary tendency as soft personalization context. It must preserve meaning, never diagnose, and must work normally when no result exists. It must not default a missing result to `assertive` as though it were measured.
- **Pulse and relationship-health scoring:** must not use this self-report result.
- **Couples compatibility:** must not produce a compatibility score or verdict from this quiz alone.
- **Dating Mode:** the Master Spec currently permits communication-style pairing as one input to its explicitly experimental matching model. That use must remain spectrum-based, uncertainty-aware, culturally reviewed, and must never be shown as deterministic compatibility.
- **Observed-message insights:** must not overwrite this self-report result. Any comparison between self-report and observed behavior must clearly name the two different signal sources.

---

## 2. Quiz Instrument

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

Every question is required. Do not submit partial answers. Never send question answers to analytics, logs, crash metadata, notifications, or the partner.

### 2.2 Question set

The style tags are implementation metadata and must never be shown in the quiz UI.

**Screen 1 — Questions 1–5**

1. `[assertive]` I express my needs clearly and directly.
2. `[passive]` I hold back my true feelings to avoid disagreement.
3. `[aggressive]` When I strongly disagree, I interrupt before the other person has finished.
4. `[passive_aggressive]` When I am frustrated, I sometimes use sarcasm instead of saying what is wrong.
5. `[assertive]` I feel able to set a boundary respectfully.

**Screen 2 — Questions 6–10**

6. `[passive]` I find it hard to say no when I do not want to agree.
7. `[aggressive]` When something goes wrong, I quickly focus on what the other person did wrong.
8. `[passive_aggressive]` I sometimes agree to something and show my resentment later.
9. `[assertive]` I make room for another person's view while explaining my own.
10. `[passive]` I avoid raising an issue even when it matters to me.

**Screen 3 — Questions 11–15**

11. `[aggressive]` When I am frustrated, my words can become harsh or dismissive.
12. `[passive_aggressive]` I sometimes show displeasure by becoming deliberately unresponsive instead of explaining it.
13. `[assertive]` I can disagree without attacking the other person's character.
14. `[passive]` I set aside my own needs even when I would prefer to speak up.
15. `[aggressive]` I take over conversations when I feel strongly about something.

**Screen 4 — Questions 16–20**

16. `[passive_aggressive]` When I feel hurt, I sometimes make an indirect critical remark.
17. `[assertive]` I can ask for what I need without demanding it.
18. `[passive]` I struggle to speak up when other people may disagree.
19. `[aggressive]` During conflict, I make accusations about the other person's behavior.
20. `[passive_aggressive]` I avoid addressing an issue directly but let my frustration show in other ways.

### 2.3 Dimension mapping

| Dimension | Questions |
|---|---|
| Assertive | Q1, Q5, Q9, Q13, Q17 |
| Passive | Q2, Q6, Q10, Q14, Q18 |
| Aggressive | Q3, Q7, Q11, Q15, Q19 |
| Passive-aggressive | Q4, Q8, Q12, Q16, Q20 |

Do not reverse-score questions in v1.1. Do not randomize question order because the resume contract uses stable question IDs. Instrument wording changes require a new `instrument_version` and renewed clinical/cultural review.

---

## 3. Scoring Contract

### 3.1 Validate input

The scoring function accepts exactly Q1–Q20, each containing an integer from 1 through 7. Missing keys, duplicate keys, non-integers, and out-of-range values are errors. Validate on both client and trusted persistence boundary.

### 3.2 Calculate independent dimension scores

Each dimension is independently converted to 0–100. Do **not** divide one dimension by the sum of all dimensions and do **not** force the four scores to total 100; these tendencies can coexist.

```text
dimension_mean = sum(the dimension's five answers) / 5
dimension_score = round(((dimension_mean - 1) / 6) * 100)
```

Interpretation anchors:

```text
all 1s -> 0
all 4s -> 50
all 7s -> 100
```

Store integer scores from 0 through 100.

### 3.3 Determine primary, secondary, and separation

Sort dimensions by:

1. score descending
2. canonical order for deterministic ties: `assertive`, `passive`, `aggressive`, `passive_aggressive`

Then set:

```text
primary = first dimension
secondary = second dimension
separation = primary_score - secondary_score
```

Presentation rules:

- `separation >= 10`: show “Your answers lean most toward {primary}, with {secondary} also present.”
- `separation < 10`: show “Your answers show a mixed pattern, with {primary} and {secondary} close together.”
- Exact ties use canonical order only for storage stability. The UI must say the dimensions are tied, not imply one truly dominates.
- Never classify a score as clinically “high,” “low,” healthy, unhealthy, good, or bad.

### 3.4 Worked example

Given dimension means:

```text
assertive = 6.4 -> round(((6.4 - 1) / 6) * 100) = 90
passive = 2.6 -> 27
aggressive = 1.2 -> 3
passive_aggressive = 2.4 -> 23
```

Result:

```text
primary = assertive
secondary = passive
separation = 63
```

The scores do not total 100, by design.

### 3.5 Pure-function requirement

Scoring must be a deterministic pure function with no database, network, clock, locale, or UI dependency. `completed_at` is added by the save operation, not the scoring function.

---

## 4. Interaction Design

### 4.1 Entry

Route: `Profile -> Know yourself -> Communication style`

Required copy:

```text
Communication style

20 questions · about 4 minutes

This reflection can help you notice how you express needs and respond
to disagreement. Communication can change across situations and relationships.

Your result is private unless you choose to share it.

There are no right or wrong answers. Choose what feels most like you lately.
```

Primary action: `Start quiz` or `Resume quiz` when local progress exists.

### 4.2 Question screens

- Four screens, five questions per screen.
- Show `Screen n of 4` and an accessible progress indicator.
- `Next` remains disabled until all five current answers are present.
- `Previous` preserves answers.
- Back navigation asks whether to save local progress or leave when answers exist.
- Touch targets, contrast, text scaling, keyboard navigation, and screen-reader labels must meet the app accessibility baseline.
- Motion uses the shared quiz transition (250 ms) and respects reduced-motion settings.

### 4.3 Resume and abandonment

- Save in-progress answers locally on device, namespaced by authenticated user ID and `instrument_version`.
- Do not write partial responses to `quiz_responses`.
- On resume, restore the last incomplete screen and all prior answers.
- Clear the local draft only after a successful server save or explicit discard.
- If the authenticated user changes, never expose the prior user's draft.

### 4.4 Result preparation

Use the shared quiz receipt transition. The animation may last up to 2 seconds, but saving must not be artificially delayed by a mandatory minimum. Respect reduced-motion settings and show an accessible progress label while persistence is pending.

If save fails, keep answers locally and offer `Try again`; do not show a completed result as though it was persisted.

---

## 5. Result Screen

### 5.1 Required content

- Heading: `Your communication snapshot`
- Primary and secondary summary using Section 3.3
- Four independently scaled bars from 0–100
- A description of the primary tendency
- Limitation note: `This reflects how you answered today. Communication can change with context, safety, culture, and relationship dynamics.`
- Actions: `Share with partner` when eligible, `Retake quiz`, `Back to profile`

Do not call the values compatibility, health, skill, or relationship scores.

### 5.2 Descriptions

| Dimension | Result copy |
|---|---|
| Assertive | Your answers suggest you often try to express needs directly while making room for the other person's perspective. |
| Passive | Your answers suggest you may sometimes hold back needs or disagreement, especially when speaking up feels difficult. |
| Aggressive | Your answers suggest that strong feelings may sometimes come through as interruption, accusation, or forceful language. This is a pattern to notice, not a judgment about you. |
| Passive-aggressive | Your answers suggest that frustration may sometimes come out indirectly rather than being named openly. This is a pattern to notice, not a fixed label. |

Descriptions must not infer motive, blame a partner, prescribe a relationship decision, or claim observed behavior.

---

## 6. Persistence and Data Contract

### 6.1 Canonical identifiers

```text
quiz_type = "communication"
instrument_version = 1
profile field = psych_profiles.communication_style
completed_quizzes value = "communication"
```

Use these identifiers exactly. Do not use `communication_style` as `quiz_type`.

### 6.2 Canonical profile JSON

```json
{
  "assertive": 90,
  "passive": 27,
  "aggressive": 3,
  "passive_aggressive": 23,
  "primary": "assertive",
  "secondary": "passive",
  "separation": 63,
  "instrument_version": 1,
  "result_version": 1,
  "completed_at": "2026-07-03T10:00:00Z"
}
```

`primary` is the canonical downstream field. Existing Conflict Translator code currently reads `communication_style.type`; implementation must migrate it to `primary`. During a staged rollout only, readers may fall back from `primary` to legacy `type`. Do not persist duplicate `type` data in new results.

When no profile/result exists, downstream features use `null`/`unknown`, never an invented `assertive` default.

### 6.3 Quiz response record

Insert one immutable `quiz_responses` row per successful completion:

```text
user_id = authenticated user
quiz_type = "communication"
responses = {"Q1": 6, ..., "Q20": 3}
result_type = primary
version = previous maximum version + 1
completed_at = server timestamp
```

The existing shared table does not currently define columns for all four spectrum scores. The source of truth for the current spectrum is `psych_profiles.communication_style`; history requirements are addressed below. Do not write undocumented columns such as `result_data` unless a migration is added first.

### 6.4 Atomic completion

Completion must be performed in a trusted transaction/RPC, not as unrelated client writes:

1. authenticate and validate all answers
2. lock or otherwise serialize the user's communication result version
3. if a current profile result exists, append its complete JSON to history
4. insert the immutable response row
5. upsert `psych_profiles.communication_style`
6. add `communication` to `completed_quizzes` without removing other values or creating duplicates
7. update `last_updated`
8. if already shared, point the existing share at the new response without sending a new notification

Use an idempotency key per submission so retries cannot create duplicate versions or history rows.

### 6.5 History schema requirement

The legacy `psych_profile_history` shape shown in the Attachment spec stores only `result_type` and attachment-specific scores. That is insufficient for communication growth history. Before implementing retake history, add a backward-compatible JSONB field:

```sql
ALTER TABLE psych_profile_history
ADD COLUMN IF NOT EXISTS result_data jsonb;
```

For communication history, store the complete prior `communication_style` JSON in `result_data`, plus:

```text
quiz_type = "communication"
result_type = prior primary
version = prior result_version
recorded_at = prior completed_at
```

History is private to the owner under RLS. Never expose history to a partner.

### 6.6 Database verification gate

The repository documentation describes `quiz_responses`, `quiz_shares`, and `psych_profile_history`, but implementation must verify that deployed migrations actually create them, their constraints, indexes, and RLS policies. “Defined in another spec” is not proof that the database contains them.

Required uniqueness/index behavior:

- unique or transactionally protected `(user_id, quiz_type, version)`
- unique `(sharer_user_id, recipient_user_id, quiz_type)`
- indexed latest-response lookup by `(user_id, quiz_type, version desc)`

---

## 7. Sharing Contract

### 7.1 Eligibility and consent

- Hidden in Personal Mode or when no active partner exists.
- Default is unshared.
- Sharing requires an explicit confirmation naming the partner and exactly what will be visible.
- Partner can see only the current primary, secondary, four scores, result date, and snapshot disclaimer.
- Partner never sees answers, local drafts, history, or private interpretation copy.
- Sharing creates no compatibility verdict.

Confirmation copy:

```text
Share your communication snapshot with {partner name}?

They will see your four tendency scores and summary. They will not see
your individual answers or previous results.
```

### 7.2 Share lifecycle

- `quiz_shares.quiz_response_id` points to the currently shared immutable response.
- First share sends one notification.
- A retake updates an existing share automatically and shows `Updated`; it does not send another notification.
- If the relationship is no longer active, the partner view must no longer expose the result under the relationship-access rules.
- Provide `Stop sharing` if the app's shared-quiz pattern supports revocation; revocation deletes the share record, not the owner's quiz result.

Sharing reads the canonical profile JSON for the spectrum while authorization is established by `quiz_shares`. Do not reconstruct communication percentages from answer data in the partner client.

---

## 8. Profile and Conflict Translator Integration

### 8.1 Profile

Before completion:

```text
Communication style · Not started
Start quiz
```

After completion:

```text
Communication style · Complete
Assertive with passive also present
View result · Retake
```

For a separation under 10, display `Mixed: {primary} + {secondary}` rather than implying a clear dominant style.

### 8.2 Conflict Translator

Reader contract:

```text
communication_style = profile.communication_style?.primary
                    ?? profile.communication_style?.type  // legacy read only
                    ?? null
```

The request may send the primary key as soft context. The prompt must describe it as self-reported and current:

```text
Self-reported communication tendency: {value or "unknown"}
```

It must not:

- presume `assertive` when absent or on fetch failure
- expose the quiz label in the rewrite
- make the rewrite more accusatory because of a style result
- use the result to infer intent or diagnose behavior
- fail translation when the profile lookup fails

### 8.3 Cache invalidation

After successful completion or retake, invalidate/refetch:

- current user's quiz completion status
- current psych profile
- profile `Know yourself` section
- any in-memory Translator context
- partner shared-result view when already shared
- any explicitly approved Dating Mode matching cache that consumes communication style

---

## 9. Build Order

### Phase 1 — Contracts and migrations

1. Verify deployed schemas, constraints, indexes, and RLS.
2. Add `psych_profile_history.result_data` and atomic completion RPC/mutation.
3. Define result model, question constants, instrument version, and canonical JSON serialization.

### Phase 2 — Scoring and tests

4. Implement pure scoring and deterministic ordering.
5. Add boundary, tie, low-separation, validation, and property tests.

### Phase 3 — Quiz flow

6. Add quiz-type routing from the shared entry screen.
7. Build four accessible question screens and local resume state.
8. Build persistence-aware receipt/loading and retry behavior.

### Phase 4 — Result and profile

9. Build the result screen and independent spectrum bars.
10. Add Profile completion, view-result, and retake flows.

### Phase 5 — Sharing

11. Add Couples Mode gating and informed confirmation.
12. Add share upsert, partner view, notification, retake update, and authorization tests.

### Phase 6 — Downstream integration

13. Migrate Conflict Translator from `.type` to `.primary`, remove the invented `assertive` default, and invalidate context after retake.
14. Update any approved Dating Mode consumer to read all four scores and uncertainty, not only the primary label.

### Phase 7 — Release gates

15. Run security, RLS, accessibility, offline/retry, and algorithm test suites.
16. Obtain licensed-clinician and Ghanaian cultural review of the instrument and result copy.
17. Record reviewer approval and `instrument_version` before production release.

---

## 10. Acceptance Criteria

### Scoring

- All 1s produce four zero scores; all 4s produce four 50 scores; all 7s produce four 100 scores.
- Scores are independently bounded 0–100 and are not forced to sum to 100.
- Exact ties are deterministic in storage and honestly presented as ties.
- A primary-secondary gap below 10 uses mixed-pattern copy.
- Invalid or incomplete responses cannot be persisted.
- Scoring branch coverage is at least 90%.

### Persistence

- First completion creates one response, one current profile result, and one completion marker.
- Retake creates one new immutable response, archives the full previous result once, and increments `result_version` once.
- Retrying the same submission causes no duplicate response, version, or history entry.
- Completion preserves all other psych-profile fields and completed-quiz values.
- No client-controlled user ID can write another user's result.

### Privacy and sharing

- Partner sees nothing before explicit sharing.
- Personal Mode cannot create a share.
- Partner never receives answers or history.
- Only active relationship members can read a share.
- Retake updates an existing share without a duplicate notification.
- Logs, analytics, notifications, and crash reports contain no answers.

### Integration

- Quiz entry routes to the Communication quiz, not the Attachment quiz.
- Profile shows current result and supports view/retake.
- Conflict Translator reads `primary`, handles `unknown`, and remains functional if profile fetch fails.
- Downstream consumers never treat the result as diagnostic or observed behavior.

### UX and Soul compliance

- No streak, leaderboard, reward currency, partner comparison, or pressure mechanic.
- “Score” is not presented as a grade, health measure, or achievement.
- Copy remains non-diagnostic, non-blaming, agency-preserving, and context-aware.
- Reduced motion, text scaling, contrast, touch targets, and screen-reader behavior pass review.
- Failure states preserve answers and provide a clear retry path.

---

## 11. Explicit Non-goals

This feature does not:

- diagnose a communication disorder or relationship problem
- determine whether either partner is right or wrong
- analyze a partner who did not take the quiz
- infer communication style from one message
- replace observed-pattern analysis
- calculate Pulse or relationship health
- prove compatibility
- give treatment advice

---

## 12. Resolved Decisions and Release Gate

| Decision | Resolution |
|---|---|
| Instrument | 20 self-report items across four dimensions |
| Scoring | Four independent 0–100 scores |
| Summary | Primary + secondary with explicit tie/low-separation handling |
| Confidence | Provisional medium; modest language required |
| Privacy | Private by default; active-partner opt-in sharing only |
| Translator use | Optional soft context; `primary` is canonical; missing means unknown |
| Compatibility | No standalone verdict; only constrained experimental Dating Mode use allowed by Master |
| Retakes | Current result replaced atomically; complete prior JSON archived |
| Production release | Blocked until clinical and Ghanaian cultural review is recorded |

This specification is ready for engineering implementation. Production release remains gated by the review named above.
