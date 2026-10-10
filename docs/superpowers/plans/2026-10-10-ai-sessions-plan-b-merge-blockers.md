# AI Sessions Plan B — Merge-Blocker Remediation

**Created:** 2026-10-10
**Branch:** `worktree-ai-sessions-plan-b` (23 commits, unmerged, HEAD `604add1b`)
**Status:** Scoped, not started.
**Blocks:** merging Plan B; starting Plan C.

---

## Why this plan exists

Plan B's 11 tasks are implemented and each was independently reviewed (several
with fix rounds that found and closed real security bugs — a partner-weaponizable
quota lockout, an impersonation hole, a consent read leak). The **final
whole-branch review returned do-not-merge**: it found two violations of the plan's
own named merge blockers that per-task review structurally could not see, because
every finding here spans RPCs that no single task owns.

Two further items were found during the plan and deliberately escalated rather
than fixed mid-flight, because each requires an architecture decision.

All four were reproduced live. Three were verified a second time by the
controller, independently, against unmodified shipped code.

Read `.superpowers/sdd/2026-09-22-ai-sessions-plan-b-schema-and-concurrency/progress.md`
(the ledger) and `final-branch-review.md` before starting. The ledger records 13
numbered rulings, three of which the final review corrected — those corrections
are folded into the tasks below.

## Global Constraints

These are Plan B's own, unchanged. Every task below inherits them.

- **No table in this plan grants direct SELECT/INSERT/UPDATE/DELETE to
  `authenticated`.** Access is a narrow `SECURITY DEFINER` RPC or a
  security-invoker view backed by RLS. Currently 56 table×role×privilege
  combinations are asserted at 0 leaked — keep it that way and re-assert it.
- **Lock order is fixed and must never vary across RPCs**: relationship advisory
  lock (`pg_advisory_xact_lock(hashtext(p_relationship_id::text))`) → requester's
  quota advisory lock (inside `reserve_ai_assistant_quota`) → session row lock
  (`SELECT ... FOR UPDATE` on `ai_sessions`) → request row lock. The plan's own
  words: a task needing a different order is a plan defect, and mixed ordering is
  a merge blocker. **Task 1 exists because three RPCs violate this.**
- **No SQL transaction may span a provider HTTP call.**
- **Every session-scoped table's primary content is deleted in the SAME
  transaction that closes the session.** The every-minute reconciler is a
  backstop, never the primary deletion path.
- **No client-readable "who ended it" field** on any session-scoped table.
- **Ordinal parity is exactly `2n-1` (user) / `2n` (Attune)** for attempt `n`,
  both derived from the same `n`.
- **`operation_fingerprint` never includes location.**
- **Every `SECURITY DEFINER` function uses `SET search_path = public`** and
  validates its actor parameter non-NULL as its first statement.

## Discipline this plan inherits (earned the hard way across Plan B)

- **Additive migrations only.** Never edit a committed migration's logic in
  place. Next sequence after `20260953110000`.
- **No vacuous tests. Assert the SPECIFIC expected error, never "any error."**
  Plan B shipped five vacuous-test findings. The suite's convention is
  `EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;`
  plus a specific-message check — all 28 handlers in the plan follow it.
- **Structural assertions must strip comments.** `pg_get_functiondef()` returns
  comments verbatim, so a plain text match is satisfied by a guard that was
  commented out. Reuse `pg_temp.strip_sql_comments()` from
  `supabase/tests/ai_session_read_authorization_contracts.sql`.
- **Any contract that denies by nulling a relationship member is
  SELF-DEFEATING** on the gated RPCs: the consent gate reads those same columns,
  so a NULL member empties the consent lookup and the contract passes against a
  genuinely exploitable mutant. Deny with a *replacement consenting member*.
- **Consent events inserted in one `DO` block share a frozen `now()`**, so the
  lookup's tiebreak falls to `id DESC` on a random uuid — intermittently green.
  Use `clock_timestamp()` for every consent insert.
- **Mutation-test every contract.** One fresh DB per mutant from a clean
  template, control run first. Fixed UUIDs make dirty reruns meaningless.
- **Fixture collisions have bitten this plan SIX times.** Sweep and
  uuid-cast-validate every new uuid, phone and email against the whole suite
  first. `users.phone` is UNIQUE, and an `ON CONFLICT DO NOTHING` insert that
  silently drops is how two of those bugs worked. Claimed in
  `b1000000-0000-0000-0000-*`: 0002-0005, 0007-0009, 001a, 0020-0022, 002a, 002b,
  0030-0038, 003a, 003b, 004a, 006a, 009a, 010a-010c, 011a, 0107, 0702, 0733.
