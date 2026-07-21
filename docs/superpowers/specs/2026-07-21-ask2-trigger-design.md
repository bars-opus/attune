# Ask-2 Trigger System — Design

## Why

`ATTUNE_MASTER_SPEC.md` §8.8 Track B (decision 29) locks in a two-ask design
for couples onboarding: Ask 1 is profile + partner invite only, with zero
"AI/analysis/insight" vocabulary anywhere in it, because the invited
partner's threat response spikes at that language arriving before any lived
trust. The attachment quiz, three relationship anchors, and the intelligence
introduction move to **Ask 2** — fired days later, anchored to a positive
signal already observed in the couple's own chat, fully skippable.

The current implementation violates this: `onboarding_flow.dart` shows the
quiz and anchors inline, immediately after mode selection, for every mode
including couples — before the invite/waiting screen even appears.

This spec covers moving couples onto the two-ask design. **Personal
(single) mode is unaffected** — Track A keeps the quiz up front, which is
already correct and must not change.

## Scope boundary

This is the trigger + re-entry system only. It does not include:
- The attachment quiz's instrument (question wording/count/scale) — that's
  a separate, explicitly unresolved clinical decision (see this session's
  spec audit). Ask-2 reuses the existing `AttachmentQuizStep` verbatim.
- A polished compatibility-preview screen — the compatibility computation
  RPC (`upsert_attachment_compatibility_cache`) and its read provider
  (`attachmentCompatibilityProvider`) already exist; Ask-2's last step
  triggers the computation and shows a minimal reveal, not a redesigned
  preview experience.

## Architecture

Five pieces, in dependency order:

### 1. Persist message-level sentiment

`supabase/functions/analyse-message/index.ts`'s Claude prompt already asks
for `"sentiment": "positive"|"neutral"|"negative"|"charged"` per message,
but `validateLayerOne()` discards it before the `UPDATE`. Add a `sentiment`
text column to `messages` (nullable, same lifecycle as `tone_score`), and
have `validateLayerOne` pass it through with the same allow-listing pattern
already used for `bid_type`.

### 2. Eligibility query (service-role RPC)

A new Postgres function, `SECURITY DEFINER` but **not** keyed off
`auth.uid()` (unlike `chat_conversation_streak`) — callable only by the
service role, since the cron sweep evaluates arbitrary relationships, not
"the calling user's own."

```sql
ask2_eligibility(p_relationship_id uuid) RETURNS TABLE (
  eligible boolean,
  first_positive_message_id uuid,
  first_positive_at timestamptz
)
```

Eligibility requires, for the given relationship:
- Both `user_a` and `user_b` are non-null and `status = 'active'`
  (mutual link already happened — Ask 1 complete).
- Both partners have sent **≥ 30 messages each** (not a combined total —
  queried directly from `messages` grouped by `sender_id`, since
  `relationships.message_count` is a combined counter and can't express
  "each").
- At least 3 distinct **local calendar days** with messages from both
  partners — reuses the day-bucketing logic `chat_conversation_streak`
  already implements, but does not require the days to be consecutive
  (the spec says "active in chat for 3+ days," not a streak).
- At least one message with `sentiment = 'positive'` exists. Return its
  `id`/`created_at` as `first_positive_message_id`/`first_positive_at` —
  needed by the state table below, NOT surfaced to the user (see anchor
  copy, below).

### 3. `ask2_state` table + cron sweep

```sql
CREATE TABLE ask2_state (
  relationship_id uuid PRIMARY KEY REFERENCES relationships(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'eligible', 'prompted', 'reminded', 'completed', 'skipped')),
  eligible_at timestamptz,
  first_positive_message_id uuid REFERENCES messages(id),
  prompted_at timestamptz,
  reminded_at timestamptz,
  completed_at timestamptz,
  skipped_at timestamptz
);
```

A new edge function `evaluate-ask2-eligibility`, cron-scheduled (piggybacks
on the existing `supabase/sql/schedule_*` pattern — hourly is enough, this
isn't latency-sensitive), does:

- For every `relationships` row with `status = 'active'` and no
  `ask2_state` row (or `status = 'pending'`), call the eligibility RPC.
- On `eligible = true`: upsert `ask2_state` to `status = 'eligible'`,
  stamp `eligible_at`/`first_positive_message_id`, then immediately
  enqueue the notification (step 4) and set `status = 'prompted'`,
  `prompted_at = now()`.
- **One reminder max**: a separate check, same sweep — any row still
  `status = 'prompted'` after 7 days with no `completed_at`/`skipped_at`
  gets exactly one more notification, then flips to `status = 'reminded'`.
  A row in `reminded` never gets another automatic notification — silence
  after that, per spec ("one gentle reminder max then silence").
- `status = 'completed'`/`'skipped'` rows are terminal and skipped by all
  future sweeps.

### 4. Notification (reuses existing pipeline, no new UI surface)

A new `NotificationType` value, `ask2Invite` (`value: 'ask2_invite'`),
added alongside `CommonNotificationTypes`. The sweep inserts a row into
`in_app_notifications` (read/unread tracking is free) and
`scheduled_notifications` (for the OneSignal push), both already wired.

Copy is deliberately generic and never paraphrases the couple's actual
messages back at them — per the earlier "no surveillance-adjacent copy"
constraint from this session's brainstorm:

> **Title:** "We noticed something good"
> **Body:** "You two have a real rhythm going. Want to see what Attune
> can tell you about how you communicate?"

Tapping the notification deep-links into the new `Ask2Flow` (piece 5).
Dismissing/ignoring the notification is exactly "skippable" — no explicit
in-app "skip" button is needed, since not tapping through already satisfies
"never penalized or nagged." If the user later opens `Ask2Flow` from the
notification and backs out before finishing, that's handled by
`Ask2Flow`'s own state, not `ask2_state` (still `prompted`/`reminded`
until they actually complete or the sweep gives up after the one
reminder).