- **Verify with the canonical single-pass `bash scripts/local_pg_setup.sh`.**
- Prove privilege/schema claims by query, never by reading SQL.

## Baseline

`bash scripts/local_pg_setup.sh` at `604add1b` → **267 migrations applied / 0
failed**, **63 SQL PASS / 1 FAIL**, **3/3 game concurrency PASS**, **5/5 AI
session concurrency PASS**. The one failure is pre-existing and unrelated:
`settings_accessor_test.sql` → `relation "vault.secrets" does not exist` (no local
Vault). Only NEW failures count.

`pg_cron` is NOT installed locally; the harness stubs it with a real `cron.job`
table plus `schedule`/`unschedule`. Registration is verifiable, firing is not.

---

## Task 1: Fix the lock-order inversion in the three completion RPCs

**Severity: Critical. This is the plan's own named merge blocker.**

**Files:**
- Create: `supabase/migrations/20260953120000_ai_session_completion_lock_order_fix.sql`
- Test: extend `supabase/tests/ai_session_commit_ideas_contracts.sql` and
  `supabase/tests/ai_session_nearby_staging_contracts.sql`
- Create: `supabase/tests/ai_session_completion_concurrent_test.sh`

**The defect.** `commit_ai_session_ideas_turn`,
`stage_ai_session_nearby_result` and `publish_ai_session_nearby_result` contain
**no `pg_advisory_xact_lock` at all** and take the request row `FOR UPDATE`
before the session row — the documented order inverted.

Reproduced live against unmodified shipped RPCs, no sleeps or instrumentation:
racing `commit_ai_session_ideas_turn` against `end_ai_session` from two backends
produced `ERROR: deadlock detected ... PL/pgSQL function end_ai_session line 61`,
in **3 of 5 trials**, with the victim alternating between the worker's commit and
**the user's own End action** (a user-facing failure surfacing a raw 40P01).

Four deadlocking pairs are known: `commit`×`end`, `publish`×`end`,
`stage`×`end`, `discard`×`publish`. Plus `commit`×`purge_expired_ai_sessions`,
where 1 of 8 trials killed the purger — and its `EXCEPTION WHEN OTHERS` swallowed
the deadlock into a WARNING, leaving an expired session `state=active` with its
content retained indefinitely.

**The mechanism is subtler than an explicit lock.** The `INSERT ai_session_turns`
FK check takes `FOR KEY SHARE` on `ai_sessions` *before* the explicit
`UPDATE ... revision` is reached, so this is **not** avoidable by dropping the
revision bump. Any fix must account for implicit parent-row locks taken by child
inserts, not just explicit `FOR UPDATE`.

**Why 11 reviews missed it:** all four `.sh` concurrency scripts race only
`prepare`/`activate`/`admit`/`end` — precisely the conforming subset. No existing
test races any completion RPC against anything.

**Winning definitions to supersede** (do not edit in place):
- `commit_ai_session_ideas_turn` → `20260953070000_ai_session_commit_ideas_rpc.sql`
- `stage_ai_session_nearby_result` → `20260953080000_ai_session_nearby_staging_rpcs.sql`
- `publish_ai_session_nearby_result` → `20260953110000_ai_session_reconciler_cron.sql`
  (note: Task 11 already redefined this one to add the consent gate — preserve
  that gate and its position; see Task 3)

**Steps:**
- [ ] Enumerate every lock each of the three RPCs takes, **including implicit
      ones** (plain `UPDATE ai_sessions`, and child-table INSERT taking
      `FOR KEY SHARE` on the parent). Write the list down before changing
      anything; the explicit-`FOR UPDATE` audits are what missed this.
- [ ] Redefine all three to acquire the relationship advisory lock first, then
      the session row, then the request row. They need `relationship_id`, which
      they currently do not resolve — add the `SELECT se.relationship_id` lookup
      ahead of the lock, as `20260953100100` does.
- [ ] Preserve every existing behaviour: the consent gate and its pre-gate
      idempotent-replay position in `publish` (Task 11 / Task 10 F1), ordinal
      parity `2n-1`/`2n` from one `n`, idempotency on retry of the same
      `request_id`, and the exact error messages existing contracts assert.
- [ ] Add a **structural** lock-order assertion for each of the three, on the
      comment-stripped live body, using `position()` so that a *reordering*
      fails with all three statements present. `supabase/tests/ai_session_purge_contracts.sql`
      Contract 8 is the precedent.
- [ ] Write `ai_session_completion_concurrent_test.sh` racing each completion RPC
      against `end_ai_session` and against `purge_expired_ai_sessions`, both
      orderings, ≥10 trials each. It must be `chmod +x` and wired into
      `scripts/local_pg_setup.sh` alongside the existing four — a non-executable
      or unwired script is Task 9's F5 all over again.
- [ ] Verify: ≥10 trials per pair with **zero** deadlocks, and the purger never
      swallows a deadlock into a WARNING. Then re-run the four pre-existing
      concurrency scripts to confirm the conforming paths still pass.

**Verification:** the deadlock repro above must stop reproducing across ≥10
trials per pair. Report trial counts, not "no deadlock observed."

---

## Task 2: Return the session revision so multi-turn is reachable

**Severity: Critical. The branch's stated purpose is unreachable by its only
consumer.**

**Files:**
- Create: `supabase/migrations/20260953130000_ai_session_revision_disclosure.sql`
- Test: extend `supabase/tests/ai_session_commit_ideas_contracts.sql`,
  `supabase/tests/ai_session_nearby_staging_contracts.sql`

**The defect.** `admit_ai_session_generation` raises `CONTEXT_CHANGED` unless
`p_expected_revision` equals the session's current `revision`.
`commit_ai_session_ideas_turn` and `publish_ai_session_nearby_result` bump it.
**No RPC returns it.** Verified by catalog query: the only plan function whose
result type mentions `revision` is `prepare_ai_session`, which returns the
initial value only.

So turn 1 admits, commit bumps the revision to 2, and turn 2 raises
`CONTEXT_CHANGED` with no legitimate way for the caller to learn the new value.
Every committed test gets past turn 1 by `SELECT revision FROM ai_sessions`
directly — a raw table read Plan C forbids itself, and which bypasses all four
§7.2 gates.

**DECIDED 2026-10-10 by the user: Option A.** Return the new revision from
`commit_ai_session_ideas_turn` and `publish_ai_session_nearby_result`. The caller
that caused the bump learns the result atomically; two return shapes change, which
Plans C and D must match.

Option B (a gated `read_ai_session_state` RPC returning revision plus request
state) was considered and **not** chosen now. It remains the fix for a separate
gap this plan does not close: a client that loses its response has no way to learn
what happened. The two are not mutually exclusive — revisit B when Plan C's error
handling needs recovery-after-lost-response, and record it in Plan C's own plan
rather than reopening this task.

**Steps:**
- [ ] Implement additively, preserving every existing return field and the
      pre-gate idempotent-replay path in `publish`. Returning the revision from
      the replay path must report the CURRENT revision, not re-bump it.
- [ ] Contract: a genuine **two-turn** sequence that never reads `ai_sessions`
      directly — admit → claim → commit → admit again using only values the RPCs
      returned. This is the assertion whose absence hid the defect; it must fail
      if revision disclosure is removed.
- [ ] If Option B: assert all four §7.2 gates (active membership in a live
      unarchived relationship, current consent at the current policy version,
      unexpired active state, creator-private or accepted-participant at the
      current `context_revision`), reuse `read_ai_session_turns`' byte-identical
      predicate shape, keep zero-rows-not-raise, and re-assert 56/0 leaked.

---

## Task 3: Gate consent on the dispatch path

**Severity: Critical. Chat content reaches a third-party AI provider after
consent was withdrawn.**

**Files:**
- Create: `supabase/migrations/20260953140000_ai_session_admit_consent_gate.sql`
- Test: extend `supabase/tests/ai_session_admit_contracts.sql`

**The defect.** Reproduced live twice (zero consent events, and
granted-then-withdrawn): `prepare` → `approve` → `activate` → `admit` → `claim` →
`commit_ai_session_ideas_turn` all succeed and the Ideas transcript is written. Of
18 plan functions, 3 check consent: the two read RPCs and `publish` (the latter
only as of Task 11).

My first two framings of this understated it, and the correction matters:

1. I first said "no write-path RPC checks consent." Wrong — `share_ai_session_turn`
   *is* gated, one call down, via Plan A's send path (verified live: `Consent
   required`).
2. I then settled on "the transcript is written ungated; nothing escapes the
   session ungated." Also understated. **The ungated step that matters is
   `claim_ai_session_dispatch`, and that call IS the authorization to make the
   provider HTTP call** — its only purpose is setting the provider-start marker
   immediately before calling Gemini. So the real exposure is that the couple's
   approved chat clippings are **transmitted to a third-party AI provider after
   consent was withdrawn**, which is the materially worse half and the half no
   gate touches.

**The fix is one RPC, not seven.** Gate `admit_ai_session_generation` alone.
Verified: it resolves `v_relationship_id` at line 47 and takes the relationship
advisory lock at line 54, so the gate slots between them with no new lock and no
lock-order change. And `claim_ai_session_dispatch` requires a request already at
`state='reserved'` with a matching `worker_token` — both produced only by a
successful `admit` — so claim/commit/stage inherit the gate transitively. Verified
by reading `claim`'s own WHERE clause.

**Steps:**
- [ ] Add the membership+consent gate to `admit_ai_session_generation`, between
      the `relationship_id` resolution and the advisory lock. Lift the predicate
      verbatim from `20260953100100_ai_session_read_rpcs_fix.sql` — it is
      byte-identical to canonical `get_ai_processing_consent_status` including
      ORDER BY and COALESCE, and matches `idx_ai_processing_consent_current`. Do
      not invent a new shape. Note this makes a **fourth** copy; see Task 5.
- [ ] Failure mode: `admit` already raises on every rejection and returns a row,
      so **raise** with a specific message. A silent return would report success
      while admitting nothing. Follow Task 11's reasoning for `publish`.
- [ ] Contracts: (a) withdrawn consent → admit raises the specific message;
      (b) never-granted consent → same; (c) both-granted → admit still succeeds
      (the over-restriction direction — Task 10's re-review found this is the
      direction most likely to be missed); (d) a **two-turn** sequence still
      works after a withdraw-then-regrant inside the window.
- [ ] Mutation-test: delete the gate → (a)/(b) fail with their specific messages;
      narrow the gate to one partner → the both-granted contract still passes but
      a one-partner-withdrawn case now admits.
- [ ] Verify the gate does not change `admit`'s lock order and that Task 5's
      admit concurrency scripts still pass.

---

## Task 4: Stop one orphaned row from wedging lease reconciliation

**Severity: Important, upgraded from Minor during the final review.**

**Files:**
- Create: `supabase/migrations/20260953150000_ai_session_lease_reconcile_fault_isolation.sql`
- Test: extend `supabase/tests/ai_session_dispatch_claim_contracts.sql`

**The defect.** `reconcile_ai_session_leases` raises
`Reservation not found for this actor` on a request row with no matching
`ai_assistant_usage` row. Two things make this worse than first recorded:

1. **The raise has no per-row handler**, so it aborts the whole transaction and
   **rolls back every healthy row processed in the same run.** One bad row
   permanently starves lease reconciliation *platform-wide*, stopping quota
   release for every user. Measured during the final review: `collateral: the
   HEALTHY request state is now reserved (rolled back)`.
2. **It is reachable by shipped scheduled code alone**, with no manual deletion:
   Plan A's registered `purge_old_ai_assistant_usage()` deletes
   `ai_assistant_usage` rows older than 30 days, and nothing prunes
   `ai_session_requests`. Reproduced: `after Plan A usage purge: request rows=1
   usage rows=0` → wedged. A cross-plan cron interaction no per-task review
   could see.

**Steps:**
- [ ] Add per-row fault isolation, matching the pattern Task 11's two sweeps
      already use (that is precisely why they cannot wedge this way). A one-line
      `CONTINUE` on the missing-usage case, or a per-row `EXCEPTION` block that
      logs a WARNING and proceeds.
- [ ] Decide and document whether an orphaned request row should also be resolved
      to a terminal state rather than skipped forever, or left for a future
      pruner. State the reasoning.
- [ ] Contract: seed one orphaned request row plus one healthy row in the same
      run; assert the healthy row IS resolved and the orphan does not abort the
      batch. Mutation-test by removing the isolation and confirming the healthy
      row rolls back.

---

## Task 5: Extract the consent predicate, and close the recorded Minors

**Severity: Minor. Do this last; none of it blocks merge on its own.**

**Files:**
- Create: `supabase/migrations/20260953160000_ai_consent_helper_and_minors.sql`
- Test: extend the relevant existing contract files

After Task 3 the consent predicate exists in **four** byte-identical copies
(`read_ai_session_turns`, `read_ai_session_staging`, `publish`, `admit`). It
could not be shared earlier because `get_ai_processing_consent_status` derives its
actor from `auth.uid()` and raises on a service-role connection, which is every
caller here.

- [ ] Extract `ai_consent_granted_for_relationship(p_relationship_id uuid)`
      taking no actor, and route all four call sites through it. A policy-version
      bump must be correct in one place, not four.
      (`ai_current_consent_policy_version()` is already shared, so today's
      exposure is the query shape, not the constant.)
- [ ] **Task 11 F1** — the purger's quota-resolution loop is never behaviourally
      executed by any contract (measured: both purge sites report `0 requests in
      reserved/started/staged at purge time`, because Contract 1 commits the turn
      first). Two surviving mutants fail *worse* than a quota hole: releasing for
      all three states, and keying the release on `creator_id` instead of the
      row's own `actor_id`, each raise → the per-session handler swallows it →
      **the session is never purged and content is retained indefinitely**. Add a
      contract that purges a session with a genuinely `reserved` request, and one
      where a **non-creator partner** admitted on a shared session.
- [ ] **Task 11 F4** — the approval trigger's `UPDATE OF member_id, session_id`
      arm is untested; narrowing it to `BEFORE INSERT` passes the suite, and the
      UPDATE forgery was reconstructed live on that mutant. Add the UPDATE leg.
- [ ] **N3** — `generation_epoch` has 3 writers and **0 readers**, so spec §6.2's
      epoch fence does not exist; the deadline fence is also absent from all three
      completion RPCs, and a commit on an expired lease is accepted (35s lease vs
      60s cron ⇒ a routine ~25s window). Decide whether to implement the fence or
      amend the spec, and say which. Currently safe only because every
      epoch-bumping path also cancels the request — which nothing enforces.
- [ ] **N5** — `ai_session_publications.consumed_marker` survives the purge
      correctly, but `session_id` is `ON DELETE CASCADE` → `ai_sessions` →
      `relationships`, so relationship deletion removes it while the table comment
      claims unconditional survival. Fix the comment or the cascade.
- [ ] **N6 (docs)** — the plan's Goal paragraph claims Realtime authorization as a
      Plan B deliverable; no `realtime.messages` policy exists in the branch. The
      self-review correctly disclaims it. Align the Goal text, and record in Plan
      C's Global Constraints that §6.1 Realtime is unclaimed by both plans as
      divided.
- [ ] **Ledger correction to carry forward:** Ruling 11 was WRONG. Task 8's
      `ai_session_nearby_staging_contracts.sql` Contract 2 is *not* a bare
      `EXCEPTION WHEN OTHERS` — it carries the standard
      `IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE` guard, mutation-proved by the final
      review, which audited all 11 plan test files and found **28 handlers, every
      one message-checked or re-raise-guarded**. There is no seventh vacuous test;
      the discipline holds branch-wide. No work needed — recorded so nobody
      "fixes" a non-defect.

---

## Also recorded for Plan C (not this plan's work)

The final review's goal-backward pass found what Plan C cannot do against this
backend. Tasks 1-3 close the first three; the rest belong in Plan C's own plan:

- Must tolerate **non-contiguous ordinals** (a failed attempt 1 then a committed
  attempt 2 yields ordinals 3,4 — a correct gap per the parity constraint).
- Must handle a raw `deadlock detected` from the completion path. After Task 1
  this should be unreachable, but the provider call is already paid for at that
  point, so a deadlock on commit means a charged generation whose result is
  discarded — Plan C needs a retry story either way.
- `service_role` retains SELECT on `ai_sessions` (the REVOKEs target only
  anon/authenticated/PUBLIC), so Plan C *can* read raw rows and thereby bypass all
  four §7.2 gates. Task 2 should remove the need; Plan C should still forbid it
  explicitly.
- A `started` request whose lease expires leaves its usage row at
  `outcome='reserved'` with the provider marker set, permanently — correct by
  design (started calls stay charged), but "in flight" and "abandoned" are
  forever indistinguishable. An observability limit worth a dashboard, not a
  defect.
- Purge-lag alerting: the purger deliberately swallows per-session errors into a
  WARNING, so a systematic purge failure shows only in the cron log.

## Execution notes

- Task order: 1 → 3 → 4 → 2 → 5. Task 1 first because every other task's
  contracts run against a backend that currently deadlocks under concurrency.
  Task 2 needs a user decision, so it should not block 1/3/4.
- Tasks 1-4 are independent in their file surfaces, but all commit to one branch:
  run one implementer at a time, with a task review between each (Plan B's
  subagent-driven pattern, which found every finding above).
- A fresh whole-branch review is required after Task 1 and Task 2 specifically —
  both change RPC shapes that 11 tasks' contracts depend on.