### 5. `Ask2Flow` — standalone re-entry widget

A new `lib/features/onboarding/presentation/screens/ask2_flow.dart`,
**not** a mode of `OnboardingFlow` — a separate `StatefulWidget` with its
own tiny linear `_step` (intro → quiz → anchors → reveal), composing the
*existing* step widgets directly:

```
IntelligenceIntroStep (new, small)
  → AttachmentQuizStep (reused as-is, couples-mode copy)
  → AnchorsStep (reused as-is, relationshipAnchorPrompts)
  → Ask2RevealStep (new, small) — triggers
    upsert_attachment_compatibility_cache, shows a minimal
    "you're both in — compatibility preview coming together" state
```

Reusing `AttachmentQuizStep`/`AnchorsStep` directly (not copy-pasting) means
any future fix to those widgets (like this session's Hero/animation/crash
work) applies to both Ask-1-single and Ask-2-couples automatically.

State: a new `ask2_answers`/`ask2_anchors` write path in
`OnboardingSubmissionService` (or a small sibling service) writes to
`onboarding_profiles` — but **`onboarding_profiles` needs a second
completion marker**, since today `completed_at` means "Ask 1 done" for
everyone. Add `ask2_completed_at timestamptz` (nullable) to
`onboarding_profiles`. `Ask2Flow`'s final step sets it; nothing else
does. This is the "separate Ask-1-done vs Ask-2-done" tracking the
infrastructure survey flagged as missing.

Entry point: the notification's deep link route (`/ask2/:relationshipId`)
pushes `Ask2Flow` on top of wherever the user is (normally the chat
screen) — it is not part of the app's initial-route decision tree the way
`OnboardingFlow` is, since it can only ever be reached after Ask 1 and
chat are already live.

## Removing the current violation

In `onboarding_flow.dart`, the couples branch (`_goToQuiz()` /
`_goToAnchors()` calls after mode selection) is removed **only for
`OnboardingMode.couples`/`couplesPending`**. Personal mode's call sequence
is untouched. After profile setup, a couples user goes straight to
`_goToQuiz()`'s replacement: nothing — mode selection leads directly to
partner invite / waiting screen, matching Ask 1's spec'd sequence exactly.

The confirmation-gate infrastructure built this session (`_confirmMoveOn`,
`AttachmentQuizDocs`, `AnchorsDocs`) is **not deleted** — it's reused
verbatim inside `Ask2Flow`'s intro step, since "explain what's coming
before showing it" is equally valid at Ask-2 time.

## Testing

- `ask2_eligibility` RPC: SQL-level test fixtures covering under-threshold
  message counts, single-partner-only volume, day-count edge cases, and
  the no-positive-sentiment-yet case.
- `evaluate-ask2-eligibility` edge function: mirrors the existing
  `analyse-message`/`analyse-session` edge function test patterns already
  in the repo.
- `Ask2Flow` widget tests: intro → quiz → anchors → reveal, and that
  backing out mid-flow doesn't corrupt `ask2_state` (still reachable via
  the notification later).
- Regression: `onboarding_flow_test.dart` and
  `attachment_quiz_step_test.dart` must keep passing unmodified for
  personal/single mode; new assertions confirm couples mode no longer
  reaches the quiz/anchors steps inline.

## Interaction with the 48-hour solo reflection fallback

Master spec: if a partner hasn't completed onboarding after 48 hours, chat
unlocks in solo reflection mode (messages are private journal entries, not
delivered to the partner). `ask2_eligibility`'s requirement of
`relationships.status = 'active'` AND both `user_a`/`user_b` non-null means
a relationship stuck in solo-reflection (partner never joined,
`user_b IS NULL`) can never become eligible — correct, since Ask-2 requires
a real two-person conversation to observe. If the partner joins later and
the relationship transitions to `status = 'active'`, the sweep picks it up
on its next run with no special-casing needed.

## Open items for you to confirm before planning

1. **Cron cadence** for `evaluate-ask2-eligibility` — hourly proposed above,
   matching the existing `analyse-session` cadence pattern. Fine, or do you
   want it tighter/looser?
2. **7-day reminder window** — spec says "one gentle reminder max," doesn't
   specify timing. I picked 7 days after the first prompt as a reasonable
   default; confirm or adjust.
